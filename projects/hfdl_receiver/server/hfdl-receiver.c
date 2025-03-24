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
#define TCP_PORT 9000
#define TCP_PORT_CU8 8000

#define NUMCLIENTS (2 * NUMCHANS)

#define CS16 (0)
#define CU8 (1)

// pretty sure fifo bytes should not be changed
// also needs to be a multiple of system pagesize but that's usually 4K
// rpi5 uses 16K pagesize, apple uses 64K, so 128K is still a multiple
// should be fine
#define FIFO_BYTES 128 * 1024

#define SAMPLE_SIZE 4 // in bytes
#define FIFO_SAMPLES (FIFO_BYTES / SAMPLE_SIZE)

int interrupted = 0;

void signal_handler(int sig)
{
  interrupted = 1;
}

#define CHUNK_SAMPLES (NUMCHANS * 256)
#define CHUNK_BYTES (CHUNK_SAMPLES * SAMPLE_SIZE)
#define CHUNK_CHANNEL_BYTES (CHUNK_BYTES / NUMCHANS)

// actually 25% more for CU8 buffers but we should have 512M to work with
#ifndef TEST
  #define TOTAL_NET_BUFFER (256 * 1024 * 1024)
#else
  #define TOTAL_NET_BUFFER (16 * 1024 * 1024)
#endif

struct client
{
  unsigned char *sendq;  // Write buffer - allocated later
  unsigned char *sendqStart;
  unsigned char *sendqEnd; // where the data in the sendQ starts
  int sendqMax;
  int fd; // File descriptor
  int listenPort;
  int listenFd;
  int format;
  int channel;
  uint64_t bytesDropped;
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

    char datebuf[16];
    time_t epoch;
    struct tm utc;

    epoch = now / (1000 * 1000);
    gmtime_r(&epoch, &utc);
    strftime(datebuf, 16, "%Y-%m-%d", &utc);

    fprintf(stream, "%s %02d:%02d:%06.3fZ ",
            datebuf,
            (int) ((now / (3600 * seconds)) % 24),
            (int) ((now / (60 * seconds)) % 60),
            (now % (60 * seconds)) * (1e-6f));

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
    return ((c->sendqEnd - c->sendq) + (c->sendq + c->sendqMax - c->sendqStart));
  }
}
static void allocateClient(struct client *c, int sendqMax) {
  // clear client struct
  memset(c, 0, sizeof(struct client));

  // multiple of CHUNK_CHANNEL_BYTES
  c->sendqMax = sendqMax / CHUNK_CHANNEL_BYTES * CHUNK_CHANNEL_BYTES;

  //fprintf(stderr, "sendqmax: %d\n", c->sendqMax);
  c->sendq = malloc(c->sendqMax);
  if (c->sendq == NULL) {
    perror("malloc allocateClient");
    exit(EXIT_FAILURE);
  }
  // reset ringbuffer
  c->sendqStart = c->sendq;
  c->sendqEnd = c->sendq;
  c->fd = -1; // indicate this client is not connected
}

