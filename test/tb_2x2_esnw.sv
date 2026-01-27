`default_nettype none
`timescale 1ns / 1ps

`include "axi_stream_if.svh"

module tb_2x2_esnw ();

  localparam int unsigned LUT_WIDTH            = 4;
  localparam int unsigned IO_INPUT_WIDTH       = 4;
  localparam int unsigned IO_OUTPUT_WIDTH      = 4;
  localparam int unsigned BITSTREAM_DATA_WIDTH = 1;

  reg clk;
  reg rst_n;

  reg  cfg;
  wire cfg_ready;
  axi_stream_if #( .DATA_WIDTH ( BITSTREAM_DATA_WIDTH ) ) cfg_bitstream();

  reg  [IO_INPUT_WIDTH -1:0]  run_in;
  reg                         run;
  wire [IO_OUTPUT_WIDTH -1:0] run_out;

  tiny_fpga_2x2_esnw
    #(.LUT_WIDTH            ( LUT_WIDTH            )
    , .IO_INPUT_WDITH       ( IO_INPUT_WIDTH       )
    , .IO_OUTPUT_WIDTH      ( IO_OUTPUT_WIDTH      )
    , .BITSTREAM_DATA_WIDTH ( BITSTREAM_DATA_WIDTH )
    )
    u_tiny_fpga_2x2_esnw
      ( .clk           ( clk                 )
      , .rst_n         ( rst_n               )
      , .cfg           ( cfg                 )
      , .cfg_bitstream ( cfg_bitstream.slave )
      , .cfg_ready     ( cfg_ready           )
      , .run           ( run                 )
      , .run_in        ( run_in              )
      , .run_out       ( run_out             )
      );

endmodule
