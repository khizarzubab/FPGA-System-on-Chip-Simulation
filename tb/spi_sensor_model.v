`timescale 1ns/1ps

// spi_sensor_model.v - SIMULATION ONLY. A pretend SPI sensor (mode 0) for the testbenches.
//
// Every time chip select goes low it starts a new transfer and sends the next value from its
// table of 16 samples, most significant bit first. The table is a slowly rising signal with
// noise (spikes up and down), which is what the FIR filter is there to smooth.
//
// It also records the byte the master sent on MOSI ('last_mosi') so a testbench can check it.
// This file is not hardware and is never synthesized.

module spi_sensor_model (
    input  wire cs_n,
    input  wire sclk,
    input  wire mosi,
    output reg  miso
);

    reg [7:0] samples [0:15];
    reg [7:0] shreg;
    reg [3:0] idx;
    reg [7:0] mosi_sh;
    reg [7:0] last_mosi;

    initial begin
        idx       = 4'd0;
        miso      = 1'b0;
        shreg     = 8'd0;
        mosi_sh   = 8'd0;
        last_mosi = 8'd0;
        samples[0]  = 8'd100;
        samples[1]  = 8'd108;
        samples[2]  = 8'd92;
        samples[3]  = 8'd140;
        samples[4]  = 8'd104;
        samples[5]  = 8'd112;
        samples[6]  = 8'd96;
        samples[7]  = 8'd150;
        samples[8]  = 8'd108;
        samples[9]  = 8'd116;
        samples[10] = 8'd100;
        samples[11] = 8'd128;
        samples[12] = 8'd112;
        samples[13] = 8'd120;
        samples[14] = 8'd104;
        samples[15] = 8'd136;
    end

    // chip select falls: load the next sample and present its top bit
    always @(negedge cs_n) begin
        shreg   = samples[idx];
        idx     = idx + 4'd1;
        miso    = shreg[7];
        mosi_sh = 8'd0;
    end

    // rising clock edge: read one bit from the master
    always @(posedge sclk) begin
        if (!cs_n) mosi_sh = {mosi_sh[6:0], mosi};
    end

    // falling clock edge: present the next bit
    always @(negedge sclk) begin
        if (!cs_n) begin
            shreg = {shreg[6:0], 1'b0};
            miso  = shreg[7];
        end
    end

    // chip select rises: transfer over
    always @(posedge cs_n) begin
        last_mosi = mosi_sh;
        miso      = 1'b0;
    end

endmodule
