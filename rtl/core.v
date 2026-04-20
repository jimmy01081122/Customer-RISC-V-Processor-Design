////////////////////////////////////////////////////////////////////////////////
//
// File: core.v
// Module: core
//
// Description:
//   Top-level RISC-V processor core implementing a non-pipelined 5-stage FSM.
//   Each cycle, the processor transitions through one pipeline stage, enabling
//   simple sequential instruction execution. The design prioritizes clarity for
//   learning, with extensive comments explaining the execution flow.
//
// Architecture: 5-Stage FSM (Non-Pipelined)
//   1. FETCH  : Fetch instruction from memory at current PC, capture on next clock
//   2. DECODE : Decode instruction fields, read register files, validate format
//   3. EXEC   : Execute ALU/FPU operations, compute branch targets, calculate addresses
//   4. MEM    : Access data memory for loads/stores (with address validation)
//   5. WB     : Write results back to register files, update PC, emit status pulse
//   6. HALT   : Hold state after EOF or fatal exceptions
//
// Memory Map:
//   Instruction Memory: 0x0000_0000 - 0x0000_0FFF (4 KB, addresses 0-4095)
//   Data Memory:        0x0000_1000 - 0x0000_1FFF (4 KB, addresses 4096-8191)
//   Unmapped accesses trigger INVALID status and halt processor
//
// Supported Instructions (16 total):
//   Integer: ADD/SUB, ADDI, SLT, SRL, LW, SW, BEQ, BLT, JALR, AUIPC
//   FP: FSUB, FMUL, FCVT.W.S, FCLASS, FLW, FSW
//   Control: EOF (termination marker)
//
// Features:
//   - 32×32-bit integer register file (x0-x31)
//   - 32×32-bit IEEE 754 FP register file (f0-f31)
//   - 32-bit integer ALU with overflow detection
//   - IEEE 754 single-precision FPU with four operations
//   - Synchronous write ports, combinational register reads
//   - Address-based memory access validation
//   - Status pulse signaling (one cycle high when instruction completes)
//
// IO Interface:
//   Inputs:
//     i_clk            : System clock (positive edge triggers pipeline advance)
//     i_rst_n          : Active-low asynchronous reset (initializes state/registers)
//     i_rdata[31:0]    : Read data from unified memory (instruction/data)
//   Outputs:
//     o_addr[31:0]     : Memory address for fetch/load/store
//     o_wdata[31:0]    : Write data for stores
//     o_we             : Write enable (high for store operations)
//     o_status[2:0]    : Instruction type (R/I/S/B/U/INVALID/EOF) on completion
//     o_status_valid   : Pulse (1 cycle) when instruction completes
//     c_state[4:0]     : Current pipeline stage (for debugging)
//     Testing ports    : rs1/rs2/rd addresses and values
//
// Author: [Original Designer]
// Date: 2024
// Version: 1.0
//
////////////////////////////////////////////////////////////////////////////////

