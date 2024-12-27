#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

//************ADC Att Driver***********
#define GPIO_BASE_ADDR 512
#define ATTN_DATA_ADDR 11
#define ATTN_CLK_ADDR 13
#define ATTN_LE_ADDR 12

#define OUTPUT "out"
#define LOW "0"
#define HIGH "1"

static FILE *handlers[1024];

static void pinMode(uint32_t pin_num, char *mode)
{
    FILE *sysfs_export;
    FILE *sysfs_direction;
    char path[40] = "";
    char pin[10];
    sprintf(pin, "%d", pin_num);
    sysfs_export = fopen("/sys/class/gpio/export", "w");
    fwrite(pin, 1, sizeof(pin), sysfs_export);
    fclose(sysfs_export);

    strcpy(path, "/sys/class/gpio/gpio");
    strcat(path, pin);
    strcat(path, "/direction");

    sysfs_direction = fopen(path, "w");
    fwrite(mode, 1, strlen(mode), sysfs_direction);
    fclose(sysfs_direction);

    strcpy(path, "/sys/class/gpio/gpio");
    strcat(path, pin);
    strcat(path, "/value");

    handlers[pin_num] = fopen(path, "w");
}

static void digitalWrite(uint32_t pin_num, char *value)
{
    fwrite(value, 1, 1, handlers[pin_num]);
}

void att_cleanUp()
{
    char pin[10];
    int pins[] = {GPIO_BASE_ADDR + ATTN_DATA_ADDR, GPIO_BASE_ADDR + ATTN_CLK_ADDR, GPIO_BASE_ADDR + ATTN_LE_ADDR};
    
    FILE *sysfs_unexport = fopen("/sys/class/gpio/unexport", "w");
    for (int i = 0; i < 3; i++) {
        int pin_num = pins[i];
        fclose(handlers[pin_num]);
        sprintf(pin, "%d", pin_num);
        fwrite(pin, 1, strlen(pin), sysfs_unexport);
    }

    fclose(sysfs_unexport);
}

int att_initial()
{
    pinMode((GPIO_BASE_ADDR + ATTN_DATA_ADDR), OUTPUT);
    pinMode((GPIO_BASE_ADDR + ATTN_CLK_ADDR), OUTPUT);
    pinMode((GPIO_BASE_ADDR + ATTN_LE_ADDR), OUTPUT);
    fprintf(stderr, "attenuator initialize succeed.\n");
}

int set_att_value(uint8_t att_val)
{
    uint8_t loop_cnt;
    digitalWrite((GPIO_BASE_ADDR + ATTN_CLK_ADDR), LOW);
    digitalWrite((GPIO_BASE_ADDR + ATTN_LE_ADDR), LOW);
    for (loop_cnt = 0; loop_cnt < 6; loop_cnt++)
    {
        if ((att_val >> (5 - loop_cnt)) & 0x01 == 0x01)
        {
            digitalWrite((GPIO_BASE_ADDR + ATTN_DATA_ADDR), HIGH);
        }
        else
        {
            digitalWrite((GPIO_BASE_ADDR + ATTN_DATA_ADDR), LOW);
        }
        usleep(5);
        digitalWrite((GPIO_BASE_ADDR + ATTN_CLK_ADDR), HIGH);
        usleep(5);
        digitalWrite((GPIO_BASE_ADDR + ATTN_CLK_ADDR), LOW);
    }
    usleep(50);
    digitalWrite((GPIO_BASE_ADDR + ATTN_LE_ADDR), HIGH);
    fprintf(stderr, "Set attenuator to %d\n", att_val);
    return 0;
}