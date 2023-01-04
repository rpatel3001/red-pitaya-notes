# Create clk_wiz
cell xilinx.com:ip:clk_wiz pll_0 {
  PRIMITIVE PLL
  PRIM_IN_FREQ.VALUE_SRC USER
  PRIM_IN_FREQ 125.0
  PRIM_SOURCE Differential_clock_capable_pin
  CLKOUT1_USED true
  CLKOUT1_REQUESTED_OUT_FREQ 125.0
  USE_RESET false
} {
  clk_in1_p adc_clk_p_i
  clk_in1_n adc_clk_n_i
}

# Create processing_system7
cell xilinx.com:ip:processing_system7 ps_0 {
  PCW_IMPORT_BOARD_PRESET cfg/red_pitaya.xml
} {
  M_AXI_GP0_ACLK pll_0/clk_out1
}

# Create all required interconnections
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {
  make_external {FIXED_IO, DDR}
  Master Disable
  Slave Disable
} [get_bd_cells ps_0]

# Create xlconstant
cell xilinx.com:ip:xlconstant const_0

# Create proc_sys_reset
cell xilinx.com:ip:proc_sys_reset rst_0 {} {
  ext_reset_in const_0/dout
}

# Create axi_cfg_register
cell pavel-demin:user:axi_cfg_register cfg_0 {
  CFG_DATA_WIDTH 32
  AXI_ADDR_WIDTH 32
  AXI_DATA_WIDTH 32
}

# Create port_slicer
cell pavel-demin:user:port_slicer slice_0 {
  DIN_WIDTH 32 DIN_FROM 0 DIN_TO 0
} {
  din cfg_0/cfg_data
}

# Create port_slicer
cell pavel-demin:user:port_slicer slice_1 {
  DIN_WIDTH 32 DIN_FROM 1 DIN_TO 1
} {
  din cfg_0/cfg_data
}

# Create port_slicer
cell pavel-demin:user:port_slicer slice_2 {
  DIN_WIDTH 32 DIN_FROM 31 DIN_TO 16
} {
  din cfg_0/cfg_data
}

# Create axi_axis_writer
cell pavel-demin:user:axi_axis_writer writer_0 {
  AXI_DATA_WIDTH 32
} {
  aclk pll_0/clk_out1
  aresetn rst_0/peripheral_aresetn
}

# Create axis_data_fifo
cell xilinx.com:ip:axis_data_fifo fifo_0 {
  TDATA_NUM_BYTES.VALUE_SRC USER
  TDATA_NUM_BYTES 4
  FIFO_DEPTH 1024
  HAS_RD_DATA_COUNT true
} {
  S_AXIS writer_0/M_AXIS
  s_axis_aclk pll_0/clk_out1
  s_axis_aresetn slice_1/dout
}

# Create axis_dwidth_converter
cell xilinx.com:ip:axis_dwidth_converter conv_0 {
  S_TDATA_NUM_BYTES.VALUE_SRC USER
  S_TDATA_NUM_BYTES 4
  M_TDATA_NUM_BYTES 2
} {
  S_AXIS fifo_0/M_AXIS
  aclk pll_0/clk_out1
  aresetn slice_1/dout
}

