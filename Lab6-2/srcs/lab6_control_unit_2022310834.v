`include "lab6_opcodes_2022310834.v"

module ControlUnit (
    input            clk,
    input            reset_n,

    input      [3:0] opcode,        // instruction[15:12]
    input      [5:0] func,          // instruction[5:0] (R-type에서만 의미 있음)
    input            ir_ack,        // interrupt handler의 acknowledge

    output reg       mem_read,      // MemRead     : mem_read_o
    output reg       mem_write,     // MemWrite    : mem_write_o
    output reg       i_or_d,        // IorD        : memory 주소 선택 (0: PC / 1: ALUOut)
    output reg       ir_write,      // IRWrite     : mem_rdata를 IR에 저장
    output reg       pc_write,      // PCWrite     : PC 갱신
    output reg       pc_write_cond, // PCWriteCond : bcond = 1이면 PC 갱신 (branch)
    output reg [1:0] pc_source,     // PCSource    : PC에 넣을 값 선택 (00: ALU 결과 / 01: jump 주소 / 10: $rs / 11: ALUOut)
    output reg       alu_src_a,     // ALUSrcA     : ALU A input 선택 (0: PC / 1: A)
    output reg [1:0] alu_src_b,     // ALUSrcB     : ALU B input 선택 (00: B / 01: sext(imm) / 10: zext(imm) / 11: 상수 1)
    output reg [4:0] alu_op,        // ALUOp       : ALU 연산 (`ALU_OP_*, ALU의 OP_i로 전달)
    output reg       reg_write,     // RegWrite    : Register File write enable
    output reg [1:0] reg_dst,       // RegDst      : write register 선택 (00: $rt / 01: $rd / 10: $2)
    output reg [1:0] wb_sel,        // WBSel       : write-back data 선택 (00: ALUOut / 01: MDR / 10: PC / 11: {imm, 8'h00})
    output reg       ir_req         // WWD         : interrupt 요청
);

// MUX select 값 (cpu.v와 동일하게 사용)
localparam PC_ALU   = 2'b00, PC_JUMP  = 2'b01, PC_RS    = 2'b10, PC_ALUOUT = 2'b11;
localparam SRCA_PC  = 1'b0,  SRCA_A   = 1'b1;
localparam SRCB_B   = 2'b00, SRCB_SEXT = 2'b01, SRCB_ZEXT = 2'b10, SRCB_ONE = 2'b11;
localparam RD_RT    = 2'b00, RD_RD    = 2'b01, RD_R2    = 2'b10;
localparam WB_ALUOUT = 2'b00, WB_MDR  = 2'b01, WB_PC    = 2'b10, WB_LHI   = 2'b11;

// FSM state
localparam S_IF1  = 4'd0,  S_IF2  = 4'd1,  S_IF3  = 4'd2,  S_IF4  = 4'd3,  S_IF5 = 4'd4;
localparam S_ID   = 4'd5,  S_EX   = 4'd6;
localparam S_MEM1 = 4'd7,  S_MEM2 = 4'd8,  S_MEM3 = 4'd9,  S_MEM4 = 4'd10, S_MEM5 = 4'd11;
localparam S_WB   = 4'd12, S_WAIT = 4'd13;

reg [3:0] state, state_nxt;

// state register
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) state <= S_IF1;
    else          state <= state_nxt;
end

