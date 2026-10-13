`timescale 1ns/1ps

// cpu.v - a small 16-bit CPU designed for this project
//
// It runs the program stored in program_rom.v. Each instruction takes 2 clock cycles:
//   cycle 1 (FETCH):   copy the instruction at address 'pc' into the instruction register 'ir'
//   cycle 2 (EXECUTE): do what the instruction says, then move 'pc' on
//
// INSTRUCTION FORMAT (16 bits). op = bits 15:12. Register fields: A = 11:9, B = 8:6, C = 5:3.
//
//   op  name   meaning
//   0   nop    do nothing
//   1   add    rA = rB + rC
//   2   sub    rA = rB - rC
//   3   and    rA = rB & rC
//   4   or     rA = rB | rC
//   5   xor    rA = rB ^ rC
//   6   addi   rA = rB + imm6              (imm6 = bits 5:0, signed -32..31)
//   7   ld     rA = memory[rB + imm6]
//   8   st     memory[rB + imm6] = rA      (rA is the value to store)
//   9   shli   rA = rB << imm              (imm = bits 3:0)
//   10  shri   rA = rB >> imm
//   11  ldi    rA = imm8                   (imm8 = bits 7:0, zero-extended)
//   12  ldih   rA[15:8] = imm8             (low byte of rA unchanged)
//   13  beq    if (rA == rB) pc = pc + 1 + imm6
//   14  bne    if (rA != rB) pc = pc + 1 + imm6
//   15  jmp    pc = bits 7:0               (when bit 11 = 0)
//       halt   stop the CPU                (when bit 11 = 1)
//
// MEMORY: addresses with bit 15 = 0 are RAM, bit 15 = 1 are peripherals (see soc_top.v).

module cpu (
    input  wire        clk,
    input  wire        rst,           // synchronous reset, active high

    output wire [7:0]  instr_addr,    // which program word we want
    input  wire [15:0] instr_data,    // the program word at that address

    output wire [15:0] mem_addr,      // data bus address
    output wire [15:0] mem_wdata,     // data to write
    output wire        mem_we,        // 1 during the execute cycle of a store
    output wire        mem_re,        // 1 during the execute cycle of a load
    input  wire [15:0] mem_rdata,     // data read back

    output wire        halted         // 1 once a halt instruction has run
);

    localparam OP_NOP     = 4'h0;
    localparam OP_ADD     = 4'h1;
    localparam OP_SUB     = 4'h2;
    localparam OP_AND     = 4'h3;
    localparam OP_OR      = 4'h4;
    localparam OP_XOR     = 4'h5;
    localparam OP_ADDI    = 4'h6;
    localparam OP_LD      = 4'h7;
    localparam OP_ST      = 4'h8;
    localparam OP_SHLI    = 4'h9;
    localparam OP_SHRI    = 4'hA;
    localparam OP_LDI     = 4'hB;
    localparam OP_LDIH    = 4'hC;
    localparam OP_BEQ     = 4'hD;
    localparam OP_BNE     = 4'hE;
    localparam OP_JMPHALT = 4'hF;

    localparam ALU_ADD = 3'd0;
    localparam ALU_SUB = 3'd1;
    localparam ALU_AND = 3'd2;
    localparam ALU_OR  = 3'd3;
    localparam ALU_XOR = 3'd4;
    localparam ALU_SHL = 3'd5;
    localparam ALU_SHR = 3'd6;

    localparam S_FETCH = 1'b0;
    localparam S_EXEC  = 1'b1;

    reg        state;
    reg [7:0]  pc;
    reg [15:0] ir;
    reg        halt_r;

    // ---- split the instruction register into its fields ----
    wire [3:0]  op        = ir[15:12];
    wire [2:0]  f_a       = ir[11:9];
    wire [2:0]  f_b       = ir[8:6];
    wire [2:0]  f_c       = ir[5:3];
    wire [15:0] imm6_sext = {{10{ir[5]}}, ir[5:0]};
    wire [7:0]  imm8      = ir[7:0];

    // ---- register file ----
    wire [15:0] ra;
    wire [15:0] rb;
    wire [15:0] rc;
    reg         rf_we;
    reg  [15:0] rf_wdata;

    regfile u_rf (
        .clk    (clk),
        .we     (rf_we),
        .waddr  (f_a),
        .wdata  (rf_wdata),
        .raddr_a(f_a),
        .raddr_b(f_b),
        .raddr_c(f_c),
        .rdata_a(ra),
        .rdata_b(rb),
        .rdata_c(rc)
    );

    // ---- ALU: choose the operation and its second input from the instruction ----
    reg  [2:0]  alu_op;
    reg  [15:0] alu_b;
    wire [15:0] alu_y;

    alu u_alu (
        .a (rb),
        .b (alu_b),
        .op(alu_op),
        .y (alu_y)
    );

    always @(*) begin
        alu_op = ALU_ADD;
        alu_b  = imm6_sext;            // default: used by addi, ld and st
        case (op)
            OP_ADD:  begin alu_op = ALU_ADD; alu_b = rc; end
            OP_SUB:  begin alu_op = ALU_SUB; alu_b = rc; end
            OP_AND:  begin alu_op = ALU_AND; alu_b = rc; end
            OP_OR:   begin alu_op = ALU_OR;  alu_b = rc; end
            OP_XOR:  begin alu_op = ALU_XOR; alu_b = rc; end
            OP_SHLI: begin alu_op = ALU_SHL; alu_b = {12'd0, ir[3:0]}; end
            OP_SHRI: begin alu_op = ALU_SHR; alu_b = {12'd0, ir[3:0]}; end
            default: begin alu_op = ALU_ADD; alu_b = imm6_sext; end
        endcase
    end

    // ---- data bus ----
    wire executing = (state == S_EXEC) && !halt_r;

    assign instr_addr = pc;
    assign mem_addr   = alu_y;                       // rB + imm6 for ld and st
    assign mem_wdata  = ra;                          // the register being stored
    assign mem_we     = executing && (op == OP_ST);
    assign mem_re     = executing && (op == OP_LD);
    assign halted     = halt_r;

    // ---- what gets written back to the register file ----
    always @(*) begin
        rf_we    = 1'b0;
        rf_wdata = 16'd0;
        if (executing) begin
            case (op)
                OP_ADD, OP_SUB, OP_AND, OP_OR, OP_XOR, OP_ADDI, OP_SHLI, OP_SHRI: begin
                    rf_we    = 1'b1;
                    rf_wdata = alu_y;
                end
                OP_LD: begin
                    rf_we    = 1'b1;
                    rf_wdata = mem_rdata;
                end
                OP_LDI: begin
                    rf_we    = 1'b1;
                    rf_wdata = {8'd0, imm8};
                end
                OP_LDIH: begin
                    rf_we    = 1'b1;
                    rf_wdata = {imm8, ra[7:0]};
                end
                default: begin
                    rf_we    = 1'b0;
                end
            endcase
        end
    end

    // ---- program counter and the fetch/execute state machine ----
    wire       take_branch   = ((op == OP_BEQ) && (ra == rb)) || ((op == OP_BNE) && (ra != rb));
    wire [7:0] pc_plus1      = pc + 8'd1;
    wire [7:0] branch_target = pc_plus1 + {{2{ir[5]}}, ir[5:0]};

    always @(posedge clk) begin
        if (rst) begin
            state  <= S_FETCH;
            pc     <= 8'd0;
            ir     <= 16'd0;
            halt_r <= 1'b0;
        end else if (!halt_r) begin
            case (state)
                S_FETCH: begin
                    ir    <= instr_data;
                    state <= S_EXEC;
                end
                S_EXEC: begin
                    state <= S_FETCH;
                    if (op == OP_JMPHALT) begin
                        if (ir[11]) halt_r <= 1'b1;
                        else        pc     <= ir[7:0];
                    end else if (take_branch) begin
                        pc <= branch_target;
                    end else begin
                        pc <= pc_plus1;
                    end
                end
                default: state <= S_FETCH;
            endcase
        end
    end

endmodule
