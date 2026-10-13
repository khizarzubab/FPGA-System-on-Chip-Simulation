`timescale 1ns/1ps

// alu.v - arithmetic and logic unit of the 16-bit CPU
//
// Purely combinational: the output 'y' follows the inputs immediately (no clock, no memory).
// 'op' selects the operation. The CPU uses this one unit for arithmetic, for computing memory
// addresses (base + offset) and for shifts.

module alu (
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire [2:0]  op,
    output reg  [15:0] y
);

    localparam ALU_ADD = 3'd0;
    localparam ALU_SUB = 3'd1;
    localparam ALU_AND = 3'd2;
    localparam ALU_OR  = 3'd3;
    localparam ALU_XOR = 3'd4;
    localparam ALU_SHL = 3'd5;   // shift left  by b[3:0] places
    localparam ALU_SHR = 3'd6;   // shift right by b[3:0] places

    always @(*) begin
        case (op)
            ALU_ADD: y = a + b;
            ALU_SUB: y = a - b;
            ALU_AND: y = a & b;
            ALU_OR:  y = a | b;
            ALU_XOR: y = a ^ b;
            ALU_SHL: y = a << b[3:0];
            ALU_SHR: y = a >> b[3:0];
            default: y = 16'd0;
        endcase
    end

endmodule
