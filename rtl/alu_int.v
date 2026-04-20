////////////////////////////////////////////////////////////////////////////////
//
// File: alu_int.v
// Module: alu_int
//
// Description:
//   32-bit integer Arithmetic Logic Unit (ALU) with overflow detection and
//   saturation behavior. Supports four core operations required by the RISC-V
//   integer instruction set. All computations are combinational (no registers),
//   enabling single-cycle execution within the processor pipeline.
//
// Features:
//   - ADD: Signed 32-bit addition with overflow detection via sign-extension
//   - SUB: Signed 32-bit subtraction with overflow handling
//   - SLT: Set Less Than (signed comparison, returns 1 or 0)
//   - SRL: Logical right shift by 0-31 positions (determined by i_b[4:0])
//   - Overflow saturation to min/max 32-bit signed values on overflow
//   - Pure Verilog-2001 compatible (no SystemVerilog extensions)
//
// IO Interface:
//   Inputs:
//     i_op[2:0]     : Operation selector (0=ADD, 1=SUB, 2=SLT, 3=SRL)
//     i_a[31:0]     : First operand (treated as signed for ADD, SUB, SLT)
//     i_b[31:0]     : Second operand (shift amount for SRL)
//   Outputs:
//     o_result[31:0]: Computed result (32-bit, sign-extended)
//     o_overflow    : High if signed operation overflowed (for exception handling)
//
// Author: [Original Designer]
// Date: 2024
// Version: 1.0
//
////////////////////////////////////////////////////////////////////////////////

module alu_int (
    // ========== Inputs ==========
    input  [2:0]  i_op,           // Operation selector (0-3)
    input  [31:0] i_a,            // First operand
    input  [31:0] i_b,            // Second operand (or shift amount for SRL)

    // ========== Outputs ==========
    output reg [31:0] o_result,   // ALU result
    output reg       o_overflow   // Overflow flag (for SAT or exception handling)
);

    //==========================================================================
    // OPERATION CODE DEFINITIONS
    //==========================================================================
    localparam OP_ADD = 3'd0;     // Addition: o_result = i_a + i_b
    localparam OP_SUB = 3'd1;     // Subtraction: o_result = i_a - i_b
    localparam OP_SLT = 3'd2;     // Set Less Than: o_result = (i_a < i_b) ? 1 : 0
    localparam OP_SRL = 3'd3;     // Shift Right Logical: o_result = i_a >> i_b[4:0]

    //==========================================================================
    // INTERNAL SIGNALS
    //==========================================================================
    // Interpret operands as signed 32-bit values for signed arithmetic
    wire signed [31:0] a_s = i_a;
    wire signed [31:0] b_s = i_b;

    // Extended width accumulator for overflow detection
    // Sign bit (bit [32]) is compared with MSB (bit [31]) to detect overflow
    reg signed [32:0] wide;

    //==========================================================================
    // COMBINATIONAL ALU LOGIC
    //==========================================================================
    always @(*) begin
        // Default outputs
        o_overflow = 1'b0;
        o_result   = 32'b0;
        wide       = 33'sd0;

        case (i_op)
            //===================================================================
            // OP_ADD: Signed addition with overflow detection
            //===================================================================
            // When two operands of the same sign are added, the result should
            // have the same sign. If not, overflow occurred.
            OP_ADD: begin
                wide       = a_s + b_s;           // Perform addition in 33-bit domain
                o_overflow = (wide[32] != wide[31]); // Check sign bit consistency
                if (o_overflow) begin
                    // Saturate result to minimum or maximum 32-bit signed value
                    o_result = wide[32] ? 32'h8000_0000 : 32'h7FFF_FFFF;
                end else begin
                    // No overflow; use lower 32 bits
                    o_result = wide[31:0];
                end
            end

            //===================================================================
            // OP_SUB: Signed subtraction with overflow detection
            //===================================================================
            // Subtraction overflow check identical to addition logic.
            OP_SUB: begin
                wide       = a_s - b_s;           // Perform subtraction in 33-bit domain
                o_overflow = (wide[32] != wide[31]); // Check sign bit consistency
                if (o_overflow) begin
                    // Saturate result to minimum or maximum 32-bit signed value
                    o_result = wide[32] ? 32'h8000_0000 : 32'h7FFF_FFFF;
                end else begin
                    // No overflow; use lower 32 bits
                    o_result = wide[31:0];
                end
            end

            //===================================================================
            // OP_SLT: Set Less Than (signed comparison)
            //===================================================================
            // Returns 1 if i_a < i_b (both treated as signed), else 0.
            // Result is always 0 or 1 (no overflow possible).
            OP_SLT: begin
                o_result = (a_s < b_s) ? 32'd1 : 32'd0;
            end

            //===================================================================
            // OP_SRL: Shift Right Logical
            //===================================================================
            // Shifts i_a right by i_b[4:0] positions (0-31).
            // Vacated high bits are filled with zeros (logical shift).
            OP_SRL: begin
                o_result = i_a >> i_b[4:0];
            end

            //===================================================================
            // Default: Unsupported operation
            //===================================================================
            default: begin
                o_result = 32'b0;
            end
        endcase
    end

endmodule

////////////////////////////////////////////////////////////////////////////////
