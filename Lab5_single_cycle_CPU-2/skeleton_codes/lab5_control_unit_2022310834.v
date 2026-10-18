`include "lab5_opcodes_2022310834.v"

module ControlUnit (
    // 추가 시작
    input      [3:0] opcode,     // instruction[15:12]
    input      [5:0] func,       // instruction[5:0] (R-type에서만 의미 있음)

    output reg [1:0] reg_dst,    // RegDst   : write register 선택 (00: $rt / 01: $rd / 10: $2)
    output reg       reg_write,  // RegWrite : Register File write enable
    output reg [1:0] alu_src,    // ALUSrc   : ALU operand2 선택 (00: $rt / 01: sext(imm) / 10: zext(imm))
    output reg [4:0] alu_op,     // ALUOp    : ALU 연산 (`ALU_OP_*, ALU의 OP_i로 전달)
    output reg       mem_read,   // MemRead  : dmem_read_o  (LWD)
    output reg       mem_write,  // MemWrite : dmem_write_o (SWD)
    output reg [1:0] wb_sel,     // WBSel    : write-back data 선택 (00: ALU / 01: Mem / 10: PC+1 / 11: {imm, 8'h00})
    output reg       branch,     // Branch   : bcond = 1이면 PC <- PC + 1 + sext(offset)
    output reg       jump,       // Jump     : PC <- {PC[15:12], target}     (JMP, JAL)
    output reg       jump_reg,   // JumpReg  : PC <- $rs                     (JPR, JRL)
    output reg       wwd         // WWD      : interrupt 요청(ir_req) + ir_ack 받을 때까지 PC 정지
    // 추가 끝
);

// 추가 시작
// MUX select 값 (cpu.v와 동일하게 사용)
localparam RD_RT    = 2'b00, RD_RD    = 2'b01, RD_R2   = 2'b10;
localparam SRC_RT   = 2'b00, SRC_SEXT = 2'b01, SRC_ZEXT = 2'b10;
localparam WB_ALU   = 2'b00, WB_MEM   = 2'b01, WB_PC1  = 2'b10, WB_LHI = 2'b11;

// Control Unit truth table 은 보고서 참고 (don't care 는 모두 0)
always @(*) begin
    // 기본값: NOP (RWD, HLT, ENI, DSI 는 이 상태 그대로 -> PC + 1 만 수행)
    reg_dst   = RD_RT;
    reg_write = 1'b0;
    alu_src   = SRC_RT;
    alu_op    = `ALU_OP_ADD;
    mem_read  = 1'b0;
    mem_write = 1'b0;
    wb_sel    = WB_ALU;
    branch    = 1'b0;
    jump      = 1'b0;
    jump_reg  = 1'b0;
    wwd       = 1'b0;

    case (opcode)
        `OPCODE_RTYPE: begin
            case (func)
                // ---------------- R-type 연산 : $rd <- $rs op $rt
                `FUNC_ADD, `FUNC_SUB, `FUNC_AND, `FUNC_ORR,
                `FUNC_NOT, `FUNC_TCP, `FUNC_SHL, `FUNC_SHR: begin
                    reg_dst   = RD_RD;
                    reg_write = 1'b1;
                    alu_src   = SRC_RT;
                    wb_sel    = WB_ALU;
                    case (func)
                        `FUNC_ADD: alu_op = `ALU_OP_ADD;
                        `FUNC_SUB: alu_op = `ALU_OP_SUB;
                        `FUNC_AND: alu_op = `ALU_OP_AND;
                        `FUNC_ORR: alu_op = `ALU_OP_OR;
                        `FUNC_NOT: alu_op = `ALU_OP_NOT;
                        `FUNC_TCP: alu_op = `ALU_OP_TCP;
                        `FUNC_SHL: alu_op = `ALU_OP_LLS;   // $rs << 1
                        `FUNC_SHR: alu_op = `ALU_OP_ARS;   // $rs >> 1 (sign extend)
                        default:   alu_op = `ALU_OP_ADD;
                    endcase
                end

                `FUNC_JPR: begin    // JPR $rs : PC <- $rs
                    jump_reg  = 1'b1;
                end

                `FUNC_JRL: begin    // JRL $rs : $2 <- PC + 1, PC <- $rs
                    jump_reg  = 1'b1;
                    reg_dst   = RD_R2;
                    reg_write = 1'b1;
                    wb_sel    = WB_PC1;
                end

                `FUNC_WWD: begin    // WWD $rs : output port(ir_msg) <- $rs
                    wwd       = 1'b1;
                end

                default: ;          // RWD, HLT, ENI, DSI : 지원 안 함 (PC + 1)
            endcase
        end

        // ---------------- I-type 연산 : $rt <- $rs op imm
        `OPCODE_ADI: begin          // ADI $rt, $rs, imm : $rt <- $rs + sext(imm)
            reg_write = 1'b1;
            alu_src   = SRC_SEXT;
            alu_op    = `ALU_OP_ADD;
        end

        `OPCODE_ORI: begin          // ORI $rt, $rs, imm : $rt <- $rs | zext(imm)
            reg_write = 1'b1;
            alu_src   = SRC_ZEXT;
            alu_op    = `ALU_OP_OR;
        end

        `OPCODE_LHI: begin          // LHI $rt, imm : $rt <- {imm, 8'h00}
            reg_write = 1'b1;
            wb_sel    = WB_LHI;
        end

        // ---------------- Memory : 주소 = $rs + sext(offset)
        `OPCODE_LWD: begin          // LWD $rt, $rs, offset : $rt <- M[addr]
            reg_write = 1'b1;
            alu_src   = SRC_SEXT;
            alu_op    = `ALU_OP_ADD;
            mem_read  = 1'b1;
            wb_sel    = WB_MEM;
        end

        `OPCODE_SWD: begin          // SWD $rt, $rs, offset : M[addr] <- $rt
            alu_src   = SRC_SEXT;
            alu_op    = `ALU_OP_ADD;
            mem_write = 1'b1;
        end

        // ---------------- Branch : ALU 비교 결과(bcond)가 1이면 PC <- PC + 1 + sext(offset)
        `OPCODE_BNE: begin branch = 1'b1; alu_op = `ALU_OP_NE; end   // $rs != $rt
        `OPCODE_BEQ: begin branch = 1'b1; alu_op = `ALU_OP_EQ; end   // $rs == $rt
        `OPCODE_BGZ: begin branch = 1'b1; alu_op = `ALU_OP_GZ; end   // $rs >  0
        `OPCODE_BLZ: begin branch = 1'b1; alu_op = `ALU_OP_LZ; end   // $rs <  0

        // ---------------- Jump
        `OPCODE_JMP: begin          // JMP target : PC <- {PC[15:12], target}
            jump      = 1'b1;
        end

        `OPCODE_JAL: begin          // JAL target : $2 <- PC + 1, PC <- {PC[15:12], target}
            jump      = 1'b1;
            reg_dst   = RD_R2;
            reg_write = 1'b1;
            wb_sel    = WB_PC1;
        end

        default: ;
    endcase
end
// 추가 끝

endmodule
