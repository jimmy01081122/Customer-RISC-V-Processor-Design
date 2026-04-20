////////////////////////////////////////////////////////////////////////////////
//
// File: define.v
// Module: N/A (Global Macro Definitions)
//
// Description:
//   Central definition file containing all macro constants used throughout the
//   RISC-V processor design. This includes instruction type classifications,
//   opcode definitions, and functional code definitions for instruction decoding.
//   DO NOT MODIFY - These definitions are critical for processor operation.
//
// Author: [Original Designer]
// Date: 2024
// Version: 1.0
//
////////////////////////////////////////////////////////////////////////////////

// DO NOT MODIFY THIS FILE

//==============================================================================
// INSTRUCTION TYPE CLASSIFICATION MACROS
//==============================================================================
// These macros classify RISC-V instruction formats as defined in the spec.
// Each type represents a different instruction encoding format.

`define R_TYPE        0    // R-Type: Register-to-register operations (func7, rs2, rs1, func3, rd, opcode)
`define I_TYPE        1    // I-Type: Immediate operations (imm[11:0], rs1, func3, rd, opcode)
`define S_TYPE        2    // S-Type: Store operations (imm[11:5], rs2, rs1, func3, imm[4:0], opcode)
`define B_TYPE        3    // B-Type: Branch operations (imm[12|10:5], rs2, rs1, func3, imm[4:1|11], opcode)
`define U_TYPE        4    // U-Type: Upper immediate (imm[31:12], rd, opcode)
`define INVALID_TYPE  5    // Invalid or unrecognized instruction type - triggers processor halt
`define EOF_TYPE      6    // End-of-file marker instruction - graceful termination signal

//==============================================================================
// OPCODE DEFINITIONS (7-bit values from bits [6:0] of instruction)
//==============================================================================
// Standard RISC-V opcodes for different instruction classes.
// These identify the primary instruction type in the fetch/decode stage.

// Integer Arithmetic and Logic Operations
`define OP_SUB    7'b0110011  // SUB, SLT, SRL operations (R-type, further decoded via funct7/funct3)
`define OP_ADDI   7'b0010011  // ADDI and I-type ALU operations with immediate operand
`define OP_AUIPC  7'b0010111  // Add Upper Immediate to PC (U-type, used for address generation)

// Memory Access Operations (Load/Store)
`define OP_LW     7'b0000011  // Load Word from data memory into integer register (32-bit)
`define OP_SW     7'b0100011  // Store Word to data memory from integer register (32-bit)

// Conditional Branch Operations
`define OP_BEQ    7'b1100011  // Branch Equal (also hosts BLT, further decoded via funct3)
`define OP_BLT    7'b1100011  // Branch Less Than (signed comparison)

// Unconditional Jump Operations
`define OP_JALR   7'b1100111  // Jump and Link Register (indirect jump with return address save)

// Floating-Point Arithmetic Operations
`define OP_FSUB   7'b1010011  // Floating-point subtract (funct7=0100000)
`define OP_FMUL   7'b1010011  // Floating-point multiply   (funct7=0001000)
`define OP_FCVTWS 7'b1010011  // Float to Word conversion  (funct7=1100000)
`define OP_FCLASS 7'b1010011  // Floating-point class      (funct7=1110000)

// Floating-Point Load/Store Operations
`define OP_FLW    7'b0000111  // Floating-point Load Word into FP register
`define OP_FSW    7'b0100111  // Floating-point Store Word from FP register

// Special Operations
`define OP_EOF    7'b1110011  // End-of-file termination signal (halts processor gracefully)

//==============================================================================
// FUNCTION CODE 7 (funct7) DEFINITIONS
//==============================================================================
// Additional function codes (bits [31:25]) to further distinguish R-type instructions
// when they share the same opcode. Critical for distinguishing floating-point variants.

`define FUNCT7_SUB    7'b0100000  // Subtraction operation (vs. addition in R-type)
`define FUNCT7_SLT    7'b0000000  // Set Less Than (signed comparison)
`define FUNCT7_SRL    7'b0000000  // Shift Right Logical

// Floating-point arithmetic variants (all under opcode 7'b1010011)
`define FUNCT7_FSUB   7'b0000100  // Floating-point subtract operation
`define FUNCT7_FMUL   7'b0001000  // Floating-point multiply operation
`define FUNCT7_FCVTWS 7'b1100000  // Convert float to signed 32-bit word (with rounding)
`define FUNCT7_FCLASS 7'b1110000  // Classify floating-point value (special, quiet NaN, etc.)

//==============================================================================
// FUNCTION CODE 3 (funct3) DEFINITIONS
//==============================================================================
// Function codes (bits [14:12]) that distinguish operations within the same opcode.
// Also used for specifying memory access width and branch condition codes.

// Integer Arithmetic Operations (within R-type with OP_SUB)
`define FUNCT3_SUB    3'b000   // Subtraction (used with funct7=0100000)
`define FUNCT3_ADDI   3'b000   // Add Immediate
`define FUNCT3_SLT    3'b010   // Set Less Than (signed comparison, returns 1 or 0)
`define FUNCT3_SRL    3'b101   // Shift Right Logical by amount in rs2[4:0]

// Memory Access Operations (specifying access width)
`define FUNCT3_LW     3'b010   // Load Word (32-bit access, sign-extend to 32 bits)
`define FUNCT3_SW     3'b010   // Store Word (32-bit write to memory)

// Branch Operations - Condition codes (within B-type)
`define FUNCT3_BEQ    3'b000   // Branch if Equal (rs1 == rs2)
`define FUNCT3_BLT    3'b100   // Branch if Less Than (signed: rs1[31]=1 < rs2[31]=1)

// Jump Operation
`define FUNCT3_JALR   3'b000   // Jump and Link Register (computes new address from rs1+imm)

// Floating-point Operations (mostly use funct3=000)
`define FUNCT3_FSUB   3'b000   // Floating-point subtract
`define FUNCT3_FMUL   3'b000   // Floating-point multiply
`define FUNCT3_FCVTWS 3'b000   // Float to Word conversion
`define FUNCT3_FCLASS 3'b000   // Floating-point class query
`define FUNCT3_FLW    3'b010   // Floating-point Load Word (32-bit)
`define FUNCT3_FSW    3'b010   // Floating-point Store Word (32-bit)

////////////////////////////////////////////////////////////////////////////////

