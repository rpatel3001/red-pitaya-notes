from scipy.io.wavfile import read
import matplotlib.pyplot as plt
from sys import argv

# read audio samples
input_data = []
for i in range(8):
  input_data += read(f"{i}.wav")
audio = input_data[1]
# plot the first 1024 samples
plt.plot(audio)
# label the axes
plt.ylabel("Amplitude")
plt.xlabel("Time")
# set the title
plt.title("Sample Wav")
# display the plot
plt.show()
