// tb_pwm.v - self-checking testbench for pwm.v
//
// A testbench is Verilog that exists only for simulation. It generates a clock, feeds inputs to the
// design under test (called the DUT) and checks the outputs. Nothing here becomes real hardware.
//
// Test: for several duty values, count how many clock cycles the output is high during one full
// PWM period (256 cycles). That count must equal the duty value.

`timescale 1ns/1ps

module tb_pwm;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg  [7:0] duty = 8'd0;
    wire       pwm_out;

    integer high_count;
    integer i;
    integer errors = 0;

    // the design under test
    pwm #(.WIDTH(8), .CLK_DIV(1)) dut (
        .clk(clk), .rst(rst), .duty(duty), .pwm_out(pwm_out)
    );

    // 10 ns period = 100 MHz clock
    always #5 clk = ~clk;

    task check_duty;
        input [7:0] d;
        begin
            duty = d;
            repeat (300) @(posedge clk);          // let the output settle after the change
            high_count = 0;
            for (i = 0; i < 256; i = i + 1) begin // look at exactly one PWM period
                @(posedge clk);
                if (pwm_out) high_count = high_count + 1;
            end
            if (high_count == d)
                $display("PASS  duty=%0d  high cycles=%0d of 256", d, high_count);
            else begin
                $display("FAIL  duty=%0d  expected %0d high cycles, got %0d", d, d, high_count);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
`ifdef __ICARUS__                    // only Icarus Verilog needs this; Vivado shows waveforms itself
        $dumpfile("build/pwm.vcd");     // waveform file you can open with GTKWave
        $dumpvars(0, tb_pwm);
`endif

        repeat (4) @(posedge clk);
        rst = 1'b0;                      // release reset

        check_duty(8'd0);
        check_duty(8'd64);
        check_duty(8'd128);
        check_duty(8'd255);

        if (errors == 0) $display("ALL PWM TESTS PASSED");
        else             $display("%0d PWM TEST(S) FAILED", errors);
        $finish;
    end

endmodule
