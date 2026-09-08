`timescale 1ns / 100ps

module ALU 
(
	input   wire    [15:0]          A_i,
	input   wire    [15:0]          B_i,
	input   wire    [3:0]           OP_i,
	input   wire                    C_i,
	
	output  wire     [15:0]         F_o,
	output  wire                    C_o
);
	
	// TODO : If your module and its pin have different OP_CODE, you should change the mapping.
	localparam  OP_ADD  = 4'b0000,
				OP_SUB  = 4'b0001,
				OP_ID   = 4'b1000,
				OP_NAND = 4'b1001, 
				OP_NOR  = 4'b1010,
				OP_XNOR = 4'b1011,
				OP_NOT  = 4'b1100,
				OP_AND  = 4'b1101, 
				OP_OR   = 4'b1110,
				OP_XOR  = 4'b1111,
				OP_LRS  = 4'b0010,
				OP_ARS  = 4'b0100,
				OP_RR   = 4'b0110,
				OP_LLS  = 4'b0011,
				OP_ALS  = 4'b0101,
				OP_RL   = 4'b0111;
	
	
	// TODO: Implement ALU


endmodule