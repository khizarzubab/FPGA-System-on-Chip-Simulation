// pwm.v - Pulse Width Modulation generator (used for motor speed and simple audio)
//
// IDEA: a counter sweeps 0,1,2 ... 255 and wraps around, over and over.
// The output is HIGH while counter < duty, and LOW the rest of the time.
//   duty = 0    -> always low   (motor stopped)
//   duty = 64   -> high 25% of the time
//   duty = 128  -> high 50% of the time (about half speed)
//   duty = 255  -> high 255 of 256 steps (almost full speed)
// A motor driver averages this on/off signal, so more "on" time = faster motor.
//
// PWM frequency = clk / CLK_DIV / 2^WIDTH
//   Example: 100 MHz clock, CLK_DIV = 20, WIDTH = 8  ->  about 19.5 kHz
//   (motor drivers want roughly 1 to 25 kHz; the default CLK_DIV = 1 is for fast simulation)

`timescale 1ns/1ps

module pwm #(
    parameter WIDTH   = 8,   // number of bits in duty (8 bits = 256 steps)
    parameter CLK_DIV = 1    // slow-down factor for the counter
)(
    input  wire             clk,
    input  wire             rst,      // synchronous reset, active high
    input  wire [WIDTH-1:0] duty,     // how long the output stays high
    output reg              pwm_out   // connect this to the motor driver input pin
);

    reg [15:0]      div_cnt;          // counts clock cycles between counter steps
    reg [WIDTH-1:0] counter;          // the 0..255 sweep

    // tick is 1 on the cycle when the sweep counter should advance
    wire tick = (div_cnt == CLK_DIV - 1);

    always @(posedge clk) begin
        if (rst) begin
            div_cnt <= 0;
            counter <= 0;
            pwm_out <= 1'b0;
        end else begin
            if (tick) begin
                div_cnt <= 0;
                counter <= counter + 1'b1;   // wraps from 255 back to 0 by itself
            end else begin
                div_cnt <= div_cnt + 1'b1;
            end

            // compare the sweep position with the requested duty
            pwm_out <= (counter < duty);
        end
    end

endmodule
