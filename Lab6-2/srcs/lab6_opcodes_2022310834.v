/***************************************
 * INSTRUCTION OPCODE
 ***************************************/
`define OPCODE_ADI   4'b0100
`define OPCODE_ORI   4'b0101
`define OPCODE_LHI   4'b0110
`define OPCODE_LWD   4'b0111
`define OPCODE_SWD   4'b1000
`define OPCODE_BNE   4'b0000
`define OPCODE_BEQ   4'b0001
`define OPCODE_BGZ   4'b0010
`define OPCODE_BLZ   4'b0011
`define OPCODE_JMP   4'b1001
`define OPCODE_JAL   4'b1010
`define OPCODE_RTYPE 4'b1111

/***************************************
 * INSTRUCTION FUNCTION CODE
 ***************************************/
`define FUNC_ADD 6'd0
`define FUNC_SUB 6'd1
`define FUNC_AND 6'd2
`define FUNC_ORR 6'd3
`define FUNC_NOT 6'd4
`define FUNC_TCP 6'd5
`define FUNC_SHL 6'd6
`define FUNC_SHR 6'd7
`define FUNC_RWD 6'd27
`define FUNC_WWD 6'd28
`define FUNC_JPR 6'd25
`define FUNC_JRL 6'd26
`define FUNC_HLT 6'd29
`define FUNC_ENI 6'd30
`define FUNC_DSI 6'd31


/***************************************
 * ALU OPCODE
 ***************************************/
`define ALU_OP_ADD   5'b00000
`define ALU_OP_SUB   5'b00001
`define ALU_OP_ID    5'b01000
`define ALU_OP_NAND  5'b01001 
`define ALU_OP_NOR   5'b01010
`define ALU_OP_XNOR  5'b01011
`define ALU_OP_NOT   5'b01100
`define ALU_OP_AND   5'b01101 
`define ALU_OP_OR    5'b01110
`define ALU_OP_XOR   5'b01111
`define ALU_OP_LRS   5'b00010
`define ALU_OP_ARS   5'b00100
`define ALU_OP_RR    5'b00110
`define ALU_OP_LLS   5'b00011
`define ALU_OP_ALS   5'b00101
`define ALU_OP_RL    5'b00111

`define ALU_OP_TCP   5'b10100
`define ALU_OP_NE    5'b10000
`define ALU_OP_EQ    5'b10001
`define ALU_OP_GZ    5'b10010
`define ALU_OP_LZ    5'b10011