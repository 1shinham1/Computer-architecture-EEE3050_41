`include "opcodes.v"

module CPU_W16_R4 #(
    parameter WORD_SIZE  = 16,
    parameter REG_BITS   = 2,
    parameter FORWARDING = 1,   // 1: EX forwarding + load-use stall (Extra 1) / 0: stall-only (RAW는 모두 stall)
    parameter PREDICT_NT = 1    // 1: predict not-taken + flush   (Extra 2) / 0: branch·JPR·JRL이 ID에 있으면 fetch stall
)
(
    // Global Signals
    input   wire    clk,      // global positive edge triggered clock
    input   wire    reset_n,  // global asynchronous negative triggered reset

    // Instruction Memory IF (Read-only)
    input   wire    [WORD_SIZE-1:0]     imem_rdata_i,   // instruction read port
    output  wire    [WORD_SIZE-1:0]     imem_raddr_o,   // instruction read address

    // Data Memory IF (Read/Write)
    output  wire    [WORD_SIZE-1:0]     dmem_addr_o,    // data read address
    input   wire    [WORD_SIZE-1:0]     dmem_rdata_i,   // data read port
    output  wire    [WORD_SIZE-1:0]     dmem_wdata_o,   // data write port
    output  wire                        dmem_read_o,    // data read enable
    output  wire                        dmem_write_o,   // data write enable  (수정: 콤마 누락)

    // Interrupt Handler IF (for debugging purpose)
    input   wire                        ir_ack_i,       // triggered when the given interrupt is properly handled
    output  wire                        ir_req_o,       // triggered when the internal interrupt occurs
    input   wire    [WORD_SIZE-1:0]     ir_msg_i,       // message transfer from interrupt handler (for RWD, not used)
    output  wire    [WORD_SIZE-1:0]     ir_msg_o        // message transfer to interrupt handler (수정: 마지막 콤마 제거)
);

/********************************************************
    5-stage pipeline : IF -> ID -> EX -> MEM -> WB
    - 제어 신호는 ID에서 만들고 WB / M / EX 그룹으로 다음 단계에 전달
    - Data hazard   : EX forwarding (EX/MEM > MEM/WB) + load-use 1 cycle stall
                      Register File은 negedge에 써서 WB -> ID 같은 사이클 읽기 해결
    - Control hazard: predict not-taken
                      JMP/JAL은 ID에서 결정 (IF/ID flush, 1 cycle)
                      taken branch, JPR/JRL은 EX에서 결정 (IF/ID, ID/EX flush, 2 cycle)
    - WWD           : WB 단계에서 ir_req, ack까지 PC와 모든 pipeline register freeze
    - 우선순위       : freeze > flush(redirect, jump) > stall
********************************************************/

    // MUX select 값 (control_unit.v와 동일)
    localparam RD_RT  = 2'b00, RD_RD    = 2'b01, RD_R2   = 2'b10;
    localparam SRC_RT = 2'b00, SRC_SEXT = 2'b01, SRC_ZEXT = 2'b10;
    localparam WB_ALU = 2'b00, WB_MEM   = 2'b01, WB_PC1  = 2'b10, WB_LHI = 2'b11;
    localparam FWD_ID = 2'b00, FWD_WB   = 2'b01, FWD_MEM = 2'b10;      // ForwardA / ForwardB
    localparam S_EXEC = 1'b0,  S_WAIT   = 1'b1;                        // WWD interrupt FSM

/********************************************************
    Wire Variable Declaration
********************************************************/

    // Pipeline control (hazard)
    wire                        stall;          // load-use : PC, IF/ID 유지 + ID/EX bubble
    wire                        ctrl_stall;     // PREDICT_NT = 0 일 때만 사용 (분기 결정 전 fetch 보류)
    wire                        ex_redirect;    // EX : taken branch / JPR / JRL -> PC 변경 + IF/ID, ID/EX flush
    wire                        id_jump;        // ID : JMP / JAL -> PC 변경 + IF/ID flush
    wire                        freeze;         // WB : WWD가 ack를 기다리는 동안 전체 유지
    wire                        id_bubble;      // ID/EX에 bubble을 넣음 (stall | ex_redirect)

    // Instruction Decoder IF (ID 단계, IF/ID.inst)
    wire    [3:0]               id_opcode;
    wire    [REG_BITS-1:0]      id_rs, id_rt, id_rd;
    wire    [5:0]               id_func;
    wire    [7:0]               id_imm8;
    wire    [11:0]              id_target;

    // Register File IF
    wire    [WORD_SIZE-1:0]     id_rs_data;     // Read data 1
    wire    [WORD_SIZE-1:0]     id_rt_data;     // Read data 2

    // Control Unit IF (cu_* : Control Unit 출력, id_* : valid로 gate한 값)
    wire    [1:0]               cu_reg_dst, cu_alu_src, cu_wb_sel;
    wire    [4:0]               cu_alu_op;
    wire                        cu_reg_write, cu_mem_read, cu_mem_write;
    wire                        cu_branch, cu_jump, cu_jump_reg, cu_wwd, cu_use_rs, cu_use_rt;
    wire                        id_reg_write, id_mem_read, id_mem_write;
    wire                        id_branch, id_jump_reg, id_wwd, id_use_rs, id_use_rt;

    // ID datapath
    reg     [WORD_SIZE-1:0]     id_imm16;       // Imm Ext : sext / zext / {imm, 8'h00}
    reg     [REG_BITS-1:0]      id_dest;        // RegDst MUX 출력
    wire    [WORD_SIZE-1:0]     id_jump_target; // {(PC+1)[15:12], target}

    // ALU IF (EX 단계)
    wire    [1:0]               forward_a, forward_b;
    reg     [WORD_SIZE-1:0]     ex_a;           // ForwardA MUX 출력 ($rs)
    reg     [WORD_SIZE-1:0]     ex_b;           // ForwardB MUX 출력 ($rt)
    wire    [WORD_SIZE-1:0]     ex_alu_b;       // ALUSrc MUX 출력
    wire    [WORD_SIZE-1:0]     ex_alu_out;
    wire                        ex_alu_carry;   // not used
    wire                        ex_bcond;
    wire    [WORD_SIZE-1:0]     ex_br_target;   // PC + 1 + sext(offset)
    wire    [WORD_SIZE-1:0]     ex_target;      // redirect target
    reg     [WORD_SIZE-1:0]     ex_result;      // EX result MUX (ALU / PC+1 / LHI)

    // Data Memory IF (MEM 단계)
    wire    [WORD_SIZE-1:0]     mem_wb_data;    // MemToReg MUX 출력

    // Program Counter IF (IF 단계)
    wire    [WORD_SIZE-1:0]     pc_plus1;
    reg     [WORD_SIZE-1:0]     pc_nxt;

/********************************************************
    Reg Variable Declaration
********************************************************/

    // Program Counter, Interrupt Handle State
    reg     [WORD_SIZE-1:0]     pc;
    reg                         state, state_nxt;
    reg                         freeze_r, ir_req_r;

    // IFID Register
    reg     [WORD_SIZE-1:0]     ifid_inst;
    reg     [WORD_SIZE-1:0]     ifid_pc1;
    reg                         ifid_valid;     // 0 : flush된 slot (NOP)

    // IDEX Register
    reg                         idex_reg_write, idex_wwd;                       // WB
    reg                         idex_mem_read, idex_mem_write;                  // M
    reg     [1:0]               idex_alu_src, idex_wb_sel;                      // EX
    reg     [4:0]               idex_alu_op;
    reg                         idex_branch, idex_jump_reg;
    reg     [WORD_SIZE-1:0]     idex_pc1, idex_a, idex_b, idex_imm;             // data
    reg     [REG_BITS-1:0]      idex_rs, idex_rt, idex_dest;

    // EXMEM Register
    reg                         exmem_reg_write, exmem_wwd;                     // WB
    reg                         exmem_mem_read, exmem_mem_write;                // M
    reg     [WORD_SIZE-1:0]     exmem_result, exmem_wdata;                      // data
    reg     [REG_BITS-1:0]      exmem_dest;

    // MEMWB Register
    reg                         memwb_reg_write, memwb_wwd;                     // WB
    reg     [WORD_SIZE-1:0]     memwb_wb_data;                                  // data
    reg     [REG_BITS-1:0]      memwb_dest;


    // ==================================================================
    // Part1: Instruction Memory Datapath (IF)
    // ==================================================================
    assign imem_raddr_o = pc;
    assign pc_plus1     = pc + 1'b1;

    // IFID Pipeline (Instruction Fetch -> Instruction Decode)
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ifid_inst  <= {WORD_SIZE{1'b0}};
            ifid_pc1   <= {WORD_SIZE{1'b0}};
            ifid_valid <= 1'b0;
        end else if (!freeze) begin
            if (ex_redirect || id_jump) begin
                ifid_valid <= 1'b0;                     // flush : 잘못 fetch한 명령어를 NOP으로
            end else if (stall) begin
                ;                                       // stall : ID 명령어 그대로 유지
            end else if (ctrl_stall) begin
                ifid_valid <= 1'b0;                     // (PREDICT_NT = 0) 분기 결정 전까지 bubble
            end else begin
                ifid_inst  <= imem_rdata_i;
                ifid_pc1   <= pc_plus1;
                ifid_valid <= 1'b1;
            end
        end
    end


    // ==================================================================
    // Part2: Register File Datapath (ID)
    // ==================================================================
    assign id_opcode = ifid_inst[15:12];
    assign id_rs     = ifid_inst[11:10];
    assign id_rt     = ifid_inst[9:8];
    assign id_rd     = ifid_inst[7:6];
    assign id_func   = ifid_inst[5:0];
    assign id_imm8   = ifid_inst[7:0];
    assign id_target = ifid_inst[11:0];

    // Register File : negedge write (앞 절반 쓰기 / 뒤 절반 읽기)
    RegisterFile #(
        .WORD_SIZE  (WORD_SIZE),
        .REG_BITS   (REG_BITS)
    ) rf_w16_r4 (
        .clk        (clk),
        .reset_n    (reset_n),
        .wr_enable  (memwb_reg_write),
        .rd_reg1    (id_rs),
        .rd_reg2    (id_rt),
        .wr_reg     (memwb_dest),
        .rd_data1   (id_rs_data),
        .rd_data2   (id_rt_data),
        .wr_data    (memwb_wb_data)
    );

    // Imm Ext : ALUSrc / WBSel로 확장 방식 선택 -> imm16 하나만 ID/EX로 전달
    always @(*) begin
        if (cu_wb_sel == WB_LHI)         id_imm16 = {id_imm8, 8'h00};          // LHI
        else if (cu_alu_src == SRC_ZEXT) id_imm16 = {8'h00, id_imm8};          // ORI
        else                             id_imm16 = {{8{id_imm8[7]}}, id_imm8}; // ADI, LWD, SWD, branch
    end

    // RegDst MUX : write register 선택
    always @(*) begin
        case (cu_reg_dst)
            RD_RD:   id_dest = id_rd;                   // R-type
            RD_R2:   id_dest = 2'd2;                    // JAL, JRL : $2 <- PC + 1
            default: id_dest = id_rt;                   // I-type
        endcase
    end

    // Jump target : IF/ID의 PC+1 상위 4bit와 target을 concat (빼기 회로 없음)
    // PC와 PC+1의 상위 4bit는 JMP가 0x?FFF 주소에 있을 때만 다르다 (memory 256 word에서는 발생하지 않음)
    assign id_jump_target = {ifid_pc1[15:12], id_target};

    // Hazard Detection Unit
    generate
        if (FORWARDING) begin : g_hdu_load_use
            // load-use : LWD가 EX에 있고 ID 명령어가 그 값을 실제로 읽으면 1 cycle stall
            assign stall = idex_mem_read &&
                           ((id_use_rs && (idex_dest == id_rs)) || (id_use_rt && (idex_dest == id_rt)));
        end else begin : g_hdu_stall_only
            // stall-only : EX, MEM 단계 명령어의 dest와 겹치면 stall (WB는 negedge write로 해결)
            wire hz_ex  = idex_reg_write  &&
                          ((id_use_rs && (idex_dest  == id_rs)) || (id_use_rt && (idex_dest  == id_rt)));
            wire hz_mem = exmem_reg_write &&
                          ((id_use_rs && (exmem_dest == id_rs)) || (id_use_rt && (exmem_dest == id_rt)));
            assign stall = hz_ex || hz_mem;
        end

        if (PREDICT_NT) begin : g_predict_not_taken
            assign ctrl_stall = 1'b0;
        end else begin : g_branch_stall
            assign ctrl_stall = id_branch || id_jump_reg;
        end
    endgenerate

    assign id_jump   = ifid_valid & cu_jump;
    assign id_bubble = stall | ex_redirect;

    // IDEX Pipeline (Instruction Decode -> Execution)
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            idex_reg_write <= 1'b0;  idex_wwd       <= 1'b0;
            idex_mem_read  <= 1'b0;  idex_mem_write <= 1'b0;
            idex_alu_src   <= SRC_RT; idex_alu_op   <= `ALU_OP_ADD;  idex_wb_sel <= WB_ALU;
            idex_branch    <= 1'b0;  idex_jump_reg  <= 1'b0;
            idex_pc1 <= {WORD_SIZE{1'b0}};  idex_a   <= {WORD_SIZE{1'b0}};
            idex_b   <= {WORD_SIZE{1'b0}};  idex_imm <= {WORD_SIZE{1'b0}};
            idex_rs  <= {REG_BITS{1'b0}};   idex_rt  <= {REG_BITS{1'b0}};  idex_dest <= {REG_BITS{1'b0}};
        end else if (!freeze) begin
            // control (WB / M / EX) : bubble이면 상태를 바꾸는 신호를 모두 0
            idex_reg_write <= id_bubble ? 1'b0 : id_reg_write;
            idex_wwd       <= id_bubble ? 1'b0 : id_wwd;
            idex_mem_read  <= id_bubble ? 1'b0 : id_mem_read;
            idex_mem_write <= id_bubble ? 1'b0 : id_mem_write;
            idex_branch    <= id_bubble ? 1'b0 : id_branch;
            idex_jump_reg  <= id_bubble ? 1'b0 : id_jump_reg;
            idex_alu_src   <= cu_alu_src;
            idex_alu_op    <= cu_alu_op;
            idex_wb_sel    <= cu_wb_sel;
            // data
            idex_pc1  <= ifid_pc1;
            idex_a    <= id_rs_data;
            idex_b    <= id_rt_data;
            idex_imm  <= id_imm16;
            idex_rs   <= id_rs;
            idex_rt   <= id_rt;
            idex_dest <= id_dest;
        end
    end


    // ==================================================================
    // Part3: ALU Datapath (EX)
    // ==================================================================
    // Forwarding Unit : EX/MEM 우선, 그다음 MEM/WB ($0도 일반 레지스터라 dest != 0 조건 없음)
    generate
        if (FORWARDING) begin : g_forwarding_unit
            assign forward_a = (exmem_reg_write && (exmem_dest == idex_rs)) ? FWD_MEM :
                               (memwb_reg_write && (memwb_dest == idex_rs)) ? FWD_WB  : FWD_ID;
            assign forward_b = (exmem_reg_write && (exmem_dest == idex_rt)) ? FWD_MEM :
                               (memwb_reg_write && (memwb_dest == idex_rt)) ? FWD_WB  : FWD_ID;
        end else begin : g_no_forwarding
            assign forward_a = FWD_ID;
            assign forward_b = FWD_ID;
        end
    endgenerate

    // ForwardA / ForwardB MUX
    always @(*) begin
        case (forward_a)
            FWD_MEM: ex_a = exmem_result;
            FWD_WB:  ex_a = memwb_wb_data;
            default: ex_a = idex_a;
        endcase
        case (forward_b)
            FWD_MEM: ex_b = exmem_result;
            FWD_WB:  ex_b = memwb_wb_data;
            default: ex_b = idex_b;
        endcase
    end

    // ALUSrc MUX : 00 -> $rt, 그 외 -> imm16 (sext / zext는 ID의 Imm Ext에서 이미 선택)
    assign ex_alu_b = (idex_alu_src == SRC_RT) ? ex_b : idex_imm;

    // Arithmetic Logic Unit
    ALU alu_w16_m (
        .A_i        (ex_a),
        .B_i        (ex_alu_b),
        .OP_i       (idex_alu_op),
        .C_i        (1'b0),
        .F_o        (ex_alu_out),
        .C_o        (ex_alu_carry),
        .bcond_o    (ex_bcond)
    );

    // Branch / JPR / JRL 결정 (EX)
    assign ex_br_target = idex_pc1 + idex_imm;                      // PC + 1 + sext(offset)
    assign ex_redirect  = (idex_branch & ex_bcond) | idex_jump_reg;
    assign ex_target    = idex_jump_reg ? ex_a : ex_br_target;      // JPR, JRL : forwarding된 $rs

    // EX result MUX : 레지스터에 쓸 최종값 (forwarding도 이 값을 사용)
    always @(*) begin
        case (idex_wb_sel)
            WB_PC1:  ex_result = idex_pc1;                          // JAL, JRL : $2 <- PC + 1
            WB_LHI:  ex_result = idex_imm;                          // LHI : {imm, 8'h00}
            default: ex_result = ex_alu_out;                        // ALU 연산, LWD/SWD 주소, WWD($rs)
        endcase
    end

    // EXMEM Pipeline (Execution -> Memory)
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            exmem_reg_write <= 1'b0;  exmem_wwd       <= 1'b0;
            exmem_mem_read  <= 1'b0;  exmem_mem_write <= 1'b0;
            exmem_result    <= {WORD_SIZE{1'b0}};
            exmem_wdata     <= {WORD_SIZE{1'b0}};
            exmem_dest      <= {REG_BITS{1'b0}};
        end else if (!freeze) begin
            exmem_reg_write <= idex_reg_write;
            exmem_wwd       <= idex_wwd;
            exmem_mem_read  <= idex_mem_read;
            exmem_mem_write <= idex_mem_write;
            exmem_result    <= ex_result;
            exmem_wdata     <= ex_b;                                // SWD : 저장할 $rt (forwarding된 값)
            exmem_dest      <= idex_dest;
        end
    end


    // ==================================================================
    // Part4: Data Memory Datapath (MEM)
    // ==================================================================
    assign dmem_addr_o  = exmem_result;
    assign dmem_wdata_o = exmem_wdata;
    assign dmem_read_o  = exmem_mem_read  & ~freeze;                // interrupt(freeze) 중에는 read/write 차단
    assign dmem_write_o = exmem_mem_write & ~freeze;

    // MemToReg MUX
    assign mem_wb_data = exmem_mem_read ? dmem_rdata_i : exmem_result;

    // MEMWB Pipeline (Memory -> Writeback)
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            memwb_reg_write <= 1'b0;
            memwb_wwd       <= 1'b0;
            memwb_wb_data   <= {WORD_SIZE{1'b0}};
            memwb_dest      <= {REG_BITS{1'b0}};
        end else if (!freeze) begin
            memwb_reg_write <= exmem_reg_write;
            memwb_wwd       <= exmem_wwd;
            memwb_wb_data   <= mem_wb_data;
            memwb_dest      <= exmem_dest;
        end
    end


    // ==================================================================
    // Part5: Control Unit Datapath (ID)
    // ==================================================================
    ControlUnit ctrl_unit (
        .opcode     (id_opcode),
        .func       (id_func),
        .reg_dst    (cu_reg_dst),
        .reg_write  (cu_reg_write),
        .alu_src    (cu_alu_src),
        .alu_op     (cu_alu_op),
        .mem_read   (cu_mem_read),
        .mem_write  (cu_mem_write),
        .wb_sel     (cu_wb_sel),
        .branch     (cu_branch),
        .jump       (cu_jump),
        .jump_reg   (cu_jump_reg),
        .wwd        (cu_wwd),
        .use_rs     (cu_use_rs),
        .use_rt     (cu_use_rt)
    );

    // flush된 slot (valid = 0)은 NOP : 상태를 바꾸는 제어 신호를 모두 0으로
    assign id_reg_write = ifid_valid & cu_reg_write;
    assign id_mem_read  = ifid_valid & cu_mem_read;
    assign id_mem_write = ifid_valid & cu_mem_write;
    assign id_branch    = ifid_valid & cu_branch;
    assign id_jump_reg  = ifid_valid & cu_jump_reg;
    assign id_wwd       = ifid_valid & cu_wwd;
    assign id_use_rs    = ifid_valid & cu_use_rs;
    assign id_use_rt    = ifid_valid & cu_use_rt;


    // ==================================================================
    // Part6: Program Counter Datapath (IF)
    // ==================================================================
    // PC MUX : EX redirect > (stall 이면 유지) > ID jump > PC + 1 (predict not-taken)
    always @(*) begin
        if (ex_redirect)                pc_nxt = ex_target;         // EX 명령어가 더 오래된 명령어
        else if (stall || ctrl_stall)   pc_nxt = pc;                // 같은 주소를 다시 fetch
        else if (id_jump)               pc_nxt = id_jump_target;    // JMP, JAL
        else                            pc_nxt = pc_plus1;
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) pc <= {WORD_SIZE{1'b0}};
        else if (!freeze) pc <= pc_nxt;
    end


    // ==================================================================
    // Part6: Interrupt Handler with FSM (WB) - Lab5 FSM 구조 유지
    // - WWD가 WB(MEM/WB)에 오면 ir_req, ack까지 freeze (PC, 모든 pipeline register 유지)
    // - ack를 받은 사이클에는 ir_req = 0 -> TB가 ack를 내려야 다음 WWD가 인식됨
    // - ir_msg_o = MEM/WB.wb_data (WWD는 ALU_OP_ID로 $rs를 그대로 전달)
    // ==================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) state <= S_EXEC;
        else          state <= state_nxt;
    end

    always @(*) begin
        state_nxt = state;
        freeze_r  = 1'b0;
        ir_req_r  = 1'b0;
        case (state)
            S_EXEC: begin
                if (memwb_wwd) begin
                    ir_req_r  = 1'b1;
                    freeze_r  = 1'b1;
                    state_nxt = S_WAIT;
                end
            end
            S_WAIT: begin
                if (ir_ack_i) begin
                    state_nxt = S_EXEC;                             // ack 수신 -> ir_req 해제, pipeline 진행
                end else begin
                    ir_req_r  = 1'b1;                               // ack 올 때까지 요청 유지
                    freeze_r  = 1'b1;
                end
            end
            default: state_nxt = S_EXEC;
        endcase
    end

    assign freeze   = freeze_r;
    assign ir_req_o = ir_req_r;
    assign ir_msg_o = memwb_wb_data;

endmodule
