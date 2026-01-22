import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# readable enum values for bitstream creation
INPUT_TYPE_NEIGHBOUR = 0
INPUT_TYPE_IO = 1
SIGNAL_TYPE_W = 2
SIGNAL_INDEX_W = 8
OUTPUT_TYPE_SEQUENTIAL = 0
OUTPUT_TYPE_CLOCKED = 1
OUTPUT_TYPE_W = 1

def _bits_lsb_first(value, width):
  return [(value >> i) & 1 for i in range(width)]

# have to set up the bit stream on our own since cocotb's extension for AXI cannot handle anything
# below 1 byte in width
async def _send_bits(dut, bits, max_wait_cycles=1000):
  dut.cfg_bitstream.tvalid.value = 0
  dut.cfg_bitstream.tdata.value = 0
  dut.cfg_bitstream.tlast.value = 0

  saw_cfg_ready_last = False
  for i, bit in enumerate(bits):
    last = 1 if i == len(bits) - 1 else 0
    for _ in range(max_wait_cycles):
      await RisingEdge(dut.clk)
      if dut.cfg_bitstream.tready.value:
        dut.cfg_bitstream.tvalid.value = 1
        dut.cfg_bitstream.tdata.value = bit
        dut.cfg_bitstream.tlast.value = last
        break
    else:
      raise RuntimeError("Timed out waiting for cfg_bitstream.tready")

  await RisingEdge(dut.clk)
  dut.cfg_bitstream.tvalid.value = 0
  dut.cfg_bitstream.tlast.value = 0

  await RisingEdge(dut.clk)
  return dut.cfg_ready.value != 0

@cocotb.test()
async def test_xor_sequential_gate(dut):
  clock = Clock(dut.clk, 10, unit="ns")
  cocotb.start_soon(clock.start())

  dut.rst_n.value = 0
  dut.cfg.value = 0
  dut.run.value = 0
  dut.run_in_neightbours.value = 0
  dut.run_in_io.value = 0
  dut.run_in_feedback.value = 0
  dut.cfg_bitstream.tvalid.value = 0
  dut.cfg_bitstream.tdata.value = 0
  dut.cfg_bitstream.tlast.value = 0

  await ClockCycles(dut.clk, 5)
  dut.rst_n.value = 1

  # Build bitstream:
  # LUT inputs 0..3: IO0, IO1, NEIGHBOUR0, NEIGHBOUR1
  INPUT_TYPE_NEIGHBOUR = 0
  INPUT_TYPE_IO = 1
  SIGNAL_TYPE_W = 2
  SIGNAL_INDEX_W = 8
  OUTPUT_TYPE_SEQUENTIAL = 0
  OUTPUT_TYPE_CLOCKED = 1
  OUTPUT_TYPE_W = 1

  bits = []
  bits += _bits_lsb_first(INPUT_TYPE_IO, SIGNAL_TYPE_W)
  bits += _bits_lsb_first(0, SIGNAL_INDEX_W)
  bits += _bits_lsb_first(INPUT_TYPE_IO, SIGNAL_TYPE_W)
  bits += _bits_lsb_first(1, SIGNAL_INDEX_W)
  bits += _bits_lsb_first(INPUT_TYPE_NEIGHBOUR, SIGNAL_TYPE_W)
  bits += _bits_lsb_first(0, SIGNAL_INDEX_W)
  bits += _bits_lsb_first(INPUT_TYPE_NEIGHBOUR, SIGNAL_TYPE_W)
  bits += _bits_lsb_first(1, SIGNAL_INDEX_W)
  bits += _bits_lsb_first(OUTPUT_TYPE_SEQUENTIAL, OUTPUT_TYPE_W)

  # LUT truth table for 4-input XOR (odd parity of 4 bits).
  bits += [bin(i).count("1") % 2 for i in range(16)]

  dut.cfg.value = 1
  await RisingEdge(dut.clk)
  dut.cfg.value = 0
  await RisingEdge(dut.clk)
  saw_cfg_ready_last = await _send_bits(dut, bits)
  assert saw_cfg_ready_last

  # Run: all four inputs high -> expect 0 (even parity)
  dut.run_in_io.value = 0b0011
  dut.run_in_neightbours.value = 0b0011
  dut.run_in_feedback.value = 0
  dut.run.value = 1
  await RisingEdge(dut.clk)
  dut.run.value = 0

  await RisingEdge(dut.clk)
  assert dut.run_out.value == 0

  # One input low -> expect 1 (odd parity)
  dut.run_in_io.value = 0b0001
  await RisingEdge(dut.clk)
  assert dut.run_out.value == 1

@cocotb.test()
async def test_xor_clocked_gate(dut):
  clock = Clock(dut.clk, 10, unit="ns")
  cocotb.start_soon(clock.start())

  dut.rst_n.value = 0
  dut.cfg.value = 0
  dut.run.value = 0
  dut.run_in_neightbours.value = 0
  dut.run_in_io.value = 0
  dut.run_in_feedback.value = 0
  dut.cfg_bitstream.tvalid.value = 0
  dut.cfg_bitstream.tdata.value = 0
  dut.cfg_bitstream.tlast.value = 0

  await ClockCycles(dut.clk, 5)
  dut.rst_n.value = 1

  # Build bitstream:
  # LUT inputs 0..3: IO0, IO1, NEIGHBOUR0, NEIGHBOUR1
  bits = []
  bits += _bits_lsb_first(INPUT_TYPE_IO, SIGNAL_TYPE_W)
  bits += _bits_lsb_first(0, SIGNAL_INDEX_W)
  bits += _bits_lsb_first(INPUT_TYPE_IO, SIGNAL_TYPE_W)
  bits += _bits_lsb_first(1, SIGNAL_INDEX_W)
  bits += _bits_lsb_first(INPUT_TYPE_NEIGHBOUR, SIGNAL_TYPE_W)
  bits += _bits_lsb_first(0, SIGNAL_INDEX_W)
  bits += _bits_lsb_first(INPUT_TYPE_NEIGHBOUR, SIGNAL_TYPE_W)
  bits += _bits_lsb_first(1, SIGNAL_INDEX_W)
  bits += _bits_lsb_first(OUTPUT_TYPE_CLOCKED, OUTPUT_TYPE_W)

  # LUT truth table for 4-input XOR (odd parity of 4 bits).
  bits += [bin(i).count("1") % 2 for i in range(16)]

  dut.cfg.value = 1
  await RisingEdge(dut.clk)
  dut.cfg.value = 0
  await RisingEdge(dut.clk)
  saw_cfg_ready_last = await _send_bits(dut, bits)
  assert saw_cfg_ready_last

  # Run: one input low -> expect 1 (odd parity)
  dut.run_in_io.value = 0b0001
  dut.run_in_neightbours.value = 0b0011
  dut.run_in_feedback.value = 0
  dut.run.value = 1
  await RisingEdge(dut.clk)
  dut.run.value = 0

  await RisingEdge(dut.clk)
  assert dut.run_out.value == 0 # not clocked through yet
  await RisingEdge(dut.clk)
  assert dut.run_out.value == 1 # clocked value comes through

  # all input high -> expect 0 (even parity)
  dut.run_in_io.value = 0b0011
  await RisingEdge(dut.clk)
  
  assert dut.run_out.value == 1 # old clocked value
  await RisingEdge(dut.clk)
  assert dut.run_out.value == 0 # clocked value comes through
