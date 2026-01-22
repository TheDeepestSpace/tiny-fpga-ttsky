`default_nettype none
`timescale 1ns / 1ps

`include "axi_stream_if.svh"

/* Testbench for clb: instantiate DUT and expose signals for cocotb. */
module tb_clb ();

  localparam int unsigned NUM_NEIGHBOUR_SIGNALS = 4;
  localparam int unsigned NUM_IO_SIGNALS        = 4;
  localparam int unsigned LUT_WIDTH             = 4;
  localparam int unsigned BITSTREAM_DATA_WIDTH  = 1;

  reg clk;
  reg rst_n;

  reg  cfg;
  wire cfg_ready;
  axi_stream_if #( .DATA_WIDTH ( BITSTREAM_DATA_WIDTH ) ) cfg_bitstream();

  reg                              run;
  reg [NUM_NEIGHBOUR_SIGNALS -1:0] run_in_neightbours;
  reg [NUM_IO_SIGNALS -1:0]        run_in_io;
  reg                              run_in_feedback;
  wire                             run_out;

  clb
    #(.NUM_NEIGHBOUR_SIGNALS ( NUM_NEIGHBOUR_SIGNALS )
    , .NUM_IO_SIGNALS        ( NUM_IO_SIGNALS        )
    , .LUT_WIDTH             ( LUT_WIDTH             )
    , .BITSTREAM_DATA_WIDTH  ( BITSTREAM_DATA_WIDTH  )
    )
    u_clb
      ( .clk   ( clk   )
      , .rst_n ( rst_n )

      , .cfg           ( cfg                   )
      , .cfg_bitstream ( cfg_bitstream.slave   )
      , .cfg_ready     ( cfg_ready             )

      , .run                ( run               )
      , .run_in_neightbours ( run_in_neightbours )
      , .run_in_io          ( run_in_io          )
      , .run_in_feedback    ( run_in_feedback    )
      , .run_out            ( run_out            )
      );

endmodule
