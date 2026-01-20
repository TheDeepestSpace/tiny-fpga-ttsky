`default_nettype none

module bitstream_reader #( parameter int unsigned NUM_BITS_TO_READ )
  ( input var logic clk
  , input var logic rst_n

  , input  var logic    start
    // TODO: design currently does not protect against rouge `tlast`s
  , axi_stream_if.slave bitstream

  , output var logic                         ready
  , output var logic [NUM_BITS_TO_READ -1:0] bits
  );

  // state declarations

  typedef enum logic [2:0]
    { STATE__INIT
    , STATE__READ_BIT
    , STATE__DONE
    } t_state;

  t_state state_now, state_next;

  always_ff @ (posedge clk)
    if (!rst_n) state_now <= STATE__INIT;
    else        state_now <= state_next;

  // readiness indicator

  assign bitstream.tready = state_now == STATE__READ_BIT;

  // reader iterator

  localparam int unsigned NUM_BITS_TO_READ_W = NUM_BITS_TO_READ <= 1 ? 1 : $clog2(NUM_BITS_TO_READ);

  logic [NUM_BITS_TO_READ_W -1:0] bit_iter;
  logic read_enough_bits;

  assign read_enough_bits = bit_iter == NUM_BITS_TO_READ_W'(NUM_BITS_TO_READ -1);

  always_ff @ (posedge clk)
    if (!rst_n)                                                      bit_iter <= '0;
    else
      case (state_now)
        STATE__INIT:                                                 bit_iter <= '0;
        STATE__READ_BIT:  if (!read_enough_bits && bitstream.tvalid) bit_iter <= bit_iter + 1;
                          else                                       bit_iter <= bit_iter;
        default:                                                     bit_iter <= bit_iter;
      endcase

  // reading bits

  always_ff @ (posedge clk)
    if (!rst_n)                                 bits <= '0;
    else
      case (state_now)
        STATE__READ_BIT:  if (bitstream.tvalid) bits[bit_iter] <= bitstream.tdata;
                          else                  bits[bit_iter] <= bits[bit_iter];
        default:                                bits[bit_iter] <= bits[bit_iter];
      endcase

  // completeness check

  assign ready = state_now == STATE__DONE;

  // state machine logic

  always_comb
    case (state_now)
      STATE__INIT:      if (start)            state_next = STATE__READ_BIT;
                        else                  state_next = STATE__INIT;
      STATE__READ_BIT:  if (read_enough_bits) state_next = STATE__DONE;
                        else                  state_next = STATE__READ_BIT;
      STATE__DONE:                            state_next = STATE__INIT;
      default:                                state_next = STATE__INIT;
    endcase

endmodule
