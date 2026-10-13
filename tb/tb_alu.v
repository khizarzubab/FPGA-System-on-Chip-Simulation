`timescale 1ns/1ps

// tb_alu.v - checks every ALU operation against hand-calculated answers

module tb_alu;

    reg  [15:0] a;
    reg  [15:0] b;
    reg  [2:0]  op;
    wire [15:0] y;
    integer     errors = 0;

    alu dut (.a(a), .b(b), .op(op), .y(y));

    task check;
        input [2:0]  t_op;
        input [15:0] t_a;
        input [15:0] t_b;
        input [15:0] expected;
        begin
            op = t_op;
            a  = t_a;
            b  = t_b;
            #1;
            if (y !== expected) begin
                $display("FAIL  op=%0d a=%h b=%h  expected %h  got %h", t_op, t_a, t_b, expected, y);
                errors = errors + 1;
            end else begin
                $display("PASS  op=%0d a=%h b=%h  ->  %h", t_op, t_a, t_b, y);
            end
        end
    endtask

    initial begin
        check(3'd0, 16'd5,    16'd3,    16'd8);        // add
        check(3'd0, 16'hFFFF, 16'd1,    16'h0000);     // add wraps around
        check(3'd1, 16'd9,    16'd4,    16'd5);        // sub
        check(3'd1, 16'd3,    16'd5,    16'hFFFE);     // sub below zero wraps
        check(3'd2, 16'hF0F0, 16'hFF00, 16'hF000);     // and
        check(3'd3, 16'hF0F0, 16'h0F0F, 16'hFFFF);     // or
        check(3'd4, 16'hFF00, 16'h0FF0, 16'hF0F0);     // xor
        check(3'd5, 16'h0003, 16'd4,    16'h0030);     // shift left by 4
        check(3'd6, 16'h00F0, 16'd4,    16'h000F);     // shift right by 4
        check(3'd7, 16'h1234, 16'h5678, 16'h0000);     // unused code gives 0

        if (errors == 0) $display("ALL ALU TESTS PASSED");
        else             $display("%0d ALU TEST(S) FAILED", errors);
        $finish;
    end

endmodule