# Create fir_compiler
cell xilinx.com:ip:fir_compiler fir_0 {
  DATA_WIDTH.VALUE_SRC USER
  DATA_WIDTH 16
  COEFFICIENTVECTOR {-1.6274649683e-08, -4.5065148664e-08, 2.0305016205e-10, 2.9493044465e-08, 1.6271813655e-08, 3.1105248515e-08, -3.8068062283e-09, -1.4483871726e-07, -8.2334421622e-08, 2.9910615264e-07, 2.9581419120e-07, -4.5053142436e-07, -6.8629526064e-07, 5.1895220668e-07, 1.2804330630e-06, -3.8983752837e-07, -2.0604851492e-06, -7.2846730255e-08, 2.9445123044e-06, 1.0016357432e-06, -3.7746961473e-06, -2.4903925695e-06, 4.3199285737e-06, 4.5539053870e-06, -4.2976578372e-06, -7.0905088621e-06, 3.4167366801e-06, 9.8580044675e-06, -1.4385639827e-06, -1.2473596054e-05, -1.7517320296e-06, 1.4446233123e-05, 6.0773416681e-06, -1.5245028169e-05, -1.1222258655e-05, 1.4399379062e-05, 1.6620173603e-05, -1.1622425517e-05, -2.1501543997e-05, 6.9268884378e-06, 2.4993985956e-05, -7.1908108703e-07, -2.6284255480e-05, -6.1678672638e-06, 2.4817987674e-05, 1.2523744759e-05, -2.0507636386e-05, -1.6910231183e-05, 1.3905701142e-05, 1.7907552566e-05, -6.2960502464e-06, -1.4437101137e-05, -3.4129588130e-07, 6.1153765101e-06, 3.5223525265e-06, 6.4236710076e-06, -6.1618279811e-07, -2.1312906731e-05, -1.0657897650e-05, 3.5412933614e-05, 3.1639889151e-05, -4.4532412601e-05, -6.2178241184e-05, 4.3873037862e-05, 1.0015462534e-04, -2.8763492663e-05, -1.4127817930e-04, -4.4463465054e-06, 1.7921261097e-04, 5.7428795381e-05, -2.0611197280e-04, -1.2902503140e-04, 2.1356900535e-04, 2.1467615955e-04, -1.9390804422e-04, -3.0631419461e-04, 1.4167240063e-04, 3.9284419849e-04, -5.5087641071e-05, -4.6127571189e-04, -6.2767324044e-05, 4.9845697753e-04, 2.0335563488e-04, -4.9326434820e-04, -3.5293413132e-04, 4.3886069739e-04, 4.9362714544e-04, -3.3492711386e-04, -6.0568521050e-04, 1.8908577607e-04, 6.7045018207e-04, -1.7376614310e-05, -6.7389096530e-04, -1.5663619355e-04, 6.1018780384e-04, 3.0428074347e-04, -4.8477890574e-04, -3.9567476956e-04, 3.1623467685e-04, 4.0480882228e-04, -1.3637975563e-04, -3.1527425329e-04, -1.1771641087e-05, 1.2587456013e-04, 7.8453079481e-05, 1.4478127619e-04, -1.3832466545e-05, -4.5569664464e-04, -2.2373571695e-04, 7.4331407200e-04, 6.5795984898e-04, -9.2547174968e-04, -1.2858766780e-03, 9.0823882852e-04, 2.0700409549e-03, -5.9653484503e-04, -2.9337028366e-03, -9.2566300332e-05, 3.7599467257e-03, 1.2149186496e-03, -4.3956295300e-03, -2.7842540569e-03, 4.6604615986e-03, 4.7586662340e-03, -4.3609916786e-03, -7.0302748135e-03, 3.3086243905e-03, 9.4194220520e-03, -1.3402194179e-03, -1.1674168414e-02, -1.6606315645e-03, 1.3474700301e-02, 5.7426503585e-03, -1.4443835009e-02, -1.0872486674e-02, 1.4154461192e-02, 1.6920446546e-02, -1.2137010300e-02, -2.3654286086e-02, 7.8710646517e-03, 3.0734358605e-02, -7.4480222828e-04, -3.7702738731e-02, -1.0059001555e-02, 4.3941284889e-02, 2.5854729503e-02, -4.8516690769e-02, -4.9238069400e-02, 4.9582918108e-02, 8.6528523576e-02, -4.1544312870e-02, -1.5756524402e-01, -5.8828337662e-03, 3.5267054851e-01, 5.4593364946e-01, 3.5267054851e-01, -5.8828337662e-03, -1.5756524402e-01, -4.1544312870e-02, 8.6528523576e-02, 4.9582918108e-02, -4.9238069400e-02, -4.8516690769e-02, 2.5854729503e-02, 4.3941284889e-02, -1.0059001555e-02, -3.7702738731e-02, -7.4480222828e-04, 3.0734358605e-02, 7.8710646517e-03, -2.3654286086e-02, -1.2137010300e-02, 1.6920446546e-02, 1.4154461192e-02, -1.0872486674e-02, -1.4443835009e-02, 5.7426503585e-03, 1.3474700301e-02, -1.6606315645e-03, -1.1674168414e-02, -1.3402194179e-03, 9.4194220520e-03, 3.3086243905e-03, -7.0302748135e-03, -4.3609916786e-03, 4.7586662340e-03, 4.6604615986e-03, -2.7842540569e-03, -4.3956295300e-03, 1.2149186496e-03, 3.7599467257e-03, -9.2566300332e-05, -2.9337028366e-03, -5.9653484503e-04, 2.0700409549e-03, 9.0823882852e-04, -1.2858766780e-03, -9.2547174968e-04, 6.5795984898e-04, 7.4331407200e-04, -2.2373571695e-04, -4.5569664464e-04, -1.3832466545e-05, 1.4478127619e-04, 7.8453079481e-05, 1.2587456013e-04, -1.1771641087e-05, -3.1527425329e-04, -1.3637975563e-04, 4.0480882228e-04, 3.1623467685e-04, -3.9567476956e-04, -4.8477890574e-04, 3.0428074347e-04, 6.1018780384e-04, -1.5663619355e-04, -6.7389096530e-04, -1.7376614310e-05, 6.7045018207e-04, 1.8908577607e-04, -6.0568521050e-04, -3.3492711386e-04, 4.9362714544e-04, 4.3886069739e-04, -3.5293413132e-04, -4.9326434820e-04, 2.0335563488e-04, 4.9845697753e-04, -6.2767324044e-05, -4.6127571189e-04, -5.5087641071e-05, 3.9284419849e-04, 1.4167240063e-04, -3.0631419461e-04, -1.9390804422e-04, 2.1467615955e-04, 2.1356900535e-04, -1.2902503140e-04, -2.0611197280e-04, 5.7428795381e-05, 1.7921261097e-04, -4.4463465054e-06, -1.4127817930e-04, -2.8763492663e-05, 1.0015462534e-04, 4.3873037862e-05, -6.2178241184e-05, -4.4532412601e-05, 3.1639889151e-05, 3.5412933614e-05, -1.0657897650e-05, -2.1312906731e-05, -6.1618279811e-07, 6.4236710076e-06, 3.5223525265e-06, 6.1153765101e-06, -3.4129588130e-07, -1.4437101137e-05, -6.2960502464e-06, 1.7907552566e-05, 1.3905701142e-05, -1.6910231183e-05, -2.0507636386e-05, 1.2523744759e-05, 2.4817987674e-05, -6.1678672638e-06, -2.6284255480e-05, -7.1908108703e-07, 2.4993985956e-05, 6.9268884378e-06, -2.1501543997e-05, -1.1622425517e-05, 1.6620173603e-05, 1.4399379062e-05, -1.1222258655e-05, -1.5245028169e-05, 6.0773416681e-06, 1.4446233123e-05, -1.7517320296e-06, -1.2473596054e-05, -1.4385639827e-06, 9.8580044675e-06, 3.4167366801e-06, -7.0905088621e-06, -4.2976578372e-06, 4.5539053870e-06, 4.3199285737e-06, -2.4903925695e-06, -3.7746961473e-06, 1.0016357432e-06, 2.9445123044e-06, -7.2846730255e-08, -2.0604851492e-06, -3.8983752837e-07, 1.2804330630e-06, 5.1895220668e-07, -6.8629526064e-07, -4.5053142436e-07, 2.9581419120e-07, 2.9910615264e-07, -8.2334421622e-08, -1.4483871726e-07, -3.8068062282e-09, 3.1105248515e-08, 1.6271813655e-08, 2.9493044465e-08, 2.0305016205e-10, -4.5065148664e-08, -1.6274649683e-08}
  COEFFICIENT_WIDTH 24
  QUANTIZATION Quantize_Only
  BESTPRECISION true
  FILTER_TYPE Interpolation
  INTERPOLATION_RATE 2
  NUMBER_CHANNELS 2
  NUMBER_PATHS 1
  SAMPLE_FREQUENCY 0.048
  CLOCK_FREQUENCY 125
  OUTPUT_ROUNDING_MODE Convergent_Rounding_to_Even
  OUTPUT_WIDTH 25
  M_DATA_HAS_TREADY true
  HAS_ARESETN true
} {
  S_AXIS_DATA conv_0/M_AXIS
  aclk pll_0/clk_out1
  aresetn slice_1/dout
}