`include "define.v"

module core #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
) (
    input i_clk,
    input i_rst_n,

    // Testbench IOs
    output reg [2:0] o_status,
    output reg       o_status_valid,

    // Memory IOs
    output reg [ADDR_WIDTH-1:0] o_addr,
    output reg [DATA_WIDTH-1:0] o_wdata,
    output reg                  o_we,
    input      [DATA_WIDTH-1:0] i_rdata,

    output [4:0]                c_state,
    
    output [DATA_WIDTH-1:0]     o_alu_result,

    // testing port
    output [DATA_WIDTH-1:0] rs1_data,
    output [4:0] rs1_address,
    output [DATA_WIDTH-1:0] rs2_data,
    output [4:0] rs2_address,
    output [4:0] rd_address,
    output [ADDR_WIDTH-1:0] rd_data_f,
    output [ADDR_WIDTH-1:0] rd_data_i
);

    //==========================================================================
    // STATE MACHINE DEFINITION & PARAMETERS
    //==========================================================================
    // Six states: five execution stages + one halt state
    // Transition in response to i_clk rising edge or fatal events (INVALID/EOF)

    localparam ST_FETCH  = 3'd0;
    localparam ST_DECODE = 3'd1;
    localparam ST_EXEC   = 3'd2;
    localparam ST_MEM    = 3'd3;
    localparam ST_WB     = 3'd4;
    localparam ST_HALT   = 3'd5;

    reg [2:0] state, next_state;
    assign c_state = state;

    // ------------------------
    // Per-instruction latches
    // ------------------------
    reg [ADDR_WIDTH-1:0] pc;           // current program counter
    reg [DATA_WIDTH-1:0] instr_reg;    // fetched instruction

    // Decoded fields
    reg [4:0]  dec_op_kind;
    reg [2:0]  dec_type;
    reg [31:0] dec_imm;
    reg [4:0]  dec_rs1, dec_rs2, dec_rd;
    reg        dec_is_fpu;
    reg        dec_invalid;

    // Operand snapshots (kept stable across later stages)
    reg [31:0] rs1_int_r, rs2_int_r;
    reg [31:0] rs1_fp_r,  rs2_fp_r;

    // Execute stage results
    reg [31:0] exec_result;
    reg        exec_invalid;
    reg        branch_taken;
    reg [ADDR_WIDTH-1:0] branch_target;
    reg [31:0] mem_addr_eff;
    reg [31:0] store_data_r;
    reg        mem_do_load;
    reg        mem_do_store;
    reg        is_load_fp;
    reg        is_store_fp;

    // Load data captured in WB for LW/FLW
    reg [31:0] load_data_r;
    reg [ADDR_WIDTH-1:0] pc_next_val;

    // ------------------------
    // Submodules
    // ------------------------
    wire [4:0] dec_rs1_w, dec_rs2_w, dec_rd_w;
    wire [31:0] dec_imm_w;
    wire [4:0]  dec_op_w;
    wire [2:0]  dec_type_w;
    wire        dec_is_fpu_w;
    decoder u_decoder(
        .instr(instr_reg),
        .rs1(dec_rs1_w),
        .rs2(dec_rs2_w),
        .rd(dec_rd_w),
        .imm(dec_imm_w),
        .op_kind(dec_op_w),
        .instr_type(dec_type_w),
        .is_fpu_op(dec_is_fpu_w)
    );

    // Register files
    wire [31:0] rs1_int_w, rs2_int_w;
    wire [31:0] rs1_fp_w,  rs2_fp_w;
    reg         rf_int_we;
    reg  [4:0]  rf_int_waddr;
    reg  [31:0] rf_int_wdata;
    reg         rf_fp_we;
    reg  [4:0]  rf_fp_waddr;
    reg  [31:0] rf_fp_wdata;

    regfile_int u_rf_int(
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_rs1_addr(dec_rs1),
        .i_rs2_addr(dec_rs2),
        .o_rs1_data(rs1_int_w),
        .o_rs2_data(rs2_int_w),
        .i_we(rf_int_we),
        .i_rd_addr(rf_int_waddr),
        .i_rd_data(rf_int_wdata)
    );

    regfile_fp u_rf_fp(
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_fs1_addr(dec_rs1),
        .i_fs2_addr(dec_rs2),
        .o_fs1_data(rs1_fp_w),
        .o_fs2_data(rs2_fp_w),
        .i_we(rf_fp_we),
        .i_fd_addr(rf_fp_waddr),
        .i_fd_data(rf_fp_wdata)
    );

    // Integer ALU
    reg  [2:0]  alu_sel;
    reg  [31:0] alu_in_a, alu_in_b;
    wire [31:0] alu_out;
    wire        alu_overflow;
    alu_int u_alu(
        .i_op(alu_sel),
        .i_a(alu_in_a),
        .i_b(alu_in_b),
        .o_result(alu_out),
        .o_overflow(alu_overflow)
    );

    // FPU helper
    reg [1:0]  fpu_sel;
    wire [31:0] fpu_out;
    wire        fpu_inv, fpu_ovf, fpu_udf;
    fpu_unit u_fpu(
        .i_op(fpu_sel),
        .i_a(rs1_fp_r),
        .i_b(rs2_fp_r),
        .o_result(fpu_out),
        .o_invalid(fpu_inv),
        .o_overflow(fpu_ovf),
        .o_underflow(fpu_udf)
    );

    // -------------
    // Helper flags
    // -------------
    // Address windows for invalid detection.
    function is_instr_addr;
        input [ADDR_WIDTH-1:0] a;
    begin
        is_instr_addr = (a <= 32'd4095);
    end
    endfunction
    function is_data_addr;
        input [ADDR_WIDTH-1:0] a;
    begin
        is_data_addr = (a >= 32'd4096) && (a <= 32'd8191);
    end
    endfunction

    // Public debug ports
    assign rs1_data    = dec_is_fpu ? rs1_fp_r : rs1_int_r;
    assign rs2_data    = dec_is_fpu ? rs2_fp_r : rs2_int_r;
    assign rs1_address = dec_rs1;
    assign rs2_address = dec_rs2;
    assign rd_address  = dec_rd;
    assign rd_data_f   = rf_fp_wdata;
    assign rd_data_i   = rf_int_wdata;
    assign o_alu_result = exec_result;

    // ----------------------------
    // ALU/FPU input selection (pure combinational)
    // ----------------------------
    always @(*) begin
        alu_in_a = rs1_int_r;
        alu_in_b = rs2_int_r;
        alu_sel  = 3'd0;
        fpu_sel  = 2'd0;
        case (dec_op_kind)
            5'd0: alu_sel = 3'd1;          // SUB
            5'd1: begin                    // ADDI
                alu_sel = 3'd0;
                alu_in_b = dec_imm;
            end
            5'd8: alu_sel = 3'd2;          // SLT
            5'd9: alu_sel = 3'd3;          // SRL
            5'd10: fpu_sel = 2'd0;         // FSUB
            5'd11: fpu_sel = 2'd1;         // FMUL
            5'd12: fpu_sel = 2'd2;         // FCVT.W.S
            5'd15: fpu_sel = 2'd3;         // FCLASS
            default: begin end
        endcase
    end

    // ----------------------------
    // Sequential part of the FSM
    // ----------------------------
    integer i;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state          <= ST_FETCH;
            pc             <= {ADDR_WIDTH{1'b0}};
            instr_reg      <= {DATA_WIDTH{1'b0}};
            dec_op_kind    <= 5'd0;
            dec_type       <= `INVALID_TYPE;
            dec_imm        <= 32'b0;
            dec_rs1        <= 5'd0;
            dec_rs2        <= 5'd0;
            dec_rd         <= 5'd0;
            dec_is_fpu     <= 1'b0;
            dec_invalid    <= 1'b0;
            rs1_int_r      <= 32'b0;
            rs2_int_r      <= 32'b0;
            rs1_fp_r       <= 32'b0;
            rs2_fp_r       <= 32'b0;
            exec_result    <= 32'b0;
            branch_taken   <= 1'b0;
            branch_target  <= {ADDR_WIDTH{1'b0}};
            mem_addr_eff   <= 32'b0;
            store_data_r   <= 32'b0;
            mem_do_load    <= 1'b0;
            mem_do_store   <= 1'b0;
            is_load_fp     <= 1'b0;
            is_store_fp    <= 1'b0;
            load_data_r    <= 32'b0;
            o_status       <= `INVALID_TYPE;
            o_status_valid <= 1'b0;
            o_addr         <= {ADDR_WIDTH{1'b0}};
            o_wdata        <= {DATA_WIDTH{1'b0}};
            o_we           <= 1'b0;
            rf_int_we      <= 1'b0;
            rf_fp_we       <= 1'b0;
        end else begin
            state          <= next_state;
            o_status_valid <= 1'b0; // default low, pulsed only in WB
            rf_int_we      <= 1'b0;
            rf_fp_we       <= 1'b0;
            o_we           <= 1'b0;

            case (state)
                ST_FETCH: begin
                    // Issue instruction fetch and capture instruction on next rising edge.
                    o_addr    <= pc;
                    o_we      <= 1'b0;
                    instr_reg <= i_rdata;
                end

                ST_DECODE: begin
                    // Snapshot decoder outputs for stability across later stages.
                    dec_op_kind <= dec_op_w;
                    dec_type    <= dec_type_w;
                    dec_imm     <= dec_imm_w;
                    dec_rs1     <= dec_rs1_w;
                    dec_rs2     <= dec_rs2_w;
                    dec_rd      <= dec_rd_w;
                    dec_is_fpu  <= dec_is_fpu_w;
                    dec_invalid <= (dec_op_w == 5'd31); // unknown decode

                    // Grab operand values.
                    rs1_int_r <= rs1_int_w;
                    rs2_int_r <= rs2_int_w;
                    rs1_fp_r  <= rs1_fp_w;
                    rs2_fp_r  <= rs2_fp_w;
                    exec_invalid <= 1'b0;
                end

                ST_EXEC: begin
                    // Stage 3: perform math/branch/address work.
                    // No external side effects happen here; we only prepare data for MEM/WB.
                    // Default flags
                    exec_invalid <= 1'b0;
                    branch_taken <= 1'b0;
                    mem_do_load  <= 1'b0;
                    mem_do_store <= 1'b0;
                    is_load_fp   <= 1'b0;
                    is_store_fp  <= 1'b0;

                    exec_result <= 32'b0;
                    mem_addr_eff <= 32'b0;
                    store_data_r <= 32'b0;
                    branch_target <= pc + dec_imm;

                    case (dec_op_kind)
                        5'd0: begin // SUB
                            exec_result  <= alu_out;
                            exec_invalid <= alu_overflow;
                        end
                        5'd1: begin // ADDI
                            exec_result  <= alu_out;
                            exec_invalid <= alu_overflow;
                        end
                        5'd2: begin // LW
                            mem_do_load  <= 1'b1;
                            mem_addr_eff <= rs1_int_r + dec_imm;
                            is_load_fp   <= 1'b0;
                        end
                        5'd3: begin // SW
                            mem_do_store <= 1'b1;
                            mem_addr_eff <= rs1_int_r + dec_imm;
                            store_data_r <= rs2_int_r;
                            is_store_fp  <= 1'b0;
                        end
                        5'd4: begin // BEQ
                            branch_taken <= (rs1_int_r == rs2_int_r);
                        end
                        5'd5: begin // BLT
                            branch_taken <= ($signed(rs1_int_r) < $signed(rs2_int_r));
                        end
                        5'd6: begin // JALR
                            exec_result  <= pc + 32'd4; // rd gets pc+4
                            branch_target <= (rs1_int_r + dec_imm) & (~32'd1);
                            branch_taken <= 1'b1;
                        end
                        5'd7: begin // AUIPC
                            exec_result <= pc + dec_imm;
                        end
                        5'd8: begin // SLT
                            exec_result <= alu_out;
                        end
                        5'd9: begin // SRL
                            exec_result <= alu_out;
                        end
                        5'd10: begin // FSUB
                            exec_result  <= fpu_out;
                            exec_invalid <= fpu_inv;
                        end
                        5'd11: begin // FMUL
                            exec_result  <= fpu_out;
                            exec_invalid <= fpu_inv;
                        end
                        5'd12: begin // FCVT.W.S
                            exec_result  <= fpu_out;
                            exec_invalid <= fpu_inv;
                        end
                        5'd13: begin // FLW
                            mem_do_load  <= 1'b1;
                            mem_addr_eff <= rs1_int_r + dec_imm;
                            is_load_fp   <= 1'b1;
                        end
                        5'd14: begin // FSW
                            mem_do_store <= 1'b1;
                            mem_addr_eff <= rs1_int_r + dec_imm;
                            store_data_r <= rs2_fp_r;
                            is_store_fp  <= 1'b1;
                        end
                        5'd15: begin // FCLASS
                            exec_result  <= fpu_out;
                            exec_invalid <= fpu_inv;
                        end
                        5'd16: begin // EOF
                            exec_result  <= 32'b0;
                        end
                        default: begin
                            exec_invalid <= 1'b1;
                        end
                    endcase
                end

                ST_MEM: begin
                    // Stage 4: actually talk to data memory when needed.
                    // Guard against bad addresses for load/store.
                    if (mem_do_load || mem_do_store) begin
                        if (!is_data_addr(mem_addr_eff)) begin
                            exec_invalid <= 1'b1;
                        end else begin
                            o_addr <= mem_addr_eff;
                            if (mem_do_store) begin
                                o_we   <= 1'b1;
                                o_wdata<= store_data_r;
                            end else begin
                                o_we   <= 1'b0;
                            end
                        end
                    end
                end

                ST_WB: begin
                    // Stage 5: capture data, write back, and emit the status pulse.
                    // Capture load read data (available one cycle after MEM read).
                    if (mem_do_load) load_data_r <= i_rdata;

                    // Stop immediately on invalid
                    if (dec_invalid || exec_invalid) begin
                        o_status       <= `INVALID_TYPE;
                        o_status_valid <= 1'b1;
                        state          <= ST_HALT;
                    end else if (dec_type == `EOF_TYPE || dec_op_kind == 5'd16) begin
                        o_status       <= `EOF_TYPE;
                        o_status_valid <= 1'b1;
                        state          <= ST_HALT;
                    end else begin
                        // Writeback for integer/FP as required.
                        case (dec_op_kind)
                            5'd0,5'd1,5'd7,5'd8,5'd9: begin // SUB, ADDI, AUIPC, SLT, SRL
                                rf_int_we     <= 1'b1;
                                rf_int_waddr  <= dec_rd;
                                rf_int_wdata  <= exec_result;
                            end
                            5'd2: begin // LW
                                rf_int_we     <= 1'b1;
                                rf_int_waddr  <= dec_rd;
                                rf_int_wdata  <= load_data_r;
                            end
                            5'd3: begin end // SW no write
                            5'd4,5'd5: begin end // branches no write
                            5'd6: begin // JALR
                                rf_int_we     <= 1'b1;
                                rf_int_waddr  <= dec_rd;
                                rf_int_wdata  <= exec_result;
                            end
                            5'd10,5'd11: begin // FSUB/FMUL -> FP dest
                                rf_fp_we     <= 1'b1;
                                rf_fp_waddr  <= dec_rd;
                                rf_fp_wdata  <= exec_result;
                            end
                            5'd12: begin // FCVT.W.S -> INT dest
                                rf_int_we     <= 1'b1;
                                rf_int_waddr  <= dec_rd;
                                rf_int_wdata  <= exec_result;
                            end
                            5'd13: begin // FLW -> FP dest
                                rf_fp_we     <= 1'b1;
                                rf_fp_waddr  <= dec_rd;
                                rf_fp_wdata  <= load_data_r;
                            end
                            5'd14: begin end // FSW no write
                            5'd15: begin // FCLASS -> INT dest
                                rf_int_we     <= 1'b1;
                                rf_int_waddr  <= dec_rd;
                                rf_int_wdata  <= exec_result;
                            end
                        endcase

                        // Generate status pulse for this instruction.
                        o_status       <= dec_type;
                        o_status_valid <= 1'b1;

                        // Next PC update with branch rules.
                        pc_next_val = pc + 32'd4;
                        if (dec_op_kind == 5'd4 || dec_op_kind == 5'd5) begin
                            pc_next_val = branch_taken ? (pc + dec_imm) : (pc + 32'd4);
                        end else if (dec_op_kind == 5'd6) begin
                            pc_next_val = branch_target;
                        end
                        pc <= pc_next_val;

                        // Clear memory request trackers for the next instruction window.
                        mem_do_load  <= 1'b0;
                        mem_do_store <= 1'b0;
                    end
                end

                ST_HALT: begin
                    // Hold everything steady after EOF or INVALID.
                    o_we <= 1'b0;
                end
            endcase

            // PC validity check before next fetch. If invalid, raise invalid and halt.
            if (state == ST_FETCH && !is_instr_addr(pc)) begin
                o_status       <= `INVALID_TYPE;
                o_status_valid <= 1'b1;
                state          <= ST_HALT;
            end
        end
    end

    // ----------------------------
    // Next-state combinational logic
    // ----------------------------
    always @(*) begin
        next_state = state;
        case (state)
            ST_FETCH:  next_state = ST_DECODE;
            ST_DECODE: next_state = ST_EXEC;
            ST_EXEC:   next_state = ST_MEM;
            ST_MEM:    next_state = ST_WB;
            ST_WB:     next_state = (dec_invalid || exec_invalid || dec_type == `EOF_TYPE || dec_op_kind == 5'd16) ? ST_HALT : ST_FETCH;
            ST_HALT:   next_state = ST_HALT;
            default:   next_state = ST_FETCH;
        endcase
    end

endmodule
