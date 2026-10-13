# FPGA System-on-Chip (simulation project)

A small computer built from scratch in Verilog. A custom 16-bit CPU runs a program that reads a
sensor over SPI, smooths the readings with an FIR filter, sets a motor speed with PWM, plays the
result through an audio echo effect, shows it as a bar on a VGA monitor, and reports every value
to a PC over UART. **No FPGA board is needed**: everything runs in simulation.

| Block | File | What it does |
| --- | --- | --- |
| CPU | `rtl/cpu.v`, `alu.v`, `regfile.v` | 16-bit RISC-style processor |
| Memory | `rtl/ram.v`, `program_rom.v` | 256-word RAM, program ROM (generated from assembly) |
| UART | `rtl/uart_tx.v`, `uart_rx.v` | serial link to the PC, 115200 baud |
| SPI | `rtl/spi_master.v` | reads the sensor (mode 0) |
| Filter | `rtl/fir_filter.v` | 4-tap low-pass (1,3,3,1)/8 |
| Motor | `rtl/pwm.v` | speed control for an L298N driver |
| Audio | `rtl/audio_echo.v` + `pwm.v` | echo effect, PWM output |
| Display | `rtl/vga_timing.v`, `vga_bargraph.v` | 640x480@60 Hz bar graph |
| Top | `rtl/soc_top.v` | connects everything |

Ethernet is not included (it is a stretch goal). Architecture details: [docs/architecture.md](docs/architecture.md).

## Run it (no board)

You need [Icarus Verilog](https://bleyer.org/icarus/) (Windows installer, add it to PATH) and Python 3.

- Windows: double-click `run_sim.bat` or run it in a terminal.
- Linux / macOS: `bash run_sim.sh`

It runs 10 test groups (each block alone, then the whole system). Success ends with
`ALL 10 TEST GROUPS PASSED`. The full-system test also writes `soc_frame.ppm`, one VGA frame;
convert it with `python scripts/ppm_to_png.py soc_frame.ppm soc_frame.png` and open the PNG.
Waveforms are in `build/*.vcd` (view with GTKWave: `gtkwave build/soc.vcd`).

### With Vivado

Tools > Run Tcl Script > `scripts/create_vivado_project.tcl`, then Run Simulation > Run Behavioral
Simulation (top is `tb_soc`). To run another test, right-click its testbench > Set as Top.

## What you should see

With the built-in sensor table the filtered values sent to the PC are
`12 51 89 105 113 117 110 109 119 123 115 110`, framed by `R` at the start and `D` at the end.
(The filter starts from zero, so the first values ramp up.) The testbench checks the UART bytes, RAM
contents, motor PWM duty, audio PWM duty and the green pixel count of the VGA bar.

## Layout

```
rtl/          hardware (Verilog)          tb/       testbenches
sw/           firmware.asm (CPU program)  scripts/  assembler, PPM->PNG, Vivado project script
constraints/  Nexys A7 pin file           docs/     architecture, motor wiring
run_sim.bat / run_sim.sh   run all tests  .github/workflows/sim.yml   CI on every push
```

Change the program: edit `sw/firmware.asm`, run `python scripts/assemble.py`, run the tests.
