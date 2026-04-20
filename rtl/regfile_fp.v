////////////////////////////////////////////////////////////////////////////////
//
// File: regfile_fp.v
// Module: regfile_fp
//
// Description:
//   RISC-V floating-point register file with 32 entries (f0-f31), each 32-bit.
//   Stores IEEE 754 single-precision floating-point values for FPU operands
//   and results. Provides dual combinational read ports and a single
//   synchronous write port, mirroring the integer register file architecture.
//
// Features:
//   - 32 registers × 32-bit IEEE 754 single-precision FP (total 1024 bits)
//   - Dual asynchronous read ports (combinational, zero latency)
//   - Single synchronous write port (writes on rising clock edge)
//   - Asynchronous active-low reset (clears all registers to 0)
//   - Registers f0-f31 are all writable (no read-only enforcement)
//
// IO Interface:
//   Inputs:
//     i_clk         : System clock (positive edge triggered for writes)
//     i_rst_n       : Active-low asynchronous reset
//     i_fs1_addr[4:0]: Source FP register 1 address (0-31)
//     i_fs2_addr[4:0]: Source FP register 2 address (0-31)
//     i_we          : Write enable (high to write on clock edge)
//     i_fd_addr[4:0] : Destination FP register address (0-31)
//     i_fd_data[31:0]: Write data [IEEE 754 single-precision FP]
//   Outputs:
//     o_fs1_data[31:0]: Data from register fs1_addr (combinational)
//     o_fs2_data[31:0]: Data from register fs2_addr (combinational)
//
// Notes:
//   - All 32 registers are writable (no architectural restrictions implemented)
//   - Stores IEEE 754 single-precision format but does not validate encoding
//   - Bypass logic required if FLW result must forward to next instruction
//
// Author: [Original Designer]
// Date: 2024
// Version: 1.0
//
////////////////////////////////////////////////////////////////////////////////

module regfile_fp (
    // ========== Clock and Reset ==========
    input         i_clk,           // System clock (positive edge for writes)
    input         i_rst_n,         // Active-low asynchronous reset

    // ========== Read Port 1 (Floating-Point) ==========
    input  [4:0]  i_fs1_addr,      // Source FP register 1 address
    output [31:0] o_fs1_data,      // Source FP register 1 data (combinational)

    // ========== Read Port 2 (Floating-Point) ==========
    input  [4:0]  i_fs2_addr,      // Source FP register 2 address
    output [31:0] o_fs2_data,      // Source FP register 2 data (combinational)

    // ========== Write Port (Synchronous, Floating-Point) ==========
    input         i_we,            // Write enable
    input  [4:0]  i_fd_addr,       // Destination FP register address
    input  [31:0] i_fd_data        // Write data [IEEE 754 SP format]
);

    //==========================================================================
    // FLOATING-POINT REGISTER STORAGE
    //==========================================================================
    // 32 registers, each 32 bits, storing IEEE 754 single-precision floats
    // Layout: [Sign(1) | Exponent(8) | Mantissa(23)]
    reg [31:0] fregs [0:31];

    // Loop variable for reset operation
    integer i;

    //==========================================================================
    // COMBINATIONAL READ PORTS (Zero latency)
    //==========================================================================
    // Both read ports are purely combinational, providing immediate access
    // to FP register contents. This enables fast feedback for dependencies
    // and simplifies pipeline forwarding.
    assign o_fs1_data = fregs[i_fs1_addr];
    assign o_fs2_data = fregs[i_fs2_addr];

    //==========================================================================
    // SYNCHRONOUS WRITE PORT + RESET LOGIC
    //==========================================================================
    // - Asynchronous reset clears all FP registers to 0.0 (all bits to 0)
    // - Synchronous write updates FP register on rising clock edge
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            // Asynchronous reset: clear all FP registers
            for (i = 0; i < 32; i = i + 1) 
                fregs[i] <= 32'b0;  // All bits to 0 (represents +0.0)
        end else if (i_we) begin
            // Synchronous write: update target FP register with new value
            fregs[i_fd_addr] <= i_fd_data;
        end
    end

endmodule

////////////////////////////////////////////////////////////////////////////////
