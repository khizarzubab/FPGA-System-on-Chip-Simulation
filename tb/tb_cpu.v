`timescale 1ns/1ps

// tb_cpu.v - runs a short test program on the CPU alone, with simple memory models
//
// The program (written here as machine code) does:
//   r1 = 10 + 9 + ... + 1 = 55           a loop with add, addi and bne
//   memory[32] = r1, then r4 = memory[32] store and load
//   r5 = r4 << 2 = 220                   shift
//   r6 = 0x1200                          ldih
//   a taken beq skips one instruction, a jmp skips another
//   r2 = 0x0F & 0x3C, r4 = 0x0F | 0x3C, r1 = 0x0F ^ 0x3C, r0 = r4 - r2
//   halt
// Afterwards the testbench compares memory and every register with the expected values.

module tb_cpu;

    reg         clk = 1'b0;
    reg         rst = 1'b1;

    wire [7:0]  instr_addr;
    wire [15:0] instr_data;
    wire [15:0] mem_addr;
    wire [15:0] mem_wdata;
    wire [15:0] mem_rdata;
    wire        mem_we;
    wire        mem_re;
    wire        halted;

    reg [15:0] rom [0:255];
    reg [15:0] ram [0:255];
    integer    i;
    integer    errors = 0;

    assign instr_data = rom[instr_addr];
    assign mem_rdata  = ram[mem_addr[7:0]];

    always @(posedge clk) begin
        if (mem_we) ram[mem_addr[7:0]] <= mem_wdata;
    end

    cpu dut (
        .clk(clk), .rst(rst),
        .instr_addr(instr_addr), .instr_data(instr_data),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_we(mem_we), .mem_re(mem_re), .mem_rdata(mem_rdata),
        .halted(halted)
    );

    always #5 clk = ~clk;

    // ---- helpers that build instruction words ----
    function [15:0] enc_r;                 // op rd, rs, rt
        input [3:0] op;
        input [2:0] rd;
        input [2:0] rs;
        input [2:0] rt;
        begin
            enc_r = {op, rd, rs, rt, 3'b000};
        end
    endfunction

    function [15:0] enc_i;                 // op ra, rb, imm6
        input [3:0] op;
        input [2:0] ra;
        input [2:0] rb;
        input [5:0] imm;
        begin
            enc_i = {op, ra, rb, imm};
        end
    endfunction

    function [15:0] enc_ldi;               // op rd, imm8
        input [3:0] op;
        input [2:0] rd;
        input [7:0] imm;
        begin
            enc_ldi = {op, rd, 1'b0, imm};
        end
    endfunction

    task check_reg;
        input integer n;
        input [15:0]  expected;
        reg   [15:0]  actual;
        begin
            actual = dut.u_rf.regs[n];
            if (actual !== expected) begin
                $display("FAIL  r%0d = %h, expected %h", n, actual, expected);
                errors = errors + 1;
            end else begin
                $display("PASS  r%0d = %h", n, actual);
            end
        end
    endtask

    initial begin
        #10_000_000;
        $display("FAIL: TIMEOUT (the CPU never halted)");
        $finish;
    end

    initial begin
`ifdef __ICARUS__
        $dumpfile("build/cpu.vcd");
        $dumpvars(0, tb_cpu);
`endif
        for (i = 0; i < 256; i = i + 1) begin
            rom[i] = 16'h0000;
            ram[i] = 16'h0000;
        end

        rom[0]  = enc_ldi(4'hB, 3'd0, 8'd0);          // ldi  r0, 0
        rom[1]  = enc_ldi(4'hB, 3'd1, 8'd0);          // ldi  r1, 0
        rom[2]  = enc_ldi(4'hB, 3'd2, 8'd10);         // ldi  r2, 10
        rom[3]  = enc_r  (4'h1, 3'd1, 3'd1, 3'd2);    // add  r1, r1, r2      (loop start)
        rom[4]  = enc_i  (4'h6, 3'd2, 3'd2, 6'd63);   // addi r2, r2, -1
        rom[5]  = enc_i  (4'hE, 3'd2, 3'd0, 6'd61);   // bne  r2, r0, -3      (back to rom[3])
        rom[6]  = enc_ldi(4'hB, 3'd3, 8'd32);         // ldi  r3, 32
        rom[7]  = enc_i  (4'h8, 3'd1, 3'd3, 6'd0);    // st   r1, [r3+0]
        rom[8]  = enc_i  (4'h7, 3'd4, 3'd3, 6'd0);    // ld   r4, [r3+0]
        rom[9]  = enc_i  (4'h9, 3'd5, 3'd4, 6'd2);    // shli r5, r4, 2
        rom[10] = enc_ldi(4'hC, 3'd6, 8'h12);         // ldih r6, 0x12
        rom[11] = enc_i  (4'hD, 3'd1, 3'd4, 6'd1);    // beq  r1, r4, +1      (taken: skips rom[12])
        rom[12] = enc_ldi(4'hB, 3'd3, 8'hEE);         // ldi  r3, 0xEE        (must be skipped)
        rom[13] = 16'hF00F;                           // jmp  15              (skips rom[14])
        rom[14] = enc_ldi(4'hB, 3'd5, 8'd0);          // ldi  r5, 0           (must be skipped)
        rom[15] = enc_ldi(4'hB, 3'd7, 8'h0F);         // ldi  r7, 0x0F
        rom[16] = enc_ldi(4'hB, 3'd1, 8'h3C);         // ldi  r1, 0x3C
        rom[17] = enc_r  (4'h3, 3'd2, 3'd7, 3'd1);    // and  r2, r7, r1
        rom[18] = enc_r  (4'h4, 3'd4, 3'd7, 3'd1);    // or   r4, r7, r1
        rom[19] = enc_r  (4'h5, 3'd1, 3'd7, 3'd1);    // xor  r1, r7, r1
        rom[20] = enc_r  (4'h2, 3'd0, 3'd4, 3'd2);    // sub  r0, r4, r2
        rom[21] = 16'hF800;                           // halt

        repeat (4) @(negedge clk);
        rst = 1'b0;

        wait (halted == 1'b1);
        repeat (4) @(negedge clk);

        if (ram[32] !== 16'd55) begin
            $display("FAIL  memory[32] = %0d, expected 55", ram[32]);
            errors = errors + 1;
        end else begin
            $display("PASS  memory[32] = 55");
        end

        check_reg(0, 16'h0033);      // r4 - r2 = 0x3F - 0x0C
        check_reg(1, 16'h0033);      // 0x0F ^ 0x3C
        check_reg(2, 16'h000C);      // 0x0F & 0x3C
        check_reg(3, 16'h0020);      // still 32: the skipped ldi did not run
        check_reg(4, 16'h003F);      // 0x0F | 0x3C
        check_reg(5, 16'h00DC);      // 220: the skipped ldi did not run
        check_reg(6, 16'h1200);
        check_reg(7, 16'h000F);

        if (errors == 0) $display("ALL CPU TESTS PASSED");
        else             $display("%0d CPU TEST(S) FAILED", errors);
        $finish;
    end

endmodule
