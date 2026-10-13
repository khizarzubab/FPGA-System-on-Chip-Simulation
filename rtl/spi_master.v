`timescale 1ns/1ps

// spi_master.v - SPI master, mode 0, 8 bits per transfer, most significant bit first
//
// SPI uses 4 wires: SCLK (clock from the master), MOSI (data to the chip), MISO (data from the
// chip) and CS_N (chip select, active low). In mode 0 the clock idles low, and both sides read
// data on the RISING clock edge and change data on the FALLING edge.
//
// HOW TO USE: put a byte on 'tx_data' and pulse 'start' for one clock. 'busy' stays high during
// the transfer. When 'busy' falls, 'rx_data' holds the byte the chip sent back.
//
// CLK_DIV = system clock cycles in half an SCLK period.
//   SCLK frequency = clk / (2 * CLK_DIV)   (CLK_DIV = 4 at 100 MHz gives 12.5 MHz)

module spi_master #(
    parameter CLK_DIV = 4
)(
    input  wire       clk,
    input  wire       rst,        // synchronous reset, active high
    input  wire       start,      // pulse high for one clock to begin a transfer
    input  wire [7:0] tx_data,    // byte to send
    output reg  [7:0] rx_data,    // byte received (valid when busy falls)
    output reg        busy,
    output reg        sclk,
    output reg        mosi,
    input  wire       miso,
    output reg        cs_n
);

    localparam S_IDLE   = 3'd0;
    localparam S_SETUP  = 3'd1;   // chip select is low, first bit is on MOSI, clock still low
    localparam S_HIGH   = 3'd2;   // clock high: the chip and we read a bit
    localparam S_LOW    = 3'd3;   // clock low: we put the next bit on MOSI
    localparam S_FINISH = 3'd4;   // last bit done: wait half a period, then release chip select

    reg [2:0]  state;
    reg [15:0] cnt;
    reg [3:0]  bit_idx;
    reg [7:0]  tx_sh;
    reg [7:0]  rx_sh;

    always @(posedge clk) begin
        if (rst) begin
            state   <= S_IDLE;
            cs_n    <= 1'b1;
            sclk    <= 1'b0;
            mosi    <= 1'b0;
            busy    <= 1'b0;
            cnt     <= 16'd0;
            bit_idx <= 4'd0;
            tx_sh   <= 8'd0;
            rx_sh   <= 8'd0;
            rx_data <= 8'd0;
        end else begin
            case (state)

                S_IDLE: begin
                    sclk <= 1'b0;
                    cs_n <= 1'b1;
                    busy <= 1'b0;
                    cnt  <= 16'd0;
                    if (start) begin
                        tx_sh   <= tx_data;
                        rx_sh   <= 8'd0;
                        bit_idx <= 4'd0;
                        cs_n    <= 1'b0;
                        busy    <= 1'b1;
                        mosi    <= tx_data[7];
                        state   <= S_SETUP;
                    end
                end

                S_SETUP: begin
                    if (cnt == CLK_DIV - 1) begin
                        cnt   <= 16'd0;
                        sclk  <= 1'b1;               // first rising edge
                        state <= S_HIGH;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_HIGH: begin
                    if (cnt == CLK_DIV - 1) begin
                        cnt   <= 16'd0;
                        sclk  <= 1'b0;               // falling edge
                        rx_sh <= {rx_sh[6:0], miso}; // read the bit just before the clock falls
                        if (bit_idx == 4'd7) begin
                            state <= S_FINISH;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                            tx_sh   <= {tx_sh[6:0], 1'b0};
                            mosi    <= tx_sh[6];     // next bit to send
                            state   <= S_LOW;
                        end
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_LOW: begin
                    if (cnt == CLK_DIV - 1) begin
                        cnt   <= 16'd0;
                        sclk  <= 1'b1;               // rising edge
                        state <= S_HIGH;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_FINISH: begin
                    if (cnt == CLK_DIV - 1) begin
                        cnt     <= 16'd0;
                        cs_n    <= 1'b1;
                        rx_data <= rx_sh;
                        busy    <= 1'b0;
                        state   <= S_IDLE;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
