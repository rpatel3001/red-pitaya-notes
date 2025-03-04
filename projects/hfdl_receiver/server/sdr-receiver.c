#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <fcntl.h>
#include <math.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>

#define NUMCHANS 12
#define TCP_PORT 1001

#define FIFO_WORDS 32768

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

int64_t microtime(void) {
    struct timeval tv;
    int64_t mst;

    gettimeofday(&tv, NULL);
    mst = ((int64_t) tv.tv_sec) * 1000LL * 1000LL;
    mst += tv.tv_usec;
    return mst;
}

#define CHUNK_SIZE (NUMCHANS * 2 * 2 * 256)
// send q must be multiple of chunkSize
// writes into send q must always be exactly chunkSize big
#define SENDQ_MAX (8 * 1024 * 1024 / CHUNK_SIZE * CHUNK_SIZE)
struct client
{
  int fd; // File descriptor
  unsigned char *sendqStart;
  unsigned char *sendqEnd; // where the data in the sendQ starts
  unsigned char sendq[SENDQ_MAX];  // Write buffer - allocated later
  int64_t last_flush;
  int64_t last_send;
};

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

static int flushClient(struct client *c)
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

  int bytesWritten = send(c->fd, c->sendqStart, toWrite, MSG_NOSIGNAL);
  int err = errno;

  // If we get -1, it's only fatal if it's not EAGAIN/EWOULDBLOCK
  if (bytesWritten < 0 && (err == EAGAIN || err == EWOULDBLOCK)) {
    //printf("block\n");
    return 0;
  }
  if (bytesWritten < 0) {
    // send error
    perror("send ");
    return -1;
  }
  if (bytesWritten > 0) {
    // Advance buffer
    c->sendqStart += bytesWritten;
    normalizeSendq(c);
  }

  //printf("sent %d\n", bytesWritten);
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
  uint64_t us, usp;

  if (CHUNK_SIZE/4 > FIFO_WORDS / 2) {
    printf("chunk size / 4 %d should be less than half of full FIFO size %d", CHUNK_SIZE/4, FIFO_WORDS);
    return -1;
  }

  int chunkSize = CHUNK_SIZE;

  printf("\nfifo words %d\nchunk bytes %d\nqueue bytes %d\n", FIFO_WORDS, CHUNK_SIZE, SENDQ_MAX);

  struct client *cl = malloc(sizeof(struct client));
  if (cl == NULL) {
    perror("malloc");
    return EXIT_FAILURE;
  }

  if((buffer = malloc(chunkSize)) == NULL)
  {
    perror("malloc");
    return EXIT_FAILURE;
  }

  if((fd = open("/dev/mem", O_RDWR)) < 0)
  {
    perror("open");
    return EXIT_FAILURE;
  }

  cfg = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x40000000);
  sts = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x41000000);
  fifo = mmap(NULL, 32*sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x42000000);

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

  while(!interrupted)
  {
    *rx_rst &= ~1;
    *rx_sel = 0;
    *rx_rate = 1280;
    for(i = 0; i < NUMCHANS; ++i)
    {
      rx_freq[i] = (uint32_t)floor(600000 / 122.88e6 * (1 << 30) + 0.5);
    }

    if((sock_client = accept(sock_server, NULL, NULL)) < 0)
    {
      perror("accept");
      return EXIT_FAILURE;
    }

    initClient(cl, sock_client);

    int64_t bytesDropped = 0;

    signal(SIGINT, signal_handler);

    *rx_rst |= 1;

    while(!interrupted)
    {
      usp = us;
      us = microtime();
      if(ioctl(sock_client, FIONREAD, &size) < 0) {
        fprintf(stderr, "fionread break\n");
        break;
      }
      if(size >= sizeof(struct control))
      {
        if(recv(sock_client, (char *)&ctrl, sizeof(struct control), MSG_WAITALL) < 0) {
          fprintf(stderr, "recv break\n");
          break;
        }

        /* set inputs */
        *rx_sel = ctrl.inps & 0xff;

        /* set rx sample rate */
        *rx_rate = rates[ctrl.rate & 3];

        /* set rx phase increments */
        for(i = 0; i < NUMCHANS; ++i)
        {
          rx_freq[i] = (uint32_t)floor(ctrl.freq[i] / 122.88e6 * (1 << 30) + 0.5);
        }
      }

      if(*rx_cntr >= FIFO_WORDS)
      {
        printf("reset %lld\n", us-usp);
        *rx_rst &= ~1;
        *rx_rst |= 1;
      }

      if(*rx_cntr >= chunkSize/4)
      {
        //printf("send %d\n", *rx_cntr);
        if(sendqLen(cl) + chunkSize >= SENDQ_MAX) {
          bytesDropped += chunkSize;
          static int64_t antiSpam;
          int64_t now = microtime();
          if (now > antiSpam) {
            fprintf(stderr, "dropped kBytes: %9.0f\n", bytesDropped / 1024.0);
            antiSpam = now + 10 * 1000 * 1000LL;
          }
          // sendq is full, drop this chunk by ??? reading from the fifo ???
          // the var buffer is not used anymore except to discard the data
          memcpy(buffer, fifo, chunkSize);
        } else {
          // copy chunk into the sendq
          memcpy(cl->sendqEnd, fifo, chunkSize);
          // advance buffer
          cl->sendqEnd += chunkSize;
          normalizeSendq(cl);
        }
      }
      else
      {
        usleep(500);
      }

      if (flushClient(cl) < 0) {
        break;
      }
    }

    if (!interrupted) {
      fprintf(stderr, "disconnected\n");
    }

    signal(SIGINT, SIG_DFL);
    close(sock_client);
  }

  *rx_rst &= ~1;

  close(sock_server);

  return EXIT_SUCCESS;
}