# Create axis_subset_converter
cell xilinx.com:ip:axis_subset_converter subset_0 {
  S_TDATA_NUM_BYTES.VALUE_SRC USER
  M_TDATA_NUM_BYTES.VALUE_SRC USER
  S_TDATA_NUM_BYTES 4
  M_TDATA_NUM_BYTES 3
  TDATA_REMAP {tdata[23:0]}
} {
  S_AXIS fir_0/M_AXIS_DATA
  aclk pll_0/clk_out1
  aresetn slice_1/dout
}

# Create fir_compiler
cell xilinx.com:ip:fir_compiler fir_1 {
  DATA_WIDTH.VALUE_SRC USER
  DATA_WIDTH 24
  COEFFICIENTVECTOR {-1.5956605232e-08, -1.4027210574e-08, -1.1469474085e-08, -8.2836180146e-09, -4.4848080991e-09, -1.0407677321e-10, 4.8110008357e-09, 1.0195908361e-08, 1.5969094293e-08, 2.2032206221e-08, 2.8270672406e-08, 3.4554644949e-08, 4.0740313387e-08, 4.6671591588e-08, 5.2182174508e-08, 5.7097954686e-08, 6.1239781454e-08, 6.4426538826e-08, 6.6478510946e-08, 6.7220997028e-08, 6.6488130959e-08, 6.4126854274e-08, 6.0000985295e-08, 5.3995321744e-08, 4.6019709490e-08, 3.6013006137e-08, 2.3946865196e-08, 9.8292645898e-09, -6.2922976469e-09, -2.4328017293e-08, -4.4143482806e-08, -6.5557931595e-08, -8.8343132082e-08, -1.1222295444e-07, -1.3687368619e-07, -1.6192514079e-07, -1.8696259810e-07, -2.1152960516e-07, -2.3513165443e-07, -2.5724074395e-07, -2.7730081109e-07, -2.9473401721e-07, -3.0894784686e-07, -3.1934296990e-07, -3.2532180081e-07, -3.2629767448e-07, -3.2170454392e-07, -3.1100709153e-07, -2.9371113275e-07, -2.6937417944e-07, -2.3761601956e-07, -1.9812916099e-07, -1.5068897995e-07, -9.5163409297e-08, -3.1521998405e-08, 4.0155824245e-08, 1.1967345374e-07, 2.0671094052e-07, 3.0082010894e-07, 4.0142111114e-07, 5.0780055343e-07, 6.1911131812e-07, 7.3437418709e-07, 8.5248135465e-07, 9.7220189568e-07, 1.0921892320e-06, 1.2109906146e-06, 1.3270586133e-06, 1.4387645756e-06, 1.5444139913e-06, 1.6422636642e-06, 1.7305405697e-06, 1.8074622400e-06, 1.8712584962e-06, 1.9201943142e-06, 1.9525935870e-06, 1.9668635208e-06, 1.9615193811e-06, 1.9352092825e-06, 1.8867387042e-06, 1.8150943962e-06, 1.7194673338e-06, 1.5992743742e-06, 1.4541782669e-06, 1.2841056739e-06, 1.0892628669e-06, 8.7014877882e-07, 6.2756510963e-07, 3.6262320741e-07, 7.6747475520e-08, -2.2832491072e-07, -5.5054815637e-07, -8.8757600555e-07, -1.2367739979e-06, -1.5952358658e-06, -1.9598040633e-06, -2.3270943647e-06, -2.6935244141e-06, -3.0553460519e-06, -3.4086811865e-06, -3.7495609242e-06, -4.0739676135e-06, -4.3778794099e-06, -4.6573169136e-06, -4.9083913879e-06, -5.1273540235e-06, -5.3106456767e-06, -5.4549464756e-06, -5.5572246687e-06, -5.6147840662e-06, -5.6253094176e-06, -5.5869090670e-06, -5.4981542305e-06, -5.3581142599e-06, -5.1663872742e-06, -4.9231255797e-06, -4.6290553358e-06, -4.2854899774e-06, -3.8943369612e-06, -3.4580974711e-06, -2.9798587931e-06, -2.4632791492e-06, -1.9125648688e-06, -1.3324398685e-06, -7.2810750670e-07, -1.0520498256e-07, 5.3024945391e-07, 1.1719161057e-06, 1.8131997731e-06, 2.4473214626e-06, 3.0673951871e-06, 3.6665090930e-06, 4.2378100594e-06, 4.7745908391e-06, 5.2703787377e-06, 5.7190247651e-06, 6.1147921466e-06, 6.4524430401e-06, 6.7273222820e-06, 6.9354369744e-06, 7.0735307280e-06, 7.1391513965e-06, 7.1307111696e-06, 7.0475379464e-06, 6.8899169725e-06, 6.6591218089e-06, 6.3574337970e-06, 5.9881492925e-06, 5.5555740719e-06, 5.0650044462e-06, 4.5226947708e-06, 3.9358111968e-06, 3.3123716776e-06, 2.6611724198e-06, 1.9917011434e-06, 1.3140377019e-06, 6.3874279225e-07, -2.3264333924e-08, -6.6083807074e-07, -1.2627473117e-06, -1.8178235389e-06, -2.3151145785e-06, -2.7440423186e-06, -3.0945625625e-06, -3.3573250902e-06, -3.5238319147e-06, -3.5865916620e-06, -3.5392679602e-06, -3.3768197153e-06, -3.0956311575e-06, -2.6936295845e-06, -2.1703887919e-06, -1.5272162734e-06, -7.6722239540e-07, 1.0463010362e-07, 1.0814977654e-06, 2.1546504936e-06, 3.3134891205e-06, 4.5455872726e-06, 5.8367580846e-06, 7.1711460306e-06, 8.5313438483e-06, 9.8985342262e-06, 1.1252655607e-05, 1.2572591147e-05, 1.3836379541e-05, 1.5021446129e-05, 1.6104852355e-05, 1.7063561385e-05, 1.7874717387e-05, 1.8515935714e-05, 1.8965600991e-05, 1.9203169893e-05, 1.9209475203e-05, 1.8967027605e-05, 1.8460311534e-05, 1.7676071333e-05, 1.6603583936e-05, 1.5234914303e-05, 1.3565149875e-05, 1.1592610425e-05, 9.3190298319e-06, 6.7497064845e-06, 3.8936192584e-06, 7.6350630891e-07, -2.6240957719e-06, -6.2488545081e-06, -1.0086687476e-05, -1.4109852857e-05, -1.8287085377e-05, -2.2583777896e-05, -2.6962208404e-05, -3.1381811650e-05, -3.5799494072e-05, -4.0169990162e-05, -4.4446257862e-05, -4.8579910017e-05, -5.2521678430e-05, -5.6221906542e-05, -5.9631066274e-05, -6.2700294162e-05, -6.5381941495e-05, -6.7630132812e-05, -6.9401326846e-05, -7.0654873715e-05, -7.1353562034e-05, -7.1464149461e-05, -7.0957870187e-05, -6.9810912891e-05, -6.8004862796e-05, -6.5527101630e-05, -6.2371159588e-05, -5.8537013692e-05, -5.4031327375e-05, -4.8867626603e-05, -4.3066408392e-05, -3.6655178207e-05, -2.9668413403e-05, -2.2147450604e-05, -1.4140295714e-05, -5.7013560503e-06, 3.1089050157e-06, 1.2224389678e-05, 2.1573861426e-05, 3.1081511833e-05, 4.0667594474e-05, 5.0249121134e-05, 5.9740614636e-05, 6.9054911790e-05, 7.8104009194e-05, 8.6799943892e-05, 9.5055700285e-05, 1.0278613406e-04, 1.0990890350e-04, 1.1634539804e-04, 1.2202165378e-04, 1.2686924534e-04, 1.3082614351e-04, 1.3383752813e-04, 1.3585654577e-04, 1.3684500217e-04, 1.3677397976e-04, 1.3562437113e-04, 1.3338731997e-04, 1.3006456185e-04, 1.2566865799e-04, 1.2022311620e-04, 1.1376239437e-04, 1.0633178295e-04, 9.7987164100e-05, 8.8794646614e-05, 7.8830077091e-05, 6.8178429108e-05, 5.6933073764e-05, 4.5194936278e-05, 3.3071544850e-05, 2.0675979360e-05, 8.1257288733e-06, -4.4585317552e-06, -1.6954234655e-05, -2.9238268401e-05, -4.1188370443e-05, -5.2684547827e-05, -6.3610510775e-05, -7.3855103032e-05, -8.3313712401e-05, -9.1889644585e-05, -9.9495443335e-05, -1.0605413994e-04, -1.1150041536e-04, -1.1578165875e-04, -1.1885890672e-04, -1.2070764867e-04, -1.2131848429e-04, -1.2069762091e-04, -1.1886719938e-04, -1.1586543913e-04, -1.1174659448e-04, -1.0658071633e-04, -1.0045321531e-04, -9.3464224592e-05, -8.5727762765e-05, -7.7370699499e-05, -6.8531529009e-05, -5.9358958701e-05, -5.0010322735e-05, -4.0649832552e-05, -3.1446678710e-05, -2.2573000519e-05, -1.4201742099e-05, -6.5044153953e-06, 3.5120750098e-07, 6.2034487662e-06, 1.0899100647e-05, 1.4295796108e-05, 1.6264346877e-05, 1.6691020751e-05, 1.5479729684e-05, 1.2554100054e-05, 7.8593967732e-06, 1.3642734054e-06, -6.9376786660e-06, -1.7026607803e-05, -2.8855330706e-05, -4.2348534519e-05, -5.7402272810e-05, -7.3883773406e-05, -9.1631573362e-05, -1.1045599342e-04, -1.3013996111e-04, -1.5044018834e-04, -1.7108870568e-04, -1.9179475178e-04, -2.1224701281e-04, -2.3211620244e-04, -2.5105796944e-04, -2.6871611549e-04, -2.8472610246e-04, -2.9871882389e-04, -3.1032461238e-04, -3.1917745045e-04, -3.2491934938e-04, -3.2720485744e-04, -3.2570565586e-04, -3.2011519848e-04, -3.1015334908e-04, -2.9557096815e-04, -2.7615439990e-04, -2.5172980928e-04, -2.2216731813e-04, -1.8738489005e-04, -1.4735191357e-04, -1.0209243483e-04, -5.1687991989e-05, 3.7199938582e-06, 6.3928314195e-05, 1.2867059474e-04, 1.9761647936e-04, 2.7037140842e-04, 3.4647701899e-04, 4.2541218973e-04, 5.0659474788e-04, 5.8938384984e-04, 6.7308304156e-04, 7.5694399804e-04, 8.4017093551e-04, 9.2192568285e-04, 1.0013333926e-03, 1.0774888653e-03, 1.1494634532e-03, 1.2163125057e-03, 1.2770833088e-03, 1.3308234672e-03, 1.3765896730e-03, 1.4134567946e-03, 1.4405272208e-03, 1.4569403856e-03, 1.4618823968e-03, 1.4545956891e-03, 1.4343886173e-03, 1.4006449055e-03, 1.3528328641e-03, 1.2905142880e-03, 1.2133529472e-03, 1.1211225846e-03, 1.0137143331e-03, 8.9114347134e-04, 7.5355543687e-04, 6.0123102058e-04, 4.3459067171e-04, 2.5419784686e-04, 6.0761343544e-05, -1.4486343514e-04, -3.6167432999e-04, -5.8852342735e-04, -8.2411924169e-04, -1.0670300995e-03, -1.3156887354e-03, -1.5683981009e-03, -1.8233383777e-03, -2.0785751767e-03, -2.3320688923e-03, -2.5816851749e-03, -2.8252064702e-03, -3.0603445681e-03, -3.2847540902e-03, -3.4960468413e-03, -3.6918069340e-03, -3.8696065959e-03, -4.0270225528e-03, -4.1616528819e-03, -4.2711342164e-03, -4.3531591827e-03, -4.4054939440e-03, -4.4259957199e-03, -4.4126301534e-03, -4.3634883893e-03, -4.2768037321e-03, -4.1509677498e-03, -3.9845456928e-03, -3.7762910988e-03, -3.5251594592e-03, -3.2303208274e-03, -2.8911712552e-03, -2.5073429495e-03, -2.0787130514e-03, -1.6054109473e-03, -1.0878240306e-03, -5.2660184436e-04, 7.7341453020e-05, 7.2282634865e-04, 1.4084089952e-03, 2.1323840137e-03, 2.8927890879e-03, 3.6874113458e-03, 4.5137955113e-03, 5.3692537945e-03, 6.2508774766e-03, 7.1555501312e-03, 8.0799624131e-03, 9.0206283296e-03, 9.9739029013e-03, 1.0936001106e-02, 1.1903017987e-02, 1.2870949804e-02, 1.3835716085e-02, 1.4793182440e-02, 1.5739183989e-02, 1.6669549236e-02, 1.7580124250e-02, 1.8466796963e-02, 1.9325521439e-02, 2.0152341940e-02, 2.0943416620e-02, 2.1695040685e-02, 2.2403668852e-02, 2.3065936961e-02, 2.3678682569e-02, 2.4238964396e-02, 2.4744080481e-02, 2.5191584907e-02, 2.5579302993e-02, 2.5905344835e-02, 2.6168117090e-02, 2.6366332945e-02, 2.6499020161e-02, 2.6565527173e-02, 2.6565527173e-02, 2.6499020161e-02, 2.6366332945e-02, 2.6168117090e-02, 2.5905344835e-02, 2.5579302993e-02, 2.5191584907e-02, 2.4744080481e-02, 2.4238964396e-02, 2.3678682569e-02, 2.3065936961e-02, 2.2403668852e-02, 2.1695040685e-02, 2.0943416620e-02, 2.0152341940e-02, 1.9325521439e-02, 1.8466796963e-02, 1.7580124250e-02, 1.6669549236e-02, 1.5739183989e-02, 1.4793182440e-02, 1.3835716085e-02, 1.2870949804e-02, 1.1903017987e-02, 1.0936001106e-02, 9.9739029013e-03, 9.0206283296e-03, 8.0799624131e-03, 7.1555501312e-03, 6.2508774766e-03, 5.3692537945e-03, 4.5137955113e-03, 3.6874113458e-03, 2.8927890879e-03, 2.1323840137e-03, 1.4084089952e-03, 7.2282634865e-04, 7.7341453020e-05, -5.2660184436e-04, -1.0878240306e-03, -1.6054109473e-03, -2.0787130514e-03, -2.5073429495e-03, -2.8911712552e-03, -3.2303208274e-03, -3.5251594592e-03, -3.7762910988e-03, -3.9845456928e-03, -4.1509677498e-03, -4.2768037321e-03, -4.3634883893e-03, -4.4126301534e-03, -4.4259957199e-03, -4.4054939440e-03, -4.3531591827e-03, -4.2711342164e-03, -4.1616528819e-03, -4.0270225528e-03, -3.8696065959e-03, -3.6918069340e-03, -3.4960468413e-03, -3.2847540902e-03, -3.0603445681e-03, -2.8252064702e-03, -2.5816851749e-03, -2.3320688923e-03, -2.0785751767e-03, -1.8233383777e-03, -1.5683981009e-03, -1.3156887354e-03, -1.0670300995e-03, -8.2411924169e-04, -5.8852342735e-04, -3.6167432999e-04, -1.4486343514e-04, 6.0761343544e-05, 2.5419784686e-04, 4.3459067171e-04, 6.0123102058e-04, 7.5355543687e-04, 8.9114347134e-04, 1.0137143331e-03, 1.1211225846e-03, 1.2133529472e-03, 1.2905142880e-03, 1.3528328641e-03, 1.4006449055e-03, 1.4343886173e-03, 1.4545956891e-03, 1.4618823968e-03, 1.4569403856e-03, 1.4405272208e-03, 1.4134567946e-03, 1.3765896730e-03, 1.3308234672e-03, 1.2770833088e-03, 1.2163125057e-03, 1.1494634532e-03, 1.0774888653e-03, 1.0013333926e-03, 9.2192568285e-04, 8.4017093551e-04, 7.5694399804e-04, 6.7308304156e-04, 5.8938384984e-04, 5.0659474788e-04, 4.2541218973e-04, 3.4647701899e-04, 2.7037140842e-04, 1.9761647936e-04, 1.2867059474e-04, 6.3928314195e-05, 3.7199938582e-06, -5.1687991989e-05, -1.0209243483e-04, -1.4735191357e-04, -1.8738489005e-04, -2.2216731813e-04, -2.5172980928e-04, -2.7615439990e-04, -2.9557096815e-04, -3.1015334908e-04, -3.2011519848e-04, -3.2570565586e-04, -3.2720485744e-04, -3.2491934938e-04, -3.1917745045e-04, -3.1032461238e-04, -2.9871882389e-04, -2.8472610246e-04, -2.6871611549e-04, -2.5105796944e-04, -2.3211620244e-04, -2.1224701281e-04, -1.9179475178e-04, -1.7108870568e-04, -1.5044018834e-04, -1.3013996111e-04, -1.1045599342e-04, -9.1631573362e-05, -7.3883773406e-05, -5.7402272810e-05, -4.2348534519e-05, -2.8855330706e-05, -1.7026607803e-05, -6.9376786660e-06, 1.3642734054e-06, 7.8593967732e-06, 1.2554100054e-05, 1.5479729684e-05, 1.6691020751e-05, 1.6264346877e-05, 1.4295796108e-05, 1.0899100647e-05, 6.2034487662e-06, 3.5120750098e-07, -6.5044153953e-06, -1.4201742099e-05, -2.2573000519e-05, -3.1446678710e-05, -4.0649832552e-05, -5.0010322735e-05, -5.9358958701e-05, -6.8531529009e-05, -7.7370699499e-05, -8.5727762765e-05, -9.3464224592e-05, -1.0045321531e-04, -1.0658071633e-04, -1.1174659448e-04, -1.1586543913e-04, -1.1886719938e-04, -1.2069762091e-04, -1.2131848429e-04, -1.2070764867e-04, -1.1885890672e-04, -1.1578165875e-04, -1.1150041536e-04, -1.0605413994e-04, -9.9495443335e-05, -9.1889644585e-05, -8.3313712401e-05, -7.3855103032e-05, -6.3610510775e-05, -5.2684547827e-05, -4.1188370443e-05, -2.9238268401e-05, -1.6954234655e-05, -4.4585317552e-06, 8.1257288733e-06, 2.0675979360e-05, 3.3071544850e-05, 4.5194936278e-05, 5.6933073764e-05, 6.8178429108e-05, 7.8830077091e-05, 8.8794646614e-05, 9.7987164100e-05, 1.0633178295e-04, 1.1376239437e-04, 1.2022311620e-04, 1.2566865799e-04, 1.3006456185e-04, 1.3338731997e-04, 1.3562437113e-04, 1.3677397976e-04, 1.3684500217e-04, 1.3585654577e-04, 1.3383752813e-04, 1.3082614351e-04, 1.2686924534e-04, 1.2202165378e-04, 1.1634539804e-04, 1.0990890350e-04, 1.0278613406e-04, 9.5055700285e-05, 8.6799943892e-05, 7.8104009194e-05, 6.9054911790e-05, 5.9740614636e-05, 5.0249121134e-05, 4.0667594474e-05, 3.1081511833e-05, 2.1573861426e-05, 1.2224389678e-05, 3.1089050157e-06, -5.7013560503e-06, -1.4140295714e-05, -2.2147450604e-05, -2.9668413403e-05, -3.6655178207e-05, -4.3066408392e-05, -4.8867626603e-05, -5.4031327375e-05, -5.8537013692e-05, -6.2371159588e-05, -6.5527101630e-05, -6.8004862796e-05, -6.9810912891e-05, -7.0957870187e-05, -7.1464149461e-05, -7.1353562034e-05, -7.0654873715e-05, -6.9401326846e-05, -6.7630132812e-05, -6.5381941495e-05, -6.2700294162e-05, -5.9631066274e-05, -5.6221906542e-05, -5.2521678430e-05, -4.8579910017e-05, -4.4446257862e-05, -4.0169990162e-05, -3.5799494072e-05, -3.1381811650e-05, -2.6962208404e-05, -2.2583777896e-05, -1.8287085377e-05, -1.4109852857e-05, -1.0086687476e-05, -6.2488545081e-06, -2.6240957719e-06, 7.6350630891e-07, 3.8936192584e-06, 6.7497064845e-06, 9.3190298319e-06, 1.1592610425e-05, 1.3565149875e-05, 1.5234914303e-05, 1.6603583936e-05, 1.7676071333e-05, 1.8460311534e-05, 1.8967027605e-05, 1.9209475203e-05, 1.9203169893e-05, 1.8965600991e-05, 1.8515935714e-05, 1.7874717387e-05, 1.7063561385e-05, 1.6104852355e-05, 1.5021446129e-05, 1.3836379541e-05, 1.2572591147e-05, 1.1252655607e-05, 9.8985342262e-06, 8.5313438483e-06, 7.1711460306e-06, 5.8367580846e-06, 4.5455872726e-06, 3.3134891205e-06, 2.1546504936e-06, 1.0814977654e-06, 1.0463010362e-07, -7.6722239540e-07, -1.5272162734e-06, -2.1703887919e-06, -2.6936295845e-06, -3.0956311575e-06, -3.3768197153e-06, -3.5392679602e-06, -3.5865916620e-06, -3.5238319147e-06, -3.3573250902e-06, -3.0945625625e-06, -2.7440423186e-06, -2.3151145785e-06, -1.8178235389e-06, -1.2627473117e-06, -6.6083807074e-07, -2.3264333925e-08, 6.3874279225e-07, 1.3140377019e-06, 1.9917011434e-06, 2.6611724198e-06, 3.3123716776e-06, 3.9358111968e-06, 4.5226947708e-06, 5.0650044462e-06, 5.5555740719e-06, 5.9881492925e-06, 6.3574337970e-06, 6.6591218089e-06, 6.8899169725e-06, 7.0475379464e-06, 7.1307111696e-06, 7.1391513965e-06, 7.0735307280e-06, 6.9354369744e-06, 6.7273222820e-06, 6.4524430401e-06, 6.1147921466e-06, 5.7190247651e-06, 5.2703787377e-06, 4.7745908391e-06, 4.2378100594e-06, 3.6665090930e-06, 3.0673951871e-06, 2.4473214626e-06, 1.8131997731e-06, 1.1719161057e-06, 5.3024945391e-07, -1.0520498256e-07, -7.2810750670e-07, -1.3324398685e-06, -1.9125648688e-06, -2.4632791492e-06, -2.9798587931e-06, -3.4580974711e-06, -3.8943369612e-06, -4.2854899774e-06, -4.6290553358e-06, -4.9231255797e-06, -5.1663872742e-06, -5.3581142599e-06, -5.4981542305e-06, -5.5869090670e-06, -5.6253094176e-06, -5.6147840662e-06, -5.5572246687e-06, -5.4549464756e-06, -5.3106456767e-06, -5.1273540235e-06, -4.9083913879e-06, -4.6573169136e-06, -4.3778794099e-06, -4.0739676135e-06, -3.7495609242e-06, -3.4086811865e-06, -3.0553460519e-06, -2.6935244141e-06, -2.3270943647e-06, -1.9598040633e-06, -1.5952358658e-06, -1.2367739979e-06, -8.8757600555e-07, -5.5054815637e-07, -2.2832491072e-07, 7.6747475520e-08, 3.6262320741e-07, 6.2756510963e-07, 8.7014877882e-07, 1.0892628669e-06, 1.2841056739e-06, 1.4541782669e-06, 1.5992743742e-06, 1.7194673338e-06, 1.8150943962e-06, 1.8867387042e-06, 1.9352092825e-06, 1.9615193811e-06, 1.9668635208e-06, 1.9525935870e-06, 1.9201943142e-06, 1.8712584962e-06, 1.8074622400e-06, 1.7305405697e-06, 1.6422636642e-06, 1.5444139913e-06, 1.4387645756e-06, 1.3270586133e-06, 1.2109906146e-06, 1.0921892320e-06, 9.7220189568e-07, 8.5248135465e-07, 7.3437418709e-07, 6.1911131812e-07, 5.0780055343e-07, 4.0142111114e-07, 3.0082010894e-07, 2.0671094052e-07, 1.1967345374e-07, 4.0155824245e-08, -3.1521998405e-08, -9.5163409297e-08, -1.5068897995e-07, -1.9812916099e-07, -2.3761601956e-07, -2.6937417944e-07, -2.9371113275e-07, -3.1100709153e-07, -3.2170454392e-07, -3.2629767448e-07, -3.2532180081e-07, -3.1934296990e-07, -3.0894784686e-07, -2.9473401721e-07, -2.7730081109e-07, -2.5724074395e-07, -2.3513165443e-07, -2.1152960516e-07, -1.8696259810e-07, -1.6192514079e-07, -1.3687368619e-07, -1.1222295444e-07, -8.8343132082e-08, -6.5557931595e-08, -4.4143482806e-08, -2.4328017293e-08, -6.2922976469e-09, 9.8292645898e-09, 2.3946865196e-08, 3.6013006137e-08, 4.6019709490e-08, 5.3995321744e-08, 6.0000985295e-08, 6.4126854274e-08, 6.6488130959e-08, 6.7220997028e-08, 6.6478510946e-08, 6.4426538826e-08, 6.1239781454e-08, 5.7097954686e-08, 5.2182174508e-08, 4.6671591588e-08, 4.0740313387e-08, 3.4554644949e-08, 2.8270672406e-08, 2.2032206221e-08, 1.5969094293e-08, 1.0195908361e-08, 4.8110008357e-09, -1.0407677321e-10, -4.4848080991e-09, -8.2836180146e-09, -1.1469474085e-08, -1.4027210574e-08, -1.5956605232e-08}
  COEFFICIENT_WIDTH 24
  QUANTIZATION Quantize_Only
  BESTPRECISION true
  FILTER_TYPE Interpolation
  RATE_CHANGE_TYPE Fixed_Fractional
  INTERPOLATION_RATE 25
  DECIMATION_RATE 24
  NUMBER_CHANNELS 2
  NUMBER_PATHS 1
  SAMPLE_FREQUENCY 0.096
  CLOCK_FREQUENCY 125
  OUTPUT_ROUNDING_MODE Convergent_Rounding_to_Even
  OUTPUT_WIDTH 25
  M_DATA_HAS_TREADY true
  HAS_ARESETN true
} {
  S_AXIS_DATA subset_0/M_AXIS
  aclk pll_0/clk_out1
  aresetn slice_1/dout
}

