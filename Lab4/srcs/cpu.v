`include "opcodes.v"

module CPU_W16_R4 (  // CPU with its word size 16 and 4 registers
    input clk,      // global positive edge triggered clock
    input reset_n,  // global asynchronous negative triggered reset 

    // interface with instruction memory 
    input      [15:0] rd_inst,    // instruction read port
    output reg [15:0] inst_addr,  // instruction address (synchronous to the clock)

    // interface for internal interrupt (for debugging purpose)
    input             ir_ack,  // interrupt acknowledge signal (acknowledge signal from the interrupt handler, triggered when the given interrupt is properly handled)
    output reg        ir_req,  // interrupt request signal (triggered when the internal interrupt occurs, may not be synchronous to the clock)
    output reg [15:0] ir_msg   // interrupt message (message transferred to the interrupt handler, may not be synchronous to the clock)
);

/*******************************************************
 * PART 1: Skeleton Codes
 *******************************************************
 
 Description
   - This part provides skeleton code of the TSC ISA based CPU
   - Useful local parameters are provided
   - Output port that should be defined as a D-FF is declared here (inst_addr -> inst_addr_nxt)
   - ALU is instantiated
   - Register File is instantiated

 Note
   - You can modify the skeleton code to optimize your design
   - You should use the ALU and Register File design implemented in previous lab assignment
   - The address for instruction memory (inst_addr) should be synchronous to the clock
 */

// SECTION: Local Parameters
localparam WORD_SIZE = 16;  // size of each word, address
localparam REG_BITS  = 2;   // the size of register index (4 registers -> 2bit register ID)

// SECTION: Wires and Registers
reg [15:0] inst_addr_nxt;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        inst_addr <= 'd0;
    end else begin
        inst_addr <= inst_addr_nxt;
    end
end

// SECTION: ALU instantiation
reg  [15:0] alu_operand1,  // ALU: first operand (or operand A) 
            alu_operand2;  // ALU: second operand (or operand B)
reg  [3 :0] alu_opcode;    // ALU: opcode (it may be different to the instruction's opcode)
wire [15:0] alu_result;    // ALU: output result
wire        alu_overflow;  // ALU: overflow or carry output

ALU alu_w16_m (
    .A_i(alu_operand1), .B_i(alu_operand2), .OP_i(alu_opcode), .C_i(1'b0), 
    .F_o(alu_result), .C_o(alu_overflow)
);

// SECTION: Register File instantiation
reg                  rf_wr_enable;  // Register File: write enable
reg  [REG_BITS -1:0] rf_rd_reg1;    // Register File: read register 1
reg  [REG_BITS -1:0] rf_rd_reg2;    // Register File: read register 2
reg  [REG_BITS -1:0] rf_wr_reg;     // Register File: write register
wire [WORD_SIZE-1:0] rf_rd_data1;   // Register File: read data 1
wire [WORD_SIZE-1:0] rf_rd_data2;   // Register File: read data 2
reg  [WORD_SIZE-1:0] rf_wr_data;    // Register File: write data

RegisterFile #(
    .WORD_SIZE(WORD_SIZE), .REG_BITS(REG_BITS)
) rf_w16_r4 (
    .clk(clk), .reset_n(reset_n),
    .wr_enable(rf_wr_enable),
    .rd_reg1(rf_rd_reg1), .rd_reg2(rf_rd_reg2), .wr_reg(rf_wr_reg),
    .rd_data1(rf_rd_data1), .rd_data2(rf_rd_data2), .wr_data(rf_wr_data)
);


/*******************************************************
 * PART 2: Instruction Decoder and Control Unit
 *******************************************************
 
 Description
   - This part is for instruction decoder and control unit
   - As you already learned in the class, the CPU converts instruction into the micro-code that
     are directly transferred to the hardware components
   - Instruction Decoder splits an instruction into multiple fields
   - Control Unit generates control signal transferred to the hardware components 
     e.g. ALU, Register File, Instruction Memory

 Note
   - We highly recommend you to implement the Control Unit as a separate module
   - We provided "control_unit.v" to implement the Control Unit
   - You can define the interface of the Control Unit (it may be different to the MIPS micro-architecture)
 */

// SECTION: Instruction Decoder

// ADD YOUR CODE HERE
// 추가 시작
wire [3:0]          opcode = rd_inst[15:12];
wire [REG_BITS-1:0] rs     = rd_inst[11:10];
wire [REG_BITS-1:0] rt     = rd_inst[9:8];
wire [REG_BITS-1:0] rd     = rd_inst[7:6];
wire [5:0]          func   = rd_inst[5:0];
wire [7:0]          imm    = rd_inst[7:0];
wire [11:0]         target = rd_inst[11:0];

// Immediate 생성
wire [WORD_SIZE-1:0] imm_sext = {{8{imm[7]}}, imm};  // ADI : 8bit imm sign-extension
wire [WORD_SIZE-1:0] imm_lhi  = {imm, 8'h00};        // LHI : imm을 상위 8bit에 배치
// 추가 끝

// SECTION: Control Unit instantiation
// 추가 시작
// Control Unit 출력 (제어 신호)
wire       ctrl_reg_write;  // Register File write enable
wire       ctrl_reg_dst;    // write register 선택 (1: rd / 0: rt)
wire       ctrl_alu_src;    // ALU operand2 선택 (1: imm_sext / 0: $rt)
wire [3:0] ctrl_alu_op;     // ALU opcode
wire       ctrl_lhi;        // write-back data 선택 (1: imm_lhi / 0: ALU result)
wire       ctrl_jump;       // JMP
wire       ctrl_wwd;        // WWD (interrupt)
// 추가 끝

ControlUnit ctrl_unit (
    // FILL OUT THE INTERFACE FOR THE CONTROL UNIT
    // 추가 시작
    .opcode   (opcode),
    .func     (func),
    .reg_write(ctrl_reg_write),
    .reg_dst  (ctrl_reg_dst),
    .alu_src  (ctrl_alu_src),
    .alu_op   (ctrl_alu_op),
    .lhi      (ctrl_lhi),
    .jump     (ctrl_jump),
    .wwd      (ctrl_wwd)
    // 추가 끝
);


/*******************************************************
 * PART 3: Finite State Machine
 *******************************************************
 
 Description
   - This part is for finite state machine (FSM) that controls the CPU

 Note
   - You may need to create an FSM to control the CPU and properly trigger interrupt
   - Note that the CPU should stop executing instructions until it receives an acknowledge signal
     from the external interrupt handler once it triggers an interrupt
   - If you did not use FSM, ignore this part!
 */

// SECTION: Finite State Machine

// ADD YOUR CODE HERE
// 추가 시작
localparam S_EXEC = 1'b0;
localparam S_WAIT = 1'b1;

reg state, state_nxt;
reg stall;              // 1이면 PC 유지 (명령어 실행 정지)

// state register (inst_addr와 같은 clock / async reset)
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= S_EXEC;
    end else begin
        state <= state_nxt;
    end
end

// next state & output logic (조합 회로 -> ir_req/ir_msg는 clock에 비동기)
always @(*) begin
    state_nxt = state;
    stall     = 1'b0;
    ir_req    = 1'b0;
    ir_msg    = {WORD_SIZE{1'b0}};

    case (state)
        S_EXEC: begin
            if (ctrl_wwd) begin
                ir_req    = 1'b1;
                ir_msg    = rf_rd_data1;   // interrupt message = $rs
                stall     = 1'b1;
                state_nxt = S_WAIT;
            end
        end

        S_WAIT: begin
            ir_msg = rf_rd_data1;          // PC가 멈춰 있으므로 여전히 같은 WWD의 $rs
            if (ir_ack) begin
                state_nxt = S_EXEC;        // ack 수신 -> ir_req 해제, PC+1
            end else begin
                ir_req    = 1'b1;          // ack 올 때까지 요청 유지
                stall     = 1'b1;
            end
        end

        default: state_nxt = S_EXEC;
    endcase
end
// 추가 끝


/*******************************************************
 * PART 4: Datapath
 *******************************************************
 Description
   - This part is for datapath of the CPU
   - The datapath determines how the hardware components are connected to each other
 */
// SECTION: Datapath
// ADD YOUR CODE HERE
// 추가 시작
// (1) Register File 연결
always @(*) begin
    rf_rd_reg1   = rs;                                  // $rs 읽기 (ADD, ADI, WWD)
    rf_rd_reg2   = rt;                                  // $rt 읽기 (ADD)
    rf_wr_reg    = ctrl_reg_dst ? rd : rt;              // RegDst MUX : R-type -> $rd, I-type -> $rt
    rf_wr_enable = ctrl_reg_write;
    rf_wr_data   = ctrl_lhi ? imm_lhi : alu_result;     // write-back MUX : LHI -> imm_lhi, 그 외 -> ALU 결과
end

// (2) ALU 연결
always @(*) begin
    alu_operand1 = rf_rd_data1;                         // A = $rs
    alu_operand2 = ctrl_alu_src ? imm_sext : rf_rd_data2; // ALUSrc MUX : ADI -> imm, ADD -> $rt
    alu_opcode   = ctrl_alu_op;
end

// (3) PC update logic (inst_addr_nxt -> 위의 D-FF에서 posedge에 inst_addr로 반영)
wire [WORD_SIZE-1:0] pc_plus1   = inst_addr + 16'd1;          // TSC는 word 단위 주소 -> +1
wire [WORD_SIZE-1:0] jmp_target = {inst_addr[15:12], target}; // 현재 PC 상위 4bit ## target 12bit

always @(*) begin
    if (stall) begin
        inst_addr_nxt = inst_addr;      // WWD : ir_ack 받을 때까지 PC 정지
    end else if (ctrl_jump) begin
        inst_addr_nxt = jmp_target;     // JMP
    end else begin
        inst_addr_nxt = pc_plus1;       // 다음 명령어
    end
end
// 추가 끝

endmodule