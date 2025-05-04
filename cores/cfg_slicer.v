
`timescale 1 ns / 1 ps

module cfg_slicer #
(
  parameter integer SAMP_WIDTH = 16,
  parameter integer NUM_CHANS = 13,
  parameter integer PHASE_WIDTH = 32,
  parameter integer SIN_WIDTH = 15,
  parameter integer CIC_IN_WIDTH = 16,
  parameter integer CIC_OUT_WIDTH = 16,
  parameter integer FIR_OUT_WIDTH = 48,
  parameter integer CFG_WIDTH = (NUM_CHANS + 1) * PHASE_WIDTH
)
(
  input wire aclk,
  input wire aresetn,
  input wire adc_ovfl,
  input wire [15:0] rdcnt,
  input wire [15:0] wrcnt,
  input wire [SAMP_WIDTH-1:0] rawdin,
  input wire [SAMP_WIDTH-1:0] din,
  input wire [CFG_WIDTH-1:0] cfg,
  output wire rstn,
  output reg [SAMP_WIDTH-1:0] outdata,
  output reg outvld,
  output wire [239:0] status
);

  localparam integer ONE_SEC = 122880000;
  localparam integer ONE_SEC_CHAN = 307200;
  localparam integer DDS_WIDTH = 32;

  localparam signed [SAMP_WIDTH-1:0] MAX_16 =  (1 << (SAMP_WIDTH-1)) - 1;
  localparam signed [SAMP_WIDTH-1:0] MIN_16 = -(1 << (SAMP_WIDTH-1));
  localparam signed [SAMP_WIDTH-1:0] MAX_15 =  (1 << (SAMP_WIDTH-2)) - 1;
  localparam signed [SAMP_WIDTH-1:0] MIN_15 = -(1 << (SAMP_WIDTH-2));

  wire [PHASE_WIDTH-1:0] phase[NUM_CHANS-1:0];
  wire [DDS_WIDTH-1:0] ddsout[NUM_CHANS-1:0];
  wire [SIN_WIDTH-1:0] sin[NUM_CHANS-1:0];
  wire [SIN_WIDTH-1:0] cos[NUM_CHANS-1:0];
  wire [CIC_IN_WIDTH-1:0] dreal[NUM_CHANS-1:0];
  wire [CIC_IN_WIDTH-1:0] dimag[NUM_CHANS-1:0];
  wire [CIC_OUT_WIDTH-1:0] freal[NUM_CHANS-1:0];
  wire [CIC_OUT_WIDTH-1:0] fimag[NUM_CHANS-1:0];
  wire fvld[NUM_CHANS-1:0];
  reg cicvld;
  reg [CIC_OUT_WIDTH*NUM_CHANS*2-1:0] cicdata;
  wire wcvld;
  wire wcrdy;
  wire [SAMP_WIDTH-1:0] wcdata;
  wire firvld;
  wire signed [FIR_OUT_WIDTH-1:0] firdata;
  wire [7:0] firuser;

  reg [CFG_WIDTH-1:0] cfgreg;

  assign rstn = cfgreg[0];
  wire blank = cfgreg[8];
  wire phasevld = cfgreg[16];

  reg adc_ovfl_latch;

  reg signed [SAMP_WIDTH-1:0] samp;
  reg signed [SAMP_WIDTH-1:0] maxsamp;
  reg [SAMP_WIDTH-1:0] rawsamp;

  assign status[31:0] = {maxsamp[15:1], adc_ovfl_latch, rdcnt};

  reg [4:0] fracshift[NUM_CHANS-1:0];

  genvar j;
  generate
    for (j = 0; j < NUM_CHANS; j = j + 1) begin
      assign phase[j] = cfg[PHASE_WIDTH*(j+1) +: PHASE_WIDTH];
      assign status[32 + j*8 +: 8] = fracshift[j];
    end
  endgenerate

  always @(posedge aclk)
  begin
    cfgreg <= cfg;
    samp <= din;
    rawsamp <= rawdin;
  end

  genvar i;
  generate
    for (i = 0; i < NUM_CHANS; i = i + 1) begin
      dds uDDS (
        .aclk(aclk),
        .s_axis_phase_tvalid(phasevld),
        .s_axis_phase_tdata(phase[i]),
        .m_axis_data_tvalid(),
        .m_axis_data_tdata(ddsout[i])
      );

      assign sin[i] = ddsout[i][30:16];
      assign cos[i] = ddsout[i][14:0];

      dsp48 #(
        .A_WIDTH(SIN_WIDTH),
        .B_WIDTH(SAMP_WIDTH),
        .P_WIDTH(CIC_IN_WIDTH)
      ) uRealDSP48 (
        .CLK(aclk),
        .A(cos[i]),
        .B(samp),
        .P(dreal[i])
      );

      dsp48 #(
        .A_WIDTH(SIN_WIDTH),
        .B_WIDTH(SAMP_WIDTH),
        .P_WIDTH(CIC_IN_WIDTH)
      ) uImagDSP48 (
        .CLK(aclk),
        .A(sin[i]),
        .B(samp),
        .P(dimag[i])
      );

      cic uRealCIC (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_data_tdata(dreal[i]),
        .s_axis_data_tvalid(1'b1),
        .s_axis_data_tready(),
        .m_axis_data_tdata(freal[i]),
        .m_axis_data_tvalid(fvld[i])
      );

      cic uImagCIC (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_data_tdata(dimag[i]),
        .s_axis_data_tvalid(1'b1),
        .s_axis_data_tready(),
        .m_axis_data_tdata(fimag[i]),
        .m_axis_data_tvalid()
      );
    end
    endgenerate

  always @(posedge aclk)
  begin
    cicvld <= fvld[0];

    cicdata <= {
      fimag[12], freal[12],
      fimag[11], freal[11],
      fimag[10], freal[10],
      fimag[9],  freal[9],
      fimag[8],  freal[8],
      fimag[7],  freal[7],
      fimag[6],  freal[6],
      fimag[5],  freal[5],
      fimag[4],  freal[4],
      fimag[3],  freal[3],
      fimag[2],  freal[2],
      fimag[1],  freal[1],
      fimag[0],  freal[0]
    };
  end

  conv uWidthConv (
    .aclk(aclk),
    .aresetn(rstn),
    .s_axis_tvalid(cicvld),
    .s_axis_tready(),
    .s_axis_tdata(cicdata),
    .m_axis_tvalid(wcvld),
    .m_axis_tready(wcrdy),
    .m_axis_tdata(wcdata)
  );

  fir uFIR (
    .aresetn(rstn),
    .aclk(aclk),
    .s_axis_data_tvalid(wcvld),
    .s_axis_data_tready(wcrdy),
    .s_axis_data_tdata(wcdata),
    .m_axis_data_tvalid(firvld),
    .m_axis_data_tuser(firuser),
    .m_axis_data_tdata(firdata)
  );

  // remove AXI padding and shift
  wire [7:0] firchan = firuser >> 1;
  wire [7:0] firband = firchan >> 1;

  reg signed [FIR_OUT_WIDTH-1:0] regfir;
  reg [7:0] regband;
  reg regvld;

  reg signed [FIR_OUT_WIDTH-1:0] shiftfir;
  reg [7:0] shiftband;
  reg shiftvld;
  reg shiftlo;
  reg shifthi;

  wire losig = (regfir < MAX_15) && (regfir > MIN_15);
  wire hisig = (regfir > MAX_16) || (regfir < MIN_16);

  integer shiftcntr = 0;
  integer lowsigcntr[NUM_CHANS-1:0];
  integer highsigcntr[NUM_CHANS-1:0];
  integer k;

  always @(posedge aclk)
  begin

    regfir <= firdata >>> fracshift[firband];
    regvld <= firvld;
    regband <= firband;

    shiftfir <= regfir;
    shiftvld <= regvld;
    shiftband <= regband;
    shiftlo <= losig;
    shifthi <= hisig;

    if (adc_ovfl) begin
      adc_ovfl_latch <= 1'b1;
    end

    if (samp > maxsamp) begin
      maxsamp <= samp;
    end else if (-samp > maxsamp) begin
      maxsamp <= -samp;
    end

    if (shiftvld) begin
      if (shiftlo) begin
        lowsigcntr[shiftband] <= lowsigcntr[shiftband] + 1;
      end else begin
        lowsigcntr[shiftband] <= 0;
      end

      if (lowsigcntr[shiftband] > ONE_SEC_CHAN*5) begin
        fracshift[shiftband] <= fracshift[shiftband] - 1;
        lowsigcntr[shiftband] <= 0;
      end

      if (shifthi) begin
        highsigcntr[shiftband] <= highsigcntr[shiftband] + 1;
      end

      if (highsigcntr[shiftband] > ONE_SEC_CHAN/1000) begin
        highsigcntr[shiftband] <= 0;
        fracshift[shiftband] <= fracshift[shiftband] + 1;
      end
    end

    if (shiftcntr > ONE_SEC) begin
        shiftcntr <= 0;
        adc_ovfl_latch <= 1'b0;
        maxsamp <= 0;
        for (k = 0; k < NUM_CHANS; k = k + 1) begin
          highsigcntr[k] <= 0;
        end
    end else begin
      shiftcntr <= shiftcntr + 1;
    end

    outvld <= shiftvld;
    outdata <= shiftfir[SAMP_WIDTH-1:0];
  end

endmodule
