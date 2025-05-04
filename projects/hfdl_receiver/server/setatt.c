#include <stdint.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#include <math.h>

// peri.c
int att_initial();
void att_cleanUp();
int set_att_value(uint8_t att_val);

int main(int argc, char **argv)
{
    if (argc != 2) {
        return 0;
    }

    int gaincode = 0;
    sscanf(argv[1], "%d", &gaincode);
    gaincode &= 0xff;

    float gain = gaincode * 0.055744 * (1+(6.079458)*(gaincode>>7?1:0));
    float gaindb = 20 * log10(gain);

    printf("gain code %d 0x%x ~0x%x is %f V/V\t%f dB\n", gaincode, gaincode, ~gaincode & 0xff, gain, gaindb);

    att_initial();

    set_att_value(gaincode);

    //att_cleanUp();
    return 0;
}

void w0(FILE* f) {
    fprintf(f, "0\n");
}

void w1(FILE* f) {
    fprintf(f, "1\n");
}

void w(FILE* f, int val) {
    //printf("wrote %d\n", val);
    if(val) {
        w1(f);
    } else {
        w0(f);
    }
}

int main2(int argc, char **argv)
{
    if (argc != 3) {
        return 0;
    }

    char gainrange = 'l';
    int gaincode = 0;
    sscanf(argv[1], "%c", &gainrange);
    sscanf(argv[2], "%d", &gaincode);

    float gain = gaincode * 0.055744 * (1+(6.079458)*(gainrange=='h'?1:0));
    float gaindb = 20 * log10(gain);

    if (gainrange == 'h') {
        gaincode |= 0x80;
    }

    printf("gain code %d 0x%x ~0x%x is %f V/V\t%f dB\n", gaincode, gaincode, ~gaincode & 0xff, gain, gaindb);

    // export GPIOs
    FILE* gpioex = fopen("/sys/class/gpio/export", "w");
    setbuf(gpioex, NULL);
    fprintf(gpioex, "523\n");
    fprintf(gpioex, "524\n");
    fprintf(gpioex, "525\n");
    fclose(gpioex);

    // set GPIO directions
    FILE* data_dir = fopen("/sys/class/gpio/gpio523/direction", "w");
    FILE* ltch_dir = fopen("/sys/class/gpio/gpio524/direction", "w");
    FILE* clck_dir = fopen("/sys/class/gpio/gpio525/direction", "w");

    setbuf(data_dir, NULL);
    setbuf(ltch_dir, NULL);
    setbuf(clck_dir, NULL);

    fprintf(data_dir, "out\n");
    fprintf(ltch_dir, "out\n");
    fprintf(clck_dir, "out\n");

    // open GPIOs
    FILE* data = fopen("/sys/class/gpio/gpio523/value", "w");
    FILE* ltch = fopen("/sys/class/gpio/gpio524/value", "w");
    FILE* clck = fopen("/sys/class/gpio/gpio525/value", "w");

    setbuf(data, NULL);
    setbuf(ltch, NULL);
    setbuf(clck, NULL);

    struct timespec ts = {0, 50};

    w0(clck);
    nanosleep(&ts, NULL);
    w1(clck);
    nanosleep(&ts, NULL);
    w0(ltch);

    for (int i = 7; i >= 0; i--) {
        w0(clck);
        w(data, (~gaincode >> i) & 1);
        nanosleep(&ts, NULL);
        w1(clck);
        nanosleep(&ts, NULL);
    }

    w1(ltch);

    // close GPIOs
    fclose(data);
    fclose(ltch);
    fclose(clck);

    // unexport GPIOs
    FILE* gpiounex = fopen("/sys/class/gpio/unexport", "w");
    setbuf(gpiounex, NULL);
    fprintf(gpiounex, "523\n");
    fprintf(gpiounex, "524\n");
    fprintf(gpiounex, "525\n");
    fclose(gpiounex);
    return 0;
}
