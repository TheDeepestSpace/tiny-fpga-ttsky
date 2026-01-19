module clb
  #(parameter int unsigned NUM_NEIGHBOUR_SIGNALS
  , parameter int unsigned NUM_IO_SIGNALS
  , parameter int unsigned LUT_WIDTH
  )
  ( input var logic clk
  , input var logic rst_n

  , input var logic cfg
  , input var logic cfg_clb_data

  , input var logic                              run
  , input var logic [NUM_NEIGHBOUR_SIGNALS -1:0] run_in_neightbounrs
  , input var logic [NUM_IO_SIGNALS -1:0]        run_in_io // TODO: not all CLBs need IO access
  , input var logic                              run_in_feedback // TODO: allow CLBs without fb

  , output var logic run_out
  );

  // state declaration

  typedef enum logic [2:0]
    { STATE__INIT
    , STATE__CONFIG_LUT_INPUT__READ_TYPE  /* reads `BIT_STREAM_SIGNAL_TYPE_W` bits */
    , STATE__CONFIG_LUT_INPUT__READ_INDEX /* reads `BIT_STREAM_SIGNAL_IDX_LENGTH` bits */
    , STATE__CONFIG_LUT_INPUT__END
    , STATE__CONFIG_LUT_TRUTH_TABLE       /* reads `2^LUT_WIDTH-1` bits */
    , STATE__IDLE
    , STATE__RUN
    } t_state;

  t_state state_now, state_next;

  always_ff @ (posedge clk)
    if (!rst_n) state_now <= STATE__INIT;
    else        state_now <= state_next;

  // configuration

  localparam int unsigned BIT_STREAM_SIGNAL_TYPE_W = 2;
  // TODO: 8 bits should be prenty to udentify an address of any input type that we support right
  // now but in the future may potentially break things if the FPGA gets to be too large
  localparam int unsigned BIT_STREAM_SIGNAL_IDX_LENGTH = 8;

  // TODO: address this wild naming, idx_idx? whats next, {insert_punchline}?
  localparam int unsigned BIT_STREAM_SIGNAL_IDX_IDX_W  = $clog(BIT_STREAM_SIGNAL_IDX_IDX_W);

  typedef enum logic [BIT_STREAM_SIGNAL_TYPE_W -1:0]
    { INPUT_TYPE__NEIGHTBOUR
    , INPUT_TYPE__IO // TODO: not the best name but i think it carried a "outside world" connotation
    , INPUT_TYPE__FEEDBACK
    } t_input_type;

  localparam int unsigned NEIGHBOUR_SIGNAL_IDX_W  = $clog2(NUM_NEIGHBOUR_SIGNALS);
  localparam int unsigned IO_SIGNAL_IDX_W         = $clog2(NUM_IO_SIGNALS);
  localparam int unsigned LUT_INPUT_IDX_W         = $clog2(LUT_WIDTH);

  t_input_type lut_input_types [LUT_WIDTH -1:0];

  logic [NEIGHBOUR_SIGNAL_IDX_W -1:0] neighbour_signal_idx [LUT_WIDTH -1:0];
  logic [IO_SIGNAL_IDX_W -1:0]        io_signal_idx        [LUT_WIDTH -1:0];

  logic [LUT_INPUT_IDX_W -1:0] lut_input_iter;

  // this feeds straight into lut_input_types vec since the width is fixed
  logic [BIT_STREAM_SIGNAL_TYPE_W -1:0] lut_input_type_iter;

  // this feeds into an intermediate register since it will need to be down-casted into the right
  // size that correspods to the respective input type
  logic [BIT_STREAM_SIGNAL_IDX_IDX_W -1:0]  lut_input_index_iter;
  logic [BIT_STREAM_SIGNAL_IDX_W -1:0]      lut_input_index_raw;

  // LUT input type parsing

  always_ff @ (posedge clk)
    if (!rst_n)
      lut_input_iter <= '0;
    else
      case (state_now)
        STATE__INIT, STATE__IDLE:
          lut_input_iter <= '0;
        STATE__CONFIG_LUT_INPUT__END:
          if (lut_input_iter != LUT_WIDTH -1)
            lut_input_iter <= lut_input_iter + 1;
          else
            lut_input_iter <= lut_input_iter;
        default:
          lut_input_iter <= lut_input_iter;
      endcase

  always_ff @ (posedge clk)
    if (!rst_n)
      lut_input_type_iter <= '0;
    else
      case (state_now)
        STATE__INIT, STATE__IDLE, STATE__CONFIG_LUT_INPUT__END:
          lut_input_type_iter <= '0;
        STATE__CONFIG_LUT_INPUT__READ_TYPE:
          if (lut_input_type_iter != BIT_STREAM_SIGNAL_TYPE_W -1)
            lut_input_type_iter <= lut_input_type_iter + 1;
          else
            lut_input_type_iter <= lut_input_type_iter;
        default:
          lut_input_type_iter <= lut_input_type_iter;
      endcase

  for ( genvar g_lut_input_iter = 0;
        g_lut_input_iter < LUT_WIDTH;
        g_lut_input_iter = g_lut_input_iter + 1 ) begin: l_store_lut_input_types
    always_ff @ (posedge clk)
      if (!rst_n)
        lut_input_types[g_lut_input_iter] <= '0;
      else
        case (state_now)
          STATE__INIT: lut_input_types[g_lut_input_iter] <= '0;
          STATE__CONFIG_LUT_INPUT__READ_TYPE:
            if (lut_input_iter == g_lut_input_iter)
              // TODO: i would like the expression to not include second order subscript here since
              // it will create implicit latches; not a probelem but just want to be explicit
              lut_input_types
                [g_lut_input_iter]
                  [BIT_STREAM_SIGNAL_TYPE_W -1 - lut_input_type_iter] <= cfg_clb_data;
            else
              lut_input_types[g_lut_input_iter] <= lut_input_types[g_lut_input_iter];
          default:
            lut_input_types[g_lut_input_iter] <= lut_input_types[g_lut_input_iter];
        endcase
  end

  // LUT input input for a given type

  always_ff @ (posedge clk)
    if (!rst_n)
      lut_input_index_iter <= '0;
    else
      case (state_now)
        STATE__INIT, STATE__IDLE, STATE__CONFIG_LUT_INPUT__END:
          lut_input_index_iter <= '0;
        STATE__CONFIG_LUT_INPUT__READ_INDEX:
          if (lut_input_index_iter != BIT_STREAM_SIGNAL_IDX_W -1)
            lut_input_index_iter <= lut_input_index_iter + 1;
          else
            lut_input_index_iter <= lut_input_index_iter;
        default:
          lut_input_index_iter <= lut_input_index_iter;
      endcase

  // fill up the raw type-independent index register
  always_ff @ (posedge clk)
    if (!rst_n) lut_input_index_raw <= '0;
    else
      case (state_now)
        STATE__INIT, STATE__IDLE, STATE__CONFIG_LUT_INPUT__END:
          lut_input_index_raw <= '0;
        STATE__CONFIG_LUT_INPUT__READ_INDEX:
          // TODO: again, not a fan of subsciprt here, rewrite in such a wauy that this line looks
          // like `lut_input_index_raw <= ...` while maintaining the same functionality
          lut_input_index_raw[lut_input_index_iter] <= cfg_clb_data;
        default:
          lut_input_index_raw <= lut_input_index_raw;
      endcase

  // propagate the type-independent raw register into the corresponding type's register for
  // a given LUT input
  for ( genvar g_lut_input_iter = 0;
        g_lut_input_iter < LUT_WIDTH;
        g_lut_input_iter = g_lut_input_iter + 1 ) begin: l_store_lut_input_type_specific_indices
    always_ff @ (posedge clk)
      if (!rst_n) neighbour_signal_idx[g_lut_input_iter] <= '0;
      else
        case (state_now)
          STATE__INIT: neighbour_signal_idx[g_lut_input_iter] <= '0;
          STATE__CONFIG_LUT_INPUT__END:
            if (lut_input_types[g_lut_input_iter] == INPUT_TYPE__NEIGHTBOUR
                && lut_input_index_iter == g_lut_input_iter)
              neighbour_signal_idx[g_lut_input_iter] <=
                NEIGHBOUR_SIGNAL_IDX_W'(lut_input_index_raw);
            else
              neighbour_signal_idx[g_lut_input_iter] <= neighbour_signal_idx[g_lut_input_iter];
          default:
            neighbour_signal_idx[g_lut_input_iter] <= neighbour_signal_idx[g_lut_input_iter];
        endcase

    always_ff @ (posedge clk)
      if (!rst_n) io_signal_idx[g_lut_input_iter] <= '0;
      else
        case (state_now)
          STATE__INIT: io_signal_idx[g_lut_input_iter] <= '0;
          STATE__CONFIG_LUT_INPUT__END:
            if (lut_input_types[g_lut_input_iter] == INPUT_TYPE__IO
                && lut_input_index_iter == g_lut_input_iter)
              io_signal_idx[g_lut_input_iter] <= IO_SIGNAL_IDX_W'(lut_input_index_raw);
            else
              io_signal_idx[g_lut_input_iter] <= io_signal_idx[g_lut_input_iter];
          default:
            io_signal_idx[g_lut_input_iter] <= io_signal_idx[g_lut_input_iter];
        endcase
  end


  // configure LUT input truth table

  localparam int unsigned LUT_DEPTH = 1 << LUT_WIDTH;
  localparam int unsigned LUT_DEPTH_W = $clog(LUT_DEPTH);

  logic [LUT_DEPTH_W -1:0] lut_truth_table_iter;

  always_ff @ (posedge clk)
    if (!rst_n) lut_truth_table_iter <= '0;
    else
      case (state_now)
        STATE__INIT, STATE__IDLE:
          lut_truth_table_iter <= '0;
        STATE__CONFIG_LUT_TRUTH_TABLE:
          if (lut_truth_table_iter != LUT_DEPTH_W -1)
            lut_input_index_iter <= lut_input_index_iter + 1;
          else
            lut_input_index_iter <= lut_input_index_iter;
        default:
          lut_input_index_iter <= lut_input_index_iter;
      endcase

  // LUT inputs

  logic [LUT_WIDTH -1:0] lut_run_in;

  for ( genvar g_lut_input_iter = 0;
        g_lut_input_iter < LUT_WIDTH;
        g_lut_input_iter = g_lut_input_iter + 1 ) begin: l_lut_inputs_mux
    always_comb
      case (lut_input_types[g_lut_input_iter])
        INPUT_TYPE__NEIGHTBOUR:
          lut_run_in[g_lut_input_iter] =
            run_in_neightbounrs[neighbour_signal_index[g_lut_input_iter]];
        INPUT_TYPE__IO:
          lut_run_in[g_lut_input_iter] = run_in_io[io_signal_idx[g_lut_input_iter]];
        INPUT_TYPE__FEEDBACK:
          lut_run_in[g_lut_input_iter] = run_in_feedback;
        default:
          lut_run_in[g_lut_input_iter] = 'x;
      endcase
  end

  // instantiate LUT

  logic lut_run_out;

  lut #( .WIDTH ( LUT_WIDTH ), .DEPTH ( LUT_DEPTH ) )
    u_lut
      ( .clk   ( clk   )
      , .rst_n ( rst_n )

      , .cfg                  ( cfg && state_now == STATE__CONFIG_LUT_TRUTH_TABLE )
      , .cfg_truth_table_data ( cfg_clb_data                                      )

      , .run     ( run         )
      , .run_in  ( lut_run_in  )
      , .run_out ( lut_run_out )
      );

  // state transition

  always_comb
    case (state_now)
      STATE__INIT:
        if (cfg)
          state_next = STATE__CONFIG_LUT_INPUT__READ_TYPE;
        else
          state_next = STATE__INIT;
      STATE__CONFIG_LUT_INPUT__READ_TYPE:
        if (lut_input_type_iter == BIT_STREAM_SIGNAL_TYPE_W - 1)
          state_next = STATE__CONFIG_LUT_INPUT__READ_INDEX;
        else
          state_next = STATE__CONFIG_LUT_INPUT__READ_TYPE;
      STATE__CONFIG_LUT_INPUT__READ_INDEX:
        if (lut_input_index_iter == BIT_STREAM_SIGNAL_IDX_IDX_W - 1)
          state_next = STATE__CONFIG_LUT_INPUT__END;
        else
          state_next = STATE__CONFIG_LUT_INPUT__READ_INDEX;
      STATE__CONFIG_LUT_INPUT__END:
        state_next = STATE__CONFIG_LUT_TRUTH_TABLE;
      STATE__CONFIG_LUT_TRUTH_TABLE:
        if (lut_truth_table_iter == LUT_DEPTH -1)
          state_next = STATE__IDLE;
        else
          state_next = STATE__CONFIG_LUT_TRUTH_TABLE;
      STATE__IDLE:
        if (run)
          state_next = STATE__RUN;
        else
          state_next = STATE__IDLE;
      STATE__RUN:
        if (run)
          state_next = STATE__RUN;
        else if (cfg)
          state_next = STATE__CONFIG;
        else
          state_next = STATE__IDLE;
      default:
        state_next = STATE__INIT;
    endcase


endmodule
