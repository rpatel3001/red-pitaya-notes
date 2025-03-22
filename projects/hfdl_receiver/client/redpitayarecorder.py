#!/usr/bin/env python3

import socket
from struct import pack
import sys
import _thread
import argparse
from signal import signal, SIGINT
from time import sleep

SAMPLE_SIZE=4  # Sample size of received data (CS16)

def read_and_separate_data(device_ip, device_port, device_freq, device_corr):
    # Open a socket to the device
    while True:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.connect((device_ip, device_port))
                print(f"RX thread connected to {device_ip}:{device_port}")

                # Send the specific byte string to the receiver immediately after connecting
                connection_message = pack("<1I", int((1.0 + 1e-6 * device_corr) * device_freq))
                s.sendall(connection_message)

                while True:
                    # Read a chunk of interleaved data (buffer is always full due to MSG_WAITALL)
                    data = s.recv(BUFFER_SIZE * SAMPLE_SIZE, socket.MSG_WAITALL)
                    if len(data) < BUFFER_SIZE * SAMPLE_SIZE:
                        s.close()
                        break  # Exit the loop if less than a full chunk is received
                    sys.stdout.buffer.write(bytes(data))
            except ConnectionRefusedError as e:
                sleep(1)
                pass
            except ConnectionResetError as e:
                sleep(1)
                pass
            except Exception as e:
                print(e)
                break

# Argument parser function
def parse_arguments():
    parser = argparse.ArgumentParser(description="TCP Client to receive SDR data")
    parser.add_argument('--server', '-s', type=str, default="localhost", help="Device IP or hostname (default: localhost)")
    parser.add_argument('--port', '-p', type=int, default=9000, help="Port to receive data from the device (default: 9000)")
    parser.add_argument('--freq', '-f', type=float, help="Center frequency in kHz (required)")
    parser.add_argument('--corr', '-c', type=float, default=0.0, help="PPM correction to apply to the center frequency")
    parser.add_argument('--buffer_size', '-b', type=int, default=1024, help="Size of each buffer (default: 1024, unit: samples)")
    return parser.parse_known_args()[0]

if __name__ == '__main__':
    def signal_handler(signal, frame):
        _thread.interrupt_main()
    signal(SIGINT, signal_handler)

    # Parse arguments
    args = parse_arguments()
    print(args)

    # Set global variables from arguments
    DEVICE_IP = args.server
    DEVICE_PORT = args.port
    DEVICE_FREQ = args.freq * 1000
    DEVICE_CORR = args.corr
    BUFFER_SIZE = args.buffer_size

    # Start the data stream
    read_and_separate_data(DEVICE_IP, DEVICE_PORT, DEVICE_FREQ, DEVICE_CORR)
