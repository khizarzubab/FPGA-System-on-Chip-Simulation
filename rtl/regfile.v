`timescale 1ns/1ps

// regfile.v - the CPU's 8 general-purpose 16-bit registers (r0 to r7)
//
// Three registers can be READ at the same time (combinational, no clock needed).
// One register is WRITTEN on the rising clock edge when 'we' is 1.
// All registers start at 0 (also on the FPGA, which supports initial values).

module regfile (
    input  wire        clk,
    input  wire        we,
    input  wire [2:0]  waddr,
    input  wire [15:0] wdata,
    input  wire [2:0]  raddr_a,
    input  wire [2:0]  raddr_b,
    input  wire [2:0]  raddr_c,
    output wire [15:0] rdata_a,
    output wire [15:0] rdata_b,
    output wire [15:0] rdata_c
);

    reg [15:0] regs [0:7];
    integer i;

    initial begin
        for (i = 0; i < 8; i = i + 1) regs[i] = 16'd0;
    end

    always @(posedge clk) begin
        if (we) regs[waddr] <= wdata;
    end

    assign rdata_a = regs[raddr_a];
    assign rdata_b = regs[raddr_b];
    assign rdata_c = regs[raddr_c];

endmodule
