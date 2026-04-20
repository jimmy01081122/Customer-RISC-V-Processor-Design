////////////////////////////////////////////////////////////////////////////////
//
// File: regfile_int.v
// Module: regfile_int
//
// Description:
//   RISC-V integer register file with 32 entries (x0-x31), each 32-bit wide.
//   Implements the general-purpose register (GPR) storage for integer operands
//   and results. Supports dual combinational read ports and single synchronous
//   write port, enabling efficient pipelined operation.
//
// Features:
//   - 32 registers × 32-bit (total 1024 bits)
//   - Dual asynchronous read ports (combinational, zero latency)
//   - Single synchronous write port (writes on rising clock edge)
//   - Asynchronous active-low reset (clears all registers to 0)
//   - Forwarding-friendly: new data available immediately on write
//
// IO Interface:
//   Inputs:
//     i_clk         : System clock (positive edge triggered for writes)
//     i_rst_n       : Active-low asynchronous reset
//     i_rs1_addr[4:0]: Source register 1 address (0-31)
//     i_rs2_addr[4:0]: Source register 2 address (0-31)
//     i_we          : Write enable (high to write on clock edge)
//     i_rd_addr[4:0] : Destination register address (0-31)
//     i_rd_data[31:0]: Write data (sampled on rising clock edge)
//   Outputs:
//     o_rs1_data[31:0]: Data from register rs1_addr (combinational)
//     o_rs2_data[31:0]: Data from register rs2_addr (combinational)
//
// Notes:
//   - x0 is not enforced as read-only (can be written, though semantics say x0 always reads 0)
//   - Bypass logic required in core if reading just-written register in same cycle
//   - All reads are combinational (no delay from address change to data valid)
//
// Author: [Original Designer]
// Date: 2024
// Version: 1.0
//
////////////////////////////////////////////////////////////////////////////////

module regfile_int (
    // ========== Clock and Reset ==========
    input         i_clk,           // System clock (positive edge for writes)
    input         i_rst_n,         // Active-low asynchronous reset

    // ========== Read Port 1 ==========
    input  [4:0]  i_rs1_addr,      // Source register 1 address
    output [31:0] o_rs1_data,      // Source register 1 data (combinational)

    // ========== Read Port 2 ==========
    input  [4:0]  i_rs2_addr,      // Source register 2 address
    output [31:0] o_rs2_data,      // Source register 2 data (combinational)

    // ========== Write Port (Synchronous) ==========
    input         i_we,            // Write enable
    input  [4:0]  i_rd_addr,       // Destination register address
    input  [31:0] i_rd_data        // Write data
);

    //==========================================================================
    // REGISTER STORAGE
    //==========================================================================
    // 32 registers, each 32 bits wide, supporting RISC-V x0-x31 naming
    reg [31:0] regs [0:31];

    // Loop variable for reset operation
    integer i;

    //==========================================================================
    // COMBINATIONAL READ PORTS (Zero latency)
    //==========================================================================
    // Both read ports are purely combinational, providing immediate access
    // to register contents. This simplifies pipeline timing and forwarding logic.
    assign o_rs1_data = regs[i_rs1_addr];
    assign o_rs2_data = regs[i_rs2_addr];

    //==========================================================================
    // SYNCHRONOUS WRITE PORT + RESET LOGIC
    //==========================================================================
    // - Asynchronous reset clears all registers to improve testability
    // - Synchronous write updates register on rising clock edge
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            // Asynchronous reset: clear all registers
            for (i = 0; i < 32; i = i + 1) 
                regs[i] <= 32'b0;
        end else if (i_we) begin
            // Synchronous write: update target register with new data
            regs[i_rd_addr] <= i_rd_data;
        end
    end

endmodule

////////////////////////////////////////////////////////////////////////////////
