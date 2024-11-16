create_clock -period 8.000 -name adc_clk -waveform {0.000 4.000} [get_ports adc_clk_p_i]

#set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

set_input_delay -clock [get_clocks adc_clk] -min -add_delay 1.300 [get_ports {adc_dat_a_i[*]}]
set_input_delay -clock [get_clocks adc_clk] -max -add_delay 4.000 [get_ports {adc_dat_a_i[*]}]
