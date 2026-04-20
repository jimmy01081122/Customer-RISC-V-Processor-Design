`timescale 1ns/1ps

// Simple sanity test for integer and FP register files.
module tb_regfile;
    reg clk;
    reg rst_n;
    reg we_int, we_fp;
    reg [4:0] waddr_int, waddr_fp;
    reg [31:0] wdata_int, wdata_fp;
    wire [31:0] r1_int, r2_int;
    wire [31:0] r1_fp,  r2_fp;

    reg [4:0] rs1, rs2;
    reg [4:0] fs1, fs2;
    reg [31:0] int_ref [0:31];
    reg [31:0] fp_ref  [0:31];
    integer idx;

    regfile_int u_int(
        .i_clk(clk), .i_rst_n(rst_n),
        .i_rs1_addr(rs1), .i_rs2_addr(rs2),
        .o_rs1_data(r1_int), .o_rs2_data(r2_int),
        .i_we(we_int), .i_rd_addr(waddr_int), .i_rd_data(wdata_int)
    );

    regfile_fp u_fp(
        .i_clk(clk), .i_rst_n(rst_n),
        .i_fs1_addr(fs1), .i_fs2_addr(fs2),
        .o_fs1_data(r1_fp), .o_fs2_data(r2_fp),
        .i_we(we_fp), .i_fd_addr(waddr_fp), .i_fd_data(wdata_fp)
    );

    integer errors;

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst_n = 0;
        we_int = 0; we_fp = 0;
        rs1 = 0; rs2 = 0; fs1 = 0; fs2 = 0;
        errors = 0;
        for (idx = 0; idx < 32; idx = idx + 1) begin
            int_ref[idx] = 32'b0;
            fp_ref[idx]  = 32'b0;
        end
        #2 rst_n = 1;

        // Write int reg 3
        @(negedge clk);
        we_int = 1; waddr_int = 5'd3; wdata_int = 32'h1234_5678;
        @(negedge clk);
        we_int = 0; rs1 = 5'd3; rs2 = 5'd0;
        @(negedge clk);
        int_ref[3] = 32'h1234_5678;
        if (r1_int !== 32'h1234_5678) begin
            $display("FAIL regfile int: r3 = 0x%08x (expect 0x12345678)", r1_int);
            errors = errors + 1;
        end else begin
            $display("PASS regfile int write/read");
        end

        // Write fp reg 4
        we_fp = 1; waddr_fp = 5'd4; wdata_fp = 32'h3f800000; // 1.0
        @(negedge clk);
        we_fp = 0; fs1 = 5'd4;
        @(negedge clk);
        fp_ref[4] = 32'h3f800000;
        if (r1_fp !== 32'h3f800000) begin
            $display("FAIL regfile fp: f4 = 0x%08x (expect 0x3f800000)", r1_fp);
            errors = errors + 1;
        end else begin
            $display("PASS regfile fp write/read");
        end

        if (errors == 0) $display("REGFILE TB PASSED");
        else $display("REGFILE TB FAILED, errors=%0d", errors);

        // Randomized stress: 50 mixed writes/reads for int and fp
        repeat (50) begin
            @(negedge clk);
            // INT write
            waddr_int = $random & 5'h1F;
            wdata_int = $random;
            we_int    = 1;
            int_ref[waddr_int] = wdata_int;

            // FP write
            waddr_fp = $random & 5'h1F;
            wdata_fp = $random;
            we_fp    = 1;
            fp_ref[waddr_fp] = wdata_fp;

            @(negedge clk);
            we_int = 0;
            we_fp  = 0;

            // Read back random addresses
            rs1 = $random & 5'h1F;
            rs2 = $random & 5'h1F;
            fs1 = $random & 5'h1F;
            fs2 = $random & 5'h1F;

            @(negedge clk);
            if (r1_int !== int_ref[rs1]) begin
                $display("FAIL rand int rs1=%0d got=0x%08x exp=0x%08x", rs1, r1_int, int_ref[rs1]);
                errors = errors + 1;
            end
            if (r2_int !== int_ref[rs2]) begin
                $display("FAIL rand int rs2=%0d got=0x%08x exp=0x%08x", rs2, r2_int, int_ref[rs2]);
                errors = errors + 1;
            end
            if (r1_fp !== fp_ref[fs1]) begin
                $display("FAIL rand fp fs1=%0d got=0x%08x exp=0x%08x", fs1, r1_fp, fp_ref[fs1]);
                errors = errors + 1;
            end
            if (r2_fp !== fp_ref[fs2]) begin
                $display("FAIL rand fp fs2=%0d got=0x%08x exp=0x%08x", fs2, r2_fp, fp_ref[fs2]);
                errors = errors + 1;
            end
        end

        if (errors == 0) $display("REGFILE RANDOM TB PASSED");
        else $display("REGFILE RANDOM TB FAILED, errors=%0d", errors);
        $finish;
    end
endmodule
