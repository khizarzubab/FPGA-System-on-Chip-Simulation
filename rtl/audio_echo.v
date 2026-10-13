`timescale 1ns/1ps

// audio_echo.v - echo effect for a stream of 8-bit samples
//
// An echo mixes the sound with a quieter copy of itself from a moment ago:
//   out = in + (in from DELAY samples ago) / 2        (limited to 255 so it cannot wrap around)
//
// A shift register ("delay line") remembers the last DELAY inputs. The oldest one is the echo.
//
// HOW TO USE: put a sample on 'sample_in' and pulse 'sample_valid' for one clock. A clock later
// 'sample_out' holds the result. In soc_top.v this value drives a PWM output (audio_pwm),
// which turns the number into an analog-style signal once smoothed by a simple RC filter.

module audio_echo #(
    parameter DELAY = 3               // echo delay, measured in samples (at least 1)
)(
    input  wire       clk,
    input  wire       rst,            // synchronous reset, active high
    input  wire       sample_valid,
    input  wire [7:0] sample_in,
    output reg  [7:0] sample_out
);

    reg [7:0] line [0:DELAY-1];       // line[0] = previous input, line[DELAY-1] = input DELAY ago
    integer i;

    wire [7:0] delayed = line[DELAY-1];
    wire [8:0] mix     = {1'b0, sample_in} + {2'b00, delayed[7:1]};   // in + delayed/2

    always @(posedge clk) begin
        if (rst) begin
            sample_out <= 8'd0;
            for (i = 0; i < DELAY; i = i + 1) line[i] <= 8'd0;
        end else if (sample_valid) begin
            sample_out <= mix[8] ? 8'hFF : mix[7:0];     // saturate at 255
            for (i = DELAY - 1; i > 0; i = i - 1) line[i] <= line[i - 1];
            line[0] <= sample_in;
        end
    end

endmodule
