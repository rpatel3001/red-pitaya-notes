#!/usr/bin/env python3

import socket
import numpy as np
from struct import pack
import sys
import _thread
import argparse
from signal import signal, SIGINT

RX_DTYPE = np.int16  # Data type of received data
#RX_DTYPE = np.uint8  # Data type of received data

def read_and_separate_data(device_ip, device_port, device_freq, device_corr):
    # Open a socket to the device
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5)
        s.connect((device_ip, device_port))
        print(f"RX thread connected to {device_ip}:{device_port}")

        # Send the specific byte string to the receiver immediately after connecting
        connection_message = pack("<1I", int((1.0 + 1e-6 * device_corr) * device_freq))
        s.settimeout(None)
        s.sendall(connection_message)

        while True:
            # Read a chunk of interleaved data (buffer is always full due to MSG_WAITALL)
            data = s.recv(BUFFER_SIZE * 2 * np.dtype(RX_DTYPE).itemsize, socket.MSG_WAITALL)
            if not data:
                break  # Exit the loop if no data is received
            sys.stdout.buffer.write(bytes(data))

# Argument parser function
def parse_arguments():
    parser = argparse.ArgumentParser(description="TCP Client to receive SDR data")
    parser.add_argument('--server', '-s', type=str, default="localhost", help="Device IP or hostname (default: localhost)")
    parser.add_argument('--port', '-p', type=int, default=9000, help="Port to receive data from the device (default: 9000)")
    parser.add_argument('--freq', '-f', type=float, help="Center frequency in kHz (required)")
    parser.add_argument('--corr', '-c', type=float, default=0.0, help="PPM correction to apply to the center frequency")
    parser.add_argument('--buffer_size', '-b', type=int, default=1024, help="Size of each buffer (default: 1024)")
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
