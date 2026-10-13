// uart_tx.v - UART transmitter (FPGA -> PC, one byte at a time)
//
// A UART frame on the wire looks like this (8N1, sent at one fixed speed called the baud rate):
//
//   idle=1 | START=0 | d0 d1 d2 d3 d4 d5 d6 d7 | STOP=1 | idle=1
//                      (least significant bit first)
//
// Every bit lasts CLKS_PER_BIT clock cycles.
//   CLKS_PER_BIT = clock frequency / baud rate
//   Example: 100 MHz / 115200 baud = 868 clocks per bit
//
// HOW TO USE: put a byte on 'data', pulse 'start' high for ONE clock cycle while 'busy' is 0.
// 'busy' stays high until the whole frame has been sent.

`timescale 1ns/1ps

module uart_tx #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst,     // synchronous reset, active high
    input  wire       start,   // pulse high for one clock to send 'data'
    input  wire [7:0] data,    // the byte to send
    output reg        tx,      // the serial line (idle level is 1)
    output reg        busy     // 1 while a frame is being sent
);

    // The four states of the finite state machine
    localparam IDLE  = 2'd0;   // waiting for 'start'
    localparam START = 2'd1;   // sending the start bit (line = 0)
    localparam DATA  = 2'd2;   // sending the 8 data bits
    localparam STOP  = 2'd3;   // sending the stop bit (line = 1)

    reg [1:0]  state;
    reg [15:0] clk_count;      // counts clocks inside the current bit
    reg [2:0]  bit_index;      // which data bit is on the line (0..7)
    reg [7:0]  shreg;          // copy of the byte, shifted right as we go

    always @(posedge clk) begin
        if (rst) begin
            state     <= IDLE;
            tx        <= 1'b1;
            busy      <= 1'b0;
            clk_count <= 16'd0;
            bit_index <= 3'd0;
            shreg     <= 8'd0;
        end else begin
            case (state)

                IDLE: begin
                    tx        <= 1'b1;
                    busy      <= 1'b0;
                    clk_count <= 16'd0;
                    bit_index <= 3'd0;
                    if (start) begin
                        shreg <= data;       // remember the byte
                        busy  <= 1'b1;
                        tx    <= 1'b0;       // start bit begins now
                        state <= START;
                    end
                end

                START: begin
                    // hold the line low for a full bit time
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;
                        tx        <= shreg[0];                 // first data bit (d0)
                        shreg     <= {1'b0, shreg[7:1]};       // shift right: next bit moves to position 0
                        bit_index <= 3'd0;
                        state     <= DATA;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;
                        if (bit_index == 3'd7) begin
                            tx    <= 1'b1;                     // all 8 bits done -> stop bit
                            state <= STOP;
                        end else begin
                            tx        <= shreg[0];             // put the next bit on the line
                            shreg     <= {1'b0, shreg[7:1]};
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                STOP: begin
                    // hold the line high for a full bit time, then finish
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;
                        busy      <= 1'b0;
                        state     <= IDLE;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
