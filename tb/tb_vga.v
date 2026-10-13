`timescale 1ns/1ps

// tb_vga.v - checks the VGA timing and the bar graph over one full frame
//
// With a 100 MHz clock and a pixel every 4 clocks, a correct 640 x 480 @ 60 Hz signal has:
//   - a line every 800 pixels            = 3,200 clocks between hsync pulses
//   - an hsync pulse 96 pixels wide      = 384 clocks
//   - a frame every 525 lines            = 1,680,000 clocks between vsync pulses
//   - 640 x 480 = 307,200 visible pixels per frame
//   - a green bar 2 * level pixels wide and 80 rows tall: 160 * level green pixels
//
// The simulation runs a little over two frames (about 3.4 million clock cycles).

module tb_vga;

    reg        clk   = 1'b0;
    reg        rst   = 1'b1;
    reg  [7:0] level = 8'd100;

    wire       hsync;
    wire       vsync;
    wire       visible;
    wire       pix_en;
    wire [9:0] x;
    wire [9:0] y;
    wire [3:0] r;
    wire [3:0] g;
    wire [3:0] b;

    vga_timing #(.PIX_DIV(4)) u_timing (
        .clk(clk), .rst(rst), .hsync(hsync), .vsync(vsync),
        .visible(visible), .pix_en(pix_en), .x(x), .y(y)
    );

    vga_bargraph u_bars (
        .visible(visible), .x(x), .y(y), .level(level), .r(r), .g(g), .b(b)
    );

    always #5 clk = ~clk;

    integer cyc         = 0;
    integer errors      = 0;
    integer last_h_fall = -1;
    integer h_fall_at   = 0;
    integer last_v_fall = -1;
    integer frames      = 0;
    integer pix_count   = 0;
    integer green_count = 0;

    always @(posedge clk) cyc <= cyc + 1;

    // count visible pixels (one per pixel strobe) and the green ones
    always @(posedge clk) begin
        if (!rst && pix_en && visible) begin
            pix_count = pix_count + 1;
            if (r == 4'd0 && g == 4'd15 && b == 4'd0) green_count = green_count + 1;
        end
    end

    // line period
    always @(negedge hsync) begin
        if (last_h_fall >= 0 && (cyc - last_h_fall) != 3200) begin
            $display("FAIL  line period is %0d clocks, expected 3200", cyc - last_h_fall);
            errors = errors + 1;
        end
        last_h_fall = cyc;
        h_fall_at   = cyc;
    end

    // hsync pulse width
    always @(posedge hsync) begin
        if (h_fall_at != 0 && (cyc - h_fall_at) != 384) begin
            $display("FAIL  hsync pulse is %0d clocks wide, expected 384", cyc - h_fall_at);
            errors = errors + 1;
        end
    end

    // frame period, pixel count and bar size
    always @(negedge vsync) begin
        if (last_v_fall >= 0) begin
            if ((cyc - last_v_fall) != 1680000) begin
                $display("FAIL  frame period is %0d clocks, expected 1680000", cyc - last_v_fall);
                errors = errors + 1;
            end
            if (pix_count != 307200) begin
                $display("FAIL  %0d visible pixels in a frame, expected 307200", pix_count);
                errors = errors + 1;
            end
            if (green_count != 160 * level) begin
                $display("FAIL  %0d green pixels, expected %0d", green_count, 160 * level);
                errors = errors + 1;
            end
            frames = frames + 1;
            if (errors == 0)
                $display("PASS  one frame: 1680000 clocks, 307200 visible pixels, %0d green pixels", green_count);
        end
        last_v_fall = cyc;
        pix_count   = 0;
        green_count = 0;
    end

    initial begin
        #100_000_000;
        $display("FAIL: TIMEOUT");
        $finish;
    end

    initial begin
`ifdef __ICARUS__
        $dumpfile("build/vga.vcd");
        $dumpvars(0, tb_vga);
`endif
        repeat (5) @(posedge clk);
        rst = 1'b0;
        wait (frames >= 1);
        if (errors == 0) $display("ALL VGA TESTS PASSED");
        else             $display("%0d VGA TEST(S) FAILED", errors);
        $finish;
    end

endmodule
