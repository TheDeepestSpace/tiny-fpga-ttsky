`default_nettype none

module lut
  #(parameter int unsigned WIDTH
  , parameter int unsigned DEPTH = 1 << WIDTH
  )
  ( input var logic clk
  , input var logic rst_n

  , input var logic     cfg
    // TODO: design currently does not protect against rouge `tlast`s
  , axi_stream_if.slave cfg_bitstream
  , output var logic    cfg_ready

  , input  var logic              run
  , input  var logic [WIDTH -1:0] run_in
  , output var logic              run_out
  );

  // state declarations

  typedef enum logic [2:0]
    { STATE__INIT
    , STATE__CONFIG_TRUTH_TABLE_BEGIN
    , STATE__CONFIG_TRUTH_TABLE_WAIT
    , STATE__IDLE
    , STATE__RUN
    } state_t;

  state_t state_now, state_next;

  always_ff @ (posedge clk)
    if (!rst_n) state_now <= STATE__INIT;
    else        state_now <= state_next;

  // configuration

  logic [DEPTH -1:0] truth_table;
  logic truth_table_ready;

  bitstream_reader #( .NUM_BITS_TO_READ ( DEPTH ) )
    u_bitstream_reader_trush_table
      ( .clk   ( clk   )
      , .rst_n ( rst_n )

      , .start     ( state_now == STATE__CONFIG_TRUTH_TABLE_BEGIN )
      , .bitstream ( cfg_bitstream                                )

      , .ready ( truth_table_ready )
      , .bits  ( truth_table       )
      );

  // runtime

  always_comb
    if (state_now == STATE__RUN)
      run_out = truth_table[run_in];
    else
      run_out = 'x;

  // state transitions

  always_comb
    case (state_now)
      STATE__INIT:
        if (cfg)
          state_next = STATE__CONFIG_TRUTH_TABLE_BEGIN;
        else
          state_next = STATE__INIT;
      STATE__CONFIG_TRUTH_TABLE_BEGIN, STATE__CONFIG_TRUTH_TABLE_WAIT:
        if (truth_table_ready)
          state_next = STATE__IDLE;
        else
          state_next = STATE__CONFIG_TRUTH_TABLE_WAIT;
      STATE__IDLE:
        if (run)
          state_next = STATE__RUN;
        else
          state_next = STATE__IDLE;
      STATE__RUN:
        if (run)
          state_next = STATE__RUN;
        else if (cfg)
          state_next = STATE__CONFIG_TRUTH_TABLE_BEGIN;
        else
          state_next = STATE__IDLE;
      default:
        state_next = STATE__INIT;
    endcase

endmodule
