import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

import tfbb

async def _send_bits(dut, bits, max_wait_cycles=1000):
  dut.cfg_bitstream.tvalid.value = 0
  dut.cfg_bitstream.tdata.value = 0
  dut.cfg_bitstream.tlast.value = 0

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
async def test_basic_reset(dut):
  clock = Clock(dut.clk, 10, unit="ns")
  cocotb.start_soon(clock.start())

  dut.rst_n.value = 0
  dut.cfg.value = 0
  dut.run.value = 0
  dut.run_in.value = 0
  dut.cfg_bitstream.tvalid.value = 0
  dut.cfg_bitstream.tdata.value = 0
  dut.cfg_bitstream.tlast.value = 0

  await ClockCycles(dut.clk, 5)
  dut.rst_n.value = 1
  await ClockCycles(dut.clk, 1)

@cocotb.test()
async def test_config_from_yaml(dut):
  clock = Clock(dut.clk, 10, unit="ns")
  cocotb.start_soon(clock.start())

  dut.rst_n.value = 0
  dut.cfg.value = 0
  dut.run.value = 0
  dut.run_in.value = 0
  dut.cfg_bitstream.tvalid.value = 0
  dut.cfg_bitstream.tdata.value = 0
  dut.cfg_bitstream.tlast.value = 0

  await ClockCycles(dut.clk, 5)
  dut.rst_n.value = 1

  design_path = os.path.join(
    os.path.dirname(__file__),
    "inputs",
    "first_test.yaml",
  )
  bits = tfbb.design_file_to_bitstream(design_path)

  dut.cfg.value = 1
  await RisingEdge(dut.clk)
  dut.cfg.value = 0
  await RisingEdge(dut.clk)

  saw_cfg_ready_last = await _send_bits(dut, bits)
  assert saw_cfg_ready_last

  # Example inputs: IO[3:0] = 0b1111
  # clb0 = AND(io0..3) -> 1
  # clb1 = XOR(io0..3) -> 0 (even parity)
  # clb2 = AND2(neighbour0, neighbour1) -> 0 (clb0=1, clb1=0)
  # clb3 = null -> 0
  expected_run_out = 0b0001

  dut.run_in.value = 0b1111
  dut.run.value = 1
  await RisingEdge(dut.clk)
  dut.run.value = 0
  await RisingEdge(dut.clk)
  assert dut.run_out.value == expected_run_out
  await RisingEdge(dut.clk)
  assert dut.run_out.value == expected_run_out # just making sure nothing else changes
