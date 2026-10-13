// tb_top_motor.v - simulates top_motor exactly as it will run on the board, with no board attached.
//
// We act like the person flipping the switches, then check the pins that would go to the L298N:
//   - JA1 (ENA, the PWM): high for duty x 40 clock cycles out of every 10240 (256 steps x 40)
//   - JA2 / JA3 (IN1, IN2): follow the direction switch when enabled, both low when disabled

`timescale 1ns/1ps

module tb_top_motor;

    reg         clk    = 1'b0;
    reg         resetn = 1'b0;           // 0 = reset button pressed
    reg  [15:0] sw     = 16'd0;
    wire [15:0] led;
    wire        ja1, ja2, ja3;

    integer high_count;
    integer i;
    integer errors = 0;

    top_motor dut (
        .CLK100MHZ(clk), .CPU_RESETN(resetn), .SW(sw), .LED(led),
        .JA1(ja1), .JA2(ja2), .JA3(ja3)
    );

    always #5 clk = ~clk;                // 100 MHz

    task check;
        input [7:0] duty;
        input       en;
        input       dir;
        begin
            sw = {dir, en, 6'b000000, duty};      // SW15 = dir, SW14 = en, SW7..0 = duty
            repeat (12000) @(posedge clk);        // wait longer than one PWM period (10240 cycles)

            high_count = 0;
            for (i = 0; i < 10240; i = i + 1) begin
                @(posedge clk);
                if (ja1) high_count = high_count + 1;
            end

            if (en && (high_count != duty * 40)) begin
                $display("FAIL  duty=%0d en=%0d: expected %0d high cycles, got %0d", duty, en, duty * 40, high_count);
                errors = errors + 1;
            end else if (!en && (high_count != 0)) begin
                $display("FAIL  disabled but PWM still toggled (%0d high cycles)", high_count);
                errors = errors + 1;
            end else if (en && (ja2 !== dir || ja3 !== ~dir)) begin
                $display("FAIL  direction pins wrong for dir=%0d (IN1=%b IN2=%b)", dir, ja2, ja3);
                errors = errors + 1;
            end else if (!en && (ja2 !== 1'b0 || ja3 !== 1'b0)) begin
                $display("FAIL  disabled but direction pins not low (IN1=%b IN2=%b)", ja2, ja3);
                errors = errors + 1;
            end else begin
                $display("PASS  duty=%0d en=%0d dir=%0d  ENA high %0d of 10240 cycles, IN1=%b IN2=%b",
                         duty, en, dir, high_count, ja2, ja3);
            end
        end
    endtask

    initial begin
`ifdef __ICARUS__
        $dumpfile("build/top_motor.vcd");
        $dumpvars(0, tb_top_motor);
`endif
        repeat (10) @(posedge clk);
        resetn = 1'b1;                            // release the reset button

        check(8'd0,   1'b1, 1'b0);                // enabled, speed 0
        check(8'd64,  1'b1, 1'b0);                // quarter speed, one direction
        check(8'd128, 1'b1, 1'b1);                // half speed, other direction
        check(8'd255, 1'b1, 1'b0);                // full speed
        check(8'd200, 1'b0, 1'b0);                // enable switch off: must stop

        if (errors == 0) $display("ALL TOP-LEVEL TESTS PASSED");
        else             $display("%0d TOP-LEVEL TEST(S) FAILED", errors);
        $finish;
    end

endmodule