# Create axis_subset_converter
cell xilinx.com:ip:axis_subset_converter subset_1 {
  S_TDATA_NUM_BYTES.VALUE_SRC USER
  M_TDATA_NUM_BYTES.VALUE_SRC USER
  S_TDATA_NUM_BYTES 4
  M_TDATA_NUM_BYTES 3
  TDATA_REMAP {tdata[23:0]}
} {
  S_AXIS fir_1/M_AXIS_DATA
  aclk pll_0/clk_out1
  aresetn slice_1/dout
}

# Create cic_compiler
cell xilinx.com:ip:cic_compiler cic_0 {
  INPUT_DATA_WIDTH.VALUE_SRC USER
  FILTER_TYPE Interpolation
  NUMBER_OF_STAGES 6
  SAMPLE_RATE_CHANGES Fixed
  FIXED_OR_INITIAL_RATE 25
  INPUT_SAMPLE_FREQUENCY 0.1
  CLOCK_FREQUENCY 125
  NUMBER_OF_CHANNELS 2
  INPUT_DATA_WIDTH 24
  QUANTIZATION Truncation
  OUTPUT_DATA_WIDTH 24
  USE_XTREME_DSP_SLICE false
  HAS_DOUT_TREADY true
  HAS_ARESETN true
} {
  S_AXIS_DATA subset_1/M_AXIS
  aclk pll_0/clk_out1
  aresetn slice_1/dout
}

