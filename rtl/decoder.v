////////////////////////////////////////////////////////////////////////////////
//
// File: decoder.v
// Module: decoder
//
// Description:
//   RISC-V instruction decoder: combinational logic that extracts operand
//   addresses, sign-extends immediates, and classifies instruction types and
//   operation codes. The decoder is purely combinational (no sequential logic),
//   providing immediate field extraction and routing for every supported
//   RISC-V instruction variant.
//
// Features:
//   - Pure combinational (zero-latency decoding)
//   - Extracts register addresses (rs1, rs2, rd) from standard fields
//   - Computes sign-extended immediates for all RISC-V formats (I, S, B, U)
//   - Classifies instructions by type (R, I, S, B, U, INVALID, EOF)
//   - Enumerates operations (OPK_*) for downstream execution
//   - Identifies floating-point operations separately
//   - Returns conservative INVALID on unrecognized patterns
//
// Supported Instructions (16 total):
//   Integer Arithmetic: SUB, ADDI, SLT, SRL
//   Memory: LW, SW
//   Control Flow: BEQ, BLT, JALR, AUIPC
//   Floating-Point: FSUB, FMUL, FCVT.W.S, FCLASS, FLW, FSW
//   Special: EOF (termination)
//
// IO Interface:
//   Inputs:
//     instr[31:0]       : 32-bit RISC-V instruction word
//   Outputs:
//     rs1[4:0]          : Source register 1 address
//     rs2[4:0]          : Source register 2 address (0 for I-type with no rs2)
//     rd[4:0]           : Destination register address
//     imm[31:0]         : Sign-extended immediate (format-specific)
//     op_kind[4:0]      : Internal operation code (0-31)
//     instr_type[2:0]   : Instruction classification (R/I/S/B/U/INVALID/EOF)
//     is_fpu_op         : High if FPU operation
//
// Author: [Original Designer]
// Date: 2024
// Version: 1.0
//
////////////////////////////////////////////////////////////////////////////////

`ifndef DECODER_V
`define DECODER_V
`include "define.v"

module decoder (
    // ========== Input: 32-bit RISC-V Instruction ==========
    input  [31:0] instr,

    // ========== Outputs: Decoded Fields ==========
    output reg [4:0]  rs1,          // Source register 1 address
    output reg [4:0]  rs2,          // Source register 2 address (0 if N/A)
    output reg [4:0]  rd,           // Destination register address
    output reg [31:0] imm,          // Sign-extended immediate (format-specific)
    output reg [4:0]  op_kind,      // Internal operation code (OPK_*)
    output reg [2:0]  instr_type,   // Instruction type (R/I/S/B/U/INVALID/EOF)
    output reg        is_fpu_op     // High if FPU operation
);

    //==========================================================================
    // INTERNAL OPERATION CODE ENUMERATION
    //==========================================================================
    // Maps each supported instruction to a unique 5-bit code for execution logic
    localparam OPK_SUB    = 0;      // Subtraction (R-type)
    localparam OPK_ADDI   = 1;      // Add Immediate
    localparam OPK_LW     = 2;      // Load Word
    localparam OPK_SW     = 3;      // Store Word
    localparam OPK_BEQ    = 4;      // Branch Equal
    localparam OPK_BLT    = 5;      // Branch Less Than (signed)
    localparam OPK_JALR   = 6;      // Jump and Link Register
    localparam OPK_AUIPC  = 7;      // Add Upper Immediate to PC
    localparam OPK_SLT    = 8;      // Set Less Than (signed)
    localparam OPK_SRL    = 9;      // Shift Right Logical
    localparam OPK_FSUB   = 10;     // Floating-point Subtract
    localparam OPK_FMUL   = 11;     // Floating-point Multiply
    localparam OPK_FCVT   = 12;     // Float to Word Conversion
    localparam OPK_FLW    = 13;     // Floating-point Load Word
    localparam OPK_FSW    = 14;     // Floating-point Store Word
    localparam OPK_FCLASS = 15;     // Floating-point Class
    localparam OPK_EOF    = 16;     // End-of-file termination
    localparam OPK_INV    = 31;     // Invalid instruction (safe default)

    //==========================================================================
    // IMMEDIATE COMPUTATION WIRES (Sign-Extended for Each Format)
    //==========================================================================
    // RISC-V immediates are scattered across the 32-bit word with different
    // layouts per format. These wires compute the full 32-bit sign-extended
    // values for each format so the decoder output is ready for execution.

    // I-Type Immediate: bits [31:20] sign-extended to 32 bits
    // Format: [imm[11:0], rs1, func3, rd, opcode]
    // Used by: ADDI, LW, JALR, FLW
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};

    // S-Type Immediate: bits [31:25] and [11:7] concatenated, sign-extended
    // Format: [imm[11:5], rs2, rs1, func3, imm[4:0], opcode]
    // Used by: SW, FSW
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};

    // B-Type Immediate: Scattered bits with specific arrangement, sign-extended
    // Format: [imm[12], imm[10:5], rs2, rs1, func3, imm[4:1], imm[11], opcode]
    // The LSB is always 0 (implicit alignment for branch targets)
    // Used by: BEQ, BLT
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};

    // U-Type Immediate: bits [31:12] in upper 20 bits, lower 12 bits zeros
    // Format: [imm[31:12], rd, opcode]
    // Used by: AUIPC
    wire [31:0] imm_u = {instr[31:12], 12'b0};

    //==========================================================================
    // COMBINATIONAL DECODER LOGIC
    //==========================================================================
    // Extracts fields from instruction word and performs full decode based
    // on opcode (bits [6:0]), funct3 (bits [14:12]), and funct7 (bits [31:25])
    always @(*) begin
        // Default values before case decode
        rs1        = instr[19:15];  // Standard rs1 position (same for all formats)
        rs2        = instr[24:20];  // Standard rs2 position
        rd         = instr[11:7];   // Standard rd position (same for all formats)
        imm        = 32'b0;          // No immediate by default
        op_kind    = OPK_INV;        // Mark as invalid until determined
        instr_type = `INVALID_TYPE;
        is_fpu_op  = 1'b0;

        //=====================================================================
        // INSTRUCTION DECODER (by opcode field [6:0])
        //=====================================================================
        case (instr[6:0])

            //===================================================================
            // Opcode 7'b0110011: Integer Arithmetic (R-Type)
            // Further decoded by funct3 and funct7
            //===================================================================
            `OP_SUB: begin
                if (instr[14:12] == `FUNCT3_SUB && instr[31:25] == `FUNCT7_SUB) begin
                    // SUB: Subtraction
                    op_kind    = OPK_SUB;
                    instr_type = `R_TYPE;
                    imm        = 32'b0;
                end else if (instr[14:12] == `FUNCT3_SLT && instr[31:25] == `FUNCT7_SLT) begin
                    // SLT: Set Less Than (signed comparison)
                    op_kind    = OPK_SLT;
                    instr_type = `R_TYPE;
                end else if (instr[14:12] == `FUNCT3_SRL && instr[31:25] == `FUNCT7_SRL) begin
                    // SRL: Shift Right Logical
                    op_kind    = OPK_SRL;
                    instr_type = `R_TYPE;
                end
            end

            //===================================================================
            // Opcode 7'b0010011: Add Immediate (I-Type)
            //===================================================================
            `OP_ADDI: begin
                if (instr[14:12] == `FUNCT3_ADDI) begin
                    op_kind    = OPK_ADDI;
                    instr_type = `I_TYPE;
                    imm        = imm_i;          // Sign-extended I-type immediate
                    rs2        = 5'd0;           // No rs2 in I-type
                end
            end

            //===================================================================
            // Opcode 7'b0000011: Load Word (I-Type)
            //===================================================================
            `OP_LW: begin
                if (instr[14:12] == `FUNCT3_LW) begin
                    op_kind    = OPK_LW;
                    instr_type = `I_TYPE;
                    imm        = imm_i;          // Offset immediate
                    rs2        = 5'd0;
                end
            end

            //===================================================================
            // Opcode 7'b0100011: Store Word (S-Type)
            //===================================================================
            `OP_SW: begin
                if (instr[14:12] == `FUNCT3_SW) begin
                    op_kind    = OPK_SW;
                    instr_type = `S_TYPE;
                    imm        = imm_s;          // Sign-extended S-type immediate
                end
            end

            //===================================================================
            // Opcode 7'b1100011: Branches (B-Type)
            // funct3 selects BEQ or BLT
            //===================================================================
            `OP_BEQ: begin
                if (instr[14:12] == `FUNCT3_BEQ) begin
                    // BEQ: Branch if Equal
                    op_kind    = OPK_BEQ;
                    instr_type = `B_TYPE;
                    imm        = imm_b;          // Sign-extended B-type immediate
                end else if (instr[14:12] == `FUNCT3_BLT) begin
                    // BLT: Branch if Less Than (signed)
                    op_kind    = OPK_BLT;
                    instr_type = `B_TYPE;
                    imm        = imm_b;          // Sign-extended B-type immediate
                end
            end

            //===================================================================
            // Opcode 7'b1100111: Jump and Link Register (I-Type)
            //===================================================================
            `OP_JALR: begin
                if (instr[14:12] == `FUNCT3_JALR) begin
                    op_kind    = OPK_JALR;
                    instr_type = `I_TYPE;
                    imm        = imm_i;          // Address offset immediate
                    rs2        = 5'd0;
                end
            end

            //===================================================================
            // Opcode 7'b0010111: Add Upper Immediate to PC (U-Type)
            //===================================================================
            `OP_AUIPC: begin
                op_kind    = OPK_AUIPC;
                instr_type = `U_TYPE;
                imm        = imm_u;              // U-type immediate [31:12]
            end

            //===================================================================
            // Opcode 7'b1010011: Floating-Point Operations (R-Type)
            // Further decoded by funct7 and funct3
            // All FPU ops under this opcode are R-type and marked as FPU operations
            //===================================================================
            `OP_FSUB: begin
                is_fpu_op  = 1'b1;
                instr_type = `R_TYPE;
                if (instr[31:25] == `FUNCT7_FSUB && instr[14:12] == `FUNCT3_FSUB)
                    // FSUB: Floating-point Subtract
                    op_kind = OPK_FSUB;
                else if (instr[31:25] == `FUNCT7_FMUL && instr[14:12] == `FUNCT3_FMUL)
                    // FMUL: Floating-point Multiply
                    op_kind = OPK_FMUL;
                else if (instr[31:25] == `FUNCT7_FCVTWS && instr[14:12] == `FUNCT3_FCVTWS)
                    // FCVT.W.S: Convert Float to Signed Word (with rounding)
                    op_kind = OPK_FCVT;
                else if (instr[31:25] == `FUNCT7_FCLASS && instr[14:12] == `FUNCT3_FCLASS)
                    // FCLASS: Classify Floating-Point Value
                    op_kind = OPK_FCLASS;
            end

            //===================================================================
            // Opcode 7'b0000111: Floating-Point Load Word (I-Type)
            //===================================================================
            `OP_FLW: begin
                if (instr[14:12] == `FUNCT3_FLW) begin
                    op_kind    = OPK_FLW;
                    instr_type = `I_TYPE;
                    imm        = imm_i;          // Offset immediate
                    is_fpu_op  = 1'b1;
                    rs2        = 5'd0;
                end
            end

            //===================================================================
            // Opcode 7'b0100111: Floating-Point Store Word (S-Type)
            //===================================================================
            `OP_FSW: begin
                if (instr[14:12] == `FUNCT3_FSW) begin
                    op_kind    = OPK_FSW;
                    instr_type = `S_TYPE;
                    imm        = imm_s;          // Sign-extended S-type immediate
                    is_fpu_op  = 1'b1;
                end
            end

            //===================================================================
            // Opcode 7'b1110011: End-of-File / Termination
            //===================================================================
            `OP_EOF: begin
                op_kind    = OPK_EOF;
                instr_type = `EOF_TYPE;
            end

            //===================================================================
            // Default: Unrecognized Instruction
            //===================================================================
            default: begin
                op_kind    = OPK_INV;
                instr_type = `INVALID_TYPE;
            end
        endcase
    end

endmodule

`endif

////////////////////////////////////////////////////////////////////////////////