static void setNonblocking(int fd) {
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

static void disconnectFd(int fd) {
  // get errors to avoid close / shutdown errors
  int err = 1;
  socklen_t len = sizeof err;
  getsockopt(fd, SOL_SOCKET, SO_ERROR, (char *) &err, &len);
  // shut down socket
  shutdown(fd, SHUT_RDWR);
  // make sure the client is closed, if this errors it's fine
  close(fd);
}

static void listenClient(struct client *c, int port) {
  emitTime(stderr);
  fprintf(stderr, "%d: open listen port %s\n", port, c->format == CS16 ? "CS16" : "CU8");

  c->listenPort = port;
  c->listenFd = socket(AF_INET, SOCK_STREAM, 0);
  if(c->listenFd < 0)
  {
    perror("socket");
    exit(EXIT_FAILURE);
  }

  int yes = 1;
  setsockopt(c->listenFd, SOL_SOCKET, SO_REUSEADDR, (void *)&yes, sizeof(yes));

  struct sockaddr_in addr;

  /* setup listening address */
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  addr.sin_port = htons(c->listenPort);

  if(bind(c->listenFd, (struct sockaddr *)&addr, sizeof(addr)) < 0)
  {
    perror("bind");
    exit(EXIT_FAILURE);
  }

  listen(c->listenFd, 1024);

  setNonblocking(c->listenFd);
}

static void acceptClientDiscard(struct client *c) {
  int fd = accept(c->listenFd, NULL, NULL);
  if (fd >= 0) {
    emitTime(stderr);
    fprintf(stderr, "%d: only one connection per channel supported\n", c->listenPort);
    disconnectFd(fd);
  }
}

static void acceptClient(struct client *c) {
  //emitTime(stderr);
  //fprintf(stderr, "accept on port %d\n", c->listenPort);
  c->fd = accept(c->listenFd, NULL, NULL);
  if(c->fd < 0) {
    return;
  }

  setNonblocking(c->fd);

  emitTime(stderr);
  fprintf(stderr, "%d: connected\n", c->listenPort);

  // reset ringbuffer
  c->sendqStart = c->sendq;
  c->sendqEnd = c->sendq;

  c->bytesDropped = 0;
}

static int closeClient(struct client *c) {
  if (c->fd == -1) {
    fprintf(stderr, "%d: called closeClient on closed client\n", c->listenPort);
  }
  disconnectFd(c->fd);

  c->fd = -1; // mark this client as disconnected

  emitTime(stderr);
  fprintf(stderr, "%d: disconnected\n", c->listenPort);
}


static void normalizeSendq(struct client *c)
{
  if (c->sendqEnd - c->sendq > c->sendqMax) {
    fprintf(stderr, "FATAL ringbuffer flaw uQuee9pa\n");
    exit(EXIT_FAILURE);
  }
  if (c->sendqEnd - c->sendq == c->sendqMax) {
    c->sendqEnd = c->sendq;
  }

  if (c->sendqStart - c->sendq > c->sendqMax) {
    fprintf(stderr, "FATAL ringbuffer flaw reeceSh3\n");
    exit(EXIT_FAILURE);
  }
  if (c->sendqStart - c->sendq == c->sendqMax) {
    c->sendqStart = c->sendq;
  }

  // always make sure we will have space to write CHUNK_CHANNEL_BYTES into the ringbuffer
  // drop half the buffer if necessary
  if (sendqLen(c) + 2 * CHUNK_CHANNEL_BYTES  >= c->sendqMax) {
    int dropBytes = c->sendqMax / 2 / CHUNK_CHANNEL_BYTES * CHUNK_CHANNEL_BYTES;
    c->bytesDropped += dropBytes;

    c->sendqEnd -= dropBytes;
    if (c->sendqEnd < c->sendq) {
      c->sendqEnd += c->sendqMax;
    }

    if (c->fd >= 0) {
      emitTime(stderr);
      fprintf(stderr, "%d: dropping %5.1f MBytes, total dropped MBytes on this port: %8lld\n", c->listenPort, dropBytes / (1024.0f * 1024.0f), c->bytesDropped / (1024 * 1024));
    }
  }
}

static int flushClient(struct client *c, int min, int limit)
{
  static int64_t byteCounter;
  int debug = 0;
  int toWrite = sendqLen(c);

  // nothing to do if we have nothing or too little to write
  if (toWrite < min || toWrite <= 0) {
    return 0;
  }

  if (c->sendqStart + toWrite > c->sendq + c->sendqMax) {
    // if the sendq wraps around, only send() the start located at the end of the buffer
    toWrite = c->sendq + c->sendqMax - c->sendqStart;
  }

  //fprintf(stderr, "toWrite %d\n", toWrite);

  if (toWrite > limit) {
      toWrite = limit;
  }

  int bytesWritten = send(c->fd, c->sendqStart, toWrite, MSG_NOSIGNAL);
  int err = errno;

  // If we get -1, it's only fatal if it's not EAGAIN/EWOULDBLOCK
  if (bytesWritten < 0 && (err == EAGAIN || err == EWOULDBLOCK)) {
    //fprintf(stderr, "block\n");
    return -2;
  }
  if (bytesWritten < 0) {
    // send error
    if (0) {
      emitTime(stderr);
      perror("send ");
    }
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
static int readClientFrequency(struct client *cl, uint32_t *freq) {
  uint32_t size = 0;
  if(ioctl(cl->fd, FIONREAD, &size) < 0) {
    perror("fionread");
    return -1;
  }
  if(size < sizeof(*freq)) {
    return 0;
  }
  if(recv(cl->fd, (char *)freq, sizeof(*freq), MSG_WAITALL) < 0) {
    perror("recv");
    return -1;
  }
  return 1;
}

int main(int argc, char *argv[])
{
  int fd, i;
  volatile void *cfg, *sts, *fifo;
  volatile uint8_t *rx_rst, *rx_sel;
  volatile uint16_t *rx_rate, *rx_cntr;
  volatile uint32_t *rx_freq;
  void *buffer;

  emitTime(stderr);
  fprintf(stderr, "startup\n");

  if (CHUNK_SAMPLES > FIFO_SAMPLES / 2) {
    fprintf(stderr, "chunk samples %d should be half or less of FIFO samples %d", CHUNK_SAMPLES, FIFO_SAMPLES);
    return -1;
  }

  //fprintf(stderr, "fifo samples %d\nchunk samples %d\n", FIFO_SAMPLES, CHUNK_SAMPLES);
  //fprintf(stderr, "chunk_channel_bytes %d\n", CHUNK_CHANNEL_BYTES);

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
  memset((void *) cfg, 0x0, sysconf(_SC_PAGESIZE));
  sts = malloc(sysconf(_SC_PAGESIZE));
  memset((void *) sts, 0x0, sysconf(_SC_PAGESIZE));
  fifo = malloc(FIFO_BYTES);
  memset((void *) fifo, 0xb, FIFO_BYTES);
  #endif

  rx_rst = (uint8_t *)(cfg + 0);
  rx_sel = (uint8_t *)(cfg + 1);
  rx_rate = (uint16_t *)(cfg + 2);
  rx_freq = (uint32_t *)(cfg + 4);

  rx_cntr = (uint16_t *)(sts + 0);

  struct client client_back[NUMCLIENTS];
  struct client *clients[NUMCLIENTS];
  for(i = 0; i < NUMCHANS; ++i) {
    clients[i] = &client_back[i];
    struct client *cl = clients[i];
    allocateClient(cl, TOTAL_NET_BUFFER / NUMCHANS);
    cl->format = CS16;
    cl->channel = i;
    listenClient(cl, TCP_PORT + i);
    // for simplicity: one connection per listen port
  }
  for(i = NUMCHANS; i < 2 * NUMCHANS; ++i) {
    clients[i] = &client_back[i];
    struct client *cl = clients[i];
    allocateClient(cl, TOTAL_NET_BUFFER / 4 / NUMCHANS); // less buffer for CU8 outputs
    cl->format = CU8;
    cl->channel = i - NUMCHANS;
    listenClient(cl, TCP_PORT_CU8 + (i - NUMCHANS));
    // for simplicity: one connection per listen port
  }

  setPriority(); // set high priority

  signal(SIGINT, signal_handler);
  signal(SIGTERM, signal_handler);
  signal(SIGHUP, signal_handler);
  signal(SIGQUIT, signal_handler);

  *rx_rst &= ~1;
  *rx_sel = 0;
  *rx_rate = 1280;
  for(i = 0; i < NUMCHANS; ++i)
  {
    rx_freq[i] = (uint32_t)floor(600000 / 122.88e6 * (1 << PHASE_BITS) + 0.5);
  }

  *rx_rst |= 1;

  struct timespec watch;
  startWatch(&watch);
  int64_t last_iteration_us = 0;
  int64_t recvTime = 0;
  int64_t readTime = 0;
  int64_t flushTime = 0;
  int64_t sleepTime = 0;
  int64_t nextNetworkMaintenance = 0;
  int64_t now = 0;
  while(!interrupted)
  {
    int doneSomething = 0;

    #ifdef TEST
    // simulate 25 MByte/s
    *rx_cntr += 25 * last_iteration_us / SAMPLE_SIZE;
    #endif

    int rx_samples = *rx_cntr;

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
      //fprintf(stderr, "rx_samples %6d > chunk samples %6d\n", rx_samples, CHUNK_SAMPLES);
      doneSomething = 1;

      memcpy(buffer, (void *) fifo, CHUNK_BYTES);

      for(int id = 0; id < NUMCLIENTS; id++) {
        struct client *cl = clients[id];
        if (cl->fd == -1) {
          continue;
        }

        if (cl->format == CU8) {
          int16_t *src = (int16_t *) buffer;
          uint8_t *target = (uint8_t *) cl->sendqEnd;
          int t = 0;
          for (int k = cl->channel; k < CHUNK_BYTES / SAMPLE_SIZE; k += NUMCHANS) {
            target[t++] = (uint8_t) ((src[2 * k + 0] >> 8) + 127);
            target[t++] = (uint8_t) ((src[2 * k + 1] >> 8) + 127);
          }
          cl->sendqEnd += t;
          if (t != CHUNK_CHANNEL_BYTES / 2) {
            fprintf(stderr, "CU8 to sendq: %d should be: %d\n", t, CHUNK_CHANNEL_BYTES / 2);
            exit(EXIT_FAILURE);
          }
        } else if (cl->format == CS16) {
          if (SAMPLE_SIZE != 4) {
            fprintf(stderr, "incompatible sample size\n");
            exit(EXIT_FAILURE);
          }

          uint32_t *src = (uint32_t *) buffer;
          uint32_t *target = (uint32_t *) cl->sendqEnd;
          int t = 0;
          for (int k = cl->channel; k < CHUNK_BYTES / SAMPLE_SIZE; k += NUMCHANS) {
            target[t++] = src[k];
          }
          int bytesCopied = t * SAMPLE_SIZE;
          cl->sendqEnd += bytesCopied;

          if (bytesCopied != CHUNK_CHANNEL_BYTES) {
            fprintf(stderr, "wrote wrong amount of bytes to sendq: %d should be: %d\n", bytesCopied, CHUNK_CHANNEL_BYTES);
            exit(EXIT_FAILURE);
          }
        }

        normalizeSendq(cl);
        //fprintf(stderr, "%d: sendq: %d\n", cl->listenPort, sendqLen(cl));
      }

      rx_samples -= CHUNK_SAMPLES;
      #ifdef TEST
      *rx_cntr -= CHUNK_SAMPLES;
      #endif
    }

    readTime = lapWatch(&watch);

    if (!doneSomething) {
      int sysCalls = 0;
      static int id;
      if (id == NUMCLIENTS) {
        id = 0;
      }
      for(; id < NUMCLIENTS && sysCalls < 3; id++) {
        struct client *cl = clients[id];
        if (cl->fd == -1) {
          continue;
        }
        //fprintf(stderr, "%d: sendq: %d\n", cl->listenPort, sendqLen(cl));
        // network packets are typically 1480 or 1500 bytes on a LAN
        // just assume 1450 for good measure
        // always send data equivalent to 6 packets per syscall
        int bytesWritten = flushClient(cl, 6 * 1450, 6 * 1450);

        if (bytesWritten == -1) {
          closeClient(cl);
          continue;
        }

        if (bytesWritten > 0) {
          sysCalls++;
        }
        if (bytesWritten == -2) {
          sysCalls++;
          // send was asked to send data but likely the OS buffer was full
        }
      }
      if (sysCalls > 0) {
        doneSomething = 1;
      }
    }

    flushTime = lapWatch(&watch);

    now = microtime();
    if (now > nextNetworkMaintenance) {
      //fprintf(stderr, "net maintenance\n");
      static int id;
      // do this every 100 ms
      if (id == NUMCLIENTS) {
        id = 0;
        nextNetworkMaintenance = now + 100 * 1000;
      }
      int sysCalls = 0;
      for(; id < NUMCLIENTS && sysCalls < 3; id++) {
        struct client *cl = clients[id];
        //fprintf(stderr, "cl->fd %d\n", cl->fd);
        if (cl->fd == -1) {
          sysCalls++;
          acceptClient(cl);
        }
        if (cl->fd == -1) {
          continue;
        }
        // disconnect new clients on the listen port, we already have a client
        // only one connection / client per channel is supported
        sysCalls++;
        acceptClientDiscard(cl);

        // only allow CS16 clients to set frequency
        // CU8 clients just get the current setting
        if (id > NUMCHANS) {
          continue;
        }

        sysCalls++;
        uint32_t freq;
        int res = readClientFrequency(cl, &freq);
        if (res < 0) {
          closeClient(cl);
          continue;
        }
        if (res > 0) {
          emitTime(stderr);
          /* set rx phase increment */
          fprintf(stderr, "%d: freq %d, phase %d\n", cl->listenPort, freq, (uint32_t)floor(freq / 122.88e6 * (1 << PHASE_BITS) + 0.5));
          rx_freq[cl->channel] = (uint32_t)floor(freq / 122.88e6 * (1 << PHASE_BITS) + 0.5);
        }
      }
      if (sysCalls > 0) {
        doneSomething = 1;
      }
    }

    recvTime = lapWatch(&watch);

    if (!doneSomething) {
      usleep(500);
    }

    sleepTime = lapWatch(&watch);

    last_iteration_us = recvTime + readTime + flushTime + sleepTime;

    if (0) {
      fprintf(stderr, "timers were: readTime %5lld flushTime %5lld recvTime %5lld sleepTime %5lld\n",
          readTime, flushTime, recvTime, sleepTime);
      lapWatch(&watch); // reset this so the printf time isn't awarded towards readtime
    }
  }

  emitTime(stderr);
  fprintf(stderr, "exiting\n");

  *rx_rst &= ~1;

  for(int id = 0; id < NUMCLIENTS; id++) {
    struct client *cl = clients[id];
    if (cl->fd >= 0) {
      closeClient(cl);
    }
    if (cl->listenFd >= 0) {
      disconnectFd(cl->listenFd);
      cl->listenFd = -1;
    }
  }

  return EXIT_SUCCESS;
}
