`default_nettype none

module tiny_fpga
  #(parameter int unsigned LUT_WIDTH
  , parameter int unsigned IO_INPUT_WDITH
  , parameter int unsigned IO_OUTPUT_WIDTH
  , parameter int unsigned BITSTREAM_DATA_WIDTH
  )
  ( input var logic clk
  , input var logic rst_n

  , input var logic     cfg
    // TODO: design currently does not protect against rouge `tlast`s
  , axi_stream_if.slave cfg_bitstream

  , input  var logic                        run
  , input  var logic [IO_INPUT_WDITH -1:0]  run_in
  , output var logic [IO_OUTPUT_WIDTH -1:0] run_out
  );

  // state declaration

  typedef enum logic [2:0]
    { STATE__INIT
    , STATE__CONFIG_CLB_BEGIN
    , STATE__CONFIG_CLB_WAIT
    , STATE__IDLE
    , STATE__RUN
    } t_state;

  t_state state_now, state_next;

  always_ff @ (posedge clk)
    if (!rst_n) state_now <= STATE__INIT;
    else        state_now <= state_next;

  // clb instantiation

  logic clb_cfg_ready;

  clb
    #(.NUM_NEIGHBOUR_SIGNALS ( 4                    )
    , .NUM_IO_SIGNALS        ( IO_INPUT_WDITH       )
    , .LUT_WIDTH             ( LUT_WIDTH            )
    , .BITSTREAM_DATA_WIDTH  ( BITSTREAM_DATA_WIDTH )
    )
    u_clb_1
      ( .clk   ( clk   )
      , .rst_n ( rst_n )

      , .cfg           ( state_now == STATE__CONFIG_CLB_BEGIN )
      , .cfg_bitstream ( cfg_bitstream                        )

      , .run                ( run        )
      , .run_in_neightbours ( 4'bzzzz    )
      , .run_in_io          ( run_in     )
      , .run_in_feedback    ( 1'bz       )
      , .run_out            ( run_out[0] )
      );

  // state machine logic

  always_comb
    case (state_now)
      STATE__INIT:
        if (cfg)
          state_next = STATE__CONFIG_CLB_BEGIN;
        else
          state_next = STATE__INIT;
      STATE__CONFIG_CLB_BEGIN, STATE__CONFIG_CLB_WAIT:
        if (clb_cfg_ready)
          state_next = STATE__IDLE;
        else
          state_next = STATE__CONFIG_CLB_WAIT;
      STATE__IDLE:
        if (run)
          state_next = STATE__RUN;
        else if (cfg)
          state_next = STATE__CONFIG_CLB_BEGIN;
        else
          state_next = STATE__IDLE;
      STATE__RUN:
        if (cfg) state_next = STATE__CONFIG_CLB_BEGIN;
        else     state_next = STATE__RUN;
      default:
        state_next = STATE__INIT;
    endcase

endmodule
