// Floating-point register file: 32 entries, 32-bit wide (IEEE754 single).
// Reset clears all registers. f0 is writable per the user's request.
module regfile_fp (
    input         i_clk,
    input         i_rst_n,
    input  [4:0]  i_fs1_addr,
    input  [4:0]  i_fs2_addr,
    output [31:0] o_fs1_data,
    output [31:0] o_fs2_data,
    input         i_we,
    input  [4:0]  i_fd_addr,
    input  [31:0] i_fd_data
);
    reg [31:0] fregs [0:31];
    integer i;

    assign o_fs1_data = fregs[i_fs1_addr];
    assign o_fs2_data = fregs[i_fs2_addr];

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            for (i = 0; i < 32; i = i + 1) fregs[i] <= 32'b0;
        end else if (i_we) begin
            fregs[i_fd_addr] <= i_fd_data;
        end
    end
endmodule
