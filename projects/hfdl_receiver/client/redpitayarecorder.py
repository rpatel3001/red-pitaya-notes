#!/usr/bin/env python3

import socket
from struct import pack
import sys
import _thread
import argparse
from signal import signal, SIGINT
import time
import math
import traceback

SAMPLE_SIZE=4  # Sample size of received data (CS16)

previousLogMsg = None
previousLogTime = 0

# omit duplicate log messages within 10 seconds
logDedupTime = 10

def log(msg):
    global previousLogMsg
    global previousLogTime
    now = time.time()
    milliseconds = math.floor(math.modf(now)[0] * 1000)
    timestamp = (
            time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime())
            + ".{0:03.0f}Z ".format(milliseconds)
            )

    if isinstance(msg, list):
        msg = ''.join(msg)

    if not isinstance(msg, str):
        msg = str(msg)

    if not msg.endswith('\n'):
        msg += '\n'

    if now < previousLogTime + logDedupTime and msg == previousLogMsg:
        return

    previousLogMsg = msg
    previousLogTime = now
    sys.stderr.write(timestamp + msg)

def read_and_separate_data(device_ip, device_port, device_freq, device_corr):
    # Open a socket to the device
    lastConnect = 0
    while True:
        # general network timeout and minimum time between trying to connect
        timeout = 1
        elapsed = time.time() - lastConnect
        if elapsed < timeout:
            time.sleep(timeout - elapsed)
        lastConnect = time.time()
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.settimeout(timeout)
                s.connect((device_ip, device_port))

                # set a timeout for receive (and send for good measure)
                # timeval is a struct composed of seconds and microseconds both as 64bit values
                timeval = pack("<qq", 2, 0 * 1000)
                s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVTIMEO, timeval)
                s.setsockopt(socket.SOL_SOCKET, socket.SO_SNDTIMEO, timeval)
                # setting this timeout is important for major network issues like a sudden
                # unplugging of the newtork cable
                # if it is not set, send and receive can apparently block indefinitely (in python?)

            except OSError as e:
                log([f"connect to {device_ip}:{device_port}: "] + traceback.format_exception_only(e))
                continue
            except Exception as e:
                log([f"connect to {device_ip}:{device_port}: "]+ traceback.format_exception(e))
                break

            try:
                s.settimeout(None) # necessary for socket.MSG_WAITALL
                log(f"RX thread connected to {device_ip}:{device_port}")

                # Send the specific byte string to the receiver immediately after connecting
                connection_message = pack("<1I", int((1.0 + 1e-6 * device_corr) * device_freq))
                s.sendall(connection_message)

                bufSize = BUFFER_SIZE * SAMPLE_SIZE
                buf = bytearray(bufSize)

                while True:
                    result = s.recv_into(buf, bufSize, socket.MSG_WAITALL)
                    if result != bufSize:
                        break # Exit the loop if less than a full chunk is received

                    sys.stdout.buffer.write(buf)

            except OSError as e:
                #log(traceback.format_exception_only(e))
                pass
            except Exception as e:
                log(traceback.format_exception(e))
                break
        log(f"RX thread disconnected from {device_ip}:{device_port}")

# Argument parser function
def parse_arguments():
    parser = argparse.ArgumentParser(description="TCP Client to receive SDR data")
    parser.add_argument('--server', '-s', type=str, default="localhost", help="Device IP or hostname (default: localhost)")
    parser.add_argument('--port', '-p', type=int, default=9000, help="Port to receive data from the device (default: 9000)")
    parser.add_argument('--freq', '-f', type=float, help="Center frequency in kHz (required)")
    parser.add_argument('--corr', '-c', type=float, default=0.0, help="PPM correction to apply to the center frequency")
    parser.add_argument('--buffer_size', '-b', type=int, default=4096, help="Size of each buffer (default: 4096, unit: samples)")
    return parser.parse_known_args()[0]

if __name__ == '__main__':
    def signal_handler(signal, frame):
        sys.exit()
    signal(SIGINT, signal_handler)

    # Parse arguments
    args = parse_arguments()
    log(args)

    # Set global variables from arguments
    DEVICE_IP = args.server
    DEVICE_PORT = args.port
    DEVICE_FREQ = args.freq * 1000
    DEVICE_CORR = args.corr
    BUFFER_SIZE = args.buffer_size

    # Start the data stream
    read_and_separate_data(DEVICE_IP, DEVICE_PORT, DEVICE_FREQ, DEVICE_CORR)
