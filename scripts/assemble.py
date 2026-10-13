#!/usr/bin/env python3
"""Assembler for the fpga-soc 16-bit CPU (standard library only).

Reads an assembly file and writes rtl/program_rom.v, the Verilog module that holds the program.

Usage (from the repository root):
    python scripts/assemble.py                       # sw/firmware.asm -> rtl/program_rom.v
    python scripts/assemble.py my.asm out/rom.v      # explicit paths

Instruction set (see docs/architecture.md and rtl/cpu.v):
    nop                      add/sub/and/or/xor rd, rs, rt
    addi rd, rs, imm         (imm -32..31)
    ld   rd, [rs+imm]        st rt, [rs+imm]        (imm -32..31)
    shli rd, rs, n           shri rd, rs, n         (n 0..15)
    ldi  rd, imm8            ldih rd, imm8          (imm8 0..255)
    beq  ra, rb, label       bne  ra, rb, label     (branch distance -32..31)
    jmp  label               halt
Registers are r0..r7. Numbers may be decimal or 0x hex. Comments start with ';'. Labels end with ':'.
"""

import os
import re
import sys

OP = {
    "nop": 0x0, "add": 0x1, "sub": 0x2, "and": 0x3, "or": 0x4, "xor": 0x5,
    "addi": 0x6, "ld": 0x7, "st": 0x8, "shli": 0x9, "shri": 0xA,
    "ldi": 0xB, "ldih": 0xC, "beq": 0xD, "bne": 0xE, "jmp": 0xF, "halt": 0xF,
}
ROM_DEPTH = 256


class AsmError(Exception):
    pass


def reg(token, line_no):
    m = re.fullmatch(r"r([0-7])", token.strip().lower())
    if not m:
        raise AsmError(f"line {line_no}: '{token}' is not a register (r0..r7)")
    return int(m.group(1))


def num(token, line_no):
    try:
        return int(token.strip(), 0)
    except ValueError:
        raise AsmError(f"line {line_no}: '{token}' is not a number")


def mem_operand(token, line_no):
    """Parse [rN], [rN+imm] or [rN-imm]. Returns (register, imm)."""
    m = re.fullmatch(r"\[\s*(r[0-7])\s*(?:([+-])\s*(\w+))?\s*\]", token.strip().lower())
    if not m:
        raise AsmError(f"line {line_no}: bad memory operand '{token}' (use [rN] or [rN+imm])")
    base = reg(m.group(1), line_no)
    imm = 0
    if m.group(2):
        imm = num(m.group(3), line_no)
        if m.group(2) == "-":
            imm = -imm
    return base, imm


def check_range(value, low, high, what, line_no):
    if not (low <= value <= high):
        raise AsmError(f"line {line_no}: {what} {value} is out of range {low}..{high}")


def parse(source):
    """First pass: strip comments, collect labels and instructions."""
    labels = {}
    program = []                      # (address, mnemonic, operands, line_no, original text)
    for line_no, raw in enumerate(source.splitlines(), start=1):
        text = raw.split(";", 1)[0].strip()
        while True:
            m = re.match(r"^([A-Za-z_]\w*)\s*:\s*(.*)$", text)
            if not m:
                break
            name = m.group(1)
            if name in labels:
                raise AsmError(f"line {line_no}: label '{name}' defined twice")
            labels[name] = len(program)
            text = m.group(2).strip()
        if not text:
            continue
        parts = text.split(None, 1)
        mnemonic = parts[0].lower()
        operands = [o.strip() for o in parts[1].split(",")] if len(parts) > 1 else []
        if mnemonic not in OP:
            raise AsmError(f"line {line_no}: unknown instruction '{mnemonic}'")
        program.append((len(program), mnemonic, operands, line_no, " ".join(text.split())))
    return labels, program