# Create dsp48
cell pavel-demin:user:dsp48 mult_0 {
  A_WIDTH 24
  B_WIDTH 16
  P_WIDTH 18
} {
  A cic_0/m_axis_data_tdata
  B slice_2/dout
  CLK pll_0/clk_out1
}

# Create c_shift_ram
cell xilinx.com:ip:c_shift_ram delay_0 {
  WIDTH.VALUE_SRC USER
  WIDTH 1
  DEPTH 4
} {
  D cic_0/m_axis_data_tvalid
  CLK pll_0/clk_out1
}

# Create axis_dwidth_converter
cell xilinx.com:ip:axis_dwidth_converter conv_1 {
  S_TDATA_NUM_BYTES.VALUE_SRC USER
  S_TDATA_NUM_BYTES 2
  M_TDATA_NUM_BYTES 4
} {
  s_axis_tdata mult_0/P
  s_axis_tvalid delay_0/Q
  s_axis_tready cic_0/m_axis_data_tready
  aclk pll_0/clk_out1
  aresetn slice_1/dout
}

# Create axis_data_fifo
cell xilinx.com:ip:axis_data_fifo fifo_1 {
  TDATA_NUM_BYTES.VALUE_SRC USER
  TDATA_NUM_BYTES 4
  FIFO_DEPTH 1024
  HAS_RD_DATA_COUNT true
} {
  S_AXIS conv_1/M_AXIS
  s_axis_aclk pll_0/clk_out1
  s_axis_aresetn slice_1/dout
}

