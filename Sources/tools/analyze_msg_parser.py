#!/usr/bin/env python3
"""Locate Corsairs Gold MSG parser strings and their x86 code references."""

from __future__ import annotations

import struct
import sys
from pathlib import Path


TOOLS_ROOT = Path(__file__).resolve().parent
PATCH_ROOT = TOOLS_ROOT.parent
GAME_ROOT = PATCH_ROOT.parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(TOOLS_ROOT / "pydeps"))

import capstone  # type: ignore[import-not-found]  # noqa: E402
import pefile  # type: ignore[import-not-found]  # noqa: E402
from capstone.x86 import X86_OP_IMM, X86_OP_MEM  # type: ignore[import-not-found]  # noqa: E402


TARGETS = (
    b"MISSIONS\\",
    b"\\MSG\\",
    b"OBJ_",
    b"ACTI",
    b"REAL",
    b"FAIL",
    b"ACTIVATION",
    b"REALIZATION",
)


def main() -> int:
    executable = GAME_ROOT / "corsairs.exe"
    raw = executable.read_bytes()
    pe = pefile.PE(str(executable))
    image_base = pe.OPTIONAL_HEADER.ImageBase

    print(f"Image base: 0x{image_base:08x}")
    print("Sections:")
    for section in pe.sections:
        name = section.Name.rstrip(b"\0").decode("ascii", errors="replace")
        print(
            f"  {name:8} RVA=0x{section.VirtualAddress:08x} "
            f"raw=0x{section.PointerToRawData:08x} size=0x{section.SizeOfRawData:x}"
        )

    target_addresses: dict[int, str] = {}
    print("String locations:")
    for target in TARGETS:
        start = 0
        occurrence = 0
        while True:
            offset = raw.find(target + b"\0", start)
            if offset < 0:
                break
            occurrence += 1
            rva = pe.get_rva_from_offset(offset)
            va = image_base + rva
            label = target.decode("ascii") + f"#{occurrence}"
            target_addresses[va] = label
            print(f"  {label:20} file=0x{offset:08x} VA=0x{va:08x}")
            start = offset + 1

    text_section = next(
        section
        for section in pe.sections
        if section.Name.rstrip(b"\0") in {b".text", b"CODE"}
    )
    text = text_section.get_data()
    text_va = image_base + text_section.VirtualAddress
    decoder = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    decoder.detail = True
    decoder.skipdata = True
    instructions = list(decoder.disasm(text, text_va))

    references: list[tuple[int, str, str]] = []
    for instruction in instructions:
        if instruction.id == 0:
            continue
        for operand in instruction.operands:
            value = None
            if operand.type == X86_OP_IMM:
                value = operand.imm & 0xFFFFFFFF
            elif operand.type == X86_OP_MEM and operand.mem.base == 0 and operand.mem.index == 0:
                value = operand.mem.disp & 0xFFFFFFFF
            if value in target_addresses:
                references.append(
                    (instruction.address, target_addresses[value], f"{instruction.mnemonic} {instruction.op_str}")
                )

    print("Code references:")
    for address, label, assembly in references:
        print(f"  0x{address:08x} -> {label:20} {assembly}")

    print("Raw pointer references outside decoded instructions:")
    for address, label in sorted(target_addresses.items()):
        needle = struct.pack("<I", address)
        offsets: list[str] = []
        start = 0
        while True:
            offset = raw.find(needle, start)
            if offset < 0:
                break
            offsets.append(f"0x{offset:08x}")
            start = offset + 1
        if offsets:
            print(f"  {label:20} {', '.join(offsets)}")

    print("MSG parser disassembly (file offsets 0x2b95e..0x2bd58):")
    parser_start = 0x2B95E
    parser_end = 0x2BD58
    parser_va = image_base + pe.get_rva_from_offset(parser_start)
    for instruction in decoder.disasm(raw[parser_start:parser_end], parser_va):
        file_offset = pe.get_offset_from_rva(instruction.address - image_base)
        print(
            f"  file=0x{file_offset:06x} VA=0x{instruction.address:08x}  "
            f"{instruction.mnemonic:8} {instruction.op_str}"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
