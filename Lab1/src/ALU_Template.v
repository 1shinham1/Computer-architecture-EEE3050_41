`timescale 1ns / 100ps

module ALU 
(
	input   wire    [15:0]          A_i,
	input   wire    [15:0]          B_i,
	input   wire    [3:0]           OP_i,
	input   wire                    C_i, // Carry in / Borrow in
	
	output  wire     [15:0]         F_o, // Function
	output  wire                    C_o // Carry out / Borrow out
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
				OP_RL   = 4'b0111; //16bit, 16명령어 수행
	
	
	// TODO: Implement ALU

	// 17-bit results : bit[16] is the carry-out (ADD) / borrow-out (SUB)
	wire [16:0] add_result = {1'b0, A_i} + {1'b0, B_i} + {16'b0, C_i};
	wire [16:0] sub_result = {1'b0, A_i} - {1'b0, B_i} - {16'b0, C_i};

	reg  [15:0] F_r; //	16bit
	reg         C_r; //	 1bit

	always @(*) begin
		case (OP_i)
			// ---------------- Arithmetic
			OP_ADD  : {C_r, F_r} = add_result;
			OP_SUB  : {C_r, F_r} = sub_result;

			// ---------------- Bitwise Boolean : C_o = 0 (1'b0)
			OP_ID   : {C_r, F_r} = {1'b0,   A_i};
			OP_NAND : {C_r, F_r} = {1'b0, ~(A_i &  B_i)};
			OP_NOR  : {C_r, F_r} = {1'b0, ~(A_i |  B_i)};
			OP_XNOR : {C_r, F_r} = {1'b0,  (A_i ~^ B_i)};
			OP_NOT  : {C_r, F_r} = {1'b0,  ~A_i};
			OP_AND  : {C_r, F_r} = {1'b0,  (A_i &  B_i)};
			OP_OR   : {C_r, F_r} = {1'b0,  (A_i |  B_i)};
			OP_XOR  : {C_r, F_r} = {1'b0,  (A_i ^  B_i)};

			// ---------------- Shift / Rotate by 1 bit : C_o = 0 (1'b0)
			// 오른쪽
			OP_LRS  : {C_r, F_r} = {1'b0, 1'b0,      A_i[15:1]};  // logical  right shift
			OP_ARS  : {C_r, F_r} = {1'b0, A_i[15],   A_i[15:1]};  // arithmetic right shift (sign extend)
			OP_RR   : {C_r, F_r} = {1'b0, A_i[0],    A_i[15:1]};  // rotate right
			// 왼쪽
			OP_LLS  : {C_r, F_r} = {1'b0, A_i[14:0], 1'b0};       // logical  left shift
			OP_ALS  : {C_r, F_r} = {1'b0, A_i[14:0], 1'b0};       // arithmetic left shift
			OP_RL   : {C_r, F_r} = {1'b0, A_i[14:0], A_i[15]};    // rotate left

			default : {C_r, F_r} = 17'b0;
		endcase
	end

	assign F_o = F_r;
	assign C_o = C_r;

endmodule
