#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <fcntl.h>
#include <math.h>
#include <time.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <sys/resource.h>
#include <sched.h>

#define PHASE_BITS 29
#define NUMCHANS 13
#define TCP_PORT 1001

// pretty sure fifo bytes should not be changed
// also needs to be a multiple of system pagesize but that's usually 4K
// rpi5 uses 16K pagesize, apple uses 64K, so 128K is still a multiple
// should be fine
#define FIFO_BYTES 128 * 1024

#define SAMPLE_SIZE 4 // in bytes
#define FIFO_SAMPLES (FIFO_BYTES / SAMPLE_SIZE)

struct control
{
  int32_t inps, rate;
  int32_t freq[NUMCHANS];
};

const int rates[4] = {1280, 640, 320, 160};

int interrupted = 0;

void signal_handler(int sig)
{
  interrupted = 1;
}

#define CHUNK_SAMPLES (NUMCHANS * 256)
#define CHUNK_BYTES (CHUNK_SAMPLES * SAMPLE_SIZE)
// send q must be multiple of CHUNK_BYTES
// writes into send q must always be exactly CHUNK_BYTES big
#define SENDQ_MAX (96 * 1024 * 1024 / CHUNK_BYTES * CHUNK_BYTES)
struct client
{
  unsigned char sendq[SENDQ_MAX];  // Write buffer - allocated later
  unsigned char *sendqStart;
  unsigned char *sendqEnd; // where the data in the sendQ starts
  int fd; // File descriptor
  int64_t last_flush;
  int64_t last_send;
};

static int64_t microtime(void) {
    struct timeval tv;
    int64_t mst;

    gettimeofday(&tv, NULL);
    mst = ((int64_t) tv.tv_sec) * (1000LL * 1000LL);
    mst += tv.tv_usec;
    return mst;
}

static void emitTime(FILE *stream) {
    int64_t now = microtime();
    int64_t seconds = 1000 * 1000;
    fprintf(stream, "%02d:%02d:%06.3fZ ",
            (int) ((now / (3600 * seconds)) % 24),
            (int) ((now / (60 * seconds)) % 60),
            (now % (60 * seconds)) / (1000.0 * 1000.0));
}

/* record current monotonic time in start_time */
static void startWatch(struct timespec *start_time) {
    clock_gettime(CLOCK_MONOTONIC, start_time);
}

// return elapsed time and set start_time to current time
static int64_t lapWatch(struct timespec *start_time) {
    struct timespec end_time;
    clock_gettime(CLOCK_MONOTONIC, &end_time);

    int64_t res = ((int64_t) end_time.tv_sec * 1000LL * 1000LL + end_time.tv_nsec / 1000LL)
        - ((int64_t) start_time->tv_sec * 1000LL * 1000LL + start_time->tv_nsec / 1000LL);

    *start_time = end_time;
    return res;
}

static void setPriority() {
    int pid = 0; // this process

    setpriority(PRIO_PROCESS, pid, -20);

    int policy = SCHED_FIFO;
    struct sched_param param = { 0 };

    param.sched_priority = 80;

    sched_setscheduler(pid, policy, &param);
}

static int sendqLen(struct client *c)
{
  if (c->sendqStart <= c->sendqEnd) {
    return (c->sendqEnd - c->sendqStart);
  } else {
    return ((c->sendqEnd - c->sendq) + (c->sendq + SENDQ_MAX - c->sendqStart));
  }
}

static void initClient(struct client *c, int fd)
{
  // clear client struct
  memset(c, 0, sizeof(struct client));
  // set fd for client
  c->fd = fd;
  c->sendqStart = c->sendq;
  c->sendqEnd = c->sendq;


  /* Set the socket nonblocking.
   * Note that fcntl(2) for F_GETFL and F_SETFL can't be
   * interrupted by a signal. */
  int flags;
  if ((flags = fcntl(fd, F_GETFL)) == -1) {
      perror("fcntl(F_GETFL)");
      exit(EXIT_FAILURE);
  }
  if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1) {
      perror("fcntl(F_SETFL,O_NONBLOCK)");
      exit(EXIT_FAILURE);
  }
}

static void normalizeSendq(struct client *c)
{
  if (c->sendqEnd - c->sendq > SENDQ_MAX) {
    fprintf(stderr, "FATAL ringbuffer flaw uQuee9pa\n");
    exit(EXIT_FAILURE);
  }
  if (c->sendqEnd - c->sendq == SENDQ_MAX) {
    c->sendqEnd = c->sendq;
  }

  if (c->sendqStart - c->sendq > SENDQ_MAX) {
    fprintf(stderr, "FATAL ringbuffer flaw reeceSh3\n");
    exit(EXIT_FAILURE);
  }
  if (c->sendqStart - c->sendq == SENDQ_MAX) {
    c->sendqStart = c->sendq;
  }
}

