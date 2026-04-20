`timescale 1ns/1ps

// Simple checks for fpu_unit using known IEEE754 constants.
module tb_fpu_unit;
    reg  [1:0]  op;
    reg  [31:0] a, b;
    wire [31:0] y;
    wire inv, ovf, udf;
    integer errors;
    integer INT_MAX, INT_MIN;
    integer sel;
    real ra, rb, rr;
    reg [31:0] bits_a, bits_b, exp_bits;
    reg ovf_r, udf_r;
    integer rounded;

    fpu_unit dut(
        .i_op(op),
        .i_a(a),
        .i_b(b),
        .o_result(y),
        .o_invalid(inv),
        .o_overflow(ovf),
        .o_underflow(udf)
    );

    // Helper functions copied from the DUT model for golden reference.
    function is_nan;
        input [31:0] f;
    begin
        is_nan = (f[30:23] == 8'hff) && (f[22:0] != 0);
    end
    endfunction

    function is_inf;
        input [31:0] f;
    begin
        is_inf = (f[30:23] == 8'hff) && (f[22:0] == 0);
    end
    endfunction

    function is_zero;
        input [31:0] f;
    begin
        is_zero = (f[30:23] == 0) && (f[22:0] == 0);
    end
    endfunction

    function is_subnormal;
        input [31:0] f;
    begin
        is_subnormal = (f[30:23] == 0) && (f[22:0] != 0);
    end
    endfunction

    function is_negative;
        input [31:0] f;
    begin
        is_negative = f[31];
    end
    endfunction

    function real fp_to_real;
        input [31:0] f;
        real mant;
        integer exp;
        real val_r;
    begin
        exp = f[30:23];
        if (exp == 0) begin
            if (f[22:0] == 0) val_r = 0.0;
            else begin
                mant = f[22:0];
                val_r = (mant / (2.0**23)) * (2.0**-126);
            end
        end else begin
            mant = 1.0 + (f[22:0] / (2.0**23));
            val_r = mant * (2.0**(exp - 127));
        end
        if (f[31]) val_r = -val_r;
        fp_to_real = val_r;
    end
    endfunction

    task real_to_fpbits;
        input  real val;
        output [31:0] bits;
        output reg ovf;
        output reg udf;
        reg sign;
        real abs_v;
        integer exp;
        real norm;
        real mant_real;
        real mant_scaled;
        integer mant;
        integer exp_field;
        real frac;
    begin
        ovf = 1'b0; udf = 1'b0; bits = 32'b0;
        if (val == 0.0) begin
            bits = 32'b0;
        end else begin
            sign = (val < 0.0);
            abs_v = sign ? -val : val;
            exp = 0; norm = abs_v;
            while (norm >= 2.0) begin norm = norm / 2.0; exp = exp + 1; end
            while (norm < 1.0) begin norm = norm * 2.0; exp = exp - 1; end
            mant_real   = norm - 1.0;
            mant_scaled = mant_real * (2.0**23);
            mant = $rtoi(mant_scaled);
            frac = mant_scaled - mant;
            if (frac > 0.5) mant = mant + 1;
            else if (frac == 0.5 && mant[0]) mant = mant + 1;
            if (mant == (1<<23)) begin mant = 0; exp = exp + 1; end
            exp_field = exp + 127;
            if (exp_field >= 255) begin
                ovf  = 1'b1;
                bits = {sign, 8'hff, 23'b0};
            end else if (exp_field <= 0) begin
                bits = 32'b0;
                udf  = 1'b1;
            end else begin
                bits = {sign, exp_field[7:0], mant[22:0]};
            end
        end
    end
    endtask

    function [31:0] fclass_bits;
        input [31:0] f;
        reg [31:0] out;
    begin
        out = 32'b0;
        if (is_inf(f) && is_negative(f))                 out[0] = 1'b1;
        else if (!is_inf(f) && is_negative(f) && !is_subnormal(f) && !is_zero(f)) out[1] = 1'b1;
        else if (is_subnormal(f) && is_negative(f))      out[2] = 1'b1;
        else if (is_zero(f) && is_negative(f))           out[3] = 1'b1;
        else if (is_zero(f) && !is_negative(f))          out[4] = 1'b1;
        else if (is_subnormal(f) && !is_negative(f))     out[5] = 1'b1;
        else if (!is_inf(f) && !is_zero(f) && !is_subnormal(f) && !is_nan(f) && !is_negative(f)) out[6] = 1'b1;
        else if (is_inf(f) && !is_negative(f))           out[7] = 1'b1;
        else if (is_nan(f) && (f[22] == 1'b0))           out[8] = 1'b1;
        else if (is_nan(f) && (f[22] == 1'b1))           out[9] = 1'b1;
        fclass_bits = out;
    end
    endfunction

    function integer round_nearest_even_int;
        input real val;
        real abs_v;
        real frac;
        integer base;
    begin
        abs_v = (val >= 0.0) ? val : -val;
        base  = $rtoi(abs_v);
        frac  = abs_v - base;
        if (frac > 0.5) base = base + 1;
        else if (frac == 0.5 && base[0]) base = base + 1;
        if (val < 0.0) base = -base;
        round_nearest_even_int = base;
    end
    endfunction

    task check;
        input [8*16-1:0] name;
        input [31:0] exp_y;
        input exp_inv;
    begin
        if (y !== exp_y || inv !== exp_inv) begin
            $display("FAIL %s: y=0x%08x inv=%b exp_y=0x%08x exp_inv=%b", name, y, inv, exp_y, exp_inv);
            errors = errors + 1;
        end else begin
            $display("PASS %s: y=0x%08x inv=%b", name, y, inv);
        end
    end
    endtask

    initial begin
        errors = 0;
        INT_MAX = 32'h7fff_ffff;
        INT_MIN = 32'h8000_0000;
        // fsub: 3.5 - 1.5 = 2.0 (0x40000000)
        op = 2'd0; a = 32'h40600000; b = 32'h3fc00000; #1;
        check("fsub 3.5-1.5", 32'h40000000, 1'b0);

        // fmul: 2.0 * 4.0 = 8.0 (0x41000000)
        op = 2'd1; a = 32'h40000000; b = 32'h40800000; #1;
        check("fmul 2*4", 32'h41000000, 1'b0);

        // fcvt.w.s: 5.8 -> round-nearest-even => 6
        op = 2'd2; a = 32'h40b9999a; b = 32'b0; #1;
        check("fcvt 5.8", 32'd6, 1'b0);

        // fclass: +inf sets bit7
        op = 2'd3; a = {1'b0, 8'hff, 23'b0}; b = 32'b0; #1;
        check("fclass +inf", 32'h00000080, 1'b0);

        // Randomized functional tests (50 iterations)
        repeat (50) begin
            sel = $random % 4;
            case (sel)
                0: begin // fsub
                    ra = ($random % 100) - 50;
                    rb = ($random % 100) - 50;
                    real_to_fpbits(ra, bits_a, ovf_r, udf_r);
                    real_to_fpbits(rb, bits_b, ovf_r, udf_r);
                    a = bits_a; b = bits_b; op = 2'd0; #1;
                    rr = ra - rb;
                    real_to_fpbits(rr, exp_bits, ovf_r, udf_r);
                    check("rand fsub", exp_bits, ovf_r | udf_r);
                end
                1: begin // fmul
                    ra = ($random % 50) - 25;
                    rb = ($random % 50) - 25;
                    real_to_fpbits(ra, bits_a, ovf_r, udf_r);
                    real_to_fpbits(rb, bits_b, ovf_r, udf_r);
                    a = bits_a; b = bits_b; op = 2'd1; #1;
                    rr = ra * rb;
                    real_to_fpbits(rr, exp_bits, ovf_r, udf_r);
                    check("rand fmul", exp_bits, ovf_r | udf_r);
                end
                2: begin // fcvt.w.s
                    ra = (($random % 200) - 100) + 0.25;
                    real_to_fpbits(ra, bits_a, ovf_r, udf_r);
                    a = bits_a; b = 32'b0; op = 2'd2; #1;
                    rounded = round_nearest_even_int(ra);
                    if (rounded > INT_MAX) begin rounded = INT_MAX; ovf_r = 1'b1; end
                    else if (rounded < INT_MIN) begin rounded = INT_MIN; ovf_r = 1'b1; end
                    check("rand fcvt", rounded[31:0], ovf_r);
                end
                default: begin // fclass
                    // Use a mix: zero, inf, normal
                    case ($random % 3)
                        0: a = 32'b0;
                        1: a = {1'b0, 8'hff, 23'b0};
                        default: begin
                            ra = ($random % 20) - 10;
                            real_to_fpbits(ra, a, ovf_r, udf_r);
                        end
                    endcase
                    b = 32'b0; op = 2'd3; #1;
                    check("rand fclass", fclass_bits(a), 1'b0);
                end
            endcase
        end

        if (errors == 0) $display("FPU_UNIT TB PASSED");
        else $display("FPU_UNIT TB FAILED, errors=%0d", errors);
        $finish;
    end
endmodule
