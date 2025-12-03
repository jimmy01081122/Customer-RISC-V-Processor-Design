// Minimal integer ALU with overflow detection and saturation.
// Supported ops: ADD, SUB, SLT (signed), SRL (logical right shift).
// Pure Verilog-2001 (no SystemVerilog features).
module alu_int (
    input  [2:0]  i_op,
    input  [31:0] i_a,
    input  [31:0] i_b,
    output reg [31:0] o_result,
    output reg       o_overflow
);
    localparam OP_ADD = 3'd0;
    localparam OP_SUB = 3'd1;
    localparam OP_SLT = 3'd2;
    localparam OP_SRL = 3'd3;

    wire signed [31:0] a_s = i_a;
    wire signed [31:0] b_s = i_b;
    reg signed [32:0] wide;

    always @(*) begin
        o_overflow = 1'b0;
        o_result   = 32'b0;
        wide       = 33'sd0;
        case (i_op)
            OP_ADD: begin
                wide       = a_s + b_s;
                o_overflow = (wide[32] != wide[31]);
                if (o_overflow)
                    o_result = wide[32] ? 32'h8000_0000 : 32'h7FFF_FFFF;
                else
                    o_result = wide[31:0];
            end
            OP_SUB: begin
                wide       = a_s - b_s;
                o_overflow = (wide[32] != wide[31]);
                if (o_overflow)
                    o_result = wide[32] ? 32'h8000_0000 : 32'h7FFF_FFFF;
                else
                    o_result = wide[31:0];
            end
            OP_SLT: o_result = (a_s < b_s) ? 32'd1 : 32'd0;
            OP_SRL: o_result = i_a >> i_b[4:0];
            default: o_result = 32'b0;
        endcase
    end
endmodule