// next state & output logic
// bcond는 여기서 읽지 않는다. alu_op와 조합 루프가 생기므로 cpu.v에서 pc_write_cond와 AND 한다.
always @(*) begin
    // 기본값: 아무것도 쓰지 않는 상태
    state_nxt     = state;
    mem_read      = 1'b0;
    mem_write     = 1'b0;
    i_or_d        = 1'b0;
    ir_write      = 1'b0;
    pc_write      = 1'b0;
    pc_write_cond = 1'b0;
    pc_source     = PC_ALU;
    alu_src_a     = SRCA_PC;
    alu_src_b     = SRCB_B;
    alu_op        = `ALU_OP_ADD;
    reg_write     = 1'b0;
    reg_dst       = RD_RT;
    wb_sel        = WB_ALUOUT;
    ir_req        = 1'b0;

    case (state)
        // ---------------- Fetch : read를 준 cycle의 4 cycle 뒤에 mem_rdata가 유효하므로 5개 state 사용
        S_IF1: begin                    // memory read 요청, PC <- PC + 1
            mem_read  = 1'b1;
            i_or_d    = 1'b0;
            alu_src_a = SRCA_PC;
            alu_src_b = SRCB_ONE;
            alu_op    = `ALU_OP_ADD;
            pc_source = PC_ALU;
            pc_write  = 1'b1;
            state_nxt = S_IF2;
        end
        S_IF2: state_nxt = S_IF3;
        S_IF3: state_nxt = S_IF4;
        S_IF4: state_nxt = S_IF5;
        S_IF5: begin                    // IR <- mem_rdata
            ir_write  = 1'b1;
            state_nxt = S_ID;
        end

        // ---------------- Decode : ALUOut <- PC + sext(imm), A <- $rs, B <- $rt
        S_ID: begin
            alu_src_a = SRCA_PC;
            alu_src_b = SRCB_SEXT;
            alu_op    = `ALU_OP_ADD;
            state_nxt = S_EX;

            case (opcode)
                `OPCODE_JMP: begin      // JMP target : PC <- {PC[15:12], target}
                    pc_source = PC_JUMP;
                    pc_write  = 1'b1;
                    state_nxt = S_IF1;
                end
                `OPCODE_JAL: begin      // JAL target : $2 <- PC, PC <- {PC[15:12], target}
                    pc_source = PC_JUMP;
                    pc_write  = 1'b1;
                    reg_dst   = RD_R2;
                    wb_sel    = WB_PC;
                    reg_write = 1'b1;
                    state_nxt = S_IF1;
                end
                `OPCODE_RTYPE: begin
                    case (func)
                        `FUNC_JPR: begin    // JPR $rs : PC <- $rs
                            pc_source = PC_RS;
                            pc_write  = 1'b1;
                            state_nxt = S_IF1;
                        end
                        `FUNC_JRL: begin    // JRL $rs : $2 <- PC, PC <- $rs
                            pc_source = PC_RS;
                            pc_write  = 1'b1;
                            reg_dst   = RD_R2;
                            wb_sel    = WB_PC;
                            reg_write = 1'b1;
                            state_nxt = S_IF1;
                        end
                        `FUNC_WWD: state_nxt = S_WAIT;
                        `FUNC_RWD, `FUNC_HLT, `FUNC_ENI, `FUNC_DSI:
                            state_nxt = S_IF1;  // 지원 안 함 (PC + 1 만 수행)
                        default: ;
                    endcase
                end
                default: ;
            endcase
        end

        // ---------------- Execute : ALU 연산 또는 branch 비교
        S_EX: begin
            alu_src_a = SRCA_A;
            state_nxt = S_WB;

            case (opcode)
                `OPCODE_RTYPE: begin    // $rd <- $rs op $rt
                    alu_src_b = SRCB_B;
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

                `OPCODE_ADI: begin      // $rt <- $rs + sext(imm)
                    alu_src_b = SRCB_SEXT;
                    alu_op    = `ALU_OP_ADD;
                end
                `OPCODE_ORI: begin      // $rt <- $rs | zext(imm)
                    alu_src_b = SRCB_ZEXT;
                    alu_op    = `ALU_OP_OR;
                end
                `OPCODE_LHI: ;          // $rt <- {imm, 8'h00} : ALU 사용 안 함

                `OPCODE_LWD, `OPCODE_SWD: begin    // 주소 = $rs + sext(offset)
                    alu_src_b = SRCB_SEXT;
                    alu_op    = `ALU_OP_ADD;
                    state_nxt = S_MEM1;
                end

                // Branch : bcond = 1이면 PC <- ALUOut (ID에서 계산한 target)
                `OPCODE_BNE, `OPCODE_BEQ, `OPCODE_BGZ, `OPCODE_BLZ: begin
                    alu_src_b     = SRCB_B;
                    pc_source     = PC_ALUOUT;
                    pc_write_cond = 1'b1;
                    state_nxt     = S_IF1;
                    case (opcode)
                        `OPCODE_BNE: alu_op = `ALU_OP_NE;   // $rs != $rt
                        `OPCODE_BEQ: alu_op = `ALU_OP_EQ;   // $rs == $rt
                        `OPCODE_BGZ: alu_op = `ALU_OP_GZ;   // $rs >  0
                        default:     alu_op = `ALU_OP_LZ;   // $rs <  0
                    endcase
                end

                default: ;
            endcase
        end

        // ---------------- Memory : 주소 = ALUOut
        S_MEM1: begin
            i_or_d = 1'b1;
            if (opcode == `OPCODE_SWD) begin    // M[ALUOut] <- B, 이후 cycle은 memory가 혼자 처리
                mem_write = 1'b1;
                state_nxt = S_IF1;
            end else begin                      // LWD : memory read 요청
                mem_read  = 1'b1;
                state_nxt = S_MEM2;
            end
        end
        S_MEM2: state_nxt = S_MEM3;
        S_MEM3: state_nxt = S_MEM4;
        S_MEM4: state_nxt = S_MEM5;
        S_MEM5: state_nxt = S_WB;               // 이 cycle 끝에 MDR <- mem_rdata

        // ---------------- Write back
        S_WB: begin
            reg_write = 1'b1;
            reg_dst   = (opcode == `OPCODE_RTYPE) ? RD_RD : RD_RT;
            case (opcode)
                `OPCODE_LWD: wb_sel = WB_MDR;
                `OPCODE_LHI: wb_sel = WB_LHI;
                default:     wb_sel = WB_ALUOUT;
            endcase
            state_nxt = S_IF1;
        end

        // ---------------- WWD : ir_ack 받을 때까지 요청 유지
        S_WAIT: begin
            if (ir_ack) state_nxt = S_IF1;
            else        ir_req    = 1'b1;
        end

        default: state_nxt = S_IF1;
    endcase
end

endmodule
