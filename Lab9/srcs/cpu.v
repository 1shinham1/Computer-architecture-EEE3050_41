`include "opcodes.v"

module CPU_W16_R4 #(
    parameter WORD_SIZE = 16,
    parameter REG_BITS  = 2
)
(
    // Global Signals
    input   wire    clk,      // global positive edge triggered clock
    input   wire    reset_n,  // global asynchronous negative triggered reset 

    // Interrupt Handler IF (for debugging purpose - internal interrupt)
    input   wire                        ir_ack_i,       // triggered when the given interrupt is properly handled
    output  wire                        ir_req_o,       // triggered when the internal interrupt occurs
    input   wire    [WORD_SIZE-1:0]     ir_msg_i,       // message transfer from interrupt handler
    output  wire    [WORD_SIZE-1:0]     ir_msg_o,       // message transfer to interrupt handler
    
    // Instruction Cache IF
    output  wire    [WORD_SIZE-1:0]     icache_addr_o,     // instruction cache address
    input   wire    [WORD_SIZE-1:0]     icache_rd_data_i,  // instruction read data 
    output  wire                        icache_rd_req_o,   // instruction read request
    input   wire                        icache_rd_ack_i,   // instruction read acknowledge

    // Data Cache IF
    output  wire    [WORD_SIZE-1:0]     dcache_addr_o,     // data cache address
    input   wire    [WORD_SIZE-1:0]     dcache_rd_data_i,  // data read
    output  wire                        dcache_rd_req_o,   // data read request
    input   wire                        dcache_rd_ack_i,   // data read acknowledge
    output  wire    [WORD_SIZE-1:0]     dcache_wr_data_o,  // data write
    output  wire                        dcache_wr_req_o,   // data write request
    input   wire                        dcache_wr_ack_i,   // data write acknowledge

    //////////////////////// Designing DMA and EXT DEV IF ////////////////////////
    
    // DMA IF (for DMA setting and handling)
    // dma_len, dma_addr, dma_ir_ack, dma_ir_req, ...
    output  wire                        dma_ir_req_o,      // Lab9 추가: DMA wake up 요청 (CPU -> DMA, 1 cycle)
    output  wire    [WORD_SIZE-1:0]     dma_len_o,         // Lab9 추가: 옮길 word 수 (8/16/32/64)
    output  wire    [WORD_SIZE-1:0]     dma_addr_o,        // Lab9 추가: memory 시작 주소
    input   wire                        dma_ir_ack_i,      // Lab9 추가: DMA 전송 완료 (DMA -> CPU)


    // EXT_DEV IF (for interrupt handling)
    // dev_ir_ack, dev_ir_req, ...
    input   wire                        dev_ir_req_i,      // Lab9 추가: device interrupt 요청 (DEV -> CPU)
    output  wire                        dev_ir_ack_o       // Lab9 추가: device interrupt 처리 완료 (CPU -> DEV)
    
);

    /*******************************************************
     * Project: Extending CPU with DMA
     *******************************************************

     Description
       * This project is to extend your CPU implementation with DMA
       * You can choose one from the single-cycle / multi-cycle / pipelined implementation of the CPU
     
      Purpose: Integrate CPU with DMA
       * You need to integrate the CPU with the DMA
       * So, several interface is redesigned (CPU, DMA, TB)
          * CPU: add device interrupt, add DMA interrupt, add DMA config, ...
          * DMA: remove device interrupt, add CPU interrupt, DMA config, ...
          * TB: Modification based with upper changes
       * Follow the specification explained in the PPT/Videos
     
     DMA Specification
       * Flow of DMA operation
        1) External device requests the CPU to wake up the DMA (by dev_ir_req)
        2) CPU stalls the program 
        3) CPU wakes up the DMA with DMA operation config (by dma_len, dma_addr)
        4) When DMA wake up, DMA requests the arbiter to grant the bus
        5) DMA and CPU run concurrently (DMA use memory's RW channel, CPU use memory's RO channel and cache)
        6) DMA migrate data from the external device to the memory
        7) DMA finished migration, DMA acknowledges to CPU, also release bus (by dma_ir_ack)
        8) CPU acknowledges the external device (by dev_ir_ack)
        
        * DMA length
          - DMA length is the number of words to be migrated from the external device to the memory
          - DMA length is based with the last 2-bit of the register $3 at stall state
          - DMA length has 4 types
            - 0: 8 words
            - 1: 16 words
            - 2: 32 words
            - 3: 64 words
          - if $3 is 16'h0003, then DMA length is 64 words
         
        * DMA address
          - DMA address is the starting address of the memory to migrate data
          - DMA address is based with the target address + 'd512 (='h0200) at stall state
          - if current PC is 16'h0012, then DMA address is 16'h0204
     */


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
    - Lab8          : imem/dmem -> I-cache / D-cache (req-ack handshake)
                      캐시가 ack를 줄 때까지 pipeline 전체 freeze (option 1)
    - Lab9          : device interrupt -> IR FSM (Part7) 이 1 cycle stall 후 DMA 설정
                      DMA가 옮기는 동안 CPU는 계속 실행, DMA 완료 시 device에 ack
********************************************************/

    // Lab8 수정 (STEP 1): Lab7의 module parameter -> localparam (Lab8 포트 선언 유지)
    localparam FORWARDING = 1;   // 1: EX forwarding + load-use stall / 0: stall-only
    localparam PREDICT_NT = 1;   // 1: predict not-taken + flush     / 0: branch·JPR·JRL이 ID에 있으면 fetch stall

    // MUX select 값 (control_unit.v와 동일)
    localparam RD_RT  = 2'b00, RD_RD    = 2'b01, RD_R2   = 2'b10;
    localparam SRC_RT = 2'b00, SRC_SEXT = 2'b01, SRC_ZEXT = 2'b10;
    localparam WB_ALU = 2'b00, WB_MEM   = 2'b01, WB_PC1  = 2'b10, WB_LHI = 2'b11;
    localparam FWD_ID = 2'b00, FWD_WB   = 2'b01, FWD_MEM = 2'b10;      // ForwardA / ForwardB
    localparam S_EXEC = 1'b0,  S_WAIT   = 1'b1;                        // WWD interrupt FSM
    localparam IR_IDLE = 2'd0, IR_CONFIG = 2'd1, IR_WAIT_DMA = 2'd2;   // Lab9 추가: device interrupt FSM

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
    wire    [WORD_SIZE-1:0]     ir_r3_data;     // Lab9 추가: Read data 3 ($3, DMA length 결정용)

    // Lab9 추가: Device Interrupt Handler
    wire                        freeze_ir;      // IR_CONFIG 1 cycle 동안 pipeline 정지

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
    reg     [1:0]               ir_state, ir_state_nxt;     // Lab9 추가: device interrupt FSM 상태

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
    // Part1: Instruction Cache Datapath (IF)
    // ==================================================================
    // Lab8 수정 (STEP 2): instruction memory -> I-cache
    assign icache_addr_o   = pc;
    assign icache_rd_req_o = 1'b1;                                  // 매 cycle fetch (ack 대기는 STEP 4 freeze)
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
                ifid_inst  <= icache_rd_data_i;          // Lab8 수정 (STEP 2)
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
        .rd_reg3    (2'd3),                 // Lab9 추가: 항상 $3
        .wr_reg     (memwb_dest),
        .rd_data1   (id_rs_data),
        .rd_data2   (id_rt_data),
        .rd_data3   (ir_r3_data),           // Lab9 추가
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
        .Bcond_o    (ex_bcond)                                      // Lab8 수정 (STEP 1): 포트 이름
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
    // Lab8 수정 (STEP 3): data memory -> D-cache
    assign dcache_addr_o    = exmem_result;                         // LWD / SWD 주소
    assign dcache_wr_data_o = exmem_wdata;                          // SWD 데이터 ($rt)
    // Lab8 수정 (STEP 4): '& ~freeze' 제거 -> freeze가 캐시 ack에 의존하므로 남겨두면 combinational loop
    //                     (handshake 규칙상 ack 받을 때까지 req 유지, freeze 중 반복 요청은 같은 주소 hit)
    assign dcache_rd_req_o  = exmem_mem_read;
    assign dcache_wr_req_o  = exmem_mem_write;

    // MemToReg MUX
    assign mem_wb_data = exmem_mem_read ? dcache_rd_data_i : exmem_result;   // Lab8 수정 (STEP 3)

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

    // Lab8 수정 (STEP 5): WWD 중복 출력 방지
    // - ack를 받았는데 캐시 대기(i_wait / d_wait)로 freeze가 남으면 WWD가 MEM/WB에 그대로 남음
    //   -> S_EXEC가 같은 WWD를 다시 요청하지 않도록 "이미 출력함" 표시
    // - pipeline이 진행하면(freeze = 0) MEM/WB에 새 명령어가 들어오므로 해제
    reg wwd_done;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)                           wwd_done <= 1'b0;
        else if (!freeze)                       wwd_done <= 1'b0;
        else if ((state == S_WAIT) && ir_ack_i) wwd_done <= 1'b1;
    end

    always @(*) begin
        state_nxt = state;
        freeze_r  = 1'b0;
        ir_req_r  = 1'b0;
        case (state)
            S_EXEC: begin
                if (memwb_wwd && !wwd_done) begin                   // Lab8 수정 (STEP 5)
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

    // ==================================================================
    // Part7: Device Interrupt Handler with FSM - Lab9 추가 (CPU extension)
    // - IR_IDLE     : 평소 실행, dev_ir_req가 오면 IR_CONFIG
    // - IR_CONFIG   : 1 cycle 프로그램 stall (freeze_ir) + DMA wake up (dma_ir_req, dma_len, dma_addr)
    // - IR_WAIT_DMA : 프로그램 다시 실행 (DMA와 동시 동작), dma_ir_ack가 오면 device에 ack -> IR_IDLE
    // - WWD FSM(Part6)과 독립적으로 동작, 만나는 곳은 freeze (OR) 뿐
    // - 상태 레지스터는 freeze와 무관하게 매 cycle 갱신
    // ==================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) ir_state <= IR_IDLE;
        else          ir_state <= ir_state_nxt;
    end

    always @(*) begin
        ir_state_nxt = ir_state;
        case (ir_state)
            IR_IDLE:     if (dev_ir_req_i) ir_state_nxt = IR_CONFIG;     // (spec 1) device -> CPU
            IR_CONFIG:                     ir_state_nxt = IR_WAIT_DMA;   // 1 cycle 뒤 프로그램 재개
            IR_WAIT_DMA: if (dma_ir_ack_i) ir_state_nxt = IR_IDLE;       // (spec 7) DMA 완료
            default:                       ir_state_nxt = IR_IDLE;
        endcase
    end

    assign freeze_ir    = (ir_state == IR_CONFIG);                  // (spec 2) stall the program
    assign dma_ir_req_o = (ir_state == IR_CONFIG);                  // (spec 3) wake up DMA with config
    assign dma_len_o    = 16'd8 << ir_r3_data[1:0];                 // $3[1:0] = 0/1/2/3 -> 8/16/32/64 words
    assign dma_addr_o   = 16'h0200 + (pc >> 2);                     // 'h0200 + PC/4 (spec 예시: PC 'h0012 -> 'h0204)
    assign dev_ir_ack_o = (ir_state == IR_WAIT_DMA) && dma_ir_ack_i;    // (spec 8) CPU -> device ack

    // Lab8 수정 (STEP 4): 캐시가 ack를 줄 때까지 pipeline 전체 freeze (option 1)
    wire i_wait = icache_rd_req_o & ~icache_rd_ack_i;                                   // fetch miss 처리 중
    wire d_wait = (dcache_rd_req_o & ~dcache_rd_ack_i) | (dcache_wr_req_o & ~dcache_wr_ack_i);  // LWD / SWD miss 처리 중

    assign freeze   = freeze_r | freeze_ir | i_wait | d_wait;       // Lab9 수정: freeze_ir 추가
    assign ir_req_o = ir_req_r;
    assign ir_msg_o = memwb_wb_data;


endmodule
