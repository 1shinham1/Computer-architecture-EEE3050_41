`include "opcodes.v"

module ControlUnit (
    // DEFINE THE INTERFACE OF THE CONTROL UNIT HERE
    // 추가 시작
    input      [3:0] opcode,     // instruction[15:12]
    input      [5:0] func,       // instruction[5:0] (R-type에서만 의미 있음)

    output reg       reg_write,  // RegWrite : Register File write enable
    output reg       reg_dst,    // RegDst   : write register 선택 (1: $rd / 0: $rt)
    output reg       alu_src,    // ALUSrc   : ALU 두 번째 operand 선택 (1: sign-extended imm / 0: $rt)
    output reg [3:0] alu_op,     // ALU opcode (ALU 모듈의 OP_i로 전달)
    output reg       lhi,        // write-back data 선택 (1: {imm, 8'h00} / 0: ALU result)
    output reg       jump,       // Jump     : PC <- {PC[15:12], target}
    output reg       wwd         // WWD      : interrupt 요청(ir_req) + ir_ack 받을 때까지 PC 정지
    // 추가 끝
);

// ADD YOUR CODE HERE
// 추가 시작
/*
Control Unit (조합 회로)
  - opcode / func 를 보고 datapath 제어 신호를 생성 (ADD, ADI, LHI, JMP, WWD)
  - 그 외 명령어는 모든 제어 신호가 0 -> NOP(NO Operation)처럼 동작 (레지스터 변경 없이 PC+1)
  inst | reg_write reg_dst alu_src alu_op lhi jump wwd
  -----+---------------------------------------------
  ADD  |     1        1       0     ADD    0   0    0
  ADI  |     1        0       1     ADD    0   0    0
  LHI  |     1        0       x      x     1   0    0
  JMP  |     0        x       x      x     0   1    0
  WWD  |     0        x       x      x     0   0    1
*/
always @(*) begin
    // 기본값: NOP
    reg_write = 1'b0;
    reg_dst   = 1'b0;
    alu_src   = 1'b0;
    alu_op    = `ALU_OP_ADD;
    lhi       = 1'b0;
    jump      = 1'b0;
    wwd       = 1'b0;

    case (opcode)
        `OPCODE_RTYPE: begin
            case (func)
                `FUNC_ADD: begin    // ADD $rd, $rs, $rt : $rd <- $rs + $rt
                    reg_write = 1'b1;
                    reg_dst   = 1'b1;
                    alu_src   = 1'b0;
                    alu_op    = `ALU_OP_ADD;
                end
                `FUNC_WWD: begin    // WWD $rs : output port(ir_msg) <- $rs
                    wwd       = 1'b1;
                end
                default: ;
            endcase
        end

        `OPCODE_ADI: begin          // ADI $rt, $rs, imm : $rt <- $rs + sign_ext(imm)
            reg_write = 1'b1;
            reg_dst   = 1'b0;
            alu_src   = 1'b1;
            alu_op    = `ALU_OP_ADD;
        end

        `OPCODE_LHI: begin          // LHI $rt, imm : $rt <- {imm, 8'h00}
            reg_write = 1'b1;
            reg_dst   = 1'b0;
            lhi       = 1'b1;
        end

        `OPCODE_JMP: begin          // JMP target : PC <- {PC[15:12], target}
            jump      = 1'b1;
        end

        default: ;
    endcase
end
// 추가 끝

endmodule
