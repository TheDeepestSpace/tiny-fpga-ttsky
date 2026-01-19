`default_nettype none

module lut
  #(parameter int unsigned WIDTH
  , parameter int unsigned DEPTH = 1 << WIDTH
  )
  ( input var logic clk
  , input var logic rst_n

  , input var logic cfg
  , input var logic cfg_truth_table_data

  , input  var logic              run
  , input  var logic [WIDTH -1:0] run_in
  , output var logic              run_out
  );

  // state declarations

  typedef enum logic [2:0]
    { STATE__INIT
    , STATE__CONFIG
    , STATE__IDLE
    , STATE__RUN
    } state_t;

  state_t state_now, state_next;

  always_ff @ (posedge clk)
    if (!rst_n) state_now <= STATE__INIT;
    else        state_now <= state_next;

  // configuration

  logic [DEPTH -1:0] truth_table;
  logic [WIDTH -1:0] truth_table_iter;

  // TODO: i actually dont think this is necessary; im forcing the consumer to hold this signal on
  // the the amounf of clock cycles this module knows it needs; does not make much sense; let cfg
  // ping once, then return to consume when we are done confooguring
  property p_cfg_duration;
    @(posedge clk) disable iff (!rst_n)
      $rose(cfg) |-> (cfg[*DEPTH] ##1 !cfg);
  endproperty
  assert property (p_cfg_duration);

  always_ff @ (posedge clk)
    if (!rst_n)                   truth_table_iter <= '0;
    else
      case (state_now)
        STATE__INIT, STATE__IDLE: truth_table_iter <= '0;
        STATE__CONFIG:            truth_table_iter <= truth_table_iter + 1;
        default:                  truth_table_iter <= truth_table_iter;
      endcase

  for ( genvar truth_table_entry_index = 0;
        truth_table_entry_index < DEPTH;
        truth_table_entry_index = truth_table_entry_index + 1 ) begin: l_truth_table_config
    always_ff @ (posedge clk)
      if (!rst_n) truth_table[truth_table_entry_index] <= '0;
      else
        case (state_now)
          STATE__INIT:
            truth_table[truth_table_entry_index] <= '0;
          STATE__CONFIG:
            if (truth_table_entry_index == truth_table_iter)
              truth_table[truth_table_entry_index] <= cfg_truth_table_data;
            else
              truth_table[truth_table_entry_index] <= truth_table[truth_table_entry_index];
          default:
            truth_table[truth_table_entry_index] <= truth_table[truth_table_entry_index];
        endcase
  end

  // runtime

  always_comb
    if (state_now == STATE__RUN)
      run_out = truth_table[run_in];
    else
      run_out = 'x;

  // state transitions

  always_comb
    case (state_now)
      STATE__INIT:    if (cfg)      state_next = STATE__CONFIG;
                      else          state_next = STATE__INIT;
      STATE__CONFIG:  if (!cfg)     state_next = STATE__IDLE;
                      else          state_next = STATE__CONFIG;
      STATE__IDLE:    if (run)      state_next = STATE__RUN;
                      else          state_next = STATE__IDLE;
      STATE__RUN:     if (run)      state_next = STATE__RUN;
                      else if (cfg) state_next = STATE__CONFIG;
                      else          state_next = STATE__IDLE;
      default:                      state_next = STATE__INIT;
    endcase

endmodule
