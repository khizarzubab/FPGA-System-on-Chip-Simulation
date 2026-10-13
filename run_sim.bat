@echo off
rem Runs every testbench with Icarus Verilog on Windows. Double-click, or run "run_sim.bat".
rem Needs iverilog and vvp on your PATH (see README.md). Stops with an error if any test fails.
rem
rem To skip the slow picture capture in the full-system test, add -Ptb_soc.CAPTURE_FRAME=0
rem to the soc line below, right after the word iverilog is called (inside the :run subroutine).

cd /d "%~dp0"
if not exist build mkdir build

call :run pwm        "rtl\pwm.v tb\tb_pwm.v"
if errorlevel 1 goto failed
call :run uart       "rtl\uart_tx.v rtl\uart_rx.v tb\tb_uart_loopback.v"
if errorlevel 1 goto failed
call :run top_motor  "rtl\pwm.v rtl\top_motor.v tb\tb_top_motor.v"
if errorlevel 1 goto failed
call :run alu        "rtl\alu.v tb\tb_alu.v"
if errorlevel 1 goto failed
call :run spi        "rtl\spi_master.v tb\spi_sensor_model.v tb\tb_spi_master.v"
if errorlevel 1 goto failed
call :run fir        "rtl\fir_filter.v tb\tb_fir_filter.v"
if errorlevel 1 goto failed
call :run echo       "rtl\audio_echo.v tb\tb_audio_echo.v"
if errorlevel 1 goto failed
call :run vga        "rtl\vga_timing.v rtl\vga_bargraph.v tb\tb_vga.v"
if errorlevel 1 goto failed
call :run cpu        "rtl\alu.v rtl\regfile.v rtl\cpu.v tb\tb_cpu.v"
if errorlevel 1 goto failed
call :run soc        "rtl\alu.v rtl\regfile.v rtl\cpu.v rtl\ram.v rtl\program_rom.v rtl\uart_tx.v rtl\uart_rx.v rtl\pwm.v rtl\spi_master.v rtl\fir_filter.v rtl\audio_echo.v rtl\vga_timing.v rtl\vga_bargraph.v rtl\soc_top.v tb\spi_sensor_model.v tb\tb_soc.v"
if errorlevel 1 goto failed

echo.
echo ALL 10 TEST GROUPS PASSED
echo Waveforms are in build\*.vcd  (open with: gtkwave build\soc.vcd)
echo The picture from the full-system test is soc_frame.ppm  (convert: python scripts\ppm_to_png.py soc_frame.ppm soc_frame.png)
exit /b 0

:failed
echo.
echo SOME TESTS FAILED (see the messages above)
exit /b 1

:run
echo.
echo === %1 ===
iverilog -g2005 -o build\%1.vvp %~2
if errorlevel 1 exit /b 1
vvp build\%1.vvp > build\%1.log
type build\%1.log
findstr /C:"FAIL" build\%1.log >nul
if not errorlevel 1 exit /b 1
findstr /C:"PASSED" build\%1.log >nul
if errorlevel 1 exit /b 1
exit /b 0
