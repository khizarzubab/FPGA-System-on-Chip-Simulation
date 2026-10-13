`timescale 1ns/1ps

// vga_bargraph.v - decides the colour of each pixel: a horizontal bar graph of one value
//
// Given the current pixel position (x, y) from vga_timing, this chooses the pixel colour:
//   - white border around the screen
//   - a green bar that starts at x = 8 and is 2 pixels long per unit of 'level' (0 to 255),
//     so level 100 draws a bar 200 pixels long, 80 pixels tall (rows 200 to 279)
//   - dark blue background everywhere else
//   - black outside the visible area (the monitor needs black during blanking)
//
// Colours are 4 bits per channel (12-bit colour), as on the Nexys A7 VGA connector.

module vga_bargraph (
    input  wire       visible,
    input  wire [9:0] x,
    input  wire [9:0] y,
    input  wire [7:0] level,
    output reg  [3:0] r,
    output reg  [3:0] g,
    output reg  [3:0] b
);

    localparam BAR_X0 = 10'd8;
    localparam BAR_Y0 = 10'd200;
    localparam BAR_Y1 = 10'd280;      // first row below the bar

    wire [9:0] bar_end   = BAR_X0 + {1'b0, level, 1'b0};     // 8 + 2 * level
    wire       in_border = (x < 10'd4) || (x >= 10'd636) || (y < 10'd4) || (y >= 10'd476);
    wire       in_bar    = (x >= BAR_X0) && (x < bar_end) && (y >= BAR_Y0) && (y < BAR_Y1);

    always @(*) begin
        if (!visible) begin
            r = 4'd0;  g = 4'd0;  b = 4'd0;
        end else if (in_border) begin
            r = 4'd15; g = 4'd15; b = 4'd15;
        end else if (in_bar) begin
            r = 4'd0;  g = 4'd15; b = 4'd0;
        end else begin
            r = 4'd0;  g = 4'd0;  b = 4'd3;
        end
    end

endmodule
