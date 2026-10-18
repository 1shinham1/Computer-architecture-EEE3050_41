`timescale 1ns / 100ps

module CPU_W16_R4_tb ();

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
        Program1;
        Program2;
        Program3;
        Program4;
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


task Program1;
begin
    $display("\n:: EXECUTING PROGRAM 1 ::");
    // Program Initialization
    inst_mem[0]  = 16'h6000;            //	LHI $0, 0
	inst_mem[1]  = 16'h6101;            //	LHI $1, 1
    inst_mem[2]  = 16'h6202;            //  LHI $2, 2
	inst_mem[3]  = 16'h6303;            //	LHI $3, 3
	inst_mem[4]  = 16'hf01c;            //	WWD $0  -> 0 
	inst_mem[5]  = 16'hf41c;            //	WWD $1  -> 256
	inst_mem[6]  = 16'hf81c;            //	WWD $2  -> 512
	inst_mem[7]  = 16'hfc1c;            //	WWD $3  -> 768
	inst_mem[8]  = 16'h4204;            //	ADI $2, $0, 4
	inst_mem[9]  = 16'h47fc;            //	ADI $3, $1, -4
	inst_mem[10] = 16'hf81c;            //	WWD $2  -> 4
	inst_mem[11] = 16'hfc1c;            //	WWD $3  -> 252
	inst_mem[12] = 16'hf6c0;            //	ADD $3, $1, $2
	inst_mem[13] = 16'hf180;            //	ADD $2, $0, $1
	inst_mem[14] = 16'hf81c;            //	WWD $2  -> 256
	inst_mem[15] = 16'hfc1c;            //	WWD $3  -> 260
	inst_mem[16] = 16'h9015;            //	JMP 21
	inst_mem[17] = 16'hf01c;            //	WWD $0  -> 0    -> not occur
	inst_mem[18] = 16'hf180;            //	ADD $2, $0, $1  -> not occur
	inst_mem[19] = 16'hf180;            //	ADD $2, $0, $1  -> not occur
	inst_mem[20] = 16'hf180;            //	ADD $2, $0, $1  -> not occur
	inst_mem[21] = 16'h6000;            //	LHI $0, 0
	inst_mem[22] = 16'h4000;            //	ADI $0, $0, 0
	inst_mem[23] = 16'hfd80;            //	ADD $2, $3, $1
	inst_mem[24] = 16'hf01c;            //	WWD $0 -> 0
	inst_mem[25] = 16'hf41c;            //	WWD $1 -> 256
	inst_mem[26] = 16'hf81c;            //	WWD $2 -> 256 + 260 = 516
	inst_mem[27] = 16'hfc1c;            //	WWD $3 -> 260
    // Expected Outputs Initialization
    ir_msg_reference[0]  = 16'd0;       // inst_mem[4]
    ir_msg_reference[1]  = 16'd256;     // inst_mem[5]
    ir_msg_reference[2]  = 16'd512;     // inst_mem[6]
    ir_msg_reference[3]  = 16'd768;     // inst_mem[7]
    ir_msg_reference[4]  = 16'd4;       // inst_mem[10]
    ir_msg_reference[5]  = 16'd252;     // inst_mem[11]
    ir_msg_reference[6]  = 16'd256;     // inst_mem[14]
    ir_msg_reference[7]  = 16'd260;     // inst_mem[15]
    ir_msg_reference[8]  = 16'd0;       // inst_mem[17]     
    ir_msg_reference[9]  = 16'd256;     // inst_mem[24]     
    ir_msg_reference[10] = 16'd516;     // inst_mem[25]
    ir_msg_reference[11] = 16'd260;     // inst_mem[26]
    // Execution
    ExecuteProgram(11);  // execute until interrupt cursor ends up to 11
end
endtask

task Program2;
begin
    $display("\n:: EXECUTING PROGRAM 2 :: Program Init");
    // Program Initialization
    inst_mem[0]  = 16'h6005;            // LHI $0, 5
	inst_mem[1]  = 16'h610d;            // LHI $1, 13
 	inst_mem[2]  = 16'h6215;            // LHI $2, 21
	inst_mem[3]  = 16'h6340;            // LHI $3, 64
    inst_mem[4]  = 16'hf01c;            // WWD $0
	inst_mem[5]  = 16'hf41c;            // WWD $1
	inst_mem[6]  = 16'hf81c;            // WWD $2
	inst_mem[7]  = 16'hfc1c;            // WWD $3
    inst_mem[8]  = 16'hf000;            // ADD $0, $0, $0
    inst_mem[9]  = 16'hfa40;            // ADD $1, $2, $2
    inst_mem[10] = 16'hf01c;            // WWD $0
	inst_mem[11] = 16'hf41c;            // WWD $1
    inst_mem[12] = 16'h60ff;            // LHI $0, 255       // (255 or 0xffff stands for -1)
    inst_mem[13] = 16'hf440;            // ADD $1, $1, $0
    inst_mem[14] = 16'hf880;            // ADD $2, $2, $0
    inst_mem[15] = 16'hf41c;            // WWD $1
	inst_mem[16] = 16'hf81c;            // WWD $2
	inst_mem[17] = 16'hfc1c;            // WWD $3
    // Expected Outputs Initialization
    $display("\n:: EXECUTING PROGRAM 2 :: Expected Outputs");
    ir_msg_reference[0] = 16'd1280;     // $0 = 5  * 256 = 1280
    ir_msg_reference[1] = 16'd3328;     // $1 = 13 * 256 = 3328
    ir_msg_reference[2] = 16'd5376;     // $2 = 21 * 256 = 5376
    ir_msg_reference[3] = 16'd16384;    // $3 = 64 * 256 = 16384
    ir_msg_reference[4] = 16'd2560;     // $0 = $0 + $0  = 2560
    ir_msg_reference[5] = 16'd10752;    // $1 = $2 + $2  = 10752
                                        // $0 = -1 * 256 = -256  
    ir_msg_reference[6] = 16'd10496;    // $1 = $1 + $0  = 10752 + (-256) = 10496
    ir_msg_reference[7] = 16'd5120;     // $2 = $1 + $0  = 5376  + (-256) = 5120
    ir_msg_reference[8] = 16'd16384;    // $3
    // Execution
    ExecuteProgram(7);  // execute until interrupt cursor ends up to 7
end
endtask
task Program3;
begin
    $display("\n:: EXECUTING PROGRAM 3 ::");
	
    // Instruction Memory Initialization (Register Initialization)
    inst_mem[16'h0]  = 16'h6000;  // LHI $0, 0x0
    inst_mem[16'h1]  = 16'h6101;  // LHI $1, 0x1
    inst_mem[16'h2]  = 16'h6202;  // LHI $2, 0x2
    inst_mem[16'h3]  = 16'h6303;  // LHI $3, 0x3

    // Arithmetic Operations (ADD, SUB, AND, ORR)
    inst_mem[16'h4]  = 16'hf500;  // ADD $0, $1, $1
    inst_mem[16'h5]  = 16'hf01c;  // WWD $0         

    inst_mem[16'h6]  = 16'hf101;  // SUB $0, $0, $1 
    inst_mem[16'h7]  = 16'hf01c;  // WWD $0         
    
    inst_mem[16'h8]  = 16'hfa42;  // AND $1, $2, $2 
    inst_mem[16'h9]  = 16'hf41c;  // WWD $1         

    inst_mem[16'hA]  = 16'hff43;  // ORR $1, $3, $3
    inst_mem[16'hB]  = 16'hf41c;  // WWD $1         

    inst_mem[16'hC]  = 16'hf404;  // NOT $0, $1
    inst_mem[16'hD]  = 16'hf805;  // TCP $0, $2
    inst_mem[16'hE]  = 16'hf406;  // SHL $0, $1
    inst_mem[16'hF]  = 16'hf047;  // SHR $1, $0

    // Load/Store Instructions
    inst_mem[16'h10] = 16'h6000;  // LHI $0, 0x0
    inst_mem[16'h11] = 16'h8340;  // SWD $3, $0, 0x40
    inst_mem[16'h12] = 16'h7140;  // LWD $1, $0, 0x40
    inst_mem[16'h13] = 16'hf41c;  // WWD $1

    // Shift Operations
    inst_mem[16'h14] = 16'hf046;  // SHL $1, $0
    inst_mem[16'h15] = 16'hf41c;  // WWD $1

    inst_mem[16'h16] = 16'hf447;  // SHR $1, $1
    inst_mem[16'h17] = 16'hf41c;  // WWD $1

    // TCP (Two's Complement)
    inst_mem[16'h18] = 16'hf885;  // TCP $2, $2     
    inst_mem[16'h19] = 16'hf81c;  // WWD $2         

    // Logical NOT
    inst_mem[16'h1A] = 16'hfcc4;  // NOT $3, $3     
    inst_mem[16'h1B] = 16'hfc1c;  // WWD $3         

    // Branch Instructions
    inst_mem[16'h1C] = 16'h011a;  // BNE $0, $1, 0x1A
    inst_mem[16'h1D] = 16'h161c;  // BEQ $1, $2, 0x1C
    inst_mem[16'h1E] = 16'h301f;  // BLZ $0, 0x1F
    inst_mem[16'h1F] = 16'h2420;  // BGZ $1, 0x20

    // Conditional WWD Outputs Based on Branches
    inst_mem[16'h20] = 16'hf01c;  // WWD $0
    inst_mem[16'h21] = 16'hf41c;  // WWD $1 

    // Another Arithmetic Section After Jump/Branch Check
    inst_mem[16'h22] = 16'hf500;  // ADD $0, $1, $1
    inst_mem[16'h23] = 16'hf01c;  // WWD $0

    inst_mem[16'h24] = 16'h9075;  // JMP to 0x75
    inst_mem[16'h25] = 16'hf101;  // SUB $0, $0, $1 
    inst_mem[16'h26] = 16'hf01c;  // WWD $0         

    // Jump Destination
    inst_mem[16'h75] = 16'hf01c;  // WWD $0 (Jump target at 0x75)
    inst_mem[16'h76] = 16'h907f;  // JMP to 0x7F (Program end)
    inst_mem[16'h7F] = 16'hf01c;  // WWD $0 (End signal)
	
    // Reference Messages for Interrupt Handler - Expected Outputs
    ir_msg_reference[0]  = 16'h0200;  // WWD $0 after ADD
    ir_msg_reference[1]  = 16'h0100;  // WWD $0 after SUB
    ir_msg_reference[2]  = 16'h0200;  // WWD $1 after AND
    ir_msg_reference[3]  = 16'h0300;  // WWD $1 after ORR
    ir_msg_reference[4]  = 16'h0300;  // WWD $1 after LWD (loaded from mem[1])
    ir_msg_reference[5]  = 16'h0000;  // WWD $1 after SHL
    ir_msg_reference[6]  = 16'h0000;  // WWD $1 after SHR
    ir_msg_reference[7]  = 16'hfe00;  // WWD $2 after TCP (Two's Complement)
    ir_msg_reference[8]  = 16'hfcff;  // WWD $3 after NOT
    ir_msg_reference[9]  = 16'h0000;  // WWD $0 after BEQ
    ir_msg_reference[10] = 16'h0000;  // WWD $1 after BEQ
    ir_msg_reference[11] = 16'h0000;  // WWD $0 after ADD (post-branch arithmetic)
    ir_msg_reference[12] = 16'h0000;  // WWD $0 after SUB (post-jump arithmetic)
    ir_msg_reference[13] = 16'h0000;  // WWD $0 (Jump target at 0x75)
    ir_msg_reference[14] = 16'h0000;  // WWD $0 (End signal at 0x7F)
    
    ExecuteProgram(14);  // execute until interrupt cursor ends up to 7
end
endtask
task Program4;
begin
    $display("\n:: EXECUTING PROGRAM 4 :: Program Init");
    // Program Initialization
    inst_mem[16'h0]  = 16'h9023;
    inst_mem[16'h1]  = 16'h1;
    inst_mem[16'h2]  = 16'hffff;
    inst_mem[16'h3]  = 16'h0;
    inst_mem[16'h4]  = 16'h0;
    inst_mem[16'h5]  = 16'h0;
    inst_mem[16'h6]  = 16'h0;
    inst_mem[16'h7]  = 16'h0;
    inst_mem[16'h8]  = 16'h0;
    inst_mem[16'h9]  = 16'h0;
    inst_mem[16'ha]  = 16'h0;
    inst_mem[16'hb]  = 16'h0;
    inst_mem[16'hc]  = 16'h0;
    inst_mem[16'hd]  = 16'h0;
    inst_mem[16'he]  = 16'h0;
    inst_mem[16'hf]  = 16'h0;
    inst_mem[16'h10] = 16'h0;
    inst_mem[16'h11] = 16'h0;
    inst_mem[16'h12] = 16'h0;
    inst_mem[16'h13] = 16'h0;
    inst_mem[16'h14] = 16'h0;
    inst_mem[16'h15] = 16'h0;
    inst_mem[16'h16] = 16'h0;
    inst_mem[16'h17] = 16'h0;
    inst_mem[16'h18] = 16'h0;
    inst_mem[16'h19] = 16'h0;
    inst_mem[16'h1a] = 16'h0;
    inst_mem[16'h1b] = 16'h0;
    inst_mem[16'h1c] = 16'h0;
    inst_mem[16'h1d] = 16'h0;
    inst_mem[16'h1e] = 16'h0;
    inst_mem[16'h1f] = 16'h0;
    inst_mem[16'h20] = 16'h0;
    inst_mem[16'h21] = 16'h0;
    inst_mem[16'h22] = 16'h0;
    inst_mem[16'h23] = 16'h6000;
    inst_mem[16'h24] = 16'hf01c;    // WWD $0 - 0
    inst_mem[16'h25] = 16'h6100;
    inst_mem[16'h26] = 16'hf41c;    // WWD $1 - 1
    inst_mem[16'h27] = 16'h6200;
    inst_mem[16'h28] = 16'hf81c;    // WWD $2 - 2
    inst_mem[16'h29] = 16'h6300;
    inst_mem[16'h2a] = 16'hfc1c;    // WWD $3 - 3
    inst_mem[16'h2b] = 16'h4401;
    inst_mem[16'h2c] = 16'hf01c;    // WWD $0 - 4
    inst_mem[16'h2d] = 16'h4001;
    inst_mem[16'h2e] = 16'hf01c;    // WWD $0 - 5
    inst_mem[16'h2f] = 16'h5901;
    inst_mem[16'h30] = 16'hf41c;    // WWD $1 - 6
    inst_mem[16'h31] = 16'h5502;
    inst_mem[16'h32] = 16'hf41c;    // WWD $1 - 7
    inst_mem[16'h33] = 16'h5503;
    inst_mem[16'h34] = 16'hf41c;    // WWD $1 - 8
    inst_mem[16'h35] = 16'hf2c0;
    inst_mem[16'h36] = 16'hfc1c;    // WWD $3 - 9
    inst_mem[16'h37] = 16'hf6c0;
    inst_mem[16'h38] = 16'hfc1c;    // WWD $3 - 10
    inst_mem[16'h39] = 16'hf1c0;
    inst_mem[16'h3a] = 16'hfc1c;    // WWD $3 - 11
    inst_mem[16'h3b] = 16'hf2c1;
    inst_mem[16'h3c] = 16'hfc1c;    // WWD $3 - 12
    inst_mem[16'h3d] = 16'hf8c1;
    inst_mem[16'h3e] = 16'hfc1c;    // WWD $3 - 13
    inst_mem[16'h3f] = 16'hf6c1;
    inst_mem[16'h40] = 16'hfc1c;    // WWD $3 - 14
    inst_mem[16'h41] = 16'hf9c1;
    inst_mem[16'h42] = 16'hfc1c;    // WWD $3 - 15
    inst_mem[16'h43] = 16'hf1c1;
    inst_mem[16'h44] = 16'hfc1c;    // WWD $3 - 16
    inst_mem[16'h45] = 16'hf4c1;
    inst_mem[16'h46] = 16'hfc1c;    // WWD $3 - 17
    inst_mem[16'h47] = 16'hf2c2;
    inst_mem[16'h48] = 16'hfc1c;    // WWD $3 - 18
    inst_mem[16'h49] = 16'hf6c2;
    inst_mem[16'h4a] = 16'hfc1c;    // WWD $3 - 19
    inst_mem[16'h4b] = 16'hf1c2;
    inst_mem[16'h4c] = 16'hfc1c;    // WWD $3 - 20
    inst_mem[16'h4d] = 16'hf2c3;
    inst_mem[16'h4e] = 16'hfc1c;    // WWD $3 - 21
    inst_mem[16'h4f] = 16'hf6c3;
    inst_mem[16'h50] = 16'hfc1c;    // WWD $3 - 22
    inst_mem[16'h51] = 16'hf1c3;
    inst_mem[16'h52] = 16'hfc1c;    // WWD $3 - 23
    inst_mem[16'h53] = 16'hf0c4;
    inst_mem[16'h54] = 16'hfc1c;    // WWD $3 - 24
    inst_mem[16'h55] = 16'hf4c4;
    inst_mem[16'h56] = 16'hfc1c;    // WWD $3 - 25
    inst_mem[16'h57] = 16'hf8c4;
    inst_mem[16'h58] = 16'hfc1c;    // WWD $3 - 26
    inst_mem[16'h59] = 16'hf0c5;
    inst_mem[16'h5a] = 16'hfc1c;    // WWD $3 - 27
    inst_mem[16'h5b] = 16'hf4c5;
    inst_mem[16'h5c] = 16'hfc1c;    // WWD $3 - 28
    inst_mem[16'h5d] = 16'hf8c5;
    inst_mem[16'h5e] = 16'hfc1c;    // WWD $3 - 29
    inst_mem[16'h5f] = 16'hf0c6;
    inst_mem[16'h60] = 16'hfc1c;    // WWD $3 - 30
    inst_mem[16'h61] = 16'hf4c6;
    inst_mem[16'h62] = 16'hfc1c;    // WWD $3 - 31
    inst_mem[16'h63] = 16'hf8c6;
    inst_mem[16'h64] = 16'hfc1c;    // WWD $3 - 32
    inst_mem[16'h65] = 16'hf0c7;    
    inst_mem[16'h66] = 16'hfc1c;    // WWD $3 - 33
    inst_mem[16'h67] = 16'hf4c7;    
    inst_mem[16'h68] = 16'hfc1c;    
    inst_mem[16'h69] = 16'hf8c7;     
    inst_mem[16'h6a] = 16'hfc1c;    
    inst_mem[16'h6b] = 16'h7801;    
    inst_mem[16'h6c] = 16'hf01c;    // WWD $0 - 36
    inst_mem[16'h6d] = 16'h7902;
    inst_mem[16'h6e] = 16'hf41c;    // WWD $1 - 37 
    inst_mem[16'h6f] = 16'h8901;    
    inst_mem[16'h70] = 16'h8802;    
    inst_mem[16'h71] = 16'h7801;    
    inst_mem[16'h72] = 16'hf01c;    // WWD $0 - 38
    inst_mem[16'h73] = 16'h7902;    
    inst_mem[16'h74] = 16'hf41c;    // WWD $1 - 39 
    inst_mem[16'h75] = 16'h9076;    
    inst_mem[16'h76] = 16'hf01c;    // WWD $0 - 40 
    inst_mem[16'h77] = 16'h9079;    
    inst_mem[16'h78] = 16'hf01d;    // HLT
    inst_mem[16'h79] = 16'hf41c;    // WWD $1 - 41 
    inst_mem[16'h7a] = 16'h0b01;    
    inst_mem[16'h7b] = 16'h907d;    
    inst_mem[16'h7c] = 16'hf01d;    // HLT
    inst_mem[16'h7d] = 16'hf01c;    // WWD $0 - 42 
    inst_mem[16'h7e] = 16'h0601;    
    inst_mem[16'h7f] = 16'hf01d;    // HLT
    inst_mem[16'h80] = 16'hf41c;    // WWD $1 - 43 
    inst_mem[16'h81] = 16'h1601;    
    inst_mem[16'h82] = 16'h9084;    
    inst_mem[16'h83] = 16'hf01d;    // HLT
    inst_mem[16'h84] = 16'hf01c;    // WWD $0 - 44 
    inst_mem[16'h85] = 16'h1b01;    
    inst_mem[16'h86] = 16'hf01d;    // HLT
    inst_mem[16'h87] = 16'hf41c;    // WWD $1 - 45 
    inst_mem[16'h88] = 16'h2001;    
    inst_mem[16'h89] = 16'h908b;    
    inst_mem[16'h8a] = 16'hf01d;    // HLT
    inst_mem[16'h8b] = 16'hf01c;    // WWD $0 - 46 
    inst_mem[16'h8c] = 16'h2401;    
    inst_mem[16'h8d] = 16'hf01d;    // HLT
    inst_mem[16'h8e] = 16'hf41c;    // WWD $1 - 47 
    inst_mem[16'h8f] = 16'h2801;    
    inst_mem[16'h90] = 16'h9092;    
    inst_mem[16'h91] = 16'hf01d;    // HLT
    inst_mem[16'h92] = 16'hf01c;    // WWD $0 - 48 
    inst_mem[16'h93] = 16'h3001;    
    inst_mem[16'h94] = 16'hf01d;    // HLT
    inst_mem[16'h95] = 16'hf41c;    // WWD $1 - 49 
    inst_mem[16'h96] = 16'h3401;    
    inst_mem[16'h97] = 16'h9099;    
    inst_mem[16'h98] = 16'hf01d;    // HLT
    inst_mem[16'h99] = 16'hf01c;    // WWD $0 - 50 
    inst_mem[16'h9a] = 16'h3801;    
    inst_mem[16'h9b] = 16'h909d;
    inst_mem[16'h9c] = 16'hf01d;    // HLT
    inst_mem[16'h9d] = 16'hf41c;    // WWD $1 - 51 
    inst_mem[16'h9e] = 16'ha0af;
    inst_mem[16'h9f] = 16'hf01c;    // WWD $0 - 52 
    inst_mem[16'ha0] = 16'ha0ae;
    inst_mem[16'ha1] = 16'hf01d;    // HLT
    inst_mem[16'ha2] = 16'hf41c;    // WWD $1 - 53 
    inst_mem[16'ha3] = 16'h6300;
    inst_mem[16'ha4] = 16'h5f03;
    inst_mem[16'ha5] = 16'h6000;
    inst_mem[16'ha6] = 16'h4005;
    inst_mem[16'ha7] = 16'ha0b2;
    inst_mem[16'ha8] = 16'hf01c;    // WWD $0 - 54 
    inst_mem[16'ha9] = 16'h90b1;
    inst_mem[16'haa] = 16'h4900;
    inst_mem[16'hab] = 16'hf41a;
    inst_mem[16'hac] = 16'hf01c;    // WWD $0 - 55 
    inst_mem[16'had] = 16'hf01d;    // HLT
    inst_mem[16'hae] = 16'h4a01;
    inst_mem[16'haf] = 16'hf819;
    inst_mem[16'hb0] = 16'hf01d;    // HLT
    inst_mem[16'hb1] = 16'ha0aa;
    inst_mem[16'hb2] = 16'h41ff;
    inst_mem[16'hb3] = 16'h2404;
    inst_mem[16'hb4] = 16'h6000;
    inst_mem[16'hb5] = 16'h5001;
    inst_mem[16'hb6] = 16'hf819;
    inst_mem[16'hb7] = 16'hf01d;    // HLT
    inst_mem[16'hb8] = 16'h8e00;
    inst_mem[16'hb9] = 16'h8c01;
    inst_mem[16'hba] = 16'h4f02;
    inst_mem[16'hbb] = 16'h40fe;
    inst_mem[16'hbc] = 16'ha0b2;
    inst_mem[16'hbd] = 16'h7dff;
    inst_mem[16'hbe] = 16'h8cff;
    inst_mem[16'hbf] = 16'h44ff;
    inst_mem[16'hc0] = 16'ha0b2;
    inst_mem[16'hc1] = 16'h7dff;
    inst_mem[16'hc2] = 16'h7efe;
    inst_mem[16'hc3] = 16'hf100;
    inst_mem[16'hc4] = 16'h4ffe;
    inst_mem[16'hc5] = 16'hf819;
    inst_mem[16'hc6] = 16'hf01d;    // HLT
    // Expected output
    $display("\n:: EXECUTING PROGRAM 4 :: Expected Outputs");
    ir_msg_reference[0]  = 16'h0000;
	ir_msg_reference[1]  = 16'h0000;
	ir_msg_reference[2]  = 16'h0000;
	ir_msg_reference[3]  = 16'h0000;
	ir_msg_reference[4]  = 16'h0001;
	ir_msg_reference[5]  = 16'h0002;
	ir_msg_reference[6]  = 16'h0001;
	ir_msg_reference[7]  = 16'h0003;
	ir_msg_reference[8]  = 16'h0003;
	ir_msg_reference[9]  = 16'h0002;
	ir_msg_reference[10] = 16'h0003;
	ir_msg_reference[11] = 16'h0005;
	ir_msg_reference[12] = 16'h0002;
	ir_msg_reference[13] = 16'hFFFE;	 
	ir_msg_reference[14] = 16'h0003;		
	ir_msg_reference[15] = 16'hFFFD;	
	ir_msg_reference[16] = 16'hFFFF;		
	ir_msg_reference[17] = 16'h0001;		
	ir_msg_reference[18] = 16'h0000;		
	ir_msg_reference[19] = 16'h0000;		
	ir_msg_reference[20] = 16'h0002;		
	ir_msg_reference[21] = 16'h0002;		
	ir_msg_reference[22] = 16'h0003;		
	ir_msg_reference[23] = 16'h0003;		
	ir_msg_reference[24] = 16'hFFFD;	
	ir_msg_reference[25] = 16'hFFFC;	
	ir_msg_reference[26] = 16'hFFFF;		
	ir_msg_reference[27] = 16'hFFFE;	
	ir_msg_reference[28] = 16'hFFFD;	
	ir_msg_reference[29] = 16'h0000;		
	ir_msg_reference[30] = 16'h0004;		
	ir_msg_reference[31] = 16'h0006;		
	ir_msg_reference[32] = 16'h0000;		
	ir_msg_reference[33] = 16'h0001;		
	ir_msg_reference[34] = 16'h0001;		
	ir_msg_reference[35] = 16'h0000;		
	ir_msg_reference[36] = 16'h0001;		
	ir_msg_reference[37] = 16'hFFFF;		
	ir_msg_reference[38] = 16'hFFFF;		
	ir_msg_reference[39] = 16'h0001;		
	ir_msg_reference[40] = 16'hFFFF;		
	ir_msg_reference[41] = 16'h0001;		
	ir_msg_reference[42] = 16'hFFFF;		
	ir_msg_reference[43] = 16'h0001;		
	ir_msg_reference[44] = 16'hFFFF;		
	ir_msg_reference[45] = 16'h0001;		
	ir_msg_reference[46] = 16'hFFFF;		
	ir_msg_reference[47] = 16'h0001;		
	ir_msg_reference[48] = 16'hFFFF;		
	ir_msg_reference[49] = 16'h0001;		
	ir_msg_reference[50] = 16'hFFFF;		
	ir_msg_reference[51] = 16'h0001;		
	ir_msg_reference[52] = 16'hFFFF;		
	ir_msg_reference[53] = 16'h0001;		
	ir_msg_reference[54] = 16'h0008;		
	ir_msg_reference[55] = 16'h0022;		
    ExecuteProgram(76);
end
endtask
    
endmodule