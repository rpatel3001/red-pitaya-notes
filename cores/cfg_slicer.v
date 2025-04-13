
`timescale 1 ns / 1 ps

module cfg_slicer #
(
  parameter integer SAMP_WIDTH = 16,
  parameter integer NUM_CHANS = 13,
  parameter integer PHASE_WIDTH = 32,
  parameter integer SIN_WIDTH = 15,
  parameter integer CIC_IN_WIDTH = 16,
  parameter integer CIC_OUT_WIDTH = 16,
  parameter integer FIR_OUT_WIDTH = 41,
  parameter integer CFG_WIDTH = (NUM_CHANS + 1) * PHASE_WIDTH
)
(
  input wire aclk,
  input wire aresetn,
  input wire [SAMP_WIDTH-1:0] din,
  input wire [CFG_WIDTH-1:0] cfg,
  output wire rst,
  output reg [SAMP_WIDTH-1:0] outdata,
  output reg outvld
);

  localparam integer ONE_SEC = 122800000;
  localparam integer DDS_WIDTH = 32;
  localparam integer ADC_DATA_WIDTH = 14;
  localparam integer PADDING_WIDTH = SAMP_WIDTH - ADC_DATA_WIDTH;
  localparam integer MAX_FRAC_SHIFT = FIR_OUT_WIDTH - SAMP_WIDTH - 2;
  localparam integer FULL_FIR_WIDTH = $ceil(FIR_OUT_WIDTH/8)*8;

  localparam signed [15:0] MAX_16 = (1 << 15) - 1;
  localparam signed [15:0] MIN_16 = -(1 << 15);
  localparam signed [15:0] MAX_15 = (1 << 14) - 1;
  localparam signed [15:0] MIN_15 = -(1 << 14);

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
  //wire [FULL_FIR_WIDTH-1:0] firdata;
  wire [47:0] firdata;
  reg phasevld;

  reg [CFG_WIDTH-1:0] cfgreg;

  assign rst = cfgreg[0];
  wire blank = cfgreg[8];
  assign phase[0] = cfgreg[PHASE_WIDTH*2-1:PHASE_WIDTH*1];
  assign phase[1] = cfgreg[PHASE_WIDTH*3-1:PHASE_WIDTH*2];
  assign phase[2] = cfgreg[PHASE_WIDTH*4-1:PHASE_WIDTH*3];
  assign phase[3] = cfgreg[PHASE_WIDTH*5-1:PHASE_WIDTH*4];
  assign phase[4] = cfgreg[PHASE_WIDTH*6-1:PHASE_WIDTH*5];
  assign phase[5] = cfgreg[PHASE_WIDTH*7-1:PHASE_WIDTH*6];
  assign phase[6] = cfgreg[PHASE_WIDTH*8-1:PHASE_WIDTH*7];
  assign phase[7] = cfgreg[PHASE_WIDTH*9-1:PHASE_WIDTH*8];
  assign phase[8] = cfgreg[PHASE_WIDTH*10-1:PHASE_WIDTH*9];
  assign phase[9] = cfgreg[PHASE_WIDTH*11-1:PHASE_WIDTH*10];
  assign phase[10] = cfgreg[PHASE_WIDTH*12-1:PHASE_WIDTH*11];
  assign phase[11] = cfgreg[PHASE_WIDTH*13-1:PHASE_WIDTH*12];
  assign phase[12] = cfgreg[PHASE_WIDTH*14-1:PHASE_WIDTH*13];

  reg [SAMP_WIDTH-1:0] samp;

  reg [4:0] fracshift = 0;
  integer shiftcntr = 0;
  integer lowsigcntr = 0;

  always @(posedge aclk)
  begin
    cfgreg <= cfg;
    phasevld <= 1'b1;//cfg != cfgreg;
    samp <= blank ? 16'b0 : din;
  end

  genvar i;
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
    .aresetn(rst),
    .s_axis_tvalid(cicvld),
    .s_axis_tready(),
    .s_axis_tdata(cicdata),
    .m_axis_tvalid(wcvld),
    .m_axis_tready(wcrdy),
    .m_axis_tdata(wcdata)
  );

  fir uFIR (
    .aresetn(rst),
    .aclk(aclk),
    .s_axis_data_tvalid(wcvld),
    .s_axis_data_tready(wcrdy),
    .s_axis_data_tdata(wcdata),
    .m_axis_data_tvalid(firvld),
    .m_axis_data_tuser(),
    .m_axis_data_tdata(firdata)
  );

  // remove AXI padding and shift
  wire signed [FIR_OUT_WIDTH-1:0] fullfir = firdata[FIR_OUT_WIDTH-1:0];
  wire signed [FIR_OUT_WIDTH-1:0] shiftfir = fullfir >>> fracshift;

  always @(posedge aclk)
  begin
    if (lowsigcntr > ONE_SEC*5) begin
      fracshift <= fracshift - 1;
      lowsigcntr <= 0;
    end else begin
      if (shiftfir < MAX_15 && shiftfir > MIN_15) begin
        lowsigcntr <= lowsigcntr + 1;
      end else begin
        lowsigcntr <= 0;
      end
    end

    if (shiftcntr > ONE_SEC) begin
      if (shiftfir > MAX_16 || shiftfir < MIN_16) begin
        fracshift <= fracshift + 1;
        shiftcntr <= 0;
      end
    end else begin
      shiftcntr <= shiftcntr + 1;
    end

    //if (shiftcntr > ONE_SEC*3) begin
    //  if (fracshift >= MAX_FRAC_SHIFT) begin
    //    fracshift = 0;
    //  end else begin
    //    fracshift <= fracshift + 1;
    //  end
    //  shiftcntr <= 0;
    //end else begin
    //  shiftcntr <= shiftcntr + 1;
    //end

    outvld <= firvld;
    outdata <= shiftfir[SAMP_WIDTH-1:0];
  end

endmodule
