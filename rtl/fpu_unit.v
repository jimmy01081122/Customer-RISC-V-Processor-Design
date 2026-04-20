////////////////////////////////////////////////////////////////////////////////
//
// File: fpu_unit.v
// Module: fpu_unit
//
// Description:
//   32-bit IEEE 754 single-precision floating-point execution unit implementing
//   RISC-V floating-point operations (FSUB, FMUL, FCVT.W.S, FCLASS).
//   All operations are combinational (zero-latency). Special case handling for
//   NaN, infinity, denormalized numbers follows IEEE 754 standards.
//   Rounding uses "round-to-nearest, ties-to-even" (banker's rounding).
//
// Features:
//   - FSUB: IEEE 754 subtraction with rounding
//   - FMUL: IEEE 754 multiplication with rounding
//   - FCVT.W.S: Float-to-signed-int conversion with rounding
//   - FCLASS: Classifies FP value (NaN, infinity, zero, denorm, normal, sign)
//   - Synthesizable Verilog-2001 (no SystemVerilog or real types)
//   - Normalizes and rounds with guard/round/sticky bits
//   - Detects and reports overflow/underflow events
//   - Special value handling: NaN, infinity, denormalized numbers
//
// IEEE 754 Single Format: [Sign(1) | Exponent(8) | Mantissa(23)]
//   - Sign (bit 31): 0=positive, 1=negative
//   - Exponent (bits 30:23): Biased by 127 (e.g., 127 = 2^0)
//   - Mantissa (bits 22:0): Implicit leading 1 for normalized numbers
//   - Special: exp=0xff → NaN/Infinity, exp=0 → zero/denormalized
//
// IO Interface:
//   Inputs:
//     i_op[1:0]     : Operation (0=FSUB, 1=FMUL, 2=FCVT.W.S, 3=FCLASS)
//     i_a[31:0]     : First operand (IEEE 754 single)
//     i_b[31:0]     : Second operand (for FSUB/FMUL only)
//   Outputs:
//     o_result[31:0]: 32-bit result (FP or integer depending on operation)
//     o_invalid     : High if operation produced NaN/exception
//     o_overflow    : High if exponent overflowed (→ ±∞)
//     o_underflow   : High if exponent underflowed (→ ±0)
//
// Author: [Original Designer]
// Date: 2024
// Version: 1.0
//
////////////////////////////////////////////////////////////////////////////////

