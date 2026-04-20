`timescale 1ns/100ps
`define CYCLE       10.0
`define HCYCLE      (`CYCLE/2)
`define MAX_CYCLE   12
`define RST_DELAY 2.0

`ifdef p0
    `define Inst 	"../00_TB/PATTERN/p0/inst.dat"
	`define OSTATUS "../00_TB/PATTERN/p0/status.dat"
	`define ODATA 	"../00_TB/PATTERN/p0/data.dat"
	`define MEM_LEN 2048
`elsif p1
    `define Inst 	"../00_TB/PATTERN/p1/inst.dat"
	`define OSTATUS "../00_TB/PATTERN/p1/status.dat"
	`define ODATA 	"../00_TB/PATTERN/p1/data.dat"
	`define MEM_LEN 2048
`elsif p2
	`define Inst 	"../00_TB/PATTERN/p2/inst.dat"
	`define OSTATUS "../00_TB/PATTERN/p2/status.dat"
	`define ODATA 	"../00_TB/PATTERN/p2/data.dat"
	`define MEM_LEN 2048
`elsif p3
	`define Inst 	"../00_TB/PATTERN/p3/inst.dat"
	`define OSTATUS "../00_TB/PATTERN/p3/status.dat"
	`define ODATA 	"../00_TB/PATTERN/p3/data.dat"
	`define MEM_LEN 2048
`else
	`define Inst 	"../00_TB/PATTERN/p0/inst.dat"
	`define OSTATUS "../00_TB/PATTERN/p0/status.dat"
	`define ODATA 	"../00_TB/PATTERN/p0/data.dat"
	`define MEM_LEN 2048
`endif

module testbed #(
	parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
) ();

//ports
	reg  rst_n;
	reg  clk = 0;
	wire            dmem_we;
	wire [ 31 : 0 ] dmem_addr;
	wire [ 31 : 0 ] dmem_wdata;
	wire [ 31 : 0 ] dmem_rdata;
	wire [  2 : 0 ] mips_status;
	wire            mips_status_valid;

