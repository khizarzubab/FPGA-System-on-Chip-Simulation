`timescale 1ns/1ps

// tb_soc.v - the whole system running at once, with a pretend PC and a pretend sensor
//
//   pretend PC  <--- UART --->  soc_top (CPU running sw/firmware.asm)  <--- SPI --->  pretend sensor
//
// What happens:
//   1. The firmware sends 'R' (ready). The pretend PC sees it and answers 'G' (go).
//   2. The firmware reads 12 sensor samples over SPI, filters each, and drives the motor PWM, the
//      audio echo and the VGA bar with the result, and sends each filtered value to the PC.
//   3. The firmware sends 'D' (done) and halts.
//
// The testbench computes what every block should have produced (a reference model written here
// in plain arithmetic) and checks:
//   - every filtered byte the PC received
//   - the copies the CPU kept in RAM
//   - the motor PWM duty (high time over one PWM period)
//   - the audio PWM duty (the echo of the last sample)
//   - the VGA picture: it also writes one whole frame to soc_frame.ppm
//
// To view the picture:  python scripts/ppm_to_png.py soc_frame.ppm soc_frame.png
// Set CAPTURE_FRAME to 0 to skip the picture and finish faster.

module tb_soc;

    parameter CLKS_PER_BIT  = 868;    // UART: 100 MHz / 115200 baud
    parameter ECHO_DELAY    = 3;
    parameter N             = 12;     // samples the firmware reads (must match sw/firmware.asm)
    parameter CAPTURE_FRAME = 1;

    reg  clk   = 1'b0;
    reg  rst_n = 1'b0;

    wire       pc_to_soc;             // UART line: PC transmit -> SoC receive
    wire       soc_to_pc;             // UART line: SoC transmit -> PC receive
    wire       spi_sclk;
    wire       spi_mosi;
    wire       spi_miso;
    wire       spi_cs_n;
    wire       motor_pwm;
    wire       motor_in1;
    wire       motor_in2;
    wire       audio_pwm;
    wire [3:0] vga_r;
    wire [3:0] vga_g;
    wire [3:0] vga_b;
    wire       vga_hs;
    wire       vga_vs;
    wire       halted;

    soc_top #(
        .CLKS_PER_BIT(CLKS_PER_BIT),
        .ECHO_DELAY  (ECHO_DELAY)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .uart_rx_pin(pc_to_soc),
        .uart_tx_pin(soc_to_pc),
        .spi_sclk   (spi_sclk),
        .spi_mosi   (spi_mosi),
        .spi_miso   (spi_miso),
        .spi_cs_n   (spi_cs_n),
        .motor_pwm  (motor_pwm),
        .motor_in1  (motor_in1),
        .motor_in2  (motor_in2),
        .audio_pwm  (audio_pwm),
        .vga_r      (vga_r),
        .vga_g      (vga_g),
        .vga_b      (vga_b),
        .vga_hs     (vga_hs),
        .vga_vs     (vga_vs),
        .halted     (halted)
    );

    spi_sensor_model sensor (
        .cs_n(spi_cs_n), .sclk(spi_sclk), .mosi(spi_mosi), .miso(spi_miso)
    );

    // ---------------- the pretend PC ----------------
    reg        pc_start = 1'b0;
    reg  [7:0] pc_data  = 8'd0;
    wire       pc_busy;
    wire [7:0] pc_rx_data;
    wire       pc_rx_valid;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) pc_tx (
        .clk(clk), .rst(~rst_n), .start(pc_start), .data(pc_data),
        .tx(pc_to_soc), .busy(pc_busy)
    );

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) pc_rx (
        .clk(clk), .rst(~rst_n), .rx(soc_to_pc),
        .data(pc_rx_data), .valid(pc_rx_valid)
    );

    // remember every byte the PC receives
    reg [7:0] rx_bytes [0:63];
    integer   rx_count = 0;

    always @(posedge clk) begin
        if (pc_rx_valid) begin
            rx_bytes[rx_count] <= pc_rx_data;
            rx_count           <= rx_count + 1;
        end
    end

    always #5 clk = ~clk;

    // ---------------- reference model and checks ----------------
    integer exp_fir  [0:63];
    integer exp_echo [0:63];
    integer x0, x1, x2, x3, mixv;
    integer i, k;
    integer errors = 0;
    integer high;
    integer pix;
    integer green;
    integer fd;

    initial begin
        #400_000_000;
        $display("FAIL: TIMEOUT");
        $finish;
    end

    initial begin
`ifdef __ICARUS__
        $dumpfile("build/soc.vcd");
        $dumpvars(0, tb_soc);
