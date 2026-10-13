`timescale 1ns/1ps

// tb_audio_echo.v - checks the echo effect with a delay of 2 samples
//
//   out[n] = in[n] + in[n-2] / 2      (limited to 255)
//
// Inputs:   100  50  20  200  200    0    0  255    0  255
// Expected: 100  50  70  225  210  100  100  255    0  255
//   n=2: 20 + 100/2 = 70           n=3: 200 + 50/2 = 225      n=4: 200 + 20/2 = 210
//   n=5: 0 + 200/2 = 100           n=6: 0 + 200/2 = 100       n=7: 255 + 0 = 255
//   n=8: 0 + 0 = 0                 n=9: 255 + 255/2 = 382, limited to 255

module tb_audio_echo;

    reg        clk   = 1'b0;
    reg        rst   = 1'b1;
    reg        valid = 1'b0;
    reg  [7:0] din   = 8'd0;
    wire [7:0] dout;
    integer    errors = 0;

    audio_echo #(.DELAY(2)) dut (
        .clk(clk), .rst(rst), .sample_valid(valid), .sample_in(din), .sample_out(dout)
    );

    always #5 clk = ~clk;

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

        push(8'd100, 8'd100);
        push(8'd50,  8'd50);
        push(8'd20,  8'd70);
        push(8'd200, 8'd225);
        push(8'd200, 8'd210);
        push(8'd0,   8'd100);
        push(8'd0,   8'd100);
        push(8'd255, 8'd255);
        push(8'd0,   8'd0);
        push(8'd255, 8'd255);      // saturates: 255 + 127 would be 382

        if (errors == 0) $display("ALL AUDIO ECHO TESTS PASSED");
        else             $display("%0d AUDIO ECHO TEST(S) FAILED", errors);
        $finish;
    end

endmodule
