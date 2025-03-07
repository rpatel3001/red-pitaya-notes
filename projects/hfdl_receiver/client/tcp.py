import socket
import numpy as np
import threading
import queue
import argparse
import time
import _thread
from struct import pack, unpack
from signal import signal, SIGINT
from select import select

# Constants
RX_DTYPE = np.int16  # Data type of received data
TX_DTYPE = np.int16  # Data type of transmitted data

new_freq = True

# Receiver thread function to read and separate data into channels
def read_and_separate_data(device_ip, device_port):
    global new_freq

    write_index = 0  # Track the index of the buffer being written to

    # Open a socket to the device
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5)
        s.connect((device_ip, device_port))
        s.settimeout(None)
        print(f"RX thread connected to {device_ip}:{device_port}")

        while True:
            if new_freq:
                new_freq = False
                # Send the specific byte string to the receiver immediately after connecting
                connection_message = pack(f"<{len(freqs)+2}I", 0, 0, *[int(f) for f in freqs])
                s.sendall(connection_message)
            # Read a chunk of interleaved data (buffer is always full due to MSG_WAITALL)
            data = s.recv(BUFFER_SIZE * NUM_CHANNELS * 2 * np.dtype(RX_DTYPE).itemsize, socket.MSG_WAITALL)
            if not data:
                break  # Exit the loop if no data is received

            # Convert the data to a numpy array of integers (assuming 16-bit data for this example)
            data_array = np.frombuffer(data, dtype=RX_DTYPE)
            real_buffers[write_index][:] = data_array[0::2]
            imag_buffers[write_index][:] = data_array[1::2]

            # Split the interleaved data into separate channels and fill the corresponding real and imaginary buffers
            for i in range(NUM_CHANNELS):
                # Once the buffer is full, push it to the queue and move to the next buffer
                buffer_queues[i].put(write_index)
            write_index = (write_index + 1) % NUM_BUFFERS

# Transmit thread function to send data over a socket for each channel
def transmit_channel_data(channel_idx, transmit_port):
    global new_freq

    while True:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind(('0.0.0.0', transmit_port + channel_idx))  # Bind to a unique port per channel
            s.setblocking(False)
            s.listen(0)
            print(f"Channel {channel_idx} waiting for a connection on port {transmit_port + channel_idx}")

            try:
                while True:
                    rdy, _, _ = select([s], [], [], 0)
                    if rdy:
                        # Accept a client connection
                        conn, addr = s.accept()
                        print(f"Channel {channel_idx} connected to {addr}")
                        break
                    else:
                        while not buffer_queues[channel_idx].empty():
                            buffer_queues[channel_idx].get_nowait()

                with conn:
                    # Send the RTL0 header to the connected client
                    RTL_HEADER = b"RTL0\x00\x00\x00\x00\x00\x00\x00\x00"  # RTL0 header to send on connect
                    conn.sendall(RTL_HEADER)
                    print(f"Channel {channel_idx} sent header to {addr}")

                    interleaved = np.zeros((BUFFER_SIZE * np.dtype(RX_DTYPE).itemsize,), dtype=RX_DTYPE)
                    interleaved2 = np.zeros((BUFFER_SIZE * np.dtype(RX_DTYPE).itemsize,), dtype=TX_DTYPE)
                    while True:
                        rdy, _, _ = select([conn], [], [], 0)
                        if rdy:
                            freqs[channel_idx] = unpack("<1I", conn.recv(4, socket.MSG_WAITALL))[0]
                            print(f"Channel {channel_idx} set to frequency {freqs[channel_idx]}")
                            new_freq = True

                        # Wait for a full buffer index to be pushed to the queue (with timeout)
                        try:
                            buffer_idx = buffer_queues[channel_idx].get(timeout=1)

                            # Send the buffer's data over the socket
                            interleaved[0::2] = real_buffers[buffer_idx][channel_idx::NUM_CHANNELS]
                            interleaved[1::2] = imag_buffers[buffer_idx][channel_idx::NUM_CHANNELS]
                            #interleaved = interleaved / 2**6 * 127.5 + 127.5
                            interleaved2 = (interleaved).astype(TX_DTYPE).tobytes()
                            conn.sendall(interleaved2)

                        except queue.Empty:
                            # Don't print when the queue times out
                            print(f"Empty queue in channel {channel_idx}")
                        except ValueError as e:
                            print(f"value error: {e}")
                            break

            except (socket.error, OSError) as e:
                print(f"Channel {channel_idx} connection error: {e}. Re-listening...")

# Main function to start the receiver and transmit threads
def start_data_stream(device_ip, device_port, transmit_port):
    global real_buffers, imag_buffers, buffer_queues

    # Initialize buffers and queues based on the arguments passed
    real_buffers = [np.zeros(BUFFER_SIZE * NUM_CHANNELS, dtype=RX_DTYPE) for _ in range(NUM_BUFFERS)]
    imag_buffers = [np.zeros(BUFFER_SIZE * NUM_CHANNELS, dtype=RX_DTYPE) for _ in range(NUM_BUFFERS)]

    buffer_queues = [queue.Queue() for _ in range(NUM_CHANNELS)]

    # Start the receiver thread to read and separate data into channels
    receiver_thread = threading.Thread(target=read_and_separate_data, args=(device_ip, device_port))
    receiver_thread.daemon = True  # Daemonize thread to exit when the main program exits
    receiver_thread.start()

    # Start the transmit threads for each channel
    transmit_threads = []
    for i in range(NUM_CHANNELS):
        transmit_thread = threading.Thread(target=transmit_channel_data, args=(i, transmit_port))
        transmit_thread.daemon = True  # Daemonize thread to exit when the main program exits
        transmit_thread.start()
        transmit_threads.append(transmit_thread)

    # Wait for the receiver thread to finish
    receiver_thread.join()

# Argument parser function
def parse_arguments():
    parser = argparse.ArgumentParser(description="TCP Client to receive and transmit interleaved SDR data")
    parser.add_argument('--device', '-d', type=str, default="web-888.lan", help="Device IP or hostname (default: web-888.lan)")
    parser.add_argument('--receive_port', '-r', type=int, default=1001, help="Port to receive data from the device (default: 1001)")
    parser.add_argument('--transmit_port', '-t', type=int, default=9000, help="Base port for transmitting data (default: 9000)")
    parser.add_argument('--buffer_size', '-b', type=int, default=1024, help="Size of each buffer (default: 1024)")
    parser.add_argument('--num_channels', '-n', type=int, default=13, help="Number of channels (default: 13)")
    parser.add_argument('--num_buffers', '-m', type=int, default=10, help="Number of buffers per channel (default: 10)")
    return parser.parse_args()

if __name__ == '__main__':
    def signal_handler(signal, frame):
        _thread.interrupt_main()
    signal(SIGINT, signal_handler)

    # Parse arguments
    args = parse_arguments()

    # Set global variables from arguments
    DEVICE_IP = args.device
    DEVICE_PORT = args.receive_port
    TRANSMIT_PORT = args.transmit_port
    BUFFER_SIZE = args.buffer_size
    NUM_CHANNELS = args.num_channels
    NUM_BUFFERS = args.num_buffers
    freqs = [1000000]*NUM_CHANNELS

    # Start the data stream
    start_data_stream(DEVICE_IP, DEVICE_PORT, TRANSMIT_PORT)