static int flushClient(struct client *c, int limit)
{
  static int64_t byteCounter;
  int debug = 0;
  int toWrite = sendqLen(c);
  if (c->sendqStart + toWrite > c->sendq + SENDQ_MAX) {
    // if the sendq wraps around, only send() the start located at the end of the buffer
    toWrite = c->sendq + SENDQ_MAX - c->sendqStart;
  }

  if (toWrite == 0) {
    //c->last_flush = now;
    return 0;
  }

  if (toWrite > limit) {
      toWrite = limit;
  }

  int bytesWritten = send(c->fd, c->sendqStart, toWrite, MSG_NOSIGNAL);
  int err = errno;

  // If we get -1, it's only fatal if it's not EAGAIN/EWOULDBLOCK
  if (bytesWritten < 0 && (err == EAGAIN || err == EWOULDBLOCK)) {
    //fprintf(stderr, "block\n");
    return 0;
  }
  if (bytesWritten < 0) {
    // send error
    emitTime(stderr);
    perror("send ");
    return -1;
  }
  if (bytesWritten > 0) {
    // Advance buffer
    c->sendqStart += bytesWritten;
    normalizeSendq(c);
  }

  //fprintf(stderr, "sent %d\n", bytesWritten);
  return bytesWritten;
}

int main(int argc, char *argv[])
{
  int fd, i;
  int sock_server, sock_client;
  volatile void *cfg, *sts, *fifo;
  volatile uint8_t *rx_rst, *rx_sel;
  volatile uint16_t *rx_rate, *rx_cntr;
  volatile uint32_t *rx_freq;
  struct sockaddr_in addr;
  struct control ctrl;
  uint32_t size, n;
  void *buffer;
  int yes = 1;
  int64_t us, usp;
  int rx_samples = 0;
  struct timespec watch;
  int dropping = 0; // dropping data until buffer is half empty
                    //
  emitTime(stderr);
  fprintf(stderr, "startup\n");

  if (CHUNK_SAMPLES > FIFO_SAMPLES / 2) {
    fprintf(stderr, "chunk samples %d should be half or less of FIFO samples %d", CHUNK_SAMPLES, FIFO_SAMPLES);
    return -1;
  }

  fprintf(stderr, "fifo samples %d\nchunk samples %d\nqueue size in chunks %d\n", FIFO_SAMPLES, CHUNK_SAMPLES, SENDQ_MAX / CHUNK_BYTES);

  struct client *cl = malloc(sizeof(struct client));
  if (cl == NULL) {
    perror("malloc");
    return EXIT_FAILURE;
  }

  if((buffer = malloc(CHUNK_BYTES)) == NULL)
  {
    perror("malloc");
    return EXIT_FAILURE;
  }

  #ifndef TEST
  if((fd = open("/dev/mem", O_RDWR)) < 0)
  {
    perror("open");
    return EXIT_FAILURE;
  }

  cfg = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x40000000);
  sts = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x41000000);
  fifo = mmap(NULL, FIFO_BYTES, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x42000000);
  #else
  cfg = malloc(sysconf(_SC_PAGESIZE));
  memset(cfg, 0x0, sysconf(_SC_PAGESIZE));
  sts = malloc(sysconf(_SC_PAGESIZE));
  memset(sts, 0x0, sysconf(_SC_PAGESIZE));
  fifo = malloc(FIFO_BYTES);
  memset(fifo, 0xb, FIFO_BYTES);
  #endif

  rx_rst = (uint8_t *)(cfg + 0);
  rx_sel = (uint8_t *)(cfg + 1);
  rx_rate = (uint16_t *)(cfg + 2);
  rx_freq = (uint32_t *)(cfg + 4);

  rx_cntr = (uint16_t *)(sts + 0);

  if((sock_server = socket(AF_INET, SOCK_STREAM, 0)) < 0)
  {
    perror("socket");
    return EXIT_FAILURE;
  }

  setsockopt(sock_server, SOL_SOCKET, SO_REUSEADDR, (void *)&yes, sizeof(yes));

  /* setup listening address */
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  addr.sin_port = htons(TCP_PORT);

  if(bind(sock_server, (struct sockaddr *)&addr, sizeof(addr)) < 0)
  {
    perror("bind");
    return EXIT_FAILURE;
  }

  listen(sock_server, 1024);

  setPriority(); // set high priority

  while(!interrupted)
  {
    *rx_rst &= ~1;
    *rx_sel = 0;
    *rx_rate = 1280;
    for(i = 0; i < NUMCHANS; ++i)
    {
      rx_freq[i] = (uint32_t)floor(600000 / 122.88e6 * (1 << PHASE_BITS) + 0.5);
    }

    if((sock_client = accept(sock_server, NULL, NULL)) < 0)
    {
      perror("accept");
      return EXIT_FAILURE;
    }

    initClient(cl, sock_client);

    int64_t bytesDropped = 0;

    signal(SIGINT, signal_handler);

    emitTime(stderr);
    fprintf(stderr, "connected\n");

    *rx_rst |= 1;

    startWatch(&watch);
    us = microtime();
    int64_t last_iteration_us = 0;
    int64_t recvTime = 0;
    int64_t readTime = 0;
    int64_t flushTime = 0;
    int64_t sleepTime = 0;
    int noReadCounter = 10;
    while(!interrupted)
    {
      #ifdef TEST
      // simulate 25 MByte/s
      *rx_cntr += 25 * last_iteration_us / SAMPLE_SIZE;
      #endif

      rx_samples = *rx_cntr;

      if(rx_samples >= FIFO_SAMPLES)
      {
        emitTime(stderr);
        fprintf(stderr, "reset. last iteration us: %8lld rx_cntr %6d > fifo samples %6d\n",
                last_iteration_us, rx_samples, FIFO_SAMPLES);
        fprintf(stderr, "timers were: readTime %5lld flushTime %5lld recvTime %5lld sleepTime %5lld\n",
                readTime, flushTime, recvTime, sleepTime);
        *rx_rst &= ~1;
        *rx_rst |= 1;
        rx_samples = 0;
        #ifdef TEST
        *rx_cntr = 0;
        #endif
      }

      while(rx_samples >= CHUNK_SAMPLES)
      {
        int wasDropping = dropping;
        int dropUntil = SENDQ_MAX / 2;
        if (sendqLen(cl) < dropUntil) {
          dropping = 0;
        }
        if (sendqLen(cl) + CHUNK_BYTES >= SENDQ_MAX) {
          dropping = 1;
        }
        if(dropping) {
          if (!wasDropping) {
            emitTime(stderr);
            fprintf(stderr, "dropping at least %d MBytes, total dropped MBytes: %8lld\n", dropUntil / 1024 / 1024, bytesDropped / 1024 / 1024);
          }
          bytesDropped += CHUNK_BYTES;
          // sendq is full, drop this chunk by ??? reading from the fifo ???
          // the var buffer is not used anymore except to discard the data
          memcpy(buffer, fifo, CHUNK_BYTES);
        } else {
          // copy chunk into the sendq
          memcpy(cl->sendqEnd, fifo, CHUNK_BYTES);
          // advance buffer
          cl->sendqEnd += CHUNK_BYTES;
          normalizeSendq(cl);
        }
        rx_samples -= CHUNK_SAMPLES;
        #ifdef TEST
        *rx_cntr -= CHUNK_SAMPLES;
        #endif
      }

      readTime = lapWatch(&watch);

      // to ensure flushClient doesn't take super long,
      // limit each send syscall to 16x the chunk size
      // this means we can send on the network 8x faster than we get data
      // enough to catch up quickly
      int bytesWritten = flushClient(cl, 8 * CHUNK_BYTES);
      if (bytesWritten < 0) {
        break;
      }

      flushTime = lapWatch(&watch);

      int noSleep = 0;

      if (bytesWritten > 0) {
        // omit sleep if progress is being made emptying our buffer to the OS network buffer
        noSleep = 1;
      }

      // only check socket read every 10 iterations, rougly 5 ms
      // never hurts to use a couple less syscalls
      if (++noReadCounter >= 10) {
        noSleep = 1; // omit sleep when reading from network
        noReadCounter = 0;
        size = 0;
        if(ioctl(sock_client, FIONREAD, &size) < 0) {
          emitTime(stderr);
          fprintf(stderr, "fionread break\n");
          break;
        }
        if(size >= sizeof(struct control))
        {
          if(recv(sock_client, (char *)&ctrl, sizeof(struct control), MSG_WAITALL) < 0) {
            emitTime(stderr);
            fprintf(stderr, "recv break\n");
            break;
          }

          /* set inputs */
          *rx_sel = ctrl.inps & 0xff;

          /* set rx sample rate */
          *rx_rate = rates[ctrl.rate & 3];

          printf("got new frequencies\n");
          /* set rx phase increments */
          for(i = 0; i < NUMCHANS; ++i)
          {
            printf("freq %d, phase %d\n", ctrl.freq[i], (uint32_t)floor(ctrl.freq[i] / 122.88e6 * (1 << PHASE_BITS) + 0.5));
            rx_freq[i] = (uint32_t)floor(ctrl.freq[i] / 122.88e6 * (1 << PHASE_BITS) + 0.5);
          }
        }
      }

      recvTime = lapWatch(&watch);

      if (!noSleep) {
        usleep(500);
      }

      sleepTime = lapWatch(&watch);

      last_iteration_us = recvTime + readTime + flushTime + sleepTime;
    }

    // make sure the client is closed, if this errors it's fine
    close(sock_client);

    emitTime(stderr);
    fprintf(stderr, "disconnected\n");

    signal(SIGINT, SIG_DFL);
    close(sock_client);
  }

  emitTime(stderr);
  fprintf(stderr, "exiting\n");

  *rx_rst &= ~1;

  close(sock_server);

  return EXIT_SUCCESS;
}
