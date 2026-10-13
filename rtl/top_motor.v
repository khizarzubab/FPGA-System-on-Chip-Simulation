// top_motor.v - top-level design for the Nexys A7-100T: switches control an L298N motor driver.
//
// A "top-level" module is the outermost one. Its ports are the real pins of the FPGA chip, and the
// constraints file (constraints/nexys_a7_motor.xdc) says which physical pin each port name is.
//
// CONTROLS (all on the board's slide switches):
//   SW[7:0]  = motor speed (0 = stopped, 255 = fastest)
//   SW[14]   = enable (1 = motor allowed to run, 0 = stopped, whatever the speed switches say)
//   SW[15]   = direction (0 = one way, 1 = the other way)
//   Red CPU RESET button = emergency stop (hold it and the PWM output goes low)
//
// OUTPUTS to the L298N module (Pmod header JA):
//   JA1 -> ENA  (the PWM signal: this is what sets the speed)
//   JA2 -> IN1  \  the two direction inputs: one high and one low = motor runs,
//   JA3 -> IN2  /  swapping them = motor runs the other way, both low = motor stops
//   LED[15:0] mirror the switches so you can see what you set.

`timescale 1ns/1ps

module top_motor (
    input  wire        CLK100MHZ,    // 100 MHz oscillator on the board
    input  wire        CPU_RESETN,   // red button, reads 0 while pressed (active low)
    input  wire [15:0] SW,           // 16 slide switches
    output wire [15:0] LED,          // 16 LEDs
    output wire        JA1,          // -> L298N ENA (PWM)
    output wire        JA2,          // -> L298N IN1
    output wire        JA3           // -> L298N IN2
);

    wire       rst    = ~CPU_RESETN;                 // our modules use active-high reset
    wire       enable = SW[14];
    wire       dir    = SW[15];
    wire [7:0] duty   = enable ? SW[7:0] : 8'd0;     // disabled = speed forced to 0

    // PWM frequency = 100 MHz / 40 / 256 = about 9.8 kHz, a comfortable rate for an L298N
    pwm #(.WIDTH(8), .CLK_DIV(40)) u_pwm (
        .clk    (CLK100MHZ),
        .rst    (rst),
        .duty   (duty),
        .pwm_out(JA1)
    );

    assign JA2 = enable &  dir;
    assign JA3 = enable & ~dir;

    assign LED = SW;

endmodule
