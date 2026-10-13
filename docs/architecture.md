# Architecture

Everything below is implemented in `rtl/` and exercised together by `tb/tb_soc.v`.

## Block diagram

```
                         +------------------------- soc_top -------------------------+
                         |                                                           |
   program_rom  -------> |  cpu (16-bit, 2 cycles/instr) --- data bus ---+           |
   (from firmware.asm)   |        |                                      |           |
                         |      ram (256 x 16)        memory-mapped peripherals      |
                         |                                               |           |
 PC <--- UART ---------> |  uart_tx / uart_rx  <-------------------------+           |
 Sensor <--- SPI ------> |  spi_master         <-------------------------+           |
 Motor driver <- PWM --- |  pwm (motor)        <-------------------------+           |
                         |  fir_filter  -> raw sample in, smoothed out   |           |
 Speaker <- audio PWM -- |  audio_echo -> pwm (audio)                    |           |
 Monitor <- VGA -------- |  vga_timing + vga_bargraph (bar = level) <----+           |
                         +-----------------------------------------------------------+
```

## Instruction set (16-bit)

op = bits 15:12, A = bits 11:9, B = bits 8:6, C = bits 5:3, imm6 = bits 5:0 (signed), imm8 = bits 7:0.

| op | name | meaning |
| --- | --- | --- |
| 0 | nop | nothing |
| 1-5 | add sub and or xor | rA = rB op rC |
| 6 | addi | rA = rB + imm6 |
| 7 | ld | rA = mem[rB + imm6] |
| 8 | st | mem[rB + imm6] = rA |
| 9 / A | shli / shri | rA = rB shifted by bits 3:0 |
| B | ldi | rA = imm8 |
| C | ldih | rA[15:8] = imm8 |
| D / E | beq / bne | if rA ==/!= rB then pc = pc + 1 + imm6 |
| F | jmp / halt | jmp to bits 7:0 (bit 11 = 0); halt (bit 11 = 1, word 0xF800) |

Write programs in `sw/firmware.asm`, then run `python scripts/assemble.py` to regenerate `rtl/program_rom.v`.

## Memory map

Addresses with bit 15 = 0 are RAM. Addresses with bit 15 = 1 are peripherals:

| Address | Write | Read |
| --- | --- | --- |
| 0x8000 | send byte over UART | received byte (clears the flag) |
| 0x8001 | - | status: bit 0 = transmitter busy, bit 1 = byte received |
| 0x8002 | motor PWM duty (0-255) | - |
| 0x8003 | start an SPI transfer | byte received from the sensor |
| 0x8004 | - | status: bit 0 = SPI busy |
| 0x8005 | FIR filter input sample | - |
| 0x8006 | - | FIR filter output |
| 0x8007 | audio echo input sample | - |
| 0x8008 | - | audio echo output |
| 0x8009 | VGA bar length (0-255) | - |

## Firmware flow

1. Send `R`. 2. Wait for `G`. 3. Twelve times: SPI read, FIR filter, set motor duty, audio and bar,
store in RAM, send over UART. 4. Send `D` and halt.

## Design rules used in this project

Synchronous design (one clock, registers updated on the rising edge), synchronous active-high reset
inside blocks, a 2-flop synchronizer on every asynchronous input, no latches (every `case` and `if`
in combinational blocks assigns every output), and a self-checking testbench for every block.
