`timescale 1ns/1ps

// soc_top.v - the complete mini system-on-chip: everything connected together
//
//                         +-----------------------------------------------+
//   program_rom --------->|  cpu  (runs the firmware, 2 clocks / instr.)  |
//                         +----------------------+------------------------+
//                                                | data bus (address, data, read, write)
//        +--------+--------+--------+---------+--+------+---------+-----------+
//        |        |        |        |         |         |         |           |
//       ram     uart     pwm      spi       fir      audio      vga        (more)
//      (data)  tx / rx  (motor)  (sensor) (filter)  (echo+pwm) (bar graph)
//
// The CPU talks to every peripheral by reading and writing fixed addresses (memory-mapped I/O):
//
//   0x0000 - 0x00FF   RAM (256 words)
//   0x8000  UART_DATA     write: send a byte        read: last byte received (clears the flag)
//   0x8001  UART_STATUS   read: bit 0 = transmitter busy, bit 1 = a received byte is waiting
//   0x8002  PWM_DUTY      write: motor speed 0..255
//   0x8003  SPI_DATA      write: start a transfer   read: byte received from the sensor
//   0x8004  SPI_STATUS    read: bit 0 = transfer in progress
//   0x8005  FIR_IN        write: give the filter a new sample
//   0x8006  FIR_OUT       read: filtered value
//   0x8007  AUDIO_IN      write: give the echo effect a new sample
//   0x8008  AUDIO_OUT     read: sample with echo
//   0x8009  VGA_LEVEL     write: length of the bar drawn on the monitor
//
// The pins of this module are what would connect to the outside world on a real board.

module soc_top #(
    parameter CLKS_PER_BIT  = 868,   // UART: 100 MHz / 115200 baud
    parameter SPI_CLK_DIV   = 4,     // SPI clock = 100 MHz / (2 * 4) = 12.5 MHz
    parameter MOTOR_CLK_DIV = 40,    // motor PWM = 100 MHz / 40 / 256 = about 9.8 kHz
    parameter ECHO_DELAY    = 3      // audio echo delay in samples
)(
    input  wire       clk,           // 100 MHz system clock
    input  wire       rst_n,         // reset, active low

    input  wire       uart_rx_pin,   // serial in  (from the PC)
    output wire       uart_tx_pin,   // serial out (to the PC)

    output wire       spi_sclk,      // SPI to the sensor
    output wire       spi_mosi,
    input  wire       spi_miso,
    output wire       spi_cs_n,

    output wire       motor_pwm,     // to the motor driver: speed
    output wire       motor_in1,     // to the motor driver: direction
    output wire       motor_in2,

    output wire       audio_pwm,     // audio out (smooth with an RC filter)

    output wire [3:0] vga_r,         // monitor
    output wire [3:0] vga_g,
    output wire [3:0] vga_b,
    output wire       vga_hs,
    output wire       vga_vs,

    output wire       halted         // 1 when the firmware has finished
);

    wire rst = ~rst_n;

    // ---------------- CPU, program and data memory ----------------
    wire [7:0]  instr_addr;
    wire [15:0] instr_data;
    wire [15:0] mem_addr;
    wire [15:0] mem_wdata;
    wire [15:0] mem_rdata;
    wire        mem_we;
    wire        mem_re;
    wire [15:0] ram_rdata;
    reg  [15:0] io_rdata;

    cpu u_cpu (
        .clk       (clk),
        .rst       (rst),
        .instr_addr(instr_addr),
        .instr_data(instr_data),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_we    (mem_we),
        .mem_re    (mem_re),
        .mem_rdata (mem_rdata),
        .halted    (halted)
    );

    program_rom u_rom (
        .addr(instr_addr),
        .data(instr_data)
    );

    // ---------------- address decoding ----------------
    wire       is_mmio = mem_addr[15];
    wire [7:0] sel     = mem_addr[7:0];
    wire       ram_we  = mem_we && !is_mmio;
    wire       io_we   = mem_we && is_mmio;
    wire       io_re   = mem_re && is_mmio;

    wire wr_uart  = io_we && (sel == 8'h00);
    wire wr_pwm   = io_we && (sel == 8'h02);
    wire wr_spi   = io_we && (sel == 8'h03);
    wire wr_fir   = io_we && (sel == 8'h05);
    wire wr_audio = io_we && (sel == 8'h07);
    wire wr_vga   = io_we && (sel == 8'h09);
    wire rd_uart  = io_re && (sel == 8'h00);

    ram #(.AW(8)) u_ram (
        .clk  (clk),
        .we   (ram_we),
        .addr (mem_addr[7:0]),
        .wdata(mem_wdata),
        .rdata(ram_rdata)
    );

    // ---------------- UART ----------------
    wire       uart_busy;
    wire       rx_valid;
    wire [7:0] rx_byte;
    reg  [7:0] rx_data_reg;
    reg        rx_ready;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_tx (
        .clk  (clk),
        .rst  (rst),
        .start(wr_uart),
        .data (mem_wdata[7:0]),
        .tx   (uart_tx_pin),
        .busy (uart_busy)
    );

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_rx (
        .clk  (clk),
        .rst  (rst),
        .rx   (uart_rx_pin),
        .data (rx_byte),
        .valid(rx_valid)
    );

    // keep the last received byte, and remember that the CPU has not read it yet
    always @(posedge clk) begin
        if (rst) begin
            rx_data_reg <= 8'd0;
            rx_ready    <= 1'b0;
        end else if (rx_valid) begin
            rx_data_reg <= rx_byte;
            rx_ready    <= 1'b1;
        end else if (rd_uart) begin
            rx_ready    <= 1'b0;
        end
    end

    // ---------------- motor PWM ----------------
    reg [7:0] pwm_duty;

    always @(posedge clk) begin
        if (rst)         pwm_duty <= 8'd0;
        else if (wr_pwm) pwm_duty <= mem_wdata[7:0];
    end

    pwm #(.WIDTH(8), .CLK_DIV(MOTOR_CLK_DIV)) u_motor_pwm (
        .clk    (clk),
        .rst    (rst),
        .duty   (pwm_duty),
        .pwm_out(motor_pwm)
    );

    assign motor_in1 = 1'b1;       // fixed direction: forward
    assign motor_in2 = 1'b0;

    // ---------------- SPI (sensor) ----------------
    wire [7:0] spi_rx;
    wire       spi_busy;

    spi_master #(.CLK_DIV(SPI_CLK_DIV)) u_spi (
        .clk    (clk),
        .rst    (rst),
        .start  (wr_spi),
        .tx_data(mem_wdata[7:0]),
        .rx_data(spi_rx),
        .busy   (spi_busy),
        .sclk   (spi_sclk),
        .mosi   (spi_mosi),
        .miso   (spi_miso),
        .cs_n   (spi_cs_n)
    );

    // ---------------- FIR filter ----------------
    wire [7:0] fir_out;

    fir_filter u_fir (
        .clk         (clk),
        .rst         (rst),
        .sample_valid(wr_fir),
        .sample_in   (mem_wdata[7:0]),
        .sample_out  (fir_out)
    );

    // ---------------- audio echo + PWM output ----------------
    wire [7:0] echo_out;

    audio_echo #(.DELAY(ECHO_DELAY)) u_echo (
        .clk         (clk),
        .rst         (rst),
        .sample_valid(wr_audio),
        .sample_in   (mem_wdata[7:0]),
        .sample_out  (echo_out)
    );

    pwm #(.WIDTH(8), .CLK_DIV(1)) u_audio_pwm (
        .clk    (clk),
        .rst    (rst),
        .duty   (echo_out),
        .pwm_out(audio_pwm)
    );

    // ---------------- VGA ----------------
    reg  [7:0] vga_level;
    wire       vga_visible;
    wire       vga_pix_en;
    wire [9:0] vga_x;
    wire [9:0] vga_y;

    always @(posedge clk) begin
        if (rst)         vga_level <= 8'd0;
        else if (wr_vga) vga_level <= mem_wdata[7:0];
    end

    vga_timing #(.PIX_DIV(4)) u_vga_timing (
        .clk    (clk),
        .rst    (rst),
        .hsync  (vga_hs),
        .vsync  (vga_vs),
        .visible(vga_visible),
        .pix_en (vga_pix_en),
        .x      (vga_x),
        .y      (vga_y)
    );

    vga_bargraph u_vga_bars (
        .visible(vga_visible),
        .x      (vga_x),
        .y      (vga_y),
        .level  (vga_level),
        .r      (vga_r),
        .g      (vga_g),
        .b      (vga_b)
    );

    // ---------------- read-back multiplexer ----------------
    always @(*) begin
        case (sel)
            8'h00:   io_rdata = {8'd0, rx_data_reg};
            8'h01:   io_rdata = {14'd0, rx_ready, uart_busy};
            8'h03:   io_rdata = {8'd0, spi_rx};
            8'h04:   io_rdata = {15'd0, spi_busy};
            8'h06:   io_rdata = {8'd0, fir_out};
            8'h08:   io_rdata = {8'd0, echo_out};
            default: io_rdata = 16'd0;
        endcase
    end

    assign mem_rdata = is_mmio ? io_rdata : ram_rdata;

endmodule
