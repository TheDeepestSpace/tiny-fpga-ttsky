`default_nettype none

module clb
  #(parameter int unsigned NUM_NEIGHBOUR_SIGNALS
  , parameter int unsigned NUM_IO_SIGNALS
  , parameter int unsigned LUT_WIDTH
  , parameter int unsigned BITSTREAM_DATA_WIDTH
  )
  ( input var logic clk
  , input var logic rst_n

  , input  var logic    cfg
    // TODO: design currently does not protect against rouge `tlast`s
  , axi_stream_if.slave cfg_bitstream
  , output var logic    cfg_ready

  , input var logic                              run
  , input var logic [NUM_NEIGHBOUR_SIGNALS -1:0] run_in_neightbours
  , input var logic [NUM_IO_SIGNALS -1:0]        run_in_io // TODO: not all CLBs need IO access
  , input var logic                              run_in_feedback // TODO: allow CLBs without fb

  , output var logic run_out
  );

  // state declaration

  typedef enum logic [3:0]
    { STATE__INIT
    , STATE__CONFIG_LUT_INPUT__READ_TYPE_BEGIN
    , STATE__CONFIG_LUT_INPUT__READ_TYPE_WAIT
    , STATE__CONFIG_LUT_INPUT__READ_INDEX_BEGIN
    , STATE__CONFIG_LUT_INPUT__READ_INDEX_WAIT
    , STATE__CONFIG_LUT_INPUT__END
    , STATE__CONFIG_LUT_BEGIN
    , STATE__CONFIG_LUT_WAIT
    , STATE__IDLE
    , STATE__RUN
    } t_state;

  t_state state_now, state_next;

  always_ff @ (posedge clk)
    if (!rst_n) state_now <= STATE__INIT;
    else        state_now <= state_next;

  // bitstream reader proxies

  axi_stream_if #( BITSTREAM_DATA_WIDTH ) cfg_bitstream_input_type_if();
  axi_stream_if #( BITSTREAM_DATA_WIDTH ) cfg_bitstream_input_index_if();
  axi_stream_if #( BITSTREAM_DATA_WIDTH ) cfg_bitstream_lut_if();

  assign cfg_bitstream_input_index_if.tvalid = cfg_bitstream.tvalid;
  assign cfg_bitstream_input_index_if.tdata  = cfg_bitstream.tdata;
  assign cfg_bitstream_input_index_if.tlast  = cfg_bitstream.tlast;

  assign cfg_bitstream_input_type_if.tvalid = cfg_bitstream.tvalid;
  assign cfg_bitstream_input_type_if.tdata  = cfg_bitstream.tdata;
  assign cfg_bitstream_input_type_if.tlast  = cfg_bitstream.tlast;

  assign cfg_bitstream_lut_if.tvalid = cfg_bitstream.tvalid;
  assign cfg_bitstream_lut_if.tdata  = cfg_bitstream.tdata;
  assign cfg_bitstream_lut_if.tlast  = cfg_bitstream.tlast;

  always_comb
    case (state_now)
      STATE__CONFIG_LUT_INPUT__READ_INDEX_BEGIN, STATE__CONFIG_LUT_INPUT__READ_INDEX_WAIT:
        cfg_bitstream.tready = cfg_bitstream_input_index_if.tready;
      STATE__CONFIG_LUT_INPUT__READ_TYPE_BEGIN, STATE__CONFIG_LUT_INPUT__READ_TYPE_WAIT:
        cfg_bitstream.tready = cfg_bitstream_input_type_if.tready;
      STATE__CONFIG_LUT_BEGIN, STATE__CONFIG_LUT_WAIT:
        cfg_bitstream.tready = cfg_bitstream_lut_if.tready;
      default:
        cfg_bitstream.tready = '0;
    endcase

  // configuration

  localparam int unsigned SIGNAL_TYPE_W = 2;
  // TODO: 8 bits should be prenty to udentify an address of any input type that we support right
  // now but in the future may potentially break things if the FPGA gets to be too large
  localparam int unsigned SIGNAL_INDEX_W = 8;

  typedef enum logic [SIGNAL_TYPE_W -1:0]
    { INPUT_TYPE__NEIGHTBOUR
    , INPUT_TYPE__IO // TODO: not the best name but i think it carried a "outside world" connotation
    , INPUT_TYPE__FEEDBACK
    } t_input_type;

  localparam int unsigned NEIGHBOUR_SIGNAL_IDX_W  = $clog2(NUM_NEIGHBOUR_SIGNALS);
  localparam int unsigned IO_SIGNAL_IDX_W         = $clog2(NUM_IO_SIGNALS);
  localparam int unsigned LUT_INPUT_IDX_W         = $clog2(LUT_WIDTH);

  t_input_type lut_input_types [LUT_WIDTH -1:0];

  logic [NEIGHBOUR_SIGNAL_IDX_W -1:0]  neighbour_signal_idx [LUT_WIDTH -1:0];
  logic [IO_SIGNAL_IDX_W -1:0]         io_signal_idx        [LUT_WIDTH -1:0];

  logic [LUT_INPUT_IDX_W -1:0] lut_input_iter;
  logic                        lut_inputs_configured;

  // LUT input iterator

  assign lut_inputs_configured = lut_input_iter == LUT_INPUT_IDX_W'(LUT_WIDTH -1);

  always_ff @ (posedge clk)
    if (!rst_n)
      lut_input_iter <= '0;
    else
      case (state_now)
        STATE__INIT, STATE__IDLE:
          lut_input_iter <= '0;
        STATE__CONFIG_LUT_INPUT__END:
          if (lut_input_iter != LUT_INPUT_IDX_W'(LUT_WIDTH -1))
            lut_input_iter <= lut_input_iter + 1;
          else
            lut_input_iter <= lut_input_iter;
        default:
          lut_input_iter <= lut_input_iter;
      endcase

  // LUT input type parsing

  logic                      lut_input_type_ready;
  logic [SIGNAL_TYPE_W -1:0] lut_input_type_raw;

  bitstream_reader #( .NUM_BITS_TO_READ ( SIGNAL_TYPE_W ) )
    u_bitstream_reader_input_type
      ( .clk   ( clk   )
      , .rst_n ( rst_n )

      , .start     ( state_now == STATE__CONFIG_LUT_INPUT__READ_TYPE_BEGIN )
      , .bitstream ( cfg_bitstream_input_type_if.slave                     )

      , .ready ( lut_input_type_ready )
      , .bits  ( lut_input_type_raw   )
      );

  for ( genvar g_lut_input_iter = 0;
        g_lut_input_iter < LUT_WIDTH;
        g_lut_input_iter = g_lut_input_iter + 1 ) begin: l_store_lut_input_types
    always_ff @ (posedge clk)
      if (!rst_n)
        lut_input_types[g_lut_input_iter] <= t_input_type'('0);
      else
        case (state_now)
          STATE__INIT:
            lut_input_types[g_lut_input_iter] <= t_input_type'('0);
          // it feels a bit odd to write lut input type on this state, but its necessary since we
          // want to make sure we will be writing the index of the input for the proper type when we
          // are done reading the index; i used to write lut input type on
          // STATE__CONFIG_LUT_INPUT__END but it was causing a bug where the index would  keep being
          // written into neightbour index because that's the default type and `lut_input_types`
          // would be written to on the same clock cycle (i.e. not avaialbe at the time fo writing
          // index); on the other hand it would also be possible to write to both neightbour and io
          // index arrays and it would be resolved at run time; revisit
          STATE__CONFIG_LUT_INPUT__READ_INDEX_BEGIN:
            if (lut_input_iter == g_lut_input_iter)
              lut_input_types[g_lut_input_iter] <= t_input_type'(lut_input_type_raw);
            else
              lut_input_types[g_lut_input_iter] <= lut_input_types[g_lut_input_iter];
          default:
            lut_input_types[g_lut_input_iter] <= lut_input_types[g_lut_input_iter];
        endcase
  end

  // LUT input index for a given type

  logic                       lut_input_index_ready;
  logic [SIGNAL_INDEX_W -1:0] lut_input_index_raw;

  bitstream_reader #( .NUM_BITS_TO_READ ( SIGNAL_INDEX_W ) )
    u_bitstream_reader_input_index
      ( .clk   ( clk   )
      , .rst_n ( rst_n )

      , .start     ( state_now == STATE__CONFIG_LUT_INPUT__READ_INDEX_BEGIN )
      , .bitstream ( cfg_bitstream_input_index_if.slave                     )

      , .ready ( lut_input_index_ready )
      , .bits  ( lut_input_index_raw   )
      );

  for ( genvar g_lut_input_iter = 0;
        g_lut_input_iter < LUT_WIDTH;
        g_lut_input_iter = g_lut_input_iter + 1 ) begin: l_store_lut_input_type_specific_indices
    always_ff @ (posedge clk)
      if (!rst_n)
        neighbour_signal_idx[g_lut_input_iter] <= '0;
      else
        case (state_now)
          STATE__INIT:
            neighbour_signal_idx[g_lut_input_iter] <= '0;
          STATE__CONFIG_LUT_INPUT__END:
            if (lut_input_types[g_lut_input_iter] == INPUT_TYPE__NEIGHTBOUR
                && lut_input_iter == g_lut_input_iter)
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
                && lut_input_iter == g_lut_input_iter)
              io_signal_idx[g_lut_input_iter] <= IO_SIGNAL_IDX_W'(lut_input_index_raw);
            else
              io_signal_idx[g_lut_input_iter] <= io_signal_idx[g_lut_input_iter];
          default:
            io_signal_idx[g_lut_input_iter] <= io_signal_idx[g_lut_input_iter];
        endcase
  end

  // LUT inputs

  logic [LUT_WIDTH -1:0] lut_run_in;

  for ( genvar g_lut_input_iter = 0;
        g_lut_input_iter < LUT_WIDTH;
        g_lut_input_iter = g_lut_input_iter + 1 ) begin: l_lut_inputs_mux
    always_comb
      case (lut_input_types[g_lut_input_iter])
        INPUT_TYPE__NEIGHTBOUR:
          lut_run_in[g_lut_input_iter] =
            run_in_neightbours[neighbour_signal_idx[g_lut_input_iter]];
        INPUT_TYPE__IO:
          lut_run_in[g_lut_input_iter] =
            run_in_io[io_signal_idx[g_lut_input_iter]];
        INPUT_TYPE__FEEDBACK:
          lut_run_in[g_lut_input_iter] = run_in_feedback;
        default:
          lut_run_in[g_lut_input_iter] = 'x;
      endcase
  end

  // instantiate LUT

  logic lut_cfg_ready;
  logic lut_run_out;

  assign cfg_ready = lut_cfg_ready;

  // TODO: add FF bells-and-whistles
  assign run_out = lut_run_out;

  lut #( .WIDTH ( LUT_WIDTH ) )
    u_lut
      ( .clk   ( clk   )
      , .rst_n ( rst_n )

      , .cfg                  ( state_now == STATE__CONFIG_LUT_BEGIN )
      , .cfg_bitstream        ( cfg_bitstream_lut_if.slave           )
      , .cfg_ready            ( lut_cfg_ready                        )

      , .run     ( run         )
      , .run_in  ( lut_run_in  )
      , .run_out ( lut_run_out )
      );

  // state transition

  always_comb
    case (state_now)
      STATE__INIT:
        if (cfg)
          state_next = STATE__CONFIG_LUT_INPUT__READ_TYPE_BEGIN;
        else
          state_next = STATE__INIT;
      STATE__CONFIG_LUT_INPUT__READ_TYPE_BEGIN, STATE__CONFIG_LUT_INPUT__READ_TYPE_WAIT:
        if (lut_input_type_ready)
          state_next = STATE__CONFIG_LUT_INPUT__READ_INDEX_BEGIN;
        else
          state_next = STATE__CONFIG_LUT_INPUT__READ_TYPE_WAIT;
      STATE__CONFIG_LUT_INPUT__READ_INDEX_BEGIN, STATE__CONFIG_LUT_INPUT__READ_INDEX_WAIT:
        if (lut_input_index_ready)
          state_next = STATE__CONFIG_LUT_INPUT__END;
        else
          state_next = STATE__CONFIG_LUT_INPUT__READ_INDEX_WAIT;
      STATE__CONFIG_LUT_INPUT__END:
        if (lut_inputs_configured)
          state_next = STATE__CONFIG_LUT_BEGIN;
        else
          state_next = STATE__CONFIG_LUT_INPUT__READ_TYPE_BEGIN;
      STATE__CONFIG_LUT_BEGIN, STATE__CONFIG_LUT_WAIT:
        if (lut_cfg_ready)
          state_next = STATE__IDLE;
        else
          state_next = STATE__CONFIG_LUT_WAIT;
      STATE__IDLE:
        if (run)
          state_next = STATE__RUN;
        else
          state_next = STATE__IDLE;
      STATE__RUN:
        if (run)
          state_next = STATE__RUN;
        else if (cfg)
          state_next = STATE__CONFIG_LUT_INPUT__READ_TYPE_BEGIN;
        else
          state_next = STATE__IDLE;
      default:
        state_next = STATE__INIT;
    endcase


endmodule
