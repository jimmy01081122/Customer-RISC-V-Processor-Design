`timescale 1ns/1ps
`include "define.v"

// Small decoder smoke test.
module tb_decoder;
    reg  [31:0] instr;
    wire [4:0] rs1, rs2, rd;
    wire [31:0] imm;
    wire [4:0] op_kind;
    wire [2:0] instr_type;
    wire       is_fpu;

    reg [4:0] rand_rs1, rand_rs2, rand_rd;
    reg [31:0] rand_imm;
    reg [12:0] bimm;
    reg [31:0] exp_imm_calc;
    decoder dut(
        .instr(instr),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .imm(imm),
        .op_kind(op_kind),
        .instr_type(instr_type),
        .is_fpu_op(is_fpu)
    );

    integer errors;
    task check;
        input [8*16-1:0] name;
        input [4:0] exp_op;
        input [4:0] exp_rs1;
        input [4:0] exp_rs2;
        input [4:0] exp_rd;
        input [31:0] exp_imm;
        input [2:0] exp_type;
        input exp_fpu;
    begin
        if (op_kind !== exp_op || rs1 !== exp_rs1 || rs2 !== exp_rs2 ||
            rd !== exp_rd || imm !== exp_imm || instr_type !== exp_type || is_fpu !== exp_fpu) begin
            $display("FAIL %s: got op=%0d rs1=%0d rs2=%0d rd=%0d imm=%0d type=%0d fpu=%b",
                name, op_kind, rs1, rs2, rd, $signed(imm), instr_type, is_fpu);
            $display("  exp op=%0d rs1=%0d rs2=%0d rd=%0d imm=%0d type=%0d fpu=%b",
                exp_op, exp_rs1, exp_rs2, exp_rd, $signed(exp_imm), exp_type, exp_fpu);
            errors = errors + 1;
        end else begin
            $display("PASS %s", name);
        end
    end
    endtask

    function [31:0] make_b;
        input [6:0] opcode;
        input [2:0] funct3;
        input [4:0] rs1_f;
        input [4:0] rs2_f;
        input signed [12:0] imm13; // bits[12:0], imm[0]=0
        reg [31:0] out;
    begin
        out = 32'b0;
        out[6:0]   = opcode;
        out[11:7]  = {imm13[11], imm13[4:1]};
        out[14:12] = funct3;
        out[19:15] = rs1_f;
        out[24:20] = rs2_f;
        out[31:25] = {imm13[12], imm13[10:5]};
        make_b = out;
    end
    endfunction

    function [31:0] make_s;
        input [6:0] opcode;
        input [2:0] funct3;
        input [4:0] rs1_f;
        input [4:0] rs2_f;
        input signed [11:0] imm12;
        reg [31:0] out;
    begin
        out = 32'b0;
        out[6:0]   = opcode;
        out[11:7]  = imm12[4:0];
        out[14:12] = funct3;
        out[19:15] = rs1_f;
        out[24:20] = rs2_f;
        out[31:25] = imm12[11:5];
        make_s = out;
    end
    endfunction

    initial begin
        errors = 0;
        // SUB x1,x2,x3
        instr = {7'b0100000, 5'd3, 5'd2, 3'b000, 5'd1, `OP_SUB};
        #1 check("sub", 5'd0, 5'd2, 5'd3, 5'd1, 32'd0, `R_TYPE, 1'b0);

        // ADDI x2,x1,5
        instr = {12'd5, 5'd1, 3'b000, 5'd2, `OP_ADDI};
        #1 check("addi", 5'd1, 5'd1, 5'd0, 5'd2, {{20{1'b0}},12'd5}, `I_TYPE, 1'b0);

        // BEQ x1,x2, offset -4
        instr = {1'b1, 6'b111111, 5'd2, 5'd1, 3'b000, 5'b11101, `OP_BEQ}; // encodes imm = -4
        #1 check("beq", 5'd4, 5'd1, 5'd2, 5'd29, {{19{1'b1}}, 1'b1, 1'b1, 6'b111111, 4'b1110, 1'b0}, `B_TYPE, 1'b0);

        // FSUB f1,f2,f3
        instr = {`FUNCT7_FSUB, 5'd3, 5'd2, `FUNCT3_FSUB, 5'd1, `OP_FSUB};
        #1 check("fsub", 5'd10, 5'd2, 5'd3, 5'd1, 32'd0, `R_TYPE, 1'b1);

        // EOF
        instr = {25'b0, 5'b0, `OP_EOF};
        #1 check("eof", 5'd16, 5'd0, 5'd0, 5'd0, 32'd0, `EOF_TYPE, 1'b0);

        // Randomized functional coverage: 50 iterations across op types
        repeat (50) begin
            rand_rs1 = $random & 5'h1F;
            rand_rs2 = $random & 5'h1F;
            rand_rd  = $random & 5'h1F;
            rand_imm = $random;
            // Build a B-type immediate with LSB=0
            bimm = {rand_imm[12], rand_imm[10:0], 1'b0};

            case ($random % 10)
                0: begin // SUB
                    instr = {7'b0100000, rand_rs2, rand_rs1, 3'b000, rand_rd, `OP_SUB};
                    #1 check("rand sub", 5'd0, rand_rs1, rand_rs2, rand_rd, 32'd0, `R_TYPE, 1'b0);
                end
                1: begin // ADDI
                    instr = {rand_imm[11:0], rand_rs1, 3'b000, rand_rd, `OP_ADDI};
                    #1 check("rand addi", 5'd1, rand_rs1, 5'd0, rand_rd, {{20{rand_imm[11]}}, rand_imm[11:0]}, `I_TYPE, 1'b0);
                end
                2: begin // LW
                    instr = {rand_imm[11:0], rand_rs1, 3'b010, rand_rd, `OP_LW};
                    #1 check("rand lw", 5'd2, rand_rs1, 5'd0, rand_rd, {{20{rand_imm[11]}}, rand_imm[11:0]}, `I_TYPE, 1'b0);
                end
                3: begin // SW
                    instr = make_s(`OP_SW, 3'b010, rand_rs1, rand_rs2, rand_imm[11:0]);
                    #1 check("rand sw", 5'd3, rand_rs1, rand_rs2, {rand_imm[4:0]}, {{20{rand_imm[11]}}, rand_imm[11:0]}, `S_TYPE, 1'b0);
                end
                4: begin // BEQ
                    instr = make_b(`OP_BEQ, 3'b000, rand_rs1, rand_rs2, bimm);
                    exp_imm_calc = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
                    #1 check("rand beq", 5'd4, rand_rs1, rand_rs2, instr[11:7], exp_imm_calc, `B_TYPE, 1'b0);
                end
                5: begin // JALR
                    instr = {rand_imm[11:0], rand_rs1, 3'b000, rand_rd, `OP_JALR};
                    #1 check("rand jalr", 5'd6, rand_rs1, 5'd0, rand_rd, {{20{rand_imm[11]}}, rand_imm[11:0]}, `I_TYPE, 1'b0);
                end
                6: begin // AUIPC
                    instr = {rand_imm[31:12], rand_rd, `OP_AUIPC};
                    #1 check("rand auipc", 5'd7, instr[19:15], instr[24:20], rand_rd, {rand_imm[31:12], 12'b0}, `U_TYPE, 1'b0);
                end
                7: begin // FSUB
                    instr = {`FUNCT7_FSUB, rand_rs2, rand_rs1, `FUNCT3_FSUB, rand_rd, `OP_FSUB};
                    #1 check("rand fsub", 5'd10, rand_rs1, rand_rs2, rand_rd, 32'd0, `R_TYPE, 1'b1);
                end
                8: begin // FLW
                    instr = {rand_imm[11:0], rand_rs1, 3'b010, rand_rd, `OP_FLW};
                    #1 check("rand flw", 5'd13, rand_rs1, 5'd0, rand_rd, {{20{rand_imm[11]}}, rand_imm[11:0]}, `I_TYPE, 1'b1);
                end
                default: begin // FSW
                    instr = make_s(`OP_FSW, 3'b010, rand_rs1, rand_rs2, rand_imm[11:0]);
                    #1 check("rand fsw", 5'd14, rand_rs1, rand_rs2, {rand_imm[4:0]}, {{20{rand_imm[11]}}, rand_imm[11:0]}, `S_TYPE, 1'b1);
                end
            endcase
        end

        if (errors == 0) $display("DECODER TB PASSED");
        else $display("DECODER TB FAILED, errors=%0d", errors);
        $finish;
    end
endmodule
