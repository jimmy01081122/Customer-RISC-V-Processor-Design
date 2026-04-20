# Custom RISC-V Processor Design
## A Learning-Oriented 32-bit Integer and Floating-Point Processor

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Instruction Set Architecture (ISA)](#instruction-set-architecture-isa)
4. [Module Hierarchy](#module-hierarchy)
5. [Memory Layout](#memory-layout)
6. [Design Specifications](#design-specifications)
7. [Building and Testing](#building-and-testing)
8. [Project Structure](#project-structure)
9. [Pin/Port Definitions](#pinport-definitions)
10. [Performance Characteristics](#performance-characteristics)
11. [Known Limitations](#known-limitations)
12. [Future Enhancements](#future-enhancements)
13. [References](#references)

---

## Overview

The **Custom RISC-V Processor** is a 32-bit educational processor implementing a subset of the RISC-V Instruction Set Architecture (ISA). Designed for clarity and learning, it features:

- **Non-pipelined 5-stage FSM** execution (FETCH → DECODE → EXECUTE → MEMORY → WRITEBACK)
- **32 integer registers** (x0-x31) for general computation
- **32 floating-point registers** (f0-f31) for IEEE 754 single-precision operations
- **Synthesizable RTL** in pure Verilog-2001 (compatible with all standard synthesis tools)
- **Comprehensive testbenches** for individual modules and integrated verification
- **Memory-based instruction/data storage** with address-based validation

### Target Applications

- **Educational use** in computer architecture courses
- **RTL design learning** and Verilog practice
- **RISC-V ISA exploration** and prototyping
- **Functional verification** and simulation

---

## Architecture

### High-Level Block Diagram

```
┌─────────────────────────────────────────────────────┐
│                    CORE (5-Stage FSM)               │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────┐  ┌─────────┐  ┌──────────┐          │
│  │  FETCH   │→ │ DECODE  │→ │  EXEC   │→ ...    │
│  └──────────┘  └─────────┘  └──────────┘          │
│      ↓            ↓              ↓                  │
│   Memory      Decoder      ALU / FPU               │
│              & RegFile    Branch Logic             │
│                                                     │
│   ┌──────────────┐        ┌────────────┐           │
│   │ Inst. Mem    │        │ Data Mem   │           │
│   │  (0-4K)      │        │  (4K-8K)   │           │
│   └──────────────┘        └────────────┘           │
│                                                     │
│   ┌──────────┬──────────┐                          │
│   │ Int Regs │ FP Regs  │                          │
│   │ (32 GPR) │ (32 FPR) │                          │
│   └──────────┴──────────┘                          │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Execution Model

The processor operates as a **non-pipelined state machine**, advancing one stage per clock cycle:

| Stage | Clock | Operation |
|-------|-------|-----------|
| **FETCH** | Cycle N | Place PC on addr bus; capture instruction from memory |
| **DECODE** | Cycle N+1 | Parse instruction, read register file, validate format |
| **EXEC** | Cycle N+2 | Execute ALU/FPU operations, compute branch targets |
| **MEM** | Cycle N+3 | Read/write data memory with address validation |
| **WB** | Cycle N+4 | Write back to register files, update PC, pulse status |

**Key Insight:** Each instruction takes exactly 5 clock cycles to complete. No pipelining overlap.

---

## Instruction Set Architecture (ISA)

### Supported Instructions (16 Total)

The processor implements a **subset of RV32I (RISC-V 32-bit Integer) + RV32F (Floating-Point)**.

#### 1. Primary Integer Arithmetic Instructions

| Instruction | Format | Operation | Encoding |
|-------------|--------|-----------|----------|
| **SUB** | R | `rd = rs1 - rs2` | `[funct7=32][rs2][rs1][funct3=0][rd][opcode=0x33]` |
| **ADDI** | I | `rd = rs1 + sign_ext(imm)` | `[imm12][rs1][0][rd][0x13]` |
| **SLT** | R | `rd = (rs1 < rs2) ? 1 : 0` (signed) | `[funct7=0][rs2][rs1][funct3=2][rd][0x33]` |
| **SRL** | R | `rd = rs1 >> rs2[4:0]` (logical) | `[funct7=0][rs2][rs1][funct3=5][rd][0x33]` |

#### 2. Memory Access Instructions

| Instruction | Format | Operation & Semantics | Encoding |
|-------------|--------|----------------------|----------|
| **LW** | I | Load 32-bit word from memory: `rd_int = M[rs1 + sign_ext(imm)]` | `[imm12][rs1][2][rd][0x03]` |
| **SW** | S | Store 32-bit word to memory: `M[rs1 + sign_ext(imm)] = rs2_int` | `[imm7][rs2][rs1][2][imm5][0x23]` |

**Address Validation:** 
- LW/SW addresses must fall in data memory range [0x1000, 0x1FFF]
- Out-of-range access triggers INVALID status and halts processor

#### 3. Control Flow Instructions (Branches & Jumps)

| Instruction | Format | Behavior | Encoding |
|-------------|--------|----------|----------|
| **BEQ** | B | Branch if equal: `PC = (rs1 == rs2) ? PC + imm : PC + 4` | `[imm12][rs2][rs1][0][imm5][0x63]` |
| **BLT** | B | Branch if less than (signed): `PC = (rs1 < rs2) ? PC + imm : PC + 4` | `[imm12][rs2][rs1][4][imm5][0x63]` |
| **JALR** | I | Jump and link: `rd = PC+4; PC = (rs1 + imm) & ~1` | `[imm12][rs1][0][rd][0x67]` |
| **AUIPC** | U | Add upper immediate to PC: `rd = PC + {imm[19:0], 12'b0}` | `[imm20][rd][0x17]` |

**Branch Encoding (B-Type Immediate):** 
- 12-bit signed, with LSB always 0 (implicit alignment)
- Computed as: `{imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode}`

#### 4. Floating-Point Arithmetic Instructions

| Instruction | Format | Operation | IEEE 754 Aspect | Encoding |
|-------------|--------|-----------|-----------------|----------|
| **FSUB** | R | `f_rd = f_rs1 - f_rs2` | Single-precision, rounding | `[funct7=0x04][rs2][rs1][0][rd][0x53]` |
| **FMUL** | R | `f_rd = f_rs1 × f_rs2` | Single-precision, rounding | `[funct7=0x08][rs2][rs1][0][rd][0x53]` |
| **FCVT.W.S** | R | `rd_int = convert_to_int(f_rs1, rounding_mode)` | Float-to-int with rounding | `[funct7=0x60][00000][rs1][0][rd][0x53]` |
| **FCLASS** | R | `rd_int = classify(f_rs1)` (10-bit mask) | Returns special value mask | `[funct7=0x70][00000][rs1][0][rd][0x53]` |

#### 5. Floating-Point Load/Store Instructions

| Instruction | Format | Operation | Encoding |
|-------------|--------|-----------|----------|
| **FLW** | I | Load FP word: `f_rd = M[rs1 + sign_ext(imm)]` | `[imm12][rs1][2][rd][0x07]` |
| **FSW** | S | Store FP word: `M[rs1 + sign_ext(imm)] = f_rs2` | `[imm7][rs2][rs1][2][imm5][0x27]` |

#### 6. Special Instructions

| Instruction | Format | Purpose | Encoding |
|-------------|--------|---------|----------|
| **EOF** | Special | End-of-file termination signal (halts processor) | `opcode = 0x73` |

### Instruction Formats

RISC-V uses five main encoding formats:

```
R-Type: [funct7(7) | rs2(5) | rs1(5) | funct3(3) | rd(5) | opcode(7)]
I-Type: [imm(12) | rs1(5) | funct3(3) | rd(5) | opcode(7)]
S-Type: [imm[11:5](7) | rs2(5) | rs1(5) | funct3(3) | imm[4:0](5) | opcode(7)]
B-Type: [imm[12|10:5](7) | rs2(5) | rs1(5) | funct3(3) | imm[4:1|11](5) | opcode(7)]
U-Type: [imm[31:12](20) | rd(5) | opcode(7)]
```

---

## Module Hierarchy

### Module Dependency Graph

```
core.v (top-level)
├── define.v (macro definitions, included)
├── decoder.v (combinational instruction decoder)
├── regfile_int.v (32×32-bit integer register file)
├── regfile_fp.v (32×32-bit floating-point register file)
├── alu_int.v (32-bit integer ALU)
└── fpu_unit.v (IEEE 754 single-precision FPU)

data_mem.vp (memory subsystem - protected)
```

### Module Specifications

#### 1. **define.v** - Global Definitions
- **Purpose:** Macro definitions for opcodes, funct fields, instruction types
- **Contents:**
  - Instruction type codes (`R_TYPE`, `I_TYPE`, `S_TYPE`, `B_TYPE`, `U_TYPE`, `INVALID_TYPE`, `EOF_TYPE`)
  - Opcode definitions (`OP_SUB`, `OP_ADDI`, `OP_LW`, etc.)
  - Funct7 field codes (`FUNCT7_SUB`, `FUNCT7_FSUB`, etc.)
  - Funct3 field codes (`FUNCT3_ADD`, `FUNCT3_LW`, etc.)
- **Status:** Read-only reference document. DO NOT MODIFY.

#### 2. **decoder.v** - Instruction Decoder
- **Type:** Combinational logic (zero-cycle latency)
- **Function:** Parses 32-bit instruction word and extracts:
  - Register addresses (rs1, rs2, rd)
  - Sign-extended immediates (I/S/B/U formats)
  - Operation code (16 variants: 0-15, 31 for INVALID)
  - Instruction type classification
  - FPU operation flag
- **Inputs:** `instr[31:0]` (32-bit instruction)
- **Outputs:** `rs1[4:0]`, `rs2[4:0]`, `rd[4:0]`, `imm[31:0]`, `op_kind[4:0]`, `instr_type[2:0]`, `is_fpu_op`
- **Usage:** Instantiated once in core.v

#### 3. **regfile_int.v** - Integer Register File
- **Type:** Synchronous memory with combinational read ports
- **Capacity:** 32 registers × 32 bits = 1 KB (RISC-V x0-x31)
- **Read Ports:** 2 asynchronous (combinational)
  - `i_rs1_addr[4:0]` → `o_rs1_data[31:0]` (zero latency)
  - `i_rs2_addr[4:0]` → `o_rs2_data[31:0]` (zero latency)
- **Write Port:** 1 synchronous
  - On rising clock with `i_we = 1`: `regs[i_rd_addr] ← i_rd_data`
- **Reset:** Asynchronous, active-low (`i_rst_n`)
- **Note:** x0 is writable (but semantics require x0 always reads 0 in real RISC-V)
- **Usage:** Instantiated once in core.v

#### 4. **regfile_fp.v** - Floating-Point Register File
- **Type:** Synchronous memory with combinational read ports
- **Capacity:** 32 registers × 32 bits = 1 KB (IEEE 754 single, f0-f31)
- **Architecture:** Identical to regfile_int.v
- **Read Ports:** 2 asynchronous (`i_fs1_addr`, `i_fs2_addr`)
- **Write Port:** 1 synchronous (`i_fd_addr`, `i_fd_data`)
- **Reset:** Asynchronous, active-low (`i_rst_n`)
- **Usage:** Instantiated once in core.v

#### 5. **alu_int.v** - Integer Arithmetic Logic Unit
- **Type:** Combinational logic (zero-cycle latency)
- **Operations:** 4 supported
  | Op Code | Operation | Example |
  |---------|-----------|---------|
  | 0 | ADD | 32-bit signed addition |
  | 1 | SUB | 32-bit signed subtraction |
  | 2 | SLT | Signed comparison (rd = rs1 < rs2 ? 1 : 0) |
  | 3 | SRL | Logical right shift (rd = rs1 >> rs2[4:0]) |
- **Overflow Handling:** Saturation to min/max 32-bit signed values
  - On ADD/SUB overflow: `o_overflow` pulse high, result saturated
  - `o_overflow` always low for SLT/SRL
- **Inputs:** `i_op[2:0]`, `i_a[31:0]`, `i_b[31:0]`
- **Outputs:** `o_result[31:0]`, `o_overflow`
- **Usage:** Instantiated once in core.v

#### 6. **fpu_unit.v** - Floating-Point Unit
- **Type:** Combinational logic (zero-cycle latency)
- **IEEE 754 Format:** Single-precision (32-bit)
  - `[Sign(1) | Exponent(8) | Mantissa(23)]`
  - Bias: 127 (exponent range -126 to 127)
- **Operations:** 4 supported
  | Op Code | Operation | Rounding |
  |---------|-----------|----------|
  | 0 | FSUB | Round-to-nearest-even (banker's rounding) |
  | 1 | FMUL | Round-to-nearest-even |
  | 2 | FCVT.W.S | Convert to signed int with rounding |
  | 3 | FCLASS | Classify special values (10-bit output) |
- **FCLASS Output Bits:**
  - `[0]`: Negative infinity
  - `[1]`: Negative normal number
  - `[2]`: Negative subnormal
  - `[3]`: Negative zero
  - `[4]`: Positive zero
  - `[5]`: Positive subnormal
  - `[6]`: Positive normal number
  - `[7]`: Positive infinity
  - `[8]`: Signaling NaN
  - `[9]`: Quiet NaN
- **Exception Flags:**
  - `o_invalid`: High if NaN or infinity encountered
  - `o_overflow`: High if exponent overflow (→ ±∞)
  - `o_underflow`: High if exponent underflow (→ ±0)
- **Special Value Handling:**
  - NaN propagation: Any NaN operand → result = 0, `o_invalid` pulse high
  - Infinity handling: INF ± number → INF, not rounded
  - Denormalized numbers: Flushed to zero
- **Inputs:** `i_op[1:0]`, `i_a[31:0]`, `i_b[31:0]`
- **Outputs:** `o_result[31:0]`, `o_invalid`, `o_overflow`, `o_underflow`
- **Usage:** Instantiated once in core.v

#### 7. **core.v** - Main Processor Core
- **Type:** Sequential logic (5-stage FSM)
- **State Count:** 6 states
  - `ST_FETCH` (0): Issue instruction fetch
  - `ST_DECODE` (1): Parse instruction, capture operands
  - `ST_EXEC` (2): Execute ALU/FPU, compute branches
  - `ST_MEM` (3): Access data memory
  - `ST_WB` (4): Write back, advance PC, pulse status
  - `ST_HALT` (5): Hold after EOF or INVALID
- **Pipeline Depth:** 5 stages = 5 clock cycles per instruction (non-pipelined)
- **Inputs:**
  - Clock/Reset: `i_clk`, `i_rst_n`
  - Memory data: `i_rdata[31:0]` (instruction/data)
- **Outputs:**
  - Memory control: `o_addr[31:0]`, `o_wdata[31:0]`, `o_we`
  - Status: `o_status[2:0]`, `o_status_valid` (pulse)
  - Debug: Register addresses, values, ALU result, FSM state

---

## Memory Layout

### Address Map

```
┌─────────────────────────────────────┐
│ Instruction Memory (I-Mem)          │
│ Base: 0x0000_0000                   │
│ Size: 4 KB (0x1000 bytes)           │
│ Valid Addresses: 0x0000 - 0x0FFF    │
└─────────────────────────────────────┘
                ↑
        (stored externally)
                
        ┌─────────┐
        │ Core    │
        └─────────┘
                ↓
┌─────────────────────────────────────┐
│ Data Memory (D-Mem)                 │
│ Base: 0x0000_1000 (0x1000)          │
│ Size: 4 KB (0x1000 bytes)           │
│ Valid Addresses: 0x1000 - 0x1FFF    │
└─────────────────────────────────────┘
```

**Unified Memory Interface:**
- Single address bus (`o_addr[31:0]`) for both instruction and data access
- Single read data bus (`i_rdata[31:0]`)
- Single write data bus (`o_wdata[31:0]`) + write enable (`o_we`)
- Memory arbitration handled by external controller

**Address Validation:**
- **Instruction fetch:** PC must be in range [0x0000, 0x0FFF]
  - Out-of-range → INVALID status, halt
- **Load/Store:** Effective address must be in range [0x1000, 0x1FFF]
  - Out-of-range → INVALID status, halt

---

## Design Specifications

### Physical Specifications

| Parameter | Value | Notes |
|-----------|-------|-------|
| **Data Width** | 32 bits | IEEE 754 single-precision FP, 32-bit signed integer |
| **Address Width** | 32 bits | Full 32-bit address space (practical usage: 13 bits) |
| **Register Count** | 64 | 32 integer + 32 floating-point |
| **Memory Size (Modeled)** | 8 KB | 4 KB instruction + 4 KB data (in simulation) |
| **Clock Signal** | Positive edge | Synchronous design, all state changes on rising clock |
| **Reset Signal** | Asynchronous, active-low | `i_rst_n = 0` → RESET, `i_rst_n = 1` → RUN |

### Timing Specifications

| Metric | Value | Conditions |
|--------|-------|-----------|
| **Instruction Latency** | 5 cycles | One cycle per pipeline stage |
| **CPI (Cycles Per Instruction)** | 5 | Non-pipelined execution |
| **Register Read Latency** | Combinational | From address change to data valid |
| **Register Write Latency** | 1 cycle | Synchronous, updated on next rising clock |
| **ALU Latency** | Combinational | Purely combinational, zero gate delay |
| **FPU Latency** | Combinational | No iteration (not single-cycle friendly for some ops) |

### Throughput Specifications

| Metric | Value | Assumptions |
|--------|-------|-------------|
| **Maximum Frequency** | Design-dependent | Typical: 50-100 MHz in 28nm or above |
| **Instructions Per Cycle (IPC)** | 0.2 | = 1 instruction / 5 cycles (non-pipelined) |
| **Peak Integer Ops/Sec** | f_clk × 0.2 | e.g., 100 MHz → 20 MIPS |
| **Peak FP Ops/Sec** | f_clk × 0.2 | e.g., 100 MHz → 20 MFLOPS (app-dependent) |

### Accuracy Specifications (Floating-Point)

| Property | Standard | Implementation |
|----------|----------|-----------------|
| **Rounding Mode** | IEEE 754 | Round-to-nearest-even (banker's rounding) |
| **Mantissa Precision** | 24 bits (implicit +1) | Standard single-precision |
| **Exponent Range** | -126 to +127 (unbiased) | Bias = 127 |
| **Subnormal Handling** | Flush-to-zero | Denormalized numbers truncate to ±0 |
| **NaN Propagation** | Quiet (no signaling) | Signaling NaN treated as quiet NaN |
| **Infinity Arithmetic** | INF ± finite = INF | Propagates infinity through operations |

---

## Building and Testing

### Environment Requirements

- **Simulation:** Icarus Verilog (iverilog) or equivalent (Modelsim, VCS, Xcelium)
- **Synthesis:** Yosys, Vivado, or equivalent
- **Programming Language:** Verilog-2001 (pure, no SystemVerilog)
- **Build System:** Makefile (provided in `scripts/`)

### Compilation and Simulation

#### Single Module Test (Example: ALU)

```bash
cd /path/to/Customer-RISC-V-Processor-Design
make -f scripts/Makefile test_alu    # Run ALU testbench
```

#### Full System Test

```bash
cd /path/to/Customer-RISC-V-Processor-Design
make -f scripts/Makefile test_all    # Run all tests
```

#### Manual Simulation

```bash
# Compile RTL and testbench
iverilog -o sim rtl/*.v tb/tb_core.v

# Run simulation
vvp sim

# View waveforms (if VCD generated)
gtkwave tb_core.vcd
```

### Expected Test Results

**Success Criteria:**
- All testbenches complete without errors
- Status signals correctly pulse for each executed instruction
- Register files update correctly after writeback
- ALU results match expected computation
- FPU results match IEEE 754 standard (within rounding tolerance)

---

## Project Structure

```
Customer-RISC-V-Processor-Design/
├── rtl/                          # RTL source files
│   ├── define.v                  # Global macro definitions
│   ├── core.v                    # Main processor core (5-stage FSM)
│   ├── decoder.v                 # Instruction decoder
│   ├── alu_int.v                 # 32-bit integer ALU
│   ├── fpu_unit.v                # IEEE 754 FPU
│   ├── regfile_int.v             # Integer register file
│   ├── regfile_fp.v              # Floating-point register file
│   └── data_mem.vp               # Data memory (protected)
│
├── tb/                           # Testbenches
│   ├── tb_alu_int.v              # ALU testbench
│   ├── tb_decoder.v              # Decoder testbench
│   ├── tb_fpu_unit.v             # FPU testbench
│   ├── tb_regfile.v              # Register file testbench
│   └── testbed_temp.v            # Integration testbench
│
├── scripts/                      # Build and utility scripts
│   ├── run_tests.sh              # Execute all tests
│   ├── clean.sh                  # Remove build artifacts
│   └── push_to_github.sh         # Git management (if applicable)
│
├── doc/                          # Documentation
│   └── (this README would go here)
│
└── README.md                     # This file
```

---

## Pin/Port Definitions

### Core Module (core.v) Pin List

#### Clock and Reset

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `i_clk` | Input | 1 | System clock (positive edge triggered) |
| `i_rst_n` | Input | 1 | Asynchronous reset, active-low (0 = reset, 1 = run) |

#### Memory Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `o_addr` | Output | 32 | Address for fetch/load/store (valid 13 bits used) |
| `i_rdata` | Input | 32 | Read data (instruction or memory content) |
| `o_wdata` | Output | 32 | Write data for store operations |
| `o_we` | Output | 1 | Write enable (1 = store, 0 = load/fetch) |

#### Status Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `o_status` | Output | 3 | Instruction type on completion (R/I/S/B/U/INVALID/EOF) |
| `o_status_valid` | Output | 1 | One-cycle pulse when instruction completes |

#### Debug/Test Ports

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `c_state` | Output | 5 | Current FSM state (0-5) for debugging |
| `o_alu_result` | Output | 32 | ALU result (for inspection) |
| `rs1_address`, `rs1_data` | Output | 5, 32 | RS1 register address and value |
| `rs2_address`, `rs2_data` | Output | 5, 32 | RS2 register address and value |
| `rd_address` | Output | 5 | Destination register address |
| `rd_data_i`, `rd_data_f` | Output | 32 | Integer and FP write-back data |

---

## Performance Characteristics

### Execution Performance

**Integer Operations:**
- ADD/SUB/SLT/SRL: 5 cycles per instruction
- Throughput: @ 100 MHz → 20 MIPS (Integer)

**Floating-Point Operations:**
- FSUB/FMUL: 5 cycles per instruction (not single-cycle friendly)
- FCVT.W.S: 5 cycles per instruction
- FCLASS: 5 cycles per instruction
- Throughput: @ 100 MHz → 20 MFLOPS

**Memory Operations:**
- LW/SW: 5 cycles per instruction (pipeline stages required)
- No caching, direct memory access
- Throughput: @ 100 MHz → 20 Mword/s

### Feature Efficiency

| Metric | Value | Observations |
|--------|-------|--------------|
| **Instruction Density** | 32-bit encoding | No RISC-V compressed (16-bit) format |
| **Register Utilization** | 62 registers total | 32 int + 32 FP (x0 and f0-f31) |
| **Memory Efficiency** | 8 KB simulated | Practical: 4 KB instr + 4 KB data |
| **Logic Complexity** | ~5,000 gates | Rough estimate for RTL synthesis |

### Power Considerations (Theoretical)

**Dynamic Power:** Proportional to frequency and activity
- Estimated toggle rate: ~20% (typical RISC workload)
- Expected power @ 100 MHz, 28nm: ~100 mW (active), <1 mW (idle)

**Leakage Power:** <10% of dynamic at 28nm

---

## Known Limitations

### Architectural Limitations

1. **No Pipelining:** 5-cycle latency per instruction limits throughput to 0.2 IPC
   - **Workaround:** Instruction-level parallelism impossible; consider pipelined version

2. **No Branch Prediction:** All branch mispredicts suffer full 5-cycle latency
   - **Workaround:** Use `JALR` for dynamic branching when possible

3. **No Cache:** All memory accesses go directly to main memory
   - **Impact:** Memory-intensive code sees stalls on slow memory
   - **Workaround:** Arrange data access patterns for locality

4. **No Dynamic Scheduling:** Instructions execute in strict order
   - **Impact:** Resource stalls are not hidden
   - **Workaround:** Compiler must schedule around dependencies

### ISA Subset Limitations

1. **Integer-Only:** No multiply/divide (DIV, MUL) instructions
2. **FP-Only:** No double-precision (RV64D) support
3. **Control-Only:** No interrupts, exceptions, or privilege modes
4. **No Atomics:** No load-link/store-conditional (LR/SC)
5. **No Compressed ISA:** No 16-bit instruction encoding

### Implementation Limitations

1. **Synthesizable Only:** Non-synthesizable constructs (e.g., `$fopen`, `$display` in RTL scope) removed
2. **Verilog-2001:** No SystemVerilog features (interfaces, classes, constraints)
3. **Simulation-Only:** Requires external testbench for full verification

---

## Future Enhancements

### Near-Term (Educational)

- [ ] Add multiply/divide (MUL, DIV, REM) instructions
- [ ] Implement simple branch predictor (BHT or GShare)
- [ ] Add compressed instruction format (16-bit RVC)
- [ ] Include privilege modes and CSR (Control/Status Register) support

### Medium-Term (Industrial)

- [ ] Implement classic 5-stage pipeline with hazard forwarding
- [ ] Add instruction and data caches (L1 cache hierarchy)
- [ ] Support for exceptions and vectored interrupts
- [ ] Add performance counters and debug interface

### Long-Term (Advanced)

- [ ] Out-of-order execution with ROB (Reorder Buffer)
- [ ] Complex branch prediction (tournament predictor)
- [ ] Multi-level cache hierarchy with coherence
- [ ] Simultaneous multithreading (SMT) or heterogeneous cores
- [ ] RV64 (64-bit) extension support

---

## References

### Official RISC-V Documentation

1. **RISC-V Unprivileged ISA Specification (v20191213)**
   - https://riscv.org/specifications/
   - Covers RV32I, RV32F, instruction encodings

2. **RISC-V Privileged ISA Specification (v20190608)**
   - Machine-mode CSRs, exception handling, privilege levels

3. **SiFive Core IP Generators**
   - https://www.sifive.com/
   - Reference implementations for inspiration

### IEEE Floating-Point Standards

4. **IEEE 754-2019: Standard for Floating-Point Arithmetic**
   - Single-precision format, rounding modes, special values
   - Available from IEEE xplore.ieee.org

5. **Hakmem Floating-Point Tricks**
   - Common techniques for FP math in hardware

### Verilog and Hardware Design

6. **Verilog-2001 LRM (Language Reference Manual)**
   - Syntax, semantics, behavioral simulation
   - Available from IEEE or Accellera (now Cadence)

7. **Verilator and Open-Source Simulation**
   - https://www.veripool.org/
   - Fast SystemC/C++ simulation backend for Verilog

### Educational Resources

8. **Patterson & Hennessy: "Computer Organization and Design"**
   - Comprehensive processor design fundamentals
   - RISC-V edition available

9. **Harris & Harris: "Digital Design and Computer Architecture"**
   - RTL design methodology, FSM design patterns

---

## License and Attribution

This processor design is provided for **educational purposes**. All RTL code is written from documentation and first principles; any resemblance to existing designs is coincidental.

**Modifications and derivatives are encouraged** for learning. Please credit the original designer and update documentation as needed.

---

## Contact and Support

For questions or issues:

1. **GitHub Issues:** Report bugs and feature requests
2. **Documentation:** Refer to inline code comments and module specifications
3. **Simulation:** Use provided testbenches as reference for correct usage

---

**Document Version:** 1.0  
**Last Updated:** April 2024  
**Author:** [Original RTL Designer]
