`default_nettype none

module tiny_fpga_2x2_esnw
  #(parameter int unsigned LUT_WIDTH       = 4
  , parameter int unsigned IO_INPUT_WDITH  = 4
  , parameter int unsigned IO_OUTPUT_WIDTH = 4
  , parameter int unsigned BITSTREAM_DATA_WIDTH
  )
  ( input var logic clk
  , input var logic rst_n

  , input  var logic    cfg
    // TODO: design currently does not protect against rouge `tlast`s
  , axi_stream_if.slave cfg_bitstream
  , output var logic    cfg_ready

  , input  var logic                        run
  , input  var logic [IO_INPUT_WDITH -1:0]  run_in
  , output var logic [IO_OUTPUT_WIDTH -1:0] run_out
  );

  // state declaration

  typedef enum logic [2:0]
    { STATE__INIT
    , STATE__CONFIG_CLB_BEGIN
    , STATE__CONFIG_CLB_WAIT
    , STATE__CONFIG_CLB_END
    , STATE__IDLE
    , STATE__RUN
    } t_state;

  t_state state_now, state_next;

  always_ff @ (posedge clk)
    if (!rst_n) state_now <= STATE__INIT;
    else        state_now <= state_next;

  // clb instantiation and configuration

  parameter int unsigned CLB_COUNT = 4;
  parameter int unsigned CLB_IDX_W = $clog2(CLB_COUNT);

  logic [CLB_IDX_W -1:0] clb_cfg_iter;
  logic [CLB_COUNT -1:0] clb_cfg_ready;
  logic                  all_clbs_configured;

  assign all_clbs_configured = clb_cfg_iter == CLB_IDX_W'(CLB_COUNT -1);
  assign cfg_ready           = all_clbs_configured;

  always_ff @ (posedge clk)
    if (!rst_n)                                        clb_cfg_iter <= '0;
    else
      case (state_now)
        STATE__INIT, STATE__IDLE:                      clb_cfg_iter <= '0;
        STATE__CONFIG_CLB_END:
          if (clb_cfg_iter < CLB_IDX_W'(CLB_COUNT -1)) clb_cfg_iter <= clb_cfg_iter + 1;
          else                                         clb_cfg_iter <= clb_cfg_iter;
        default:                                       clb_cfg_iter <= clb_cfg_iter;
      endcase

  // clb bitstream tready proxy

  logic [CLB_COUNT -1:0] clb_cfg_bitstream_tready;
  assign cfg_bitstream.tready = clb_cfg_bitstream_tready[clb_cfg_iter];

  //  clb 0   clb 1
  //
  //  clb 2   clb 3

  logic [CLB_COUNT -1:0] clb_out;

  // this is kind of a bummer but without cloking the CLB outputs we get `Signal unoptimizable:
  // Circular combinational logic`; i think this can be addressed later
  logic [CLB_COUNT -1:0] clocked_clb_out;

  always_ff @ (posedge clk) clocked_clb_out <= clb_out;

  assign run_out = clb_out;

  logic [CLB_COUNT -1:0] run_in_neightbours [CLB_COUNT -1:0];


  // ES seq/NW clk routing (--> = sequential, ->> = clocked)
  //
  //  0 --> 1[0]
  //  0 --> 2[0]
  //  0 --> 3[0]
  //
  //  1 --> 3[1]
  //  1 --> 2[1]
  //  1 ->> 0[0]
  //
  //  2 --> 3[2]
  //  2 ->> 0[1]
  //  2 ->> 1[1]
  //
  //  3 ->> 0[2]
  //  3 ->> 1[2]
  //  3 ->> 2[2]

  //                               [3] [2]                 [1]                 [0]
  assign run_in_neightbours[0] = { 'x, clocked_clb_out[3], clocked_clb_out[2], clocked_clb_out[1] };
  assign run_in_neightbours[1] = { 'x, clocked_clb_out[3], clocked_clb_out[2], clb_out[0]         };
  assign run_in_neightbours[2] = { 'x, clocked_clb_out[3], clb_out[1]        , clb_out[0]         };
  assign run_in_neightbours[3] = { 'x, clb_out[2]        , clb_out[1]        , clb_out[0]         };

  for (genvar g_clb_idx = 0; g_clb_idx < CLB_COUNT; g_clb_idx = g_clb_idx + 1) begin: l_clbs
    axi_stream_if #( .DATA_WIDTH ( BITSTREAM_DATA_WIDTH ) ) clb_cfg_bitstream_if();

    assign clb_cfg_bitstream_if.tvalid         = cfg_bitstream.tvalid;
    assign clb_cfg_bitstream_if.tdata          = cfg_bitstream.tdata;
    assign clb_cfg_bitstream_if.tlast          = cfg_bitstream.tlast;
    assign clb_cfg_bitstream_tready[g_clb_idx] = clb_cfg_bitstream_if.tready;

    clb
      #(.NUM_NEIGHBOUR_SIGNALS ( 4                    )
      , .NUM_IO_SIGNALS        ( IO_INPUT_WDITH       )
      , .LUT_WIDTH             ( LUT_WIDTH            )
      , .BITSTREAM_DATA_WIDTH  ( BITSTREAM_DATA_WIDTH )
      )
      u_clb
        ( .clk   ( clk   )
        , .rst_n ( rst_n )

        , .cfg           ( state_now == STATE__CONFIG_CLB_BEGIN && g_clb_idx == clb_cfg_iter )
        , .cfg_bitstream ( clb_cfg_bitstream_if                                              )
        , .cfg_ready     ( clb_cfg_ready[g_clb_idx]                                          )

        , .run                ( run                           )
        , .run_in_neightbours ( run_in_neightbours[g_clb_idx] )
        , .run_in_io          ( run_in                        )
        , .run_in_feedback    ( 1'bx                          )
        , .run_out            ( clb_out[g_clb_idx]            )
        );
  end

  // state machine logic

  always_comb
    case (state_now)
      STATE__INIT:
        if (cfg)                         state_next = STATE__CONFIG_CLB_BEGIN;
        else                             state_next = STATE__INIT;
      STATE__CONFIG_CLB_BEGIN, STATE__CONFIG_CLB_WAIT:
        if (clb_cfg_ready[clb_cfg_iter]) state_next = STATE__CONFIG_CLB_END;
        else                             state_next = STATE__CONFIG_CLB_WAIT;
      STATE__CONFIG_CLB_END:
        if (all_clbs_configured)         state_next = STATE__IDLE;
        else                             state_next = STATE__CONFIG_CLB_BEGIN;
      STATE__IDLE:
        if (run)                         state_next = STATE__RUN;
        else if (cfg)                    state_next = STATE__CONFIG_CLB_BEGIN;
        else                             state_next = STATE__IDLE;
      STATE__RUN:
        if (cfg)                         state_next = STATE__CONFIG_CLB_BEGIN;
        else                             state_next = STATE__RUN;
      default:                           state_next = STATE__INIT;
    endcase

endmodule
