`default_nettype none

module tiny_fpga_6x6_esnw
  #(parameter int unsigned LUT_WIDTH       = 4
  , parameter int unsigned IO_INPUT_WDITH  = 4
  , parameter int unsigned IO_OUTPUT_WIDTH = 6
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

  parameter int unsigned CLB_COUNT = 36;
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

  //  clb  0   clb  1   clb  2   clb  3   clb  4   clb 5
  //
  //  clb  6   clb  7   clb  8   clb  9   clb 10   clb 11
  //
  //  clb 12   clb 13   clb 14   clb 15   clb 16   clb 17
  //
  //  clb 18   clb 19   clb 20   clb 21   clb 22   clb 23
  //
  //  clb 24   clb 25   clb 26   clb 27   clb 28   clb 29
  //
  //  clb 30   clb 31   clb 32   clb 33   clb 34   clb 35
  parameter int unsigned CLB_ROW_COUNT = 6;
  parameter int unsigned CLB_COL_COUNT = 6;
  parameter int unsigned CLB_NUM_NEIGHBOUR_SIGNALS = 8;
`define CLB_COORDS(row, col) ((row) * CLB_ROW_COUNT + (col))

  /* verilator lint_off UNOPTFLAT */
  // it does not like my implementation of ES/NW probably due to internal issues with its
  // optimizer, im not sure; any way i pinky promise i did not create combinational loops
  logic [CLB_COUNT -1:0] clb_out;
  /* verilator lint_on UNOPTFLAT */

  // in this module we are doing ES/NW routing, so we are goign to need some of the clb out's
  // clocked to pass it back to NW neighbours
  logic [CLB_COUNT -1:0] clocked_clb_out;

  always_ff @ (posedge clk) clocked_clb_out <= clb_out;

  // output routing

  for (genvar g_clb_row = 0; g_clb_row < CLB_ROW_COUNT; g_clb_row = g_clb_row + 1)
  begin: l_clb_rows_output_routing
    assign run_out[g_clb_row] =  clb_out[`CLB_COORDS(g_clb_row, CLB_COL_COUNT - 1)];
  end

  // ES seq/NW clk routing + diagonals

  logic [CLB_NUM_NEIGHBOUR_SIGNALS -1:0] run_in_neightbours [CLB_COUNT -1:0];

  for (genvar g_clb_row = 0; g_clb_row < CLB_ROW_COUNT; g_clb_row = g_clb_row + 1)
  begin: l_clb_rows_routing
    for (genvar g_clb_col = 0; g_clb_col < CLB_COL_COUNT; g_clb_col = g_clb_col + 1)
    begin: l_clb_cols_routing

`define IS_FIRST_ROW (g_clb_row == 0)
`define IS_FIRST_COL (g_clb_col == 0)
`define IS_LAST_ROW  (g_clb_row == CLB_ROW_COUNT - 1)
`define IS_LAST_COL  (g_clb_col == CLB_COL_COUNT - 1)

      assign run_in_neightbours[`CLB_COORDS(g_clb_row, g_clb_col)] =

        /* 7 -> E  */
        { `IS_LAST_COL
          ? 'x : clocked_clb_out[`CLB_COORDS(g_clb_row    , g_clb_col + 1)]

        /* 6 -> SE */
        , `IS_LAST_COL || `IS_LAST_ROW
          ? 'x : clocked_clb_out[`CLB_COORDS(g_clb_row + 1, g_clb_col + 1)]

        /* 5 -> S  */
        , `IS_LAST_ROW
          ? 'x : clocked_clb_out[`CLB_COORDS(g_clb_row + 1, g_clb_col    )]

        /* 4 -> SW */
        , `IS_LAST_ROW || `IS_FIRST_COL
          ? 'x : clocked_clb_out[`CLB_COORDS(g_clb_row + 1, g_clb_col - 1)]

        /* 3 -> W  */
        , `IS_FIRST_COL
          ? 'x : clb_out        [`CLB_COORDS(g_clb_row    , g_clb_col - 1)]

        /* 2 -> NW */
        , `IS_FIRST_COL || `IS_FIRST_ROW
          ? 'x : clb_out        [`CLB_COORDS(g_clb_row - 1, g_clb_col - 1)]

        /* 1 -> N  */
        , `IS_FIRST_ROW
          ? 'x : clb_out        [`CLB_COORDS(g_clb_row - 1, g_clb_col    )]

        /* 0 -> NE */
        , `IS_FIRST_ROW || `IS_LAST_COL
          ? 'x : clb_out        [`CLB_COORDS(g_clb_row - 1, g_clb_col + 1)]
        };
    end
  end

  for (genvar g_clb_idx = 0; g_clb_idx < CLB_COUNT; g_clb_idx = g_clb_idx + 1) begin: l_clbs
    axi_stream_if #( .DATA_WIDTH ( BITSTREAM_DATA_WIDTH ) ) clb_cfg_bitstream_if();

    assign clb_cfg_bitstream_if.tvalid         = cfg_bitstream.tvalid;
    assign clb_cfg_bitstream_if.tdata          = cfg_bitstream.tdata;
    assign clb_cfg_bitstream_if.tlast          = cfg_bitstream.tlast;
    assign clb_cfg_bitstream_tready[g_clb_idx] = clb_cfg_bitstream_if.tready;

    clb
      #(.NUM_NEIGHBOUR_SIGNALS ( CLB_NUM_NEIGHBOUR_SIGNALS )
      , .NUM_IO_SIGNALS        ( IO_INPUT_WDITH            )
      , .LUT_WIDTH             ( LUT_WIDTH                 )
      , .BITSTREAM_DATA_WIDTH  ( BITSTREAM_DATA_WIDTH      )
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
