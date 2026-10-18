`include "lab5_opcodes_2022310834.v"

module CPU_W16_R4 #(
    parameter WORD_SIZE = 16,
    parameter REG_BITS  = 2
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
    Wire Variable Declaration
********************************************************
    Instruction Decoder IF
    - Instruction Opcode Signal
    - Instruction RS Signal
    - Instruction RT Signal
    - Instruction RD Signal
    - Instruction Function Code Signal
    - Instruction Immediate Signal
    - Instruction Target Address Signal

    Register File IF
    - Register Write Enable Signal
    - Register Read Address 1 Signal
    - Register Read Address 2 Signal
    - Register Write Address Signal
    - Register Read Data 1 Signal
    - Register Read Data 2 Signal
    - Register Write Data Signal
    - etc.

    ALU IF
    - ALU Operand 1 Signal
    - ALU Operand 2 Signal
    - ALU Operation Signal
    - ALU Result Signal
    - ALU Overflow Signal           (Maybe not used)
    - ALU Branch Condition Signal   (need to implemenet for branch inst.)

    Control Unit IF
    - Instruction Opcode Signal
    - Instruction Function Code Signal
    - Register Write Destination Select Signal
    - Register Write Enable Signal
    - Register Write Data Source Select Signal
    - ALU Operand 2 Source Select Signal
    - ALU Operation Signal
    - Memory Read Signal
    - Memory Write Signal
    - Jump Enable Signal
    - Branch Enable Signal
    - Jump Target Address Select Signal
    - Internal Interrupt Trap Enable Signal
    - Internal Interrupt Acknowledge Signal
    - etc.

    Program Counter IF
    - Program Counter Source Select Signals (ex. PC_SRC1, PC_SRC2, ...)
    - Next Address Signal
    - Jump Target Address Signal
    - Branch Target Address Signal
    - etc.
********************************************************/

    // Instruction Decoder IF
    wire    [3:0]               opcode;         // inst[15:12]
    wire    [REG_BITS-1:0]      rs;             // inst[11:10]
    wire    [REG_BITS-1:0]      rt;             // inst[9:8]
    wire    [REG_BITS-1:0]      rd;             // inst[7:6]
    wire    [5:0]               func;           // inst[5:0]
    wire    [7:0]               imm;            // inst[7:0]  (immediate / branch offset)
    wire    [11:0]              target;         // inst[11:0] (jump target)
    wire    [WORD_SIZE-1:0]     imm_sext;       // sign-extend  : ADI, LWD, SWD, branch offset
    wire    [WORD_SIZE-1:0]     imm_zext;       // zero-extend  : ORI
    wire    [WORD_SIZE-1:0]     imm_lhi;        // {imm, 8'h00} : LHI

    // Register File IF
    reg     [REG_BITS-1:0]      rf_wr_reg;      // RegDst MUX 출력
    reg     [WORD_SIZE-1:0]     rf_wr_data;     // WBSel MUX 출력
    wire    [WORD_SIZE-1:0]     rf_rd_data1;    // $rs
    wire    [WORD_SIZE-1:0]     rf_rd_data2;    // $rt

    // ALU IF
    reg     [WORD_SIZE-1:0]     alu_operand2;   // ALUSrc MUX 출력 (operand1 = $rs)
    wire    [WORD_SIZE-1:0]     alu_result;
    wire                        alu_overflow;   // not used
    wire                        alu_bcond;      // branch 조건 (NE/EQ/GZ/LZ)

    // Control Unit IF
    wire    [1:0]               ctrl_reg_dst;
    wire                        ctrl_reg_write;
    wire    [1:0]               ctrl_alu_src;
    wire    [4:0]               ctrl_alu_op;
    wire                        ctrl_mem_read;
    wire                        ctrl_mem_write;
    wire    [1:0]               ctrl_wb_sel;
    wire                        ctrl_branch;
    wire                        ctrl_jump;
    wire                        ctrl_jump_reg;
    wire                        ctrl_wwd;

    // Program Counter IF
    wire    [WORD_SIZE-1:0]     pc_plus1;       // PC + 1
    wire    [WORD_SIZE-1:0]     br_target;      // PC + 1 + sext(offset)
    wire    [WORD_SIZE-1:0]     jmp_target;     // {PC[15:12], target}
    wire                        br_taken;       // Branch & bcond
    reg     [WORD_SIZE-1:0]     pc_nxt;         // 다음 PC (PC MUX 출력)



/********************************************************
    Reg Variable Declaration
********************************************************
    State Signal
    - Interrupt Handling State Signals (ex. IDLE, ACTIVE, ...)
    - Program Counter Signal
    - etc.

    State Dependent Signals
    - Data Memory Control Signals (if interrupted, read/write is disabled)
    - Interrupt Handler Control Signals (interrupt request is based with interrupt state)
    - etc.
********************************************************/

    // Program Counter, Interrupt Handle State
    localparam S_EXEC = 1'b0;                   // 명령어 실행
    localparam S_WAIT = 1'b1;                   // WWD : ir_ack 대기

    reg     [WORD_SIZE-1:0]     pc;
    reg                         state, state_nxt;
    reg                         stall;          // 1이면 PC 유지, dmem read/write 차단
    reg                         ir_req;
    reg     [WORD_SIZE-1:0]     ir_msg;

    // MUX select 값 (control_unit.v와 동일)
    localparam RD_RT    = 2'b00, RD_RD    = 2'b01, RD_R2    = 2'b10;
    localparam SRC_RT   = 2'b00, SRC_SEXT = 2'b01, SRC_ZEXT = 2'b10;
    localparam WB_ALU   = 2'b00, WB_MEM   = 2'b01, WB_PC1   = 2'b10, WB_LHI = 2'b11;


    // Part1: Instruction Memory Datapath
    assign imem_raddr_o = pc;

    assign opcode   = imem_rdata_i[15:12];
    assign rs       = imem_rdata_i[11:10];
    assign rt       = imem_rdata_i[9:8];
    assign rd       = imem_rdata_i[7:6];
    assign func     = imem_rdata_i[5:0];
    assign imm      = imem_rdata_i[7:0];
    assign target   = imem_rdata_i[11:0];

    assign imm_sext = {{8{imm[7]}}, imm};
    assign imm_zext = {8'h00, imm};
    assign imm_lhi  = {imm, 8'h00};


    // Part2: Register File Datapath
    // RegDst MUX : write register 선택
    always @(*) begin
        case (ctrl_reg_dst)
            RD_RD:   rf_wr_reg = rd;            // R-type
            RD_R2:   rf_wr_reg = 2'd2;          // JAL, JRL : $2 <- PC + 1
            default: rf_wr_reg = rt;            // I-type
        endcase
    end

    // WBSel MUX : write-back data 선택
    always @(*) begin
        case (ctrl_wb_sel)
            WB_MEM:  rf_wr_data = dmem_rdata_i; // LWD
            WB_PC1:  rf_wr_data = pc_plus1;     // JAL, JRL
            WB_LHI:  rf_wr_data = imm_lhi;      // LHI
            default: rf_wr_data = alu_result;   // ALU 연산
        endcase
    end

    // Register File
    RegisterFile #(
        .WORD_SIZE  (WORD_SIZE),
        .REG_BITS   (REG_BITS)
    ) rf_w16_r4 (
        .clk        (clk),
        .reset_n    (reset_n),
        .wr_enable  (ctrl_reg_write),
        .rd_reg1    (rs),
        .rd_reg2    (rt),
        .wr_reg     (rf_wr_reg),
        .rd_data1   (rf_rd_data1),
        .rd_data2   (rf_rd_data2),
        .wr_data    (rf_wr_data)
    );

    // Part3: ALU Datapath
    // ALUSrc MUX : ALU operand2 선택
    always @(*) begin
        case (ctrl_alu_src)
            SRC_SEXT: alu_operand2 = imm_sext;  // ADI, LWD, SWD
            SRC_ZEXT: alu_operand2 = imm_zext;  // ORI
            default:  alu_operand2 = rf_rd_data2;
        endcase
    end

    // Arithmetic Logic Unit
    ALU alu_w16_m (
        .A_i        (rf_rd_data1),
        .B_i        (alu_operand2),
        .OP_i       (ctrl_alu_op),
        .C_i        (1'b0),
        .F_o        (alu_result),
        .C_o        (alu_overflow),
        .bcond_o    (alu_bcond)
    );

    // Data Memory IF : 주소 = ALU 결과, 쓰기 데이터 = $rt
    assign dmem_addr_o  = alu_result;
    assign dmem_wdata_o = rf_rd_data2;
    assign dmem_read_o  = ctrl_mem_read  & ~stall;  // interrupt 중에는 read/write 차단
    assign dmem_write_o = ctrl_mem_write & ~stall;


    // Part4: Control Unit Datapath

    // Control Unit
    ControlUnit ctrl_unit (
        .opcode     (opcode),
        .func       (func),
        .reg_dst    (ctrl_reg_dst),
        .reg_write  (ctrl_reg_write),
        .alu_src    (ctrl_alu_src),
        .alu_op     (ctrl_alu_op),
        .mem_read   (ctrl_mem_read),
        .mem_write  (ctrl_mem_write),
        .wb_sel     (ctrl_wb_sel),
        .branch     (ctrl_branch),
        .jump       (ctrl_jump),
        .jump_reg   (ctrl_jump_reg),
        .wwd        (ctrl_wwd)
    );

    // Part5: Program Counter Datapath
    assign pc_plus1   = pc + 1'b1;                  // word addressing -> +1
    assign br_target  = pc_plus1 + imm_sext;        // 다음 명령어 주소 + offset (TSC-ISA)
    assign jmp_target = {pc[15:12], target};        // 현재 PC 상위 4bit ## target 12bit
    assign br_taken   = ctrl_branch & alu_bcond;

    // PC MUX : Branch -> Jump -> JumpReg 순서로 덮어씀 (뒤가 우선)
    always @(*) begin
        pc_nxt = br_taken ? br_target : pc_plus1;   // Branch MUX
        if (ctrl_jump)     pc_nxt = jmp_target;     // Jump MUX    (JMP, JAL)
        if (ctrl_jump_reg) pc_nxt = rf_rd_data1;    // JumpReg MUX (JPR, JRL)
        if (stall)         pc_nxt = pc;             // WWD : ir_ack 받을 때까지 PC 정지
    end


    // Part6: Program Counter & Interrupt Handler with FSM
    // - program counter, data memory, interrupt handler is dependant with interrupt state
    // - interrupt occured, program counter update is
    // - interrupt occured, data memory read/write is disabled
    // - Instruction Memory Model (Read-only / Single Port)
    //      - 16-bit aligned memory
    //      - you need to update imem_addr +1 to PC up (not +2)
    //      - no jump/branch, imem_addr_nxt = imem_addr + 1
    //      - branch, imem_addr_nxt = imem_addr + imm_value
    //      - jump, imem_addr_nxt = target address
    // - Example
    //      - imem_rdata = 16'h2001; BGZ $0, 1        -> if ($0 > 0) pc=pc+1
    //          - 16'h2001 = 16'b0010_0000_0000_0001
    //      - imem_rdata = 16'h908b; JMP 0x8b(139)    -> pc='d139
    //          - 16'h908b = 16'b1001_0000_1000_1011

    // PC, state register
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            pc    <= {WORD_SIZE{1'b0}};
            state <= S_EXEC;
        end else begin
            pc    <= pc_nxt;
            state <= state_nxt;
        end
    end

    // next state & output logic (Lab4 FSM 구조 유지)
    always @(*) begin
        state_nxt = state;
        stall     = 1'b0;
        ir_req    = 1'b0;
        ir_msg    = {WORD_SIZE{1'b0}};

        case (state)
            S_EXEC: begin
                if (ctrl_wwd) begin
                    ir_req    = 1'b1;
                    ir_msg    = rf_rd_data1;    // interrupt message = $rs
                    stall     = 1'b1;
                    state_nxt = S_WAIT;
                end
            end

            S_WAIT: begin
                ir_msg = rf_rd_data1;           // PC가 멈춰 있으므로 여전히 같은 WWD의 $rs
                if (ir_ack_i) begin
                    state_nxt = S_EXEC;         // ack 수신 -> ir_req 해제, PC + 1
                end else begin
                    ir_req    = 1'b1;           // ack 올 때까지 요청 유지
                    stall     = 1'b1;
                end
            end

            default: state_nxt = S_EXEC;
        endcase
    end

    assign ir_req_o = ir_req;
    assign ir_msg_o = ir_msg;


endmodule
