`default_nettype none

`include "axi_stream_if.svh"

module tt_um_tiny_fpga
  ( input  var logic [7:0] ui_in    // Dedicated inputs
  , output var logic [7:0] uo_out   // Dedicated outputs
  , input  var logic [7:0] uio_in   // IOs: Input path
  , output var logic [7:0] uio_out  // IOs: Output path
  , output var logic [7:0] uio_oe   // IOs: Enable path (active high: 0=input, 1=output)
  , input  var logic       ena      // always 1 when the design is powered, so you can ignore it
  , input  var logic       clk      // clock
  , input  var logic       rst_n    // reset_n - low to reset
  );

  axi_stream_if #( .DATA_WIDTH ( 1 ) ) bitstream_if();

  assign bitstream_if.tvalid = ui_in[0];
  assign uo_out[0] = bitstream_if.tready;
  assign bitstream_if.tdata = ui_in[1];
  assign bitstream_if.tlast = ui_in[2];

  assign uio_oe = 8'b11110000;

  logic _unused_inputs;
  assign _unused_inputs = {ena, uio_in[7:3] };

  assign { uio_out[3:0], uo_out[7:1] } = '0;

  tiny_fpga #( .LUT_WIDTH ( 4 ), .IO_INPUT_WDITH ( 4 ), .IO_OUTPUT_WIDTH ( 4 ) )
    u_tiny_fpga
      ( .clk   ( clk   )
      , .rst_n ( rst_n )

      , .cfg           ( ui_in[3]           )
      , .cfg_bitstream ( bitstream_if.slave )

      , .run     ( ui_in[4]     )
      , .run_in  ( uio_in [3:0] )
      , .run_out ( uio_out[7:4] )
      );

endmodule
