`timescale 1ns/1ps

// Quick self-checking testbench for alu_int.
module tb_alu_int;
    reg  [2:0]  op;
    reg  [31:0] a, b;
    wire [31:0] y;
    wire        ovf;
    reg         exp_ovf;
    reg [31:0]  exp_y;
    integer     sel_rand;

    alu_int dut(
        .i_op(op),
        .i_a(a),
        .i_b(b),
        .o_result(y),
        .o_overflow(ovf)
    );

    integer errors;

    // Golden computation for signed add/sub saturation.
    task sat_add;
        input signed [31:0] a;
        input signed [31:0] b;
        output [31:0] res;
        output reg ovf;
        reg signed [32:0] wide;
    begin
        wide = a + b;
        ovf  = (wide[32] != wide[31]);
        if (ovf) res = wide[32] ? 32'h8000_0000 : 32'h7FFF_FFFF;
        else     res = wide[31:0];
    end
    endtask

    task sat_sub;
        input signed [31:0] a;
        input signed [31:0] b;
        output [31:0] res;
        output reg ovf;
        reg signed [32:0] wide;
    begin
        wide = a - b;
        ovf  = (wide[32] != wide[31]);
        if (ovf) res = wide[32] ? 32'h8000_0000 : 32'h7FFF_FFFF;
        else     res = wide[31:0];
    end
    endtask

    task check(input [8*20-1:0] name, input [31:0] exp_y, input exp_ovf);
    begin
        if (y !== exp_y || ovf !== exp_ovf) begin
            $display("FAIL %s: got y=%0d ovf=%b exp_y=%0d exp_ovf=%b", name, $signed(y), ovf, $signed(exp_y), exp_ovf);
            errors = errors + 1;
        end else begin
            $display("PASS %s: y=%0d ovf=%b", name, $signed(y), ovf);
        end
    end
    endtask

    initial begin
        errors = 0;
        // ADD simple
        op = 3'd0; a = 32'd5; b = 32'd7; #1; check("add 5+7", 32'd12, 1'b0);
        // ADD overflow (saturates)
        a = 32'h7FFF_FFFF; b = 32'd1; #1; check("add overflow", 32'h7FFF_FFFF, 1'b1);
        // SUB simple
        op = 3'd1; a = 32'd10; b = 32'd20; #1; check("sub 10-20", -32'sd10, 1'b0);
        // SLT
        op = 3'd2; a = -5; b = 3; #1; check("slt -5<3", 32'd1, 1'b0);
        // SRL
        op = 3'd3; a = 32'hF0; b = 2; #1; check("srl F0>>2", 32'h3C, 1'b0);

        // Randomized stress (50 iterations)
        repeat (50) begin
            sel_rand = $random % 4;
            case (sel_rand)
                0: op = 3'd0;
                1: op = 3'd1;
                2: op = 3'd2;
                default: op = 3'd3;
            endcase
            a  = $random;
            b  = $random;
            #1;
            if (op == 3'd0) begin
                sat_add(a, b, exp_y, exp_ovf);
                check("rand add", exp_y, exp_ovf);
            end else if (op == 3'd1) begin
                sat_sub(a, b, exp_y, exp_ovf);
                check("rand sub", exp_y, exp_ovf);
            end else if (op == 3'd2) begin
                check("rand slt", ($signed(a) < $signed(b)) ? 32'd1 : 32'd0, 1'b0);
            end else begin
                check("rand srl", a >> b[4:0], 1'b0);
            end
        end

        if (errors == 0) $display("ALU_INT TB PASSED");
        else $display("ALU_INT TB FAILED, errors=%0d", errors);
        $finish;
    end
endmodule
