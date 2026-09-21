#!/usr/bin/env python3
"""Wrap a relocation-free ARM .text section in a minimal Linux ELF32."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


def extract_text(elf: bytes) -> bytes:
    if elf[:7] != b"\x7fELF\x01\x01\x01":
        raise ValueError("input is not a little-endian ELF32 object")

    header = struct.unpack_from("<16sHHIIIIIHHHHHH", elf, 0)
    section_offset = header[6]
    section_size = header[11]
    section_count = header[12]
    string_index = header[13]
    if not section_offset or not section_count:
        raise ValueError("input object has no section table")

    sections = [
        struct.unpack_from("<IIIIIIIIII", elf, section_offset + i * section_size)
        for i in range(section_count)
    ]
    strings = sections[string_index]
    names = elf[strings[4] : strings[4] + strings[5]]

    text_index = None
    text_section = None
    for index, section in enumerate(sections):
        name_offset = section[0]
        name_end = names.find(b"\0", name_offset)
        name = names[name_offset:name_end]
        if name == b".text":
            text_index = index
            text_section = section
            break
    if text_section is None or text_index is None:
        raise ValueError("input object has no .text section")

    code = bytearray(elf[text_section[4] : text_section[4] + text_section[5]])

    # Clang leaves same-section ARM BL instructions as R_ARM_CALL entries for
    # the linker. Resolve those here; the final minimal ELF has no section or
    # dynamic relocation tables.
    for relocation_section in sections:
        section_type = relocation_section[1]
        target_index = relocation_section[7]
        if section_type != 9 or target_index != text_index:  # SHT_REL
            continue
        symbol_section = sections[relocation_section[6]]
        symbol_entry_size = symbol_section[9] or 16
        symbol_count = symbol_section[5] // symbol_entry_size
        symbols = [
            struct.unpack_from(
                "<IIIBBH", elf, symbol_section[4] + i * symbol_entry_size
            )
            for i in range(symbol_count)
        ]
        relocation_entry_size = relocation_section[9] or 8
        for position in range(
            relocation_section[4],
            relocation_section[4] + relocation_section[5],
            relocation_entry_size,
        ):
            offset, info = struct.unpack_from("<II", elf, position)
            symbol_index = info >> 8
            relocation_type = info & 0xFF
            if relocation_type not in (28, 29):  # R_ARM_CALL/JUMP24
                raise ValueError(f"unsupported ARM relocation type {relocation_type}")
            symbol_value = symbols[symbol_index][1]
            instruction = struct.unpack_from("<I", code, offset)[0]
            addend = (instruction & 0x00FFFFFF) << 2
            if addend & 0x02000000:
                addend -= 0x04000000
            displacement = symbol_value + addend - offset
            if displacement % 4 or not -(1 << 25) <= displacement < (1 << 25):
                raise ValueError("ARM branch relocation is out of range")
            instruction = (instruction & 0xFF000000) | ((displacement >> 2) & 0x00FFFFFF)
            struct.pack_into("<I", code, offset, instruction)

    return bytes(code)


def make_executable(code: bytes) -> bytes:
    page_size = 0x1000
    base_address = 0x10000
    code_offset = page_size
    entry = base_address + code_offset
    file_size = code_offset + len(code)

    ident = b"\x7fELF\x01\x01\x01\x00" + b"\x00" * 8
    elf_header = struct.pack(
        "<16sHHIIIIIHHHHHH",
        ident,
        2,          # ET_EXEC
        40,         # EM_ARM
        1,          # EV_CURRENT
        entry,
        52,         # program header offset
        0,          # no section table required at runtime
        0x05000000, # EABI version 5
        52,
        32,
        1,
        0,
        0,
        0,
    )
    program_header = struct.pack(
        "<IIIIIIII",
        1,          # PT_LOAD
        0,
        base_address,
        base_address,
        file_size,
        file_size,
        5,          # PF_R | PF_X
        page_size,
    )
    padding = b"\x00" * (code_offset - len(elf_header) - len(program_header))
    return elf_header + program_header + padding + code


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("object", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    code = extract_text(args.object.read_bytes())
    args.output.write_bytes(make_executable(code))
    args.output.chmod(0o755)


if __name__ == "__main__":
    main()
