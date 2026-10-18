// Extra credit: testbench for jump and link instructions (JAL, JRL) and JPR.
// Same instruction / data memory models and interrupt handler as cpu_tb.v; runs Program5 only.
// Run: iverilog cpu_tb_jal.v cpu.v alu.v register_file.v control_unit.v data_memory.v
`timescale 1ns / 100ps

module CPU_W16_R4_jal_tb ();

    // Parameter Definitions
    parameter  CLOCK_PS     = 10;   // clock period
    parameter  HCLOCK_PS    = 5;    // half clock period
    localparam WORD_SIZE    = 16;   // 16-bit word size (16-bit = 2B)
    localparam REG_BITS     = 2;    // 16-bit register file with 4 registers (2B x 4 = 8B)
    localparam MEM_SIZE     = 256;  // 16-bit aligned memory (2B x 256 = 512B)

    // Global Signals
    reg clk;
    reg reset_n;
    
    // Instruction Memory IF (Read-only / Single Port)
    reg     [WORD_SIZE-1:0]     imem_rdata;         // instruction read data
    wire    [WORD_SIZE-1:0]     imem_addr;          // instruction read address
    
    // Data Memory IF (Read/Write / Ture Single Port)
    wire    [WORD_SIZE-1:0]     dmem_addr;          // data memory access address
    wire    [WORD_SIZE-1:0]     dmem_rdata;         // data memory read data (to CPU)
    wire    [WORD_SIZE-1:0]     dmem_wdata;         // data memory write data (from CPU)
    wire                        dmem_read;          // data memory read enable
    wire                        dmem_write;         // data memory write enable
    
    // Interrupt Handler IF (for debugging purpose)
    reg                         ir_ack;             // interrupt acknowledge signal
    wire                        ir_req;             // interrupt request 
    reg     [WORD_SIZE-1:0]     ir_msg_to_cpu;      // handler -> cpu (for RWD, not used) 
    wire    [WORD_SIZE-1:0]     ir_msg_to_handler;  // cpu -> handler (for WWD)
    
    // CPU Instance
    CPU_W16_R4 #(
        .WORD_SIZE      (WORD_SIZE),
        .REG_BITS       (REG_BITS)
    ) u_CPU_W16_R4 (
        .clk            (clk),
        .reset_n        (reset_n),
        .imem_rdata_i   (imem_rdata),
        .imem_raddr_o   (imem_addr),
        .ir_ack_i       (ir_ack),
        .ir_req_o       (ir_req),
        .ir_msg_i       (ir_msg_to_cpu),
        .ir_msg_o       (ir_msg_to_handler),
        .dmem_addr_o    (dmem_addr),
        .dmem_rdata_i   (dmem_rdata),
        .dmem_wdata_o   (dmem_wdata),
        .dmem_read_o    (dmem_read),
        .dmem_write_o   (dmem_write)
    );

    // Instruction Memory Model (Read-only)
    integer i;
    reg [WORD_SIZE-1:0] inst_mem [0:MEM_SIZE-1];
    initial begin
        for (i = 0; i < MEM_SIZE; i = i + 1) begin
            inst_mem[i] = {WORD_SIZE{1'b0}};
        end
    end
    always @(*) begin
        imem_rdata = inst_mem[imem_addr];   // 16-bit aligned memory
    end
                                            
    // Instruction Memory Instance (We use Model code instead of module,
    //                              it is convenient for debugging purpose)
    // InstructionMemory #(
    //     .WORD_SIZE    (WORD_SIZE),
    //     .MEM_SIZE     (MEM_SIZE)
    // ) u_inst_mem (
    //     .imem_raddr_i (imem_raddr),
    //     .imem_rdata_o (imem_rdata)
    // );
    
    
    // Data Memory IF (Read/Write)
    DataMemory #(
        .WORD_SIZE    (WORD_SIZE),
        .MEM_SIZE     (MEM_SIZE)
    ) u_data_mem (
        .clk          (clk),
        .dmem_read_i  (dmem_read),
        .dmem_write_i (dmem_write),
        .dmem_addr_i  (dmem_addr),
        .dmem_wdata_i (dmem_wdata),
        .dmem_rdata_o (dmem_rdata)
    );
    

    // Clock Signal Generation
    integer timestamp;
    initial begin : CLOCK_GENERATOR
        clk = 1'b0;
        timestamp = 0;
        forever #HCLOCK_PS clk = ~clk;
    end
    always @(posedge clk) begin
        timestamp = timestamp + 1;
    end


    // Interrupt Handler
    reg [31:0] ir_passed, ir_cursor;
    reg [WORD_SIZE-1:0] ir_msg_reference [0:MEM_SIZE-1];
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ir_ack      <= 1'b0;
            ir_passed   <= 'd0;
            ir_cursor   <= 'd0;
        end 
        else if (ir_req && (!ir_ack)) begin
            ir_ack      <= 1'b1;
            ir_cursor   <= ir_cursor + 1;
            if (ir_msg_to_handler == ir_msg_reference[ir_cursor]) begin
                $display("test #%2d succeed with message: %1d", ir_cursor, ir_msg_to_handler);
                ir_passed <= ir_passed + 1;
            end else begin
                $display("test #%2d failed since output message (%3d) is not the same with the reference (%3d)", ir_cursor, ir_msg_to_handler, ir_msg_reference[ir_cursor]);
            end
        end 
        else if (!ir_req) begin
            ir_ack <= 1'b0;
        end
    end


    // Testbench
    integer iter_cnt;
    initial begin
        ir_msg_to_cpu = 'd0;
        //$dumpfile("vcd/cpu_tb.vcd");
        //$dumpvars(0, top);
        Program5;   // jump and link test only
        $finish();
    end


// Task Definitions (Sub-Task, Program, ...)
task ExecuteProgram;
    input [31:0] cursor_limit;
begin
    reset_n = 'd0;
    #CLOCK_PS;
    reset_n = 'd1;
    iter_cnt = 0;
    while ((ir_cursor <= cursor_limit) && (iter_cnt < MEM_SIZE)) begin
        #CLOCK_PS;
        iter_cnt = iter_cnt + 1;
    end
    $display("%1d succeed out of %1d tests in total", ir_passed, ir_cursor);
end
endtask

// Extra credit: jump and link test
//  - JAL : $2 <- PC + 1, PC <- {PC[15:12], target}
//  - JRL : $2 <- PC + 1, PC <- $rs  (JRL $2 must jump to the old $2)
//  - JPR : return with $2, nested call keeps the outer $2 in data memory
//  - every subroutine ends with JPR $2 followed by a "WWD $0" trap (prints 0, never expected)
task Program5;
begin
    $display("\n:: EXECUTING PROGRAM 5 :: (jump and link)");
    for (i = 0; i < MEM_SIZE; i = i + 1) begin
        inst_mem[i] = {WORD_SIZE{1'b0}};    // 16'h0000 = BNE $0, $0, 0 (never taken, NOP)
    end

    // main
    inst_mem[16'h00] = 16'ha020;  // JAL 0x20            : $2 <- 0x01, call A
    inst_mem[16'h01] = 16'hf41c;  // WWD $1              : returned from A ($1 = 5)
    inst_mem[16'h02] = 16'h6300;  // LHI $3, 0
    inst_mem[16'h03] = 16'h5f28;  // ORI $3, $3, 0x28    : $3 = 0x0028 (address of B)
    inst_mem[16'h04] = 16'hfc1a;  // JRL $3              : $2 <- 0x05, call B
    inst_mem[16'h05] = 16'hf41c;  // WWD $1              : returned from B ($1 = 6)
    inst_mem[16'h06] = 16'h6200;  // LHI $2, 0
    inst_mem[16'h07] = 16'h5a30;  // ORI $2, $2, 0x30    : $2 = 0x0030 (address of C)
    inst_mem[16'h08] = 16'hf81a;  // JRL $2              : PC <- old $2 (0x30), $2 <- 0x09
    inst_mem[16'h09] = 16'hf41c;  // WWD $1              : returned from C ($1 = 7)
    inst_mem[16'h0a] = 16'ha038;  // JAL 0x38            : $2 <- 0x0b, call D (nested)
    inst_mem[16'h0b] = 16'hf41c;  // WWD $1              : returned from D ($1 = 8)
    inst_mem[16'h0c] = 16'h900c;  // JMP 0x0c            : end (stay here)

    // A : called by JAL
    inst_mem[16'h20] = 16'hf81c;  // WWD $2              : 0x0001 (return address = PC + 1)
    inst_mem[16'h21] = 16'h4105;  // ADI $1, $0, 5
    inst_mem[16'h22] = 16'hf819;  // JPR $2              : return to 0x01
    inst_mem[16'h23] = 16'hf01c;  // WWD $0              : trap
    // B : called by JRL $3
    inst_mem[16'h28] = 16'hf81c;  // WWD $2              : 0x0005
    inst_mem[16'h29] = 16'h4501;  // ADI $1, $1, 1
    inst_mem[16'h2a] = 16'hf819;  // JPR $2              : return to 0x05
    inst_mem[16'h2b] = 16'hf01c;  // WWD $0              : trap
    // C : called by JRL $2
    inst_mem[16'h30] = 16'hf81c;  // WWD $2              : 0x0009
    inst_mem[16'h31] = 16'h4501;  // ADI $1, $1, 1
    inst_mem[16'h32] = 16'hf819;  // JPR $2              : return to 0x09
    inst_mem[16'h33] = 16'hf01c;  // WWD $0              : trap
    // D : calls E, keeps its own return address in M[0x40]
    inst_mem[16'h38] = 16'h8240;  // SWD $2, $0, 0x40    : M[0x40] <- 0x000b
    inst_mem[16'h39] = 16'ha03e;  // JAL 0x3e            : $2 <- 0x3a, call E
    inst_mem[16'h3a] = 16'h7240;  // LWD $2, $0, 0x40    : $2 <- 0x000b
    inst_mem[16'h3b] = 16'hf81c;  // WWD $2              : 0x000b
    inst_mem[16'h3c] = 16'hf819;  // JPR $2              : return to 0x0b
    inst_mem[16'h3d] = 16'hf01c;  // WWD $0              : trap
    // E : called by JAL inside D
    inst_mem[16'h3e] = 16'hf81c;  // WWD $2              : 0x003a
    inst_mem[16'h3f] = 16'h4501;  // ADI $1, $1, 1
    inst_mem[16'h40] = 16'hf819;  // JPR $2              : return to 0x3a
    inst_mem[16'h41] = 16'hf01c;  // WWD $0              : trap

    // Expected Outputs
    ir_msg_reference[0] = 16'h0001;  // A    : $2 after JAL 0x20 at 0x00
    ir_msg_reference[1] = 16'h0005;  // main : $1 set by A
    ir_msg_reference[2] = 16'h0005;  // B    : $2 after JRL $3 at 0x04
    ir_msg_reference[3] = 16'h0006;  // main : $1 set by B
    ir_msg_reference[4] = 16'h0009;  // C    : $2 after JRL $2 at 0x08
    ir_msg_reference[5] = 16'h0007;  // main : $1 set by C
    ir_msg_reference[6] = 16'h003a;  // E    : $2 after JAL 0x3e at 0x39
    ir_msg_reference[7] = 16'h000b;  // D    : $2 restored from M[0x40]
    ir_msg_reference[8] = 16'h0008;  // main : $1 set by E

    ExecuteProgram(8);   // 9 messages (cursor 0 ~ 8)
end
endtask

endmodule
