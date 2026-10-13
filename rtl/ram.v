`timescale 1ns/1ps

// ram.v - data memory: 256 words of 16 bits
//
// Read is combinational (the value at 'addr' is always on 'rdata'); write happens on the
// rising clock edge when 'we' is 1. The CPU reaches it with addresses 0x0000 to 0x00FF.

module ram #(
    parameter AW = 8                 // address width: 2^AW words
)(
    input  wire          clk,
    input  wire          we,
    input  wire [AW-1:0] addr,
    input  wire [15:0]   wdata,
    output wire [15:0]   rdata
);

    reg [15:0] mem [0:(1 << AW) - 1];
    integer i;

    initial begin
        for (i = 0; i < (1 << AW); i = i + 1) mem[i] = 16'd0;
    end

    always @(posedge clk) begin
        if (we) mem[addr] <= wdata;
    end

    assign rdata = mem[addr];

endmodule
