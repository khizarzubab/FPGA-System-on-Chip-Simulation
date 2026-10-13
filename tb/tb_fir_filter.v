`timescale 1ns/1ps

// tb_fir_filter.v - checks the filter y = (x0 + 3*x1 + 3*x2 + x3) / 8 against hand-calculated values
//
// Four experiments, each starting from a reset (all remembered samples = 0):
//   1. an impulse (one sample of 80, then zeros): shows the filter's weights 1, 3, 3, 1
//   2. a steady input of 200: the output must climb to exactly 200
//   3. noisy input alternating 100 / 150: the output is smoother than the input
//   4. a steady input of 255: the biggest value must not overflow

module tb_fir_filter;

    reg        clk   = 1'b0;
    reg        rst   = 1'b1;
    reg        valid = 1'b0;
    reg  [7:0] din   = 8'd0;
    wire [7:0] dout;
    integer    errors = 0;

    fir_filter dut (
        .clk(clk), .rst(rst), .sample_valid(valid), .sample_in(din), .sample_out(dout)
    );

    always #5 clk = ~clk;

    task do_reset;
        begin
            @(negedge clk);
            rst = 1'b1;
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    task push;
        input [7:0] x;
        input [7:0] expected;
        begin
            @(negedge clk);
            din   = x;
            valid = 1'b1;
            @(negedge clk);
            valid = 1'b0;
            #1;
            if (dout !== expected) begin
                $display("FAIL  input %0d: expected %0d, got %0d", x, expected, dout);
                errors = errors + 1;
            end else begin
                $display("PASS  input %0d -> output %0d", x, dout);
            end
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;

        // 1. impulse
        push(8'd80,  8'd10);     // 80 / 8
        push(8'd0,   8'd30);     // 3*80 / 8
        push(8'd0,   8'd30);
        push(8'd0,   8'd10);     // 80 / 8
        push(8'd0,   8'd0);

        // 2. steady 200
        do_reset;
        push(8'd200, 8'd25);     // 200 / 8
        push(8'd200, 8'd100);    // 800 / 8
        push(8'd200, 8'd175);    // 1400 / 8
        push(8'd200, 8'd200);    // 1600 / 8
        push(8'd200, 8'd200);

        // 3. noise
        do_reset;
        push(8'd100, 8'd12);     // 100 / 8
        push(8'd150, 8'd56);     // (150 + 300) / 8
        push(8'd100, 8'd106);    // (100 + 450 + 300) / 8
        push(8'd150, 8'd125);    // (150 + 300 + 450 + 100) / 8

        // 4. largest input
        do_reset;
        push(8'd255, 8'd31);
        push(8'd255, 8'd127);
        push(8'd255, 8'd223);
        push(8'd255, 8'd255);

        if (errors == 0) $display("ALL FIR FILTER TESTS PASSED");
        else             $display("%0d FIR FILTER TEST(S) FAILED", errors);
        $finish;
    end

endmodule
