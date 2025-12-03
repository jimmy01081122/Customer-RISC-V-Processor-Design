// Integer register file: 32 entries, 32-bit wide.
// - Combinational read ports for rs1/rs2.
// - Synchronous write port.
// - Asynchronous active-low reset clears all registers to 0.
module regfile_int (
    input         i_clk,
    input         i_rst_n,
    input  [4:0]  i_rs1_addr,
    input  [4:0]  i_rs2_addr,
    output [31:0] o_rs1_data,
    output [31:0] o_rs2_data,
    input         i_we,
    input  [4:0]  i_rd_addr,
    input  [31:0] i_rd_data
);
    reg [31:0] regs [0:31];
    integer i;

    // Combinational reads make the core simple to schedule.
    assign o_rs1_data = regs[i_rs1_addr];
    assign o_rs2_data = regs[i_rs2_addr];

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            for (i = 0; i < 32; i = i + 1) regs[i] <= 32'b0;
        end else if (i_we) begin
            regs[i_rd_addr] <= i_rd_data;
        end
    end
endmodule
