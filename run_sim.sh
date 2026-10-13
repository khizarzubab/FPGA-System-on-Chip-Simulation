#!/usr/bin/env bash
# Runs every testbench with Icarus Verilog (Linux, macOS, or Git Bash / WSL on Windows).
# Usage:  bash run_sim.sh
# Needs iverilog and vvp on your PATH. Exits with an error if any test fails.
#
# To skip the slow picture capture in the full-system test, edit the soc line below and add
#   -Ptb_soc.CAPTURE_FRAME=0

set -u
cd "$(dirname "$0")"
mkdir -p build
fail=0

run_test() {
    local name="$1"
    shift
    echo
    echo "=== $name ==="
    if ! iverilog -g2005 -o "build/$name.vvp" "$@"; then
        echo "FAIL: $name did not compile"
        fail=1
        return
    fi
    vvp "build/$name.vvp" | tee "build/$name.log"
    if grep -q "FAIL" "build/$name.log" || ! grep -q "PASSED" "build/$name.log"; then
        echo ">>> $name FAILED"
        fail=1
    fi
}

run_test pwm        rtl/pwm.v tb/tb_pwm.v
run_test uart       rtl/uart_tx.v rtl/uart_rx.v tb/tb_uart_loopback.v
run_test top_motor  rtl/pwm.v rtl/top_motor.v tb/tb_top_motor.v
run_test alu        rtl/alu.v tb/tb_alu.v
run_test spi        rtl/spi_master.v tb/spi_sensor_model.v tb/tb_spi_master.v
run_test fir        rtl/fir_filter.v tb/tb_fir_filter.v
run_test echo       rtl/audio_echo.v tb/tb_audio_echo.v
run_test vga        rtl/vga_timing.v rtl/vga_bargraph.v tb/tb_vga.v
run_test cpu        rtl/alu.v rtl/regfile.v rtl/cpu.v tb/tb_cpu.v
run_test soc        rtl/alu.v rtl/regfile.v rtl/cpu.v rtl/ram.v rtl/program_rom.v \
                    rtl/uart_tx.v rtl/uart_rx.v rtl/pwm.v rtl/spi_master.v rtl/fir_filter.v \
                    rtl/audio_echo.v rtl/vga_timing.v rtl/vga_bargraph.v rtl/soc_top.v \
                    tb/spi_sensor_model.v tb/tb_soc.v

echo
if [ "$fail" -ne 0 ]; then
    echo "SOME TESTS FAILED (see the messages above)"
    exit 1
fi
echo "ALL 10 TEST GROUPS PASSED"
echo "Waveforms are in build/*.vcd (open with: gtkwave build/soc.vcd)"
echo "The picture from the full-system test is soc_frame.ppm (convert: python3 scripts/ppm_to_png.py soc_frame.ppm soc_frame.png)"
