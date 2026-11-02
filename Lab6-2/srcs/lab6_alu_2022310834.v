`include "lab6_opcodes_2022310834.v"

module ALU (
    input   wire    [15:0]          A_i,
	input   wire    [15:0]          B_i,
	input   wire    [4:0]           OP_i,      // Lab5 수정: 4bit -> 5bit (`ALU_OP_*)
	input   wire                    C_i,

	output  wire     [15:0]         F_o,
	output  wire                    C_o,
	output  wire                    bcond_o    // Lab5 추가: branch 조건 (NE/EQ/GZ/LZ 결과)
);
    // Lab5 수정: 4bit localparam -> opcodes.v 의 5bit `ALU_OP_* 값 사용 (기존 16개는 MSB = 0)
	// Arithmetic
	localparam  OP_ADD  = `ALU_OP_ADD;
	localparam  OP_SUB  = `ALU_OP_SUB;
	//  Bitwise Boolean operation
	localparam  OP_ID   = `ALU_OP_ID;
	localparam  OP_NAND = `ALU_OP_NAND;
	localparam  OP_NOR  = `ALU_OP_NOR;
	localparam  OP_XNOR = `ALU_OP_XNOR;
	localparam  OP_NOT  = `ALU_OP_NOT;
	localparam  OP_AND  = `ALU_OP_AND;
	localparam  OP_OR   = `ALU_OP_OR;
	localparam  OP_XOR  = `ALU_OP_XOR;
	// Shifting
	localparam  OP_LRS  = `ALU_OP_LRS;
	localparam  OP_ARS  = `ALU_OP_ARS;
	localparam  OP_RR   = `ALU_OP_RR;
	localparam  OP_LLS  = `ALU_OP_LLS;
	localparam  OP_ALS  = `ALU_OP_ALS;
	localparam  OP_RL   = `ALU_OP_RL;
	// Lab5 추가 (MSB = 1)
	localparam  OP_TCP  = `ALU_OP_TCP;
	localparam  OP_NE   = `ALU_OP_NE;
	localparam  OP_EQ   = `ALU_OP_EQ;
	localparam  OP_GZ   = `ALU_OP_GZ;
	localparam  OP_LZ   = `ALU_OP_LZ;

	// COPY AND PASTE YOUR ALU CODE HERE!
	// 추가 시작 (Lab1 ALU 코드 붙여넣기)

	// 17-bit results : bit[16] is the carry-out (ADD) / borrow-out (SUB)
	wire [16:0] add_result = {1'b0, A_i} + {1'b0, B_i} + {16'b0, C_i};
	wire [16:0] sub_result = {1'b0, A_i} - {1'b0, B_i} - {16'b0, C_i};

	reg  [15:0] F_r; //	16bit
	reg         C_r; //	 1bit
	reg         bcond_r; // Lab5 추가

	always @(*) begin
		bcond_r = 1'b0;    // branch 비교 연산이 아니면 0

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

			// ---------------- Lab5 추가 : Two's complement (TCP $rd <- ~$rs + 1)
			OP_TCP  : {C_r, F_r} = {1'b0, (~A_i + 16'd1)};

			// ---------------- Lab5 추가 : Branch condition -> bcond_o (F_o, C_o = 0)
			OP_NE   : begin {C_r, F_r} = 17'b0; bcond_r = (A_i != B_i);               end  // BNE
			OP_EQ   : begin {C_r, F_r} = 17'b0; bcond_r = (A_i == B_i);               end  // BEQ
			OP_GZ   : begin {C_r, F_r} = 17'b0; bcond_r = (!A_i[15]) && (A_i != 16'd0); end  // BGZ : $rs > 0 (signed)
			OP_LZ   : begin {C_r, F_r} = 17'b0; bcond_r = A_i[15];                    end  // BLZ : $rs < 0 (signed)

			default : {C_r, F_r} = 17'b0;
		endcase
	end

	assign F_o     = F_r;
	assign C_o     = C_r;
	assign bcond_o = bcond_r;

	// 추가 끝

endmodule