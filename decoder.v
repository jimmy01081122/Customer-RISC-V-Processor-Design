`ifndef DECODER_V
`define DECODER_V
`include "define.v"

// Simple combinational decoder.
// It extracts fields, sign-extends immediates, and classifies the instruction.
module decoder (
    input  [31:0] instr,
    output reg [4:0] rs1,
    output reg [4:0] rs2,
    output reg [4:0] rd,
    output reg [31:0] imm,
    output reg [4:0] op_kind,      // internal opcode enumeration (see localparams below)
    output reg [2:0] instr_type,   // one of the *_TYPE macros
    output reg       is_fpu_op
);
    // Internal encoding for each supported instruction.
    localparam OPK_SUB    = 0;
    localparam OPK_ADDI   = 1;
    localparam OPK_LW     = 2;
    localparam OPK_SW     = 3;
    localparam OPK_BEQ    = 4;
    localparam OPK_BLT    = 5;
    localparam OPK_JALR   = 6;
    localparam OPK_AUIPC  = 7;
    localparam OPK_SLT    = 8;
    localparam OPK_SRL    = 9;
    localparam OPK_FSUB   = 10;
    localparam OPK_FMUL   = 11;
    localparam OPK_FCVT   = 12;
    localparam OPK_FLW    = 13;
    localparam OPK_FSW    = 14;
    localparam OPK_FCLASS = 15;
    localparam OPK_EOF    = 16;
    localparam OPK_INV    = 31; // safe default

    // Immediate builders
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};

    always @(*) begin
        rs1        = instr[19:15];
        rs2        = instr[24:20];
        rd         = instr[11:7];
        imm        = 32'b0;
        op_kind    = OPK_INV;
        instr_type = `INVALID_TYPE;
        is_fpu_op  = 1'b0;

        case (instr[6:0])
            `OP_SUB: begin
                if (instr[14:12] == `FUNCT3_SUB && instr[31:25] == `FUNCT7_SUB) begin
                    op_kind    = OPK_SUB;
                    instr_type = `R_TYPE;
                    imm        = 32'b0;
                end else if (instr[14:12] == `FUNCT3_SLT && instr[31:25] == `FUNCT7_SLT) begin
                    op_kind    = OPK_SLT;
                    instr_type = `R_TYPE;
                end else if (instr[14:12] == `FUNCT3_SRL && instr[31:25] == `FUNCT7_SRL) begin
                    op_kind    = OPK_SRL;
                    instr_type = `R_TYPE;
                end
            end
            `OP_ADDI: begin
                if (instr[14:12] == `FUNCT3_ADDI) begin
                    op_kind    = OPK_ADDI;
                    instr_type = `I_TYPE;
                    imm        = imm_i;
                    rs2        = 5'd0; // no rs2 in I-type
                end
            end
            `OP_LW: begin
                if (instr[14:12] == `FUNCT3_LW) begin
                    op_kind    = OPK_LW;
                    instr_type = `I_TYPE;
                    imm        = imm_i;
                    rs2        = 5'd0;
                end
            end
            `OP_SW: begin
                if (instr[14:12] == `FUNCT3_SW) begin
                    op_kind    = OPK_SW;
                    instr_type = `S_TYPE;
                    imm        = imm_s;
                end
            end
            `OP_BEQ: begin
                if (instr[14:12] == `FUNCT3_BEQ) begin
                    op_kind    = OPK_BEQ;
                    instr_type = `B_TYPE;
                    imm        = imm_b;
                end else if (instr[14:12] == `FUNCT3_BLT) begin
                    op_kind    = OPK_BLT;
                    instr_type = `B_TYPE;
                    imm        = imm_b;
                end
            end
            `OP_JALR: begin
                if (instr[14:12] == `FUNCT3_JALR) begin
                    op_kind    = OPK_JALR;
                    instr_type = `I_TYPE;
                    imm        = imm_i;
                    rs2        = 5'd0;
                end
            end
            `OP_AUIPC: begin
                op_kind    = OPK_AUIPC;
                instr_type = `U_TYPE;
                imm        = imm_u;
            end
            `OP_FSUB: begin
                is_fpu_op  = 1'b1;
                instr_type = `R_TYPE;
                if (instr[31:25] == `FUNCT7_FSUB && instr[14:12] == `FUNCT3_FSUB)
                    op_kind = OPK_FSUB;
                else if (instr[31:25] == `FUNCT7_FMUL && instr[14:12] == `FUNCT3_FMUL)
                    op_kind = OPK_FMUL;
                else if (instr[31:25] == `FUNCT7_FCVTWS && instr[14:12] == `FUNCT3_FCVTWS)
                    op_kind = OPK_FCVT;
                else if (instr[31:25] == `FUNCT7_FCLASS && instr[14:12] == `FUNCT3_FCLASS)
                    op_kind = OPK_FCLASS;
            end
            `OP_FLW: begin
                if (instr[14:12] == `FUNCT3_FLW) begin
                    op_kind    = OPK_FLW;
                    instr_type = `I_TYPE;
                    imm        = imm_i;
                    is_fpu_op  = 1'b1;
                    rs2        = 5'd0;
                end
            end
            `OP_FSW: begin
                if (instr[14:12] == `FUNCT3_FSW) begin
                    op_kind    = OPK_FSW;
                    instr_type = `S_TYPE;
                    imm        = imm_s;
                    is_fpu_op  = 1'b1;
                end
            end
            `OP_EOF: begin
                op_kind    = OPK_EOF;
                instr_type = `EOF_TYPE;
            end
            default: begin
                op_kind    = OPK_INV;
                instr_type = `INVALID_TYPE;
            end
        endcase
    end
endmodule
`endif