# Create xlconstant
cell xilinx.com:ip:xlconstant const_1 {
  CONST_WIDTH 8
  CONST_VAL 49
}

# Create axis_pdm
cell pavel-demin:user:axis_pdm pdm_0 {
  AXIS_TDATA_WIDTH 16
  CNTR_WIDTH 8
} {
  S_AXIS fifo_1/M_AXIS
  cfg_data const_1/dout
  dout dac_pwm_o
  aclk pll_0/clk_out1
  aresetn slice_0/dout
}

# Create xlconcat
cell xilinx.com:ip:xlconcat concat_0 {
  NUM_PORTS 2
  IN0_WIDTH 32
  IN1_WIDTH 32
} {
  In0 fifo_0/axis_rd_data_count
  In1 fifo_1/axis_rd_data_count
}

# Create axi_sts_register
cell pavel-demin:user:axi_sts_register sts_0 {
  STS_DATA_WIDTH 64
  AXI_ADDR_WIDTH 32
  AXI_DATA_WIDTH 32
} {
  sts_data concat_0/dout
}

addr 0x40000000 4K sts_0/S_AXI /ps_0/M_AXI_GP0

addr 0x40001000 4K cfg_0/S_AXI /ps_0/M_AXI_GP0

addr 0x40002000 4K writer_0/S_AXI /ps_0/M_AXI_GP0
