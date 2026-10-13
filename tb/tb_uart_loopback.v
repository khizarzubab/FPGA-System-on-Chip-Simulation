// tb_uart_loopback.v - connects the UART transmitter straight into the UART receiver.
//
//   [ uart_tx ] --tx_line--> [ uart_rx ]
//
// Test 1: send "Hello" and print the received characters in the terminal (your early win).
// Test 2: send every possible byte value, 0 to 255, and check each one arrives unchanged.
//
// CLKS_PER_BIT is 16 here instead of 868 so the simulation runs quickly. The logic is identical.

`timescale 1ns/1ps

module tb_uart_loopback;

    parameter CLKS_PER_BIT = 16;

    reg        clk   = 1'b0;
    reg        rst   = 1'b1;
    reg        start = 1'b0;
    reg  [7:0] tx_data = 8'd0;

    wire       tx_line;
    wire       busy;
    wire [7:0] rx_data;
    wire       rx_valid;

    integer errors = 0;
    integer i;
    reg     show = 1'b0;     // when 1, print each received byte as a character

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst(rst), .start(start), .data(tx_data), .tx(tx_line), .busy(busy)
    );

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .rst(rst), .rx(tx_line), .data(rx_data), .valid(rx_valid)
    );

    always #5 clk = ~clk;    // 100 MHz

    // Send one byte, wait for the receiver to report it, then compare.
    // Inputs are changed on the falling clock edge so they never race with the design's rising edge.
    task send_byte;
        input [7:0] b;
        begin
            @(negedge clk);
            tx_data = b;
            start   = 1'b1;
            @(negedge clk);
            start   = 1'b0;

            @(posedge rx_valid);                 // wait until the receiver has a byte
            if (rx_data !== b) begin
                $display("FAIL  sent 0x%02h  received 0x%02h", b, rx_data);
                errors = errors + 1;
            end else if (show) begin
                $write("%c", rx_data);           // print as a text character
            end

            wait (busy == 1'b0);                 // make sure the transmitter is idle again
        end
    endtask

    // safety net: stop the simulation if something hangs
    initial begin
        #50_000_000;
        $display("TIMEOUT - simulation took too long");
        $finish;
    end

    initial begin
`ifdef __ICARUS__                    // only Icarus Verilog needs this; Vivado shows waveforms itself
        $dumpfile("build/uart_loopback.vcd");
        $dumpvars(0, tb_uart_loopback);
`endif

        repeat (5) @(negedge clk);
        rst = 1'b0;
        repeat (5) @(negedge clk);

        // Test 1: text
        $write("Received text: ");
        show = 1'b1;
        send_byte("H");
        send_byte("e");
        send_byte("l");
        send_byte("l");
        send_byte("o");
        show = 1'b0;
        $write("\n");

        // Test 2: all 256 byte values
        for (i = 0; i < 256; i = i + 1)
            send_byte(i);

        if (errors == 0) $display("ALL UART TESTS PASSED (Hello + 256 byte values)");
        else             $display("%0d UART TEST(S) FAILED", errors);
        $finish;
    end

endmodule