def encode(addr, mnemonic, ops, labels, line_no):
    op = OP[mnemonic]

    def need(n):
        if len(ops) != n:
            raise AsmError(f"line {line_no}: '{mnemonic}' needs {n} operand(s), got {len(ops)}")

    if mnemonic == "nop":
        need(0)
        return 0x0000
    if mnemonic == "halt":
        need(0)
        return 0xF800
    if mnemonic in ("add", "sub", "and", "or", "xor"):
        need(3)
        rd, rs, rt = (reg(o, line_no) for o in ops)
        return (op << 12) | (rd << 9) | (rs << 6) | (rt << 3)
    if mnemonic == "addi":
        need(3)
        rd, rs = reg(ops[0], line_no), reg(ops[1], line_no)
        imm = num(ops[2], line_no)
        check_range(imm, -32, 31, "immediate", line_no)
        return (op << 12) | (rd << 9) | (rs << 6) | (imm & 0x3F)
    if mnemonic in ("ld", "st"):
        need(2)
        ra = reg(ops[0], line_no)
        base, imm = mem_operand(ops[1], line_no)
        check_range(imm, -32, 31, "offset", line_no)
        return (op << 12) | (ra << 9) | (base << 6) | (imm & 0x3F)
    if mnemonic in ("shli", "shri"):
        need(3)
        rd, rs = reg(ops[0], line_no), reg(ops[1], line_no)
        n = num(ops[2], line_no)
        check_range(n, 0, 15, "shift amount", line_no)
        return (op << 12) | (rd << 9) | (rs << 6) | n
    if mnemonic in ("ldi", "ldih"):
        need(2)
        rd = reg(ops[0], line_no)
        imm = num(ops[1], line_no)
        check_range(imm, 0, 255, "immediate", line_no)
        return (op << 12) | (rd << 9) | imm
    if mnemonic in ("beq", "bne"):
        need(3)
        ra, rb = reg(ops[0], line_no), reg(ops[1], line_no)
        if ops[2] not in labels:
            raise AsmError(f"line {line_no}: unknown label '{ops[2]}'")
        distance = labels[ops[2]] - (addr + 1)
        check_range(distance, -32, 31, f"branch distance to '{ops[2]}'", line_no)
        return (op << 12) | (ra << 9) | (rb << 6) | (distance & 0x3F)
    if mnemonic == "jmp":
        need(1)
        if ops[0] not in labels:
            raise AsmError(f"line {line_no}: unknown label '{ops[0]}'")
        return 0xF000 | labels[ops[0]]
    raise AsmError(f"line {line_no}: cannot encode '{mnemonic}'")


def assemble(source):
    labels, program = parse(source)
    if len(program) > ROM_DEPTH:
        raise AsmError(f"program has {len(program)} instructions, the ROM holds {ROM_DEPTH}")
    words = []
    for addr, mnemonic, ops, line_no, text in program:
        words.append((addr, encode(addr, mnemonic, ops, labels, line_no), text))
    return words, labels


def rom_verilog(words, source_name):
    lines = [
        "`timescale 1ns/1ps",
        "",
        f"// program_rom.v - GENERATED by scripts/assemble.py from {source_name}. Do not edit by hand.",
        "// Edit the .asm file and run the assembler again to regenerate this file.",
        "//",
        "// A combinational ROM: 'data' is always the instruction stored at 'addr'.",
        "",
        "module program_rom (",
        "    input  wire [7:0]  addr,",
        "    output reg  [15:0] data",
        ");",
        "",
        "    always @(*) begin",
        "        case (addr)",
    ]
    for addr, word, text in words:
        lines.append(f"            8'd{addr}: data = 16'h{word:04X};   // {text}")
    lines += [
        "            default: data = 16'h0000;   // nop",
        "        endcase",
        "    end",
        "",
        "endmodule",
        "",
    ]
    return "\n".join(lines)


def main():
    root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "sw", "firmware.asm")
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, "rtl", "program_rom.v")
    with open(src, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        words, labels = assemble(source)
    except AsmError as e:
        print(f"assembler error: {e}", file=sys.stderr)
        return 1
    with open(dst, "w", encoding="utf-8", newline="\n") as f:
        f.write(rom_verilog(words, os.path.relpath(src, root).replace(os.sep, "/")))
    print(f"assembled {len(words)} instructions from {src} -> {dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
