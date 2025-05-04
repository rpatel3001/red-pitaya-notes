CFLAGS = -g -O3 -march=armv7-a -mtune=cortex-a9 -mfpu=neon -mfloat-abi=hard

all: hfdl-receiver setatt

hfdl-receiver: hfdl-receiver.c peri.c
	gcc $(CFLAGS) -o $@ $^ -lm

setatt: setatt.c peri.c
	gcc $(CFLAGS) -o $@ $^ -lm

clean:
	rm -f hfdl-receiver setatt
