`timescale 1ns/1ps

// vga_timing.v - sync signal generator for a 640 x 480 @ 60 Hz VGA monitor
//
// A VGA monitor draws the picture one line at a time, left to right, top to bottom. This block
// produces the two sync pulses that tell the monitor when a line and a frame start, and the
// current pixel position (x, y).
//
//   one line  = 640 visible + 16 front porch + 96 sync + 48 back porch = 800 pixel periods
//   one frame = 480 visible + 10 front porch +  2 sync + 33 back porch = 525 lines
//
// The pixel clock should be about 25 MHz. We make it from the 100 MHz system clock by letting
// the position counters advance once every PIX_DIV (= 4) clock cycles: 'pix_en' is the strobe.

module vga_timing #(
    parameter PIX_DIV = 4
)(
    input  wire       clk,
    input  wire       rst,        // synchronous reset, active high
    output wire       hsync,      // active low
    output wire       vsync,      // active low
    output wire       visible,    // 1 while (x, y) is inside the 640 x 480 picture area
    output wire       pix_en,     // 1 on the last clock of every pixel period
    output wire [9:0] x,
    output wire [9:0] y
);

    localparam H_VISIBLE = 640;
    localparam H_FRONT   = 16;
    localparam H_SYNC    = 96;
    localparam H_TOTAL   = 800;

    localparam V_VISIBLE = 480;
    localparam V_FRONT   = 10;
    localparam V_SYNC    = 2;
    localparam V_TOTAL   = 525;

    reg [2:0] div;
    reg [9:0] hcnt;
    reg [9:0] vcnt;

    assign pix_en = (div == PIX_DIV - 1);

    always @(posedge clk) begin
        if (rst) begin
            div  <= 3'd0;
            hcnt <= 10'd0;
            vcnt <= 10'd0;
        end else if (pix_en) begin
            div <= 3'd0;
            if (hcnt == H_TOTAL - 1) begin
                hcnt <= 10'd0;
                if (vcnt == V_TOTAL - 1) vcnt <= 10'd0;
                else                     vcnt <= vcnt + 1'b1;
            end else begin
                hcnt <= hcnt + 1'b1;
            end
        end else begin
            div <= div + 1'b1;
        end
    end

    assign x       = hcnt;
    assign y       = vcnt;
    assign visible = (hcnt < H_VISIBLE) && (vcnt < V_VISIBLE);
    assign hsync   = ~((hcnt >= H_VISIBLE + H_FRONT) && (hcnt < H_VISIBLE + H_FRONT + H_SYNC));
    assign vsync   = ~((vcnt >= V_VISIBLE + V_FRONT) && (vcnt < V_VISIBLE + V_FRONT + V_SYNC));

endmodule
