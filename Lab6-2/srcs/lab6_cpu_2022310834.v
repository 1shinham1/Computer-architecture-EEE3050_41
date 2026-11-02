`include "lab6_opcodes_2022310834.v"

module CPU_W16_R4 #(
    parameter WORD_SIZE = 16,
    parameter REG_BITS  = 2
)
(
    // Global Signals
    input   wire    clk,      // global positive edge triggered clock
    input   wire    reset_n,  // global asynchronous negative triggered reset

    // Interrupt Handler IF (for debugging purpose)
    input   wire                        ir_ack_i,       // triggered when the given interrupt is properly handled
    output  wire                        ir_req_o,       // triggered when the internal interrupt occurs
    input   wire    [WORD_SIZE-1:0]     ir_msg_i,       // message transfer from interrupt handler
    output  wire    [WORD_SIZE-1:0]     ir_msg_o,       // message transfer to interrupt handler

    // Memory IF
    output  wire    [WORD_SIZE-1:0]     mem_addr_o,    // memory read address
    input   wire    [WORD_SIZE-1:0]     mem_rdata_i,   // memory read port
    output  wire    [WORD_SIZE-1:0]     mem_wdata_o,   // memory write port
    output  wire                        mem_read_o,    // memory read enable
    output  wire                        mem_write_o    // memory write enable
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
    wire    [3:0]               opcode;         // ir[15:12]
    wire    [REG_BITS-1:0]      rs;             // ir[11:10]
    wire    [REG_BITS-1:0]      rt;             // ir[9:8]
    wire    [REG_BITS-1:0]      rd;             // ir[7:6]
    wire    [5:0]               func;           // ir[5:0]
    wire    [7:0]               imm;            // ir[7:0]  (immediate / branch offset)
    wire    [11:0]              target;         // ir[11:0] (jump target)
    wire    [WORD_SIZE-1:0]     imm_sext;       // sign extend : ADI, LWD, SWD, branch offset
    wire    [WORD_SIZE-1:0]     imm_zext;       // zero extend : ORI
    wire    [WORD_SIZE-1:0]     imm_lhi;        // {imm, 8'h00} : LHI

    // Register File IF
    reg     [REG_BITS-1:0]      rf_wr_reg;      // RegDst MUX 출력
    reg     [WORD_SIZE-1:0]     rf_wr_data;     // WBSel MUX 출력
    wire    [WORD_SIZE-1:0]     rf_rd_data1;    // $rs
    wire    [WORD_SIZE-1:0]     rf_rd_data2;    // $rt

    // ALU IF
    wire    [WORD_SIZE-1:0]     alu_operand1;   // ALUSrcA MUX 출력
    reg     [WORD_SIZE-1:0]     alu_operand2;   // ALUSrcB MUX 출력
    wire    [WORD_SIZE-1:0]     alu_result;
    wire                        alu_overflow;   // not used
    wire                        alu_bcond;      // branch 조건 (NE/EQ/GZ/LZ)

    // Control Unit IF
    wire                        ctrl_mem_read;
    wire                        ctrl_mem_write;
    wire                        ctrl_i_or_d;
    wire                        ctrl_ir_write;
    wire                        ctrl_pc_write;
    wire                        ctrl_pc_write_cond;
    wire    [1:0]               ctrl_pc_source;
    wire                        ctrl_alu_src_a;
    wire    [1:0]               ctrl_alu_src_b;
    wire    [4:0]               ctrl_alu_op;
    wire                        ctrl_reg_write;
    wire    [1:0]               ctrl_reg_dst;
    wire    [1:0]               ctrl_wb_sel;

    // Program Counter IF
    wire    [WORD_SIZE-1:0]     jmp_target;     // {PC[15:12], target}
    wire                        pc_en;          // PCWrite | (PCWriteCond & bcond)
    reg     [WORD_SIZE-1:0]     pc_nxt;         // PCSource MUX 출력



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
    // FSM state는 control_unit.v에 있고, 아래 register는 모두 DFF 모듈의 출력이다
    wire    [WORD_SIZE-1:0]     pc;
    wire    [WORD_SIZE-1:0]     ir;             // 실행 중인 instruction
    wire    [WORD_SIZE-1:0]     mdr;            // LWD로 읽은 data
    wire    [WORD_SIZE-1:0]     reg_a;          // 읽어 둔 $rs
    wire    [WORD_SIZE-1:0]     reg_b;          // 읽어 둔 $rt
    wire    [WORD_SIZE-1:0]     alu_out;        // ALU 결과

    // MUX select 값 (control_unit.v와 동일)
    localparam PC_ALU   = 2'b00, PC_JUMP  = 2'b01, PC_RS    = 2'b10, PC_ALUOUT = 2'b11;
    localparam SRCB_B   = 2'b00, SRCB_SEXT = 2'b01, SRCB_ZEXT = 2'b10, SRCB_ONE = 2'b11;
    localparam RD_RT    = 2'b00, RD_RD    = 2'b01, RD_R2    = 2'b10;
    localparam WB_ALUOUT = 2'b00, WB_MDR  = 2'b01, WB_PC    = 2'b10, WB_LHI   = 2'b11;


    // Part1: Instruction Memory Datapath
    // Unified memory : IorD MUX로 주소 선택, 쓰기 데이터 = B
    assign mem_addr_o  = ctrl_i_or_d ? alu_out : pc;
    assign mem_wdata_o = reg_b;
    assign mem_read_o  = ctrl_mem_read;
    assign mem_write_o = ctrl_mem_write;

    assign opcode   = ir[15:12];
    assign rs       = ir[11:10];
    assign rt       = ir[9:8];
    assign rd       = ir[7:6];
    assign func     = ir[5:0];
    assign imm      = ir[7:0];
    assign target   = ir[11:0];

    assign imm_sext = {{8{imm[7]}}, imm};
    assign imm_zext = {8'h00, imm};
    assign imm_lhi  = {imm, 8'h00};


    // Part2: Register File Datapath
    // RegDst MUX : write register 선택
    always @(*) begin
        case (ctrl_reg_dst)
            RD_RD:   rf_wr_reg = rd;            // R-type
            RD_R2:   rf_wr_reg = 2'd2;          // JAL, JRL : return address
            default: rf_wr_reg = rt;            // I-type
        endcase
    end

    // WBSel MUX : write-back data 선택
    always @(*) begin
        case (ctrl_wb_sel)
            WB_MDR:  rf_wr_data = mdr;          // LWD
            WB_PC:   rf_wr_data = pc;           // JAL, JRL : PC는 IF1에서 이미 다음 주소
            WB_LHI:  rf_wr_data = imm_lhi;      // LHI
            default: rf_wr_data = alu_out;      // ALU 연산
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
    // ALUSrcA MUX : ALU operand1 선택
    assign alu_operand1 = ctrl_alu_src_a ? reg_a : pc;

    // ALUSrcB MUX : ALU operand2 선택
    always @(*) begin
        case (ctrl_alu_src_b)
            SRCB_SEXT: alu_operand2 = imm_sext;         // ADI, LWD, SWD, branch target
            SRCB_ZEXT: alu_operand2 = imm_zext;         // ORI
            SRCB_ONE:  alu_operand2 = 16'd1;             // next PC
            default:   alu_operand2 = reg_b;
        endcase
    end

    // Arithmetic Logic Unit
    ALU alu_w16_m (
        .A_i        (alu_operand1),
        .B_i        (alu_operand2),
        .OP_i       (ctrl_alu_op),
        .C_i        (1'b0),
        .F_o        (alu_result),
        .C_o        (alu_overflow),
        .bcond_o    (alu_bcond)
    );


    // Part4: Control Unit Datapath

    // Control Unit
    ControlUnit ctrl_unit (
        .clk            (clk),
        .reset_n        (reset_n),
        .opcode         (opcode),
        .func           (func),
        .ir_ack         (ir_ack_i),
        .mem_read       (ctrl_mem_read),
        .mem_write      (ctrl_mem_write),
        .i_or_d         (ctrl_i_or_d),
        .ir_write       (ctrl_ir_write),
        .pc_write       (ctrl_pc_write),
        .pc_write_cond  (ctrl_pc_write_cond),
        .pc_source      (ctrl_pc_source),
        .alu_src_a      (ctrl_alu_src_a),
        .alu_src_b      (ctrl_alu_src_b),
        .alu_op         (ctrl_alu_op),
        .reg_write      (ctrl_reg_write),
        .reg_dst        (ctrl_reg_dst),
        .wb_sel         (ctrl_wb_sel),
        .ir_req         (ir_req_o)
    );

    // Interrupt message = $rs (WAIT에 오기 전 ID 끝에서 A에 저장됨)
    assign ir_msg_o = reg_a;

    // Part5: Program Counter Datapath
    assign jmp_target = {pc[15:12], target};
    assign pc_en      = ctrl_pc_write | (ctrl_pc_write_cond & alu_bcond);

    // PCSource MUX
    always @(*) begin
        case (ctrl_pc_source)
            PC_JUMP:   pc_nxt = jmp_target;     // JMP, JAL
            PC_RS:     pc_nxt = rf_rd_data1;    // JPR, JRL : ID에서 끝나므로 A 대신 RF 출력 사용
            PC_ALUOUT: pc_nxt = alu_out;        // taken branch
            default:   pc_nxt = alu_result;     // next PC
        endcase
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

    // PC, IR은 필요한 cycle에만 저장
    DFF #(.WIDTH(WORD_SIZE)) pc_reg      (.clk(clk), .reset_n(reset_n), .en(pc_en),         .d(pc_nxt),      .q(pc));
    DFF #(.WIDTH(WORD_SIZE)) ir_reg      (.clk(clk), .reset_n(reset_n), .en(ctrl_ir_write), .d(mem_rdata_i), .q(ir));

    // MDR, A, B, ALUOut은 저장한 바로 다음 cycle에 사용하므로 매 cycle 저장 - en에 항상 1
    DFF #(.WIDTH(WORD_SIZE)) mdr_reg     (.clk(clk), .reset_n(reset_n), .en(1'b1),          .d(mem_rdata_i), .q(mdr));
    DFF #(.WIDTH(WORD_SIZE)) reg_a_reg   (.clk(clk), .reset_n(reset_n), .en(1'b1),          .d(rf_rd_data1), .q(reg_a));
    DFF #(.WIDTH(WORD_SIZE)) reg_b_reg   (.clk(clk), .reset_n(reset_n), .en(1'b1),          .d(rf_rd_data2), .q(reg_b));
    DFF #(.WIDTH(WORD_SIZE)) alu_out_reg (.clk(clk), .reset_n(reset_n), .en(1'b1),          .d(alu_result),  .q(alu_out));

endmodule


// Enable이 있는 D-FF : PC, IR, MDR, A, B, ALUOut에 공통으로 사용
module DFF #(
    parameter WIDTH = 16
)
(
    input   wire                clk,
    input   wire                reset_n,
    input   wire                en,
    input   wire    [WIDTH-1:0] d,
    output  reg     [WIDTH-1:0] q
);
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)   q <= {WIDTH{1'b0}};
        else if (en)    q <= d;
    end
endmodule