`endif
        #1;                                    // let the sensor model fill its table

        // reference: FIR  y = (x0 + 3*x1 + 3*x2 + x3) / 8, remembered samples start at 0
        x0 = 0; x1 = 0; x2 = 0; x3 = 0;
        for (i = 0; i < N; i = i + 1) begin
            x3 = x2;
            x2 = x1;
            x1 = x0;
            x0 = sensor.samples[i];
            exp_fir[i] = (x0 + 3 * x1 + 3 * x2 + x3) / 8;
        end

        // reference: echo  out = in + (in from ECHO_DELAY samples ago) / 2, limited to 255
        for (i = 0; i < N; i = i + 1) begin
            if (i >= ECHO_DELAY) mixv = exp_fir[i] + exp_fir[i - ECHO_DELAY] / 2;
            else                 mixv = exp_fir[i];
            exp_echo[i] = (mixv > 255) ? 255 : mixv;
        end

        // ---- reset, then the conversation with the firmware ----
        repeat (20) @(posedge clk);
        rst_n = 1'b1;

        wait (rx_count >= 1);                  // the firmware says 'R'
        if (rx_bytes[0] !== 8'h52) begin
            $display("FAIL  first byte from the SoC is 0x%02h, expected 0x52 ('R')", rx_bytes[0]);
            errors = errors + 1;
        end else begin
            $display("PC: received 'R' (ready) from the SoC");
        end

        repeat (100) @(posedge clk);
        @(negedge clk);
        pc_data  = 8'h47;                      // 'G'
        pc_start = 1'b1;
        @(negedge clk);
        pc_start = 1'b0;
        $display("PC: sent 'G' (go)");

        wait (halted == 1'b1);
        wait (rx_count >= N + 2);              // 'R', N data bytes, 'D'
        repeat (10) @(posedge clk);

        // ---- check what the PC received and what the CPU stored ----
        $display("sample  raw  filtered(expected)  received  ram  echo(expected)");
        for (i = 0; i < N; i = i + 1) begin
            $display("%4d   %4d   %6d             %6d   %4d  %6d",
                     i, sensor.samples[i], exp_fir[i], rx_bytes[i + 1], dut.u_ram.mem[i], exp_echo[i]);
            if (rx_bytes[i + 1] !== exp_fir[i]) begin
                $display("FAIL  UART byte %0d: got %0d, expected %0d", i, rx_bytes[i + 1], exp_fir[i]);
                errors = errors + 1;
            end
            if (dut.u_ram.mem[i] !== exp_fir[i]) begin
                $display("FAIL  RAM word %0d: got %0d, expected %0d", i, dut.u_ram.mem[i], exp_fir[i]);
                errors = errors + 1;
            end
        end
        if (rx_bytes[N + 1] !== 8'h44) begin
            $display("FAIL  last byte is 0x%02h, expected 0x44 ('D')", rx_bytes[N + 1]);
            errors = errors + 1;
        end else begin
            $display("PC: received 'D' (done) from the SoC");
        end
        if (errors == 0) $display("PASS  UART text, SPI sensor, FIR filter and RAM all agree with the reference");

        // ---- motor PWM: high for duty * 40 clocks out of every 10240 ----
        repeat (12000) @(posedge clk);
        high = 0;
        for (k = 0; k < 10240; k = k + 1) begin
            @(posedge clk);
            if (motor_pwm) high = high + 1;
        end
        if (high !== exp_fir[N - 1] * 40) begin
            $display("FAIL  motor PWM high %0d clocks, expected %0d", high, exp_fir[N - 1] * 40);
            errors = errors + 1;
        end else begin
            $display("PASS  motor PWM duty %0d of 255 (%0d of 10240 clocks high)", exp_fir[N - 1], high);
        end

        // ---- audio PWM: duty equals the echo of the last sample ----
        high = 0;
        for (k = 0; k < 256; k = k + 1) begin
            @(posedge clk);
            if (audio_pwm) high = high + 1;
        end
        if (high !== exp_echo[N - 1]) begin
            $display("FAIL  audio PWM duty %0d, expected %0d", high, exp_echo[N - 1]);
            errors = errors + 1;
        end else begin
            $display("PASS  audio echo output %0d (last filtered sample %0d plus its echo)", high, exp_fir[N - 1]);
        end

        // ---- VGA: capture one whole frame ----
        if (CAPTURE_FRAME != 0) begin
            fd = $fopen("soc_frame.ppm", "w");
            if (fd != 0) $fwrite(fd, "P3\n640 480\n255\n");
            @(posedge clk);
            while (!(dut.vga_x == 10'd0 && dut.vga_y == 10'd0 && dut.vga_pix_en)) @(posedge clk);
            pix   = 0;
            green = 0;
            while (pix < 307200) begin
                if (dut.vga_pix_en && dut.vga_visible) begin
                    if (fd != 0) $fwrite(fd, "%0d %0d %0d\n", vga_r * 17, vga_g * 17, vga_b * 17);
                    if (vga_r == 4'd0 && vga_g == 4'd15 && vga_b == 4'd0) green = green + 1;
                    pix = pix + 1;
                end
                @(posedge clk);
            end
            if (fd != 0) $fclose(fd);
            if (green !== 160 * exp_fir[N - 1]) begin
                $display("FAIL  VGA bar has %0d green pixels, expected %0d", green, 160 * exp_fir[N - 1]);
                errors = errors + 1;
            end else begin
                $display("PASS  VGA frame: bar length matches the filtered value (%0d green pixels); picture saved to soc_frame.ppm", green);
            end
        end

        if (errors == 0) $display("ALL SYSTEM TESTS PASSED");
        else             $display("%0d SYSTEM TEST(S) FAILED", errors);
        $finish;
    end

endmodule
