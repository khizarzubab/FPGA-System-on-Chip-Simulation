// uart_rx.v - UART receiver (PC -> FPGA, one byte at a time)
//
// The receiver has no clock wire. It only knows the agreed baud rate (CLKS_PER_BIT).
// Strategy:
//   1. Wait for the line to fall from 1 to 0 (the start bit begins).
//   2. Wait HALF a bit time so we are in the MIDDLE of the start bit, and check it is still 0
//      (this rejects short noise glitches).
//   3. From then on, wait one FULL bit time between samples, so each sample lands in the
//      middle of a data bit, where the signal is most stable.
//   4. After 8 data bits, wait through the stop bit, then announce the byte.
//
// OUTPUT: when a byte has arrived, 'valid' is high for ONE clock cycle and 'data' holds the byte.

`timescale 1ns/1ps

module uart_rx #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst,     // synchronous reset, active high
    input  wire       rx,      // serial input from outside the chip (idle level is 1)
    output reg  [7:0] data,    // the received byte (valid when 'valid' = 1)
    output reg        valid    // one-clock pulse: a new byte is ready
);

    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    // The rx pin changes at any moment, not in step with our clock. Passing it through two
    // flip-flops (a "synchronizer") stops a half-changed value from corrupting the state machine.
    reg rx_meta;
    reg rx_s;
    always @(posedge clk) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_s    <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_s    <= rx_meta;
        end
    end

    reg [1:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;
    reg [7:0]  rx_data;        // bits are collected here, then copied to 'data' at the end

    always @(posedge clk) begin
        valid <= 1'b0;         // default: the pulse lasts only one cycle

        if (rst) begin
            state     <= IDLE;
            clk_count <= 16'd0;
            bit_index <= 3'd0;
            rx_data   <= 8'd0;
            data      <= 8'd0;
        end else begin
            case (state)

                IDLE: begin
                    clk_count <= 16'd0;
                    bit_index <= 3'd0;
                    if (rx_s == 1'b0) state <= START;      // falling edge: a frame is starting
                end

                START: begin
                    if (clk_count == (CLKS_PER_BIT - 1) / 2) begin
                        // we are now in the middle of the start bit
                        if (rx_s == 1'b0) begin
                            clk_count <= 16'd0;
                            state     <= DATA;             // real start bit, go collect data
                        end else begin
                            state <= IDLE;                 // it was only a glitch
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count          <= 16'd0;
                        rx_data[bit_index] <= rx_s;        // sample in the middle of this bit
                        if (bit_index == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                STOP: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;
                        data      <= rx_data;              // publish the finished byte
                        valid     <= 1'b1;                 // tell the rest of the design
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
