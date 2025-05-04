
`timescale 1 ns / 1 ps

module axis_red_pitaya_adc #
(
  parameter integer ADC_DATA_WIDTH = 16
)
(
  // System signals
  input  wire        aclk,

  // ADC signals
  output wire        adc_csn,
  input  wire [15:0] adc_dat_a,
  input  wire [15:0] adc_dat_b,

  // Master side
  output wire        m_axis_tvalid,
  output wire [15:0] m_axis_tdata,
  output wire [15:0] m_axis_tdata_raw
);
  localparam PADDING_WIDTH = 16 - ADC_DATA_WIDTH;

  reg  [ADC_DATA_WIDTH-1:0] int_dat_a_reg;
  reg  [ADC_DATA_WIDTH-1:0] int_dat_b_reg;

  always @(posedge aclk)
  begin
    int_dat_a_reg <= adc_dat_a;
    int_dat_b_reg <= adc_dat_b;
  end

  assign adc_csn = 1'b1;

  assign m_axis_tvalid = 1'b1;
  assign m_axis_tdata_raw = int_dat_a_reg;

  //assign m_axis_tdata = {{(PADDING_WIDTH+1){int_dat_a_reg[ADC_DATA_WIDTH-1]}}, ~int_dat_a_reg[ADC_DATA_WIDTH-2:0]};
  assign m_axis_tdata = {~int_dat_a_reg[15], int_dat_a_reg[14:0]};

endmodule
