`timescale 1ns/1ps

// fir_filter.v - a 4-tap low-pass FIR filter (smooths noisy samples)
//
// FIR = Finite Impulse Response: each output is a weighted sum of the last few input samples.
//   y = ( 1*x0 + 3*x1 + 3*x2 + 1*x3 ) / 8
// x0 is the newest sample, x3 the oldest. The weights add up to 8, so a steady input comes out
// unchanged, while quick jumps (noise) are averaged away.
//
// No multiplier is needed: 3*x is x + (x << 1), and dividing by 8 is dropping 3 bits.
//
// HOW TO USE: put a sample on 'sample_in' and pulse 'sample_valid' for one clock. A clock later
// 'sample_out' holds the filtered result for that sample. It stays until the next sample.

module fir_filter (
    input  wire       clk,
    input  wire       rst,           // synchronous reset, active high
    input  wire       sample_valid,  // pulse: take 'sample_in' as a new sample
    input  wire [7:0] sample_in,
    output wire [7:0] sample_out
);

    reg [7:0] x0;    // newest sample
    reg [7:0] x1;
    reg [7:0] x2;
    reg [7:0] x3;    // oldest sample

    always @(posedge clk) begin
        if (rst) begin
            x0 <= 8'd0;
            x1 <= 8'd0;
            x2 <= 8'd0;
            x3 <= 8'd0;
        end else if (sample_valid) begin
            x3 <= x2;
            x2 <= x1;
            x1 <= x0;
            x0 <= sample_in;
        end
    end

    // 12 bits are enough: the largest sum is 8 * 255 = 2040
    wire [11:0] e0 = {4'd0, x0};
    wire [11:0] e1 = {4'd0, x1};
    wire [11:0] e2 = {4'd0, x2};
    wire [11:0] e3 = {4'd0, x3};
    wire [11:0] sum = e0 + e1 + (e1 << 1) + e2 + (e2 << 1) + e3;

    assign sample_out = sum[10:3];       // divide by 8

endmodule
