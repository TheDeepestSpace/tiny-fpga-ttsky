# Tiny FPGA Bitstream Builder

from __future__ import annotations

from enum import Enum
from typing import List

import yaml
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

SIGNAL_TYPE_W = 2
SIGNAL_INDEX_W = 8
OUTPUT_TYPE_W = 1


class InputType(str, Enum):
  NEIGHBOUR = "neighbour"
  IO = "io"
  FEEDBACK = "feedback"


class OutputType(str, Enum):
  SEQUENTIAL = "sequential"
  CLOCKED = "clocked"


class TargetSpec(BaseModel):
  clb_count: int = Field(alias="clb-count")
  lut_width: int = Field(alias="lut-width")

  model_config = ConfigDict(extra="forbid", populate_by_name=True)


class ClbInput(BaseModel):
  type: InputType
  index: int

  model_config = ConfigDict(extra="forbid", populate_by_name=True)


class ClbConfig(BaseModel):
  inputs: List[ClbInput]
  output_type: OutputType = Field(alias="output-type")
  lut_truth_table: List[int] = Field(alias="lut-truth-table")

  model_config = ConfigDict(extra="forbid", populate_by_name=True)

  @field_validator("lut_truth_table", mode="before")
  @classmethod
  def _coerce_truth_table(cls, value):
    if not isinstance(value, list):
      raise ValueError("lut-truth-table must be a list")
    coerced = []
    for bit in value:
      if isinstance(bit, bool):
        coerced.append(1 if bit else 0)
      elif isinstance(bit, int):
        coerced.append(bit)
      elif isinstance(bit, str) and bit.strip().isdigit():
        coerced.append(int(bit.strip()))
      else:
        raise ValueError(f"Invalid truth table bit: {bit}")
    return coerced


class Design(BaseModel):
  target: TargetSpec
  clbs: List[ClbConfig]

  model_config = ConfigDict(extra="ignore", populate_by_name=True)

  @model_validator(mode="after")
  def _validate_design(self):
    if len(self.clbs) != self.target.clb_count:
      raise ValueError(
        f"Expected {self.target.clb_count} CLBs, got {len(self.clbs)}"
      )

    expected_truth_table_len = 1 << self.target.lut_width
    for idx, clb in enumerate(self.clbs):
      if len(clb.inputs) != self.target.lut_width:
        raise ValueError(
          f"CLB {idx} expected {self.target.lut_width} inputs, got {len(clb.inputs)}"
        )
      if len(clb.lut_truth_table) != expected_truth_table_len:
        raise ValueError(
          f"CLB {idx} expected {expected_truth_table_len} truth table entries, "
          f"got {len(clb.lut_truth_table)}"
        )
      for bit in clb.lut_truth_table:
        if bit not in (0, 1):
          raise ValueError(f"CLB {idx} truth table entries must be 0/1, got {bit}")

    return self

def _input_type_code(value: InputType) -> int:
  return {
    InputType.NEIGHBOUR: 0,
    InputType.IO: 1,
    InputType.FEEDBACK: 2,
  }[value]


def _output_type_code(value: OutputType) -> int:
  return {
    OutputType.SEQUENTIAL: 0,
    OutputType.CLOCKED: 1,
  }[value]

def design_file_to_bitstream(path: str) -> List[int]:

  def design_to_bitstream(design: Design) -> List[int]:

    def clb_to_bitstream(clb: ClbConfig) -> List[int]:

      def bits_lsb_first(value: int, width: int) -> List[int]:
        return [(value >> i) & 1 for i in range(width)]

      bits: List[int] = []
      for clb_input in clb.inputs:
        bits.extend(bits_lsb_first(_input_type_code(clb_input.type), SIGNAL_TYPE_W))
        bits.extend(bits_lsb_first(clb_input.index, SIGNAL_INDEX_W))
      bits.extend(bits_lsb_first(_output_type_code(clb.output_type), OUTPUT_TYPE_W))
      bits.extend(int(bit) for bit in clb.lut_truth_table)
      return bits

    bits: List[int] = []
    for clb in design.clbs:
      bits.extend(clb_to_bitstream(clb))
    return bits


  def load_design(path: str) -> Design:

    def parse_design_dict(raw: dict) -> Design:
      if not isinstance(raw, dict):
        raise ValueError("Design file must be a mapping")
      return Design.model_validate(raw)

    with open(path, "r", encoding="utf-8") as handle:
      data = yaml.safe_load(handle)
    return parse_design_dict(data)



  return design_to_bitstream(load_design(path))
