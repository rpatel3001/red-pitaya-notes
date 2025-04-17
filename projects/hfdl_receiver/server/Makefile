CFLAGS = -g -O3 -march=armv7-a -mtune=cortex-a9 -mfpu=neon -mfloat-abi=hard

all: hfdl-receiver

hfdl-receiver: hfdl-receiver.c
	gcc $(CFLAGS) -o $@ $^ -lm

clean:
	rm -f hfdl-receiver