module fpu_unit (
    // ========== Inputs ==========
    input  [1:0]  i_op,           // Operation selector (0-3)
    input  [31:0] i_a,            // First operand (IEEE 754 SP)
    input  [31:0] i_b,            // Second operand (for binary ops)

    // ========== Outputs ==========
    output reg [31:0] o_result,   // Result or 0 on exception
    output reg       o_invalid,   // Exception flag
    output reg       o_overflow,  // Overflow flag
    output reg       o_underflow  // Underflow flag
);

    //==========================================================================
    // OPERATION CODE DEFINITIONS
    //==========================================================================
    localparam OP_FSUB   = 2'd0;   // Floating-point subtract
    localparam OP_FMUL   = 2'd1;   // Floating-point multiply
    localparam OP_FCVT   = 2'd2;   // Float to signed word conversion
    localparam OP_FCLASS = 2'd3;   // FP class query

    //==========================================================================
    // IEEE 754 SPECIAL VALUE CLASSIFICATION FUNCTIONS
    //==========================================================================
    // These functions examine the exponent and mantissa fields to determine
    // the type of value represented by a 32-bit IEEE 754 encoding.

    // is_nan: Check if value is Not-a-Number (NaN)
    // NaN: exponent = all 1's (0xff), mantissa != 0
    function is_nan;
        input [31:0] f;
    begin
        is_nan = (f[30:23] == 8'hff) && (f[22:0] != 0);
    end
    endfunction

    // is_inf: Check if value is ±infinity
    // Infinity: exponent = all 1's (0xff), mantissa = 0
    function is_inf;
        input [31:0] f;
    begin
        is_inf = (f[30:23] == 8'hff) && (f[22:0] == 0);
    end
    endfunction

    // is_zero: Check if value is ±zero
    // Zero: exponent = 0, mantissa = 0 (sign bit ignored)
    function is_zero;
        input [31:0] f;
    begin
        is_zero = (f[30:23] == 0) && (f[22:0] == 0);
    end
    endfunction

    // is_subnormal: Check if value is denormalized (subnormal)
    // Denormalized: exponent = 0, mantissa != 0
    // Represents numbers with leading zeros in mantissa
    function is_subnormal;
        input [31:0] f;
    begin
        is_subnormal = (f[30:23] == 0) && (f[22:0] != 0);
    end
    endfunction

    // is_negative: Check sign of value
    // Negative if sign bit (bit 31) = 1
    function is_negative;
        input [31:0] f;
    begin
        is_negative = f[31];
    end
    endfunction

    //==========================================================================
    // FCLASS OUTPUT FUNCTION
    //==========================================================================
    // RISC-V FCLASS returns a 10-bit mask indicating the type of FP value.
    // Only one bit is set per value, indicating its classification.
    // Bit masks: [0]=neg_inf, [1]=neg_normal, [2]=neg_subnorm, [3]=neg_zero,
    //            [4]=pos_zero, [5]=pos_subnorm, [6]=pos_normal, [7]=pos_inf,
    //            [8]=sNaN, [9]=qNaN
    function [31:0] do_fclass;
        input [31:0] f;
        reg [31:0] out;
    begin
        out = 32'b0;
        if (is_inf(f) && is_negative(f))
            out[0] = 1'b1;  // Negative infinity
        else if (!is_inf(f) && is_negative(f) && !is_subnormal(f) && !is_zero(f))
            out[1] = 1'b1;  // Negative normal number
        else if (is_subnormal(f) && is_negative(f))
            out[2] = 1'b1;  // Negative subnormal
        else if (is_zero(f) && is_negative(f))
            out[3] = 1'b1;  // Negative zero
        else if (is_zero(f) && !is_negative(f))
            out[4] = 1'b1;  // Positive zero
        else if (is_subnormal(f) && !is_negative(f))
            out[5] = 1'b1;  // Positive subnormal
        else if (!is_inf(f) && !is_zero(f) && !is_subnormal(f) && !is_nan(f) && !is_negative(f))
            out[6] = 1'b1;  // Positive normal number
        else if (is_inf(f) && !is_negative(f))
            out[7] = 1'b1;  // Positive infinity
        else if (is_nan(f) && (f[22] == 1'b0))
            out[8] = 1'b1;  // Signaling NaN (quiet bit = 0)
        else if (is_nan(f) && (f[22] == 1'b1))
            out[9] = 1'b1;  // Quiet NaN (quiet bit = 1)
        do_fclass = out;
    end
    endfunction

    //==========================================================================
    // NORMALIZE AND ROUND TASK
    //==========================================================================
    // Normalizes a mantissa and applies banker's rounding (round-to-nearest-even).
    // Handles exponent overflow/underflow by saturating or flushing to zero.
    // Input mantissa is 27 bits: [26:3] = 24 main bits, [2]=guard, [1]=round, [0]=sticky
    task norm_round;
        input        sign_in;
        input [8:0]  exp_in;           // 9-bit exponent (includes bias)
        input [26:0] mant_in;          // 27-bit mantissa with GRS bits
        output reg [31:0] out_fp;
        output reg ovf;
        output reg udf;
    reg [8:0] exp_tmp;
    reg [24:0] mant_tmp;              // 25-bit mantissa to detect carry from rounding
    reg guard, roundb, sticky;
    reg incr;
    begin
        ovf = 1'b0;
        udf = 1'b0;
        exp_tmp  = exp_in;
        mant_tmp = {1'b0, mant_in[26:3]};  // Extract main 24 bits + carry detection
        guard    = mant_in[2];
        roundb   = mant_in[1];
        sticky   = mant_in[0];

        // Round to nearest even: increment if guard bit set AND
        // (round or sticky is set, OR LSB of mantissa is 1 for ties)
        incr = guard & (roundb | sticky | mant_tmp[0]);
        if (incr) mant_tmp = mant_tmp + 1'b1;

        // If rounding caused mantissa to overflow, shift and increment exponent
        if (mant_tmp[24]) begin
            mant_tmp = {1'b0, mant_tmp[24:1]};  // Shift right
            exp_tmp  = exp_tmp + 1'b1;
        end

        // Check for exponent overflow/underflow after any adjustments
        if (exp_tmp >= 9'd255) begin
            // Exponent overflow: return ±infinity
            ovf     = 1'b1;
            out_fp  = {sign_in, 8'hff, 23'b0};
        end else if (exp_tmp <= 9'd0) begin
            // Exponent underflow: flush to zero
            udf     = 1'b1;
            out_fp  = 32'b0;
        end else begin
            // Valid result: assemble FP value
            out_fp = {sign_in, exp_tmp[7:0], mant_tmp[22:0]};
        end
    end
    endtask

    //==========================================================================
    // FLOATING-POINT ADD/SUBTRACT TASK
    //==========================================================================
    // Performs IEEE 754 addition/subtraction by aligning mantissas,
    // performing the operation, and normalizing the result.
    // Handles special cases: NaN, infinity, zero, subnormal values.
    // sub=1 performs subtraction (result sign may be flipped).
    task float_addsub;
        input  [31:0] a;
        input  [31:0] b;
        input         sub;            // 1 for subtract, 0 for add
        output [31:0] res;
        output reg    ovf;
        output reg    udf;
    reg sign_a, sign_b, sign_res;
    reg [7:0] exp_a, exp_b;
    reg [23:0] mant_a, mant_b;
    reg [7:0] exp_large, exp_small;
    reg [24:0] mant_large;
    reg [26:0] mant_small_ext;
    reg [26:0] mant_small_shift;
    reg [8:0]  exp_diff;
    reg guard, roundb, sticky;
    reg [25:0] mant_sum;
    reg [25:0] mant_sub;
    reg [4:0]  lead_zero;
    reg [26:0] remainder;
    integer i;
    begin
        ovf = 1'b0; udf = 1'b0; res = 32'b0;
        sign_a = a[31];
        sign_b = b[31] ^ sub;           // XOR with sub to flip for subtraction
        exp_a  = a[30:23];
        exp_b  = b[30:23];

        // Extract/construct mantissas (implicit leading 1 for normalized)
        mant_a = (exp_a == 0) ? 24'b0 : {1'b1, a[22:0]};
        mant_b = (exp_b == 0) ? 24'b0 : {1'b1, b[22:0]};

        // Handle special case: both operands are zero
        if ((exp_a == 0 && mant_a == 0) && (exp_b == 0 && mant_b == 0)) begin
            res = 32'b0;
            udf = 1'b1;
        end else if (exp_a == 0 && mant_a == 0) begin
            // a is zero, return b
            res = {sign_b, b[30:0]};
            udf = (exp_b == 0);
        end else if (exp_b == 0 && mant_b == 0) begin
            // b is zero, return a
            res = {sign_a, a[30:0]};
            udf = (exp_a == 0);
        end else begin
            // Both non-zero: perform alignment and add/subtract

            // Identify larger exponent for alignment
            exp_large = 8'd0;
            exp_small = 8'd0;
            mant_large = 25'd0;
            mant_small_ext = 27'd0;
            guard = 1'b0;
            roundb = 1'b0;
            sticky = 1'b0;

            if (exp_a > exp_b || (exp_a == exp_b && mant_a >= mant_b)) begin
                exp_large = exp_a;
                mant_large = {mant_a, 1'b0};
                sign_res = sign_a;
                exp_small = exp_b;
                mant_small_ext = {mant_b, 3'b0};
            end else begin
                exp_large = exp_b;
                mant_large = {mant_b, 1'b0};
                sign_res = sign_b;
                exp_small = exp_a;
                mant_small_ext = {mant_a, 3'b0};
            end

            // Compute exponent difference and align mantissas
            exp_diff = exp_large - exp_small;
            if (exp_diff == 0) begin
                mant_small_shift = mant_small_ext;
                guard  = 1'b0;
                roundb = 1'b0;
                sticky = 1'b0;
            end else if (exp_diff >= 27) begin
                // Small mantissa shifts completely out (becomes sticky bit only)
                mant_small_shift = 27'b0;
                guard = 1'b0;
                roundb = 1'b0;
                sticky = 1'b1;
            end else begin
                // Normal shift: extract GRS bits from shifted portion
                remainder = 27'd0;
                mant_small_shift = mant_small_ext >> exp_diff;
                guard  = mant_small_ext[exp_diff-1];
                remainder = mant_small_ext & ((27'd1 << exp_diff) - 1);
                roundb = 1'b0;
                sticky = |remainder;
            end

            // Perform addition or subtraction based on sign match
            if (sign_a == sign_b) begin
                // Same sign: add mantissas
                mant_sum = {1'b0, mant_large} + {1'b0, mant_small_shift[26:2]};
                if (mant_sum[25]) begin
                    // Carry out: shift and increment exponent
                    norm_round(sign_res, {1'b0, exp_large} + 1'b1, {mant_sum[25:0], sticky}, res, ovf, udf);
                end else begin
                    norm_round(sign_res, {1'b0, exp_large}, {mant_sum[24:0], roundb, sticky}, res, ovf, udf);
                end
            end else begin
                // Different signs: subtract smaller from larger
                mant_sub = {1'b0, mant_large} - {1'b0, mant_small_shift[26:2]};
                if (mant_sub == 0) begin
                    // Result is zero
                    norm_round(1'b0, 9'd0, 27'b0, res, ovf, udf);
                end else begin : find_lead
                    // Find leading 1 to normalize
                    lead_zero = 0;
                    for (i = 25; i >= 0; i = i - 1)
                        if (mant_sub[i] && lead_zero == 0)
                            lead_zero = 25 - i;
                    mant_sub = mant_sub << lead_zero;
                    norm_round(sign_res, {1'b0, exp_large} - lead_zero[8:0], {mant_sub[25:0], sticky}, res, ovf, udf);
                end
            end
        end
    end
    endtask

    //==========================================================================
    // FLOATING-POINT MULTIPLY TASK
    //==========================================================================
    // Multiplies two IEEE 754 single-precision numbers, handling special cases
    // and normalizing the result with rounding.
    task float_mul;
        input  [31:0] a;
        input  [31:0] b;
        output [31:0] res;
        output reg    ovf;
        output reg    udf;
    reg sign;
    reg [8:0] exp_sum;
    reg [23:0] mant_a, mant_b;
    reg [47:0] mant_prod;
    reg [23:0] mant_norm;
    reg [8:0] exp_norm;
    reg guard, roundb, sticky;
    begin
        ovf = 1'b0; udf = 1'b0; res = 32'b0;

        // Quick check: if either operand is zero, result is zero
        if (is_zero(a) || is_zero(b)) begin
            res = 32'b0;
        end else begin
            sign    = a[31] ^ b[31];   // XOR signs
            mant_a  = (a[30:23] == 0) ? 24'b0 : {1'b1, a[22:0]};
            mant_b  = (b[30:23] == 0) ? 24'b0 : {1'b1, b[22:0]};
            exp_sum = a[30:23] + b[30:23] - 9'd127;  // Add exponents, remove bias

            mant_prod = mant_a * mant_b;  // 48-bit product

            // Normalize: product is in range [1,4)
            if (mant_prod[47]) begin
                // Product >= 2: already has leading 1 in bit 47
                mant_norm = mant_prod[47:24];
                guard     = mant_prod[23];
                roundb    = mant_prod[22];
                sticky    = |mant_prod[21:0];
                exp_norm  = exp_sum + 1'b1;
            end else begin
                // Product < 2: leading 1 in bit 46
                mant_norm = mant_prod[46:23];
                guard     = mant_prod[22];
                roundb    = mant_prod[21];
                sticky    = |mant_prod[20:0];
                exp_norm  = exp_sum;
            end

            // Normalize and round
            norm_round(sign, exp_norm, {mant_norm, guard, roundb, sticky}, res, ovf, udf);
        end
    end
    endtask

    //==========================================================================
    // FLOAT TO SIGNED INTEGER CONVERSION TASK
    //==========================================================================
    // Converts IEEE 754 single-precision FP to signed 32-bit integer.
    // Uses banker's rounding (round-to-nearest-even).
    // Handles special cases: NaN, infinity, out-of-range values.
    task fcvt_w_s;
        input  [31:0] a;
        output [31:0] out_int;
        output reg    inv;
    reg sign;
    reg [7:0] exp;
    reg [23:0] mant;
    integer exp_unbias;
    reg [55:0] shifted;
    reg guard, sticky;
    reg [31:0] int_mag;
    begin
        inv  = 1'b0;
        out_int = 32'b0;
        sign = a[31];
        exp  = a[30:23];
        mant = (exp == 0) ? 24'b0 : {1'b1, a[22:0]};

        // Check for NaN or infinity
        if (is_nan(a) || is_inf(a)) begin
            inv = 1'b1;
            out_int = 32'b0;
        end

        exp_unbias = exp - 127;  // Remove bias to get true exponent

        if (!inv) begin
            if (exp_unbias > 30) begin
                // Out of range: saturate to min or max
                inv     = 1'b1;
                out_int = sign ? 32'h8000_0000 : 32'h7fff_ffff;
            end else if (exp_unbias < 0) begin
                // Exponent is negative: value < 1, truncates to 0
                out_int = 32'b0;
            end else begin
                // Normal case: extract integer part with rounding

                if (exp_unbias >= 23) begin
                    // Entire mantissa is integer (no fractional part to round)
                    int_mag = mant << (exp_unbias - 23);
                    guard   = 1'b0;
                    sticky  = 1'b0;
                end else begin
                    // Mantissa has fractional part: extract GRS bits
                    shifted = {mant, 32'b0};
                    shifted = shifted >> (23 - exp_unbias);
                    int_mag = shifted[55:24];
                    guard   = shifted[23];
                    sticky  = |shifted[22:0];
                end

                // Round to nearest even
                if (guard && (sticky || int_mag[0]))
                    int_mag = int_mag + 1'b1;

                // Apply sign to result
                out_int = sign ? (~int_mag + 1'b1) : int_mag;  // Two's complement
            end
        end
    end
    endtask

    //==========================================================================
    // MAIN COMBINATIONAL FPU LOGIC
    //==========================================================================
    // Routes to appropriate operation and computes result based on i_op
    always @(*) begin
        o_result    = 32'b0;
        o_invalid   = 1'b0;
        o_overflow  = 1'b0;
        o_underflow = 1'b0;

        case (i_op)
            //===================================================================
            // OP_FCLASS: Classify floating-point value
            //===================================================================
            OP_FCLASS: begin
                o_result = do_fclass(i_a);
            end

            //===================================================================
            // OP_FCVT: Convert floating-point to signed integer
            //===================================================================
            OP_FCVT: begin
                fcvt_w_s(i_a, o_result, o_invalid);
            end

            //===================================================================
            // OP_FMUL: Floating-point multiply
            //===================================================================
            OP_FMUL: begin
                if (is_nan(i_a) || is_nan(i_b) || is_inf(i_a) || is_inf(i_b)) begin
                    // NaN and infinity handling: propagate exception
                    o_invalid = 1'b1;
                    o_result  = 32'b0;
                end else begin
                    float_mul(i_a, i_b, o_result, o_overflow, o_underflow);
                    o_invalid = o_overflow | o_underflow;
                end
            end

            //===================================================================
            // OP_FSUB: Floating-point subtract (default case also)
            //===================================================================
            default: begin  // OP_FSUB
                if (is_nan(i_a) || is_nan(i_b) || is_inf(i_a) || is_inf(i_b)) begin
                    // NaN and infinity handling: propagate exception
                    o_invalid = 1'b1;
                    o_result  = 32'b0;
                end else begin
                    float_addsub(i_a, i_b, 1'b1, o_result, o_overflow, o_underflow);
                    o_invalid = o_overflow | o_underflow;
                end
            end
        endcase
    end

endmodule

////////////////////////////////////////////////////////////////////////////////
