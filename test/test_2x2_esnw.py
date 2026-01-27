import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

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
