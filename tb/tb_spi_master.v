`timescale 1ns/1ps

// tb_spi_master.v - connects the SPI master to the pretend sensor and reads 6 samples.
//
// For each transfer it checks:
//   - the byte received equals the next sample in the sensor's table
//   - the byte the sensor saw on MOSI equals the byte we sent

module tb_spi_master;

    reg        clk     = 1'b0;
    reg        rst     = 1'b1;
    reg        start   = 1'b0;
    reg  [7:0] tx_data = 8'd0;
    wire [7:0] rx_data;
    wire       busy;
    wire       sclk;
    wire       mosi;
    wire       miso;
    wire       cs_n;

    integer errors = 0;
    integer n;

    spi_master #(.CLK_DIV(4)) dut (
        .clk(clk), .rst(rst), .start(start), .tx_data(tx_data),
        .rx_data(rx_data), .busy(busy),
        .sclk(sclk), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );

    spi_sensor_model sensor (
        .cs_n(cs_n), .sclk(sclk), .mosi(mosi), .miso(miso)
    );

    always #5 clk = ~clk;

    task transfer;
        input [7:0] send;
        input [7:0] expected_rx;
        begin
            @(negedge clk);
            tx_data = send;
            start   = 1'b1;
            @(negedge clk);
            start   = 1'b0;
            wait (busy == 1'b0);
            @(negedge clk);                    // let everything settle
            if (rx_data !== expected_rx) begin
                $display("FAIL  received 0x%02h, expected 0x%02h", rx_data, expected_rx);
                errors = errors + 1;
            end else if (sensor.last_mosi !== send) begin
                $display("FAIL  sensor saw 0x%02h on MOSI, we sent 0x%02h", sensor.last_mosi, send);
                errors = errors + 1;
            end else begin
                $display("PASS  sent 0x%02h, received %0d", send, rx_data);
            end
        end
    endtask

    initial begin
        #5_000_000;
        $display("FAIL: TIMEOUT");
        $finish;
    end

    initial begin
`ifdef __ICARUS__
        $dumpfile("build/spi_master.vcd");
        $dumpvars(0, tb_spi_master);
`endif
        repeat (4) @(negedge clk);
        rst = 1'b0;
        repeat (4) @(negedge clk);

        for (n = 0; n < 6; n = n + 1)
            transfer(8'hA5 + n, sensor.samples[n]);

        if (errors == 0) $display("ALL SPI TESTS PASSED");
        else             $display("%0d SPI TEST(S) FAILED", errors);
        $finish;
    end

endmodule