// TB variables
    // reg                        valid_seq   [0:`SEQ_LEN-1];

    // reg  [ INST_W+2*DATA_W-1:0] input_data  [0:`PAT_LEN-1];
    reg [	DATA_WIDTH-1:0] golden_data [0:`MEM_LEN-1];
	reg	[	2:0]			golden_status[0:`MEM_LEN-1];
	reg	[	2:0]			output_status_log[0:`MEM_LEN-1];
	integer i, j, cycle_count, record_count, output_end, errors, total_errors;

	wire [4:0] c_state;
// read data
    initial begin
        // $readmemb(`IDATA, input_data);
        $readmemb(`ODATA, golden_data);
		$readmemb(`OSTATUS, golden_status);
    end

	wire signed [31:0] alu_check;
	core u_core (
		.i_clk(clk),
		.i_rst_n(rst_n),
		.o_status(mips_status),
		.o_status_valid(mips_status_valid),
		.o_we(dmem_we),
		.o_addr(dmem_addr),
		.o_wdata(dmem_wdata),
		.i_rdata(dmem_rdata),
		.c_state(c_state),
		.o_alu_result(alu_check)
	);
 

	data_mem  u_data_mem (
		.i_clk(clk),
		.i_rst_n(rst_n),
		.i_we(dmem_we),
		.i_addr(dmem_addr),
		.i_wdata(dmem_wdata),
		.o_rdata(dmem_rdata)
	);
	integer clock ;
	initial begin
       $fsdbDumpfile("alu.fsdb");
       $fsdbDumpvars(0, testbed, "+mda");
	   clock = 0;
    end
    
	always #(`HCYCLE) clk = ~clk;

	always @(negedge clk) begin
		clock = clock+1;
	end
	// load data memory
	initial begin
		// initialization
		rst_n = 1;
		output_end = 0;
		#(0.25 * `CYCLE) rst_n = 0;
		#(`CYCLE) rst_n = 1;
		$readmemb (`Inst, u_data_mem.mem_r);
		// should record o_status

		cycle_count  = 0;
		record_count = 0;

		while (cycle_count < `MAX_CYCLE) begin
			@(negedge clk);
			$display ("clock : %0d",clock);
			$display ("o_status : %0d",mips_status);
			$display ("o_status_valid : %0d",mips_status_valid);
			$display ("o_addr : %0d",dmem_addr);
			$display ("i_rdata : %32b",dmem_rdata);
			$display ("o_wdata : %0d",dmem_wdata);
			$display ("c_state : %0d",c_state);
			$display ("alu_result : %0d",alu_check);
			$display ("we : %0d",dmem_we);

			cycle_count = cycle_count + 1;

			// 若 o_status_valid 為高 -> 記錄 o_status
			if (mips_status_valid) begin
				output_status_log[record_count] = mips_status;
				record_count = record_count + 1;
			end

			// 若遇到 EOF -> 跳出監控
			if (mips_status_valid && mips_status == `EOF_TYPE) begin
				$display("[TB] EOF detected at output %0d", record_count-1);
				break;
			end else if (mips_status_valid && mips_status == `INVALID_TYPE) begin
				$display("[TB] INVALID detected at output %0d", record_count-1);
				break;
			end
		end

		if (cycle_count >= `MAX_CYCLE) begin
			$display("[TB][ERROR] Time Limit Exceeded after %0d cycles!", `MAX_CYCLE);
			$display("Compute finished, start validating o_status result...");
			validate_status();
			$finish;
		end

		@(negedge clk);
		output_end = 1;
		// check output
	end

    // Result
    initial begin
		$readmemb (`Inst, u_data_mem.mem_r);
        wait (output_end);
		

        $display("Compute finished, start validating o_status result...");
		validate_status();
		$display("o_status validation finished, start validating memeory result...");
        validate_memory();
        $display("Simulation finish");
        # (2 * `CYCLE);
        $finish;
    end

	task validate_memory; 
        total_errors = 0;
        // $display("===============================================================================");
        // $display("Instruction: %b", input_data[0][2*DATA_W +: INST_W]);
        // $display("===============================================================================");

        
		total_errors = 0;
        for(i = 0; i < `MEM_LEN; i = i + 1) begin
			errors = 0;
			// if(i < 1024) begin
			// 	if(golden_data[i] !== u_data_mem.mem_r[i]) begin
			// 		$display("[ERROR  ]   [%d] Your Result:%32b Golden:%32b", i, u_data_mem.mem_r[i], golden_data[i]);
			// 		errors = 1;
			// 	end
			// end else begin
			if(golden_data[i] !== u_data_mem.mem_r[i]) begin
				$display("[ERROR  ]   [%d] Your Result:%32b Golden:%32b", i, u_data_mem.mem_r[i], golden_data[i]);
				errors = 1;
			end else begin
				// Does not print
				if(i > 1023 && golden_data[i] != 32'b0)
                	$display("[CORRECT]   [%d] Your Result:%32b Golden:%32b", i, u_data_mem.mem_r[i], golden_data[i]);
            end
			total_errors = total_errors + errors;
		end
			// if(errors == 0)
			// 	$display("Data             [PASS]");
			// else
			// 	$display("Data             [FAIL]");
				
			if(total_errors == 0)
				$display(">>> Congratulation! All result are correct");
			else
				$display(">>> There are %d errors QQ", total_errors);
				
			$display("===============================================================================");
    endtask

	task validate_status; 

        errors = 0;
        for(j = 0; j < record_count; j = j + 1) begin
            if(golden_status[j] !== output_status_log[j]) begin
                $display("[ERROR  ]   [%d] Your Result:%3b Golden:%3b", j, output_status_log[j], golden_status[j]);
                errors = errors + 1;
            end else begin
				// Does not print
                $display("[CORRECT]   [%d] Your Result:%3b Golden:%3b", j, output_status_log[j], golden_status[j]);
            end


    	end
		if(errors == 0)
			$display(">>> Congratulation! All result are correct");
		else
			$display(">>> There are %d errors QQ", total_errors);
				
		$display("===============================================================================");
    endtask
endmodule