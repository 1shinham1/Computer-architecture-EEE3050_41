`timescale 1ns / 100ps

module CPU_W16_R4_tb ();

    /*******************************************************
     * PART 1: Testbench Header
     *******************************************************/

    // Parameter Definitions
    parameter  CLOCK_PS     = 10;   // clock period
    parameter  HCLOCK_PS    = 5;    // half clock period
    localparam WORD_SIZE    = 16;   // 16-bit word size (16-bit = 2B)
    localparam REG_BITS     = 2;    // 16-bit register file with 4 registers (2B x 4 = 8B)
    localparam MEM_SIZE     = 256;  // 16-bit aligned memory (2B x 256 = 512B)

    // Global Signals
    reg clk;
    reg reset_n;
    // Data Memory IF (Read/Write / Ture Single Port)
    wire    [WORD_SIZE-1:0]     mem_addr;          // data memory access address
    wire    [WORD_SIZE-1:0]     mem_rdata;         // data memory read data (to CPU)
    wire    [WORD_SIZE-1:0]     mem_wdata;         // data memory write data (from CPU)
    wire                        mem_read;          // data memory read enable
    wire                        mem_write;         // data memory write enable
    // Interrupt Handler IF (For debugging purpose)
    reg                         ir_ack;             // interrupt acknowledge signal
    wire                        ir_req;             // interrupt request 
    reg     [WORD_SIZE-1:0]     ir_msg_to_cpu;      // handler -> cpu (for RWD, not used) 
    wire    [WORD_SIZE-1:0]     ir_msg_to_handler;  // cpu -> handler (for WWD)
    
    // CPU Instance
    CPU_W16_R4 #(
        .WORD_SIZE      (WORD_SIZE),
        .REG_BITS       (REG_BITS)
    ) top (
        .clk            (clk),
        .reset_n        (reset_n),
        .ir_ack_i       (ir_ack),
        .ir_req_o       (ir_req),
        .ir_msg_i       (ir_msg_to_cpu),
        .ir_msg_o       (ir_msg_to_handler),
        .mem_addr_o    (mem_addr),
        .mem_rdata_i   (mem_rdata),
        .mem_wdata_o   (mem_wdata),
        .mem_read_o    (mem_read),
        .mem_write_o   (mem_write)
    );


    /*******************************************************
     * PART 2: Clock Generation
     *******************************************************/

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


    /*******************************************************
     * PART 3: Memory Model
     *******************************************************
     
     Description
       - This part is for the unified instruction-data memory

     Specification
       - Memory read and write access latency is 4 cycles
       - Any request given to the memory is guaranteed to be handled in fixed latency
         (no handshake required between the memory and the client)
       - Subsequent request given to the memory will be handled contiguously
         For exmaple, if memory read request is given at the clock time 4 and 5, then the 
         response will be given at the clock time 8 and 9, respectively

     */

    // Data Memory (Read/Write)
    reg [WORD_SIZE-1:0] data_mem            [0:MEM_SIZE-1];
    reg [WORD_SIZE-1:0] data_rd_buffer      [0:3];
    reg [WORD_SIZE-1:0] data_wr_buffer      [0:3];
    reg [WORD_SIZE-1:0] data_wr_addr_buffer [0:3];
    reg                 data_wr_req_buffer  [0:3];

    integer i;
        
    // Memory Initialize
    initial begin
        for (i = 0; i < MEM_SIZE; i = i + 1) begin
            data_mem[i] = {WORD_SIZE{1'b0}};
        end
    end

    // Read Operation
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < 4; i = i + 1) begin
                data_rd_buffer[i] <= 'd0;
            end
        end else begin
            if (mem_read) begin
                data_rd_buffer[0] <= data_mem[mem_addr];  
            end else begin
                data_rd_buffer[0] <= {WORD_SIZE{1'b0}}; // read disabled, return 0
            end
            
            data_rd_buffer[1] <= data_rd_buffer[0];
            data_rd_buffer[2] <= data_rd_buffer[1];
            data_rd_buffer[3] <= data_rd_buffer[2];
        end
    end

    assign mem_rdata = data_rd_buffer[3];

    // Write Operation
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < 4; i = i + 1) begin
                data_wr_buffer[i]      <= 'd0;
                data_wr_addr_buffer[i] <= 'd0;
                data_wr_req_buffer[i]  <= 'd0;
            end
        end else begin
            data_wr_buffer[0] <= mem_wdata;
            data_wr_buffer[1] <= data_wr_buffer[0];
            data_wr_buffer[2] <= data_wr_buffer[1];
            data_wr_buffer[3] <= data_wr_buffer[2];

            data_wr_addr_buffer[0] <= mem_addr;
            data_wr_addr_buffer[1] <= data_wr_addr_buffer[0];
            data_wr_addr_buffer[2] <= data_wr_addr_buffer[1];
            data_wr_addr_buffer[3] <= data_wr_addr_buffer[2];

            data_wr_req_buffer[0] <= mem_write;
            data_wr_req_buffer[1] <= data_wr_req_buffer[0];
            data_wr_req_buffer[2] <= data_wr_req_buffer[1];
            data_wr_req_buffer[3] <= data_wr_req_buffer[2];

            if (data_wr_req_buffer[3]) begin
                data_mem[data_wr_addr_buffer[3]] <= data_wr_buffer[3];
            end
        end
    end


    /*******************************************************
     * PART 4: Interrupt Handler and Debugging
     *******************************************************/

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


    /*******************************************************
     * PART 5: Test Sequence
     *******************************************************/

    integer iter_cnt;
    initial begin
        ir_msg_to_cpu = 'd0;
        $dumpfile("vcd/cpu_tb.vcd");
        $dumpvars(0, top);
        Program1;
        Program2;
        // Program3; - Not implemented yet (you need to implement this)
        Program4;
        $finish();
    end

    task ExecuteProgram;
        input [31:0] cursor_limit;
    begin
        reset_n = 'd0;
        #CLOCK_PS;
        reset_n = 'd1;
        iter_cnt = 0;
        while ((ir_cursor <= cursor_limit) && (iter_cnt < 16384)) begin
            #CLOCK_PS;
            iter_cnt = iter_cnt + 1;
        end
        $display("* %1d succeed out of %1d tests in total", ir_passed, ir_cursor);
        $display("* simulated execution time: %1d cycles", iter_cnt);
    end
    endtask

    task Program1;
    begin
        $display("\n:: EXECUTING PROGRAM 1 ::");
        // Program Initialization
        data_mem[0]  = 16'h6000;            //	LHI $0, 0
        data_mem[1]  = 16'h6101;            //	LHI $1, 1
        data_mem[2]  = 16'h6202;            //  LHI $2, 2
        data_mem[3]  = 16'h6303;            //	LHI $3, 3
        data_mem[4]  = 16'hf01c;            //	WWD $0  -> 0 
        data_mem[5]  = 16'hf41c;            //	WWD $1  -> 256
        data_mem[6]  = 16'hf81c;            //	WWD $2  -> 512
        data_mem[7]  = 16'hfc1c;            //	WWD $3  -> 768
        data_mem[8]  = 16'h4204;            //	ADI $2, $0, 4
        data_mem[9]  = 16'h47fc;            //	ADI $3, $1, -4
        data_mem[10] = 16'hf81c;            //	WWD $2  -> 4
        data_mem[11] = 16'hfc1c;            //	WWD $3  -> 252
        data_mem[12] = 16'hf6c0;            //	ADD $3, $1, $2
        data_mem[13] = 16'hf180;            //	ADD $2, $0, $1
        data_mem[14] = 16'hf81c;            //	WWD $2  -> 256
        data_mem[15] = 16'hfc1c;            //	WWD $3  -> 260
        data_mem[16] = 16'h9015;            //	JMP 21
        data_mem[17] = 16'hf01c;            //	WWD $0  -> 0    -> not occur
        data_mem[18] = 16'hf180;            //	ADD $2, $0, $1  -> not occur
        data_mem[19] = 16'hf180;            //	ADD $2, $0, $1  -> not occur
        data_mem[20] = 16'hf180;            //	ADD $2, $0, $1  -> not occur
        data_mem[21] = 16'h6000;            //	LHI $0, 0
        data_mem[22] = 16'h4000;            //	ADI $0, $0, 0
        data_mem[23] = 16'hfd80;            //	ADD $2, $3, $1
        data_mem[24] = 16'hf01c;            //	WWD $0 -> 0
        data_mem[25] = 16'hf41c;            //	WWD $1 -> 256
        data_mem[26] = 16'hf81c;            //	WWD $2 -> 256 + 260 = 516
        data_mem[27] = 16'hfc1c;            //	WWD $3 -> 260
        // Expected Outputs Initialization
        ir_msg_reference[0]  = 16'd0;       // data_mem[4]
        ir_msg_reference[1]  = 16'd256;     // data_mem[5]
        ir_msg_reference[2]  = 16'd512;     // data_mem[6]
        ir_msg_reference[3]  = 16'd768;     // data_mem[7]
        ir_msg_reference[4]  = 16'd4;       // data_mem[10]
        ir_msg_reference[5]  = 16'd252;     // data_mem[11]
        ir_msg_reference[6]  = 16'd256;     // data_mem[14]
        ir_msg_reference[7]  = 16'd260;     // data_mem[15]
        ir_msg_reference[8]  = 16'd0;       // data_mem[17]     
        ir_msg_reference[9]  = 16'd256;     // data_mem[24]     
        ir_msg_reference[10] = 16'd516;     // data_mem[25]
        ir_msg_reference[11] = 16'd260;     // data_mem[26]
        // Execution
        ExecuteProgram(11);  // execute until interrupt cursor ends up to 11
    end
    endtask

    task Program2;
    begin
        $display("\n:: EXECUTING PROGRAM 2 ::");
        // Program Initialization
        data_mem[0]  = 16'h6005;            // LHI $0, 5
        data_mem[1]  = 16'h610d;            // LHI $1, 13
        data_mem[2]  = 16'h6215;            // LHI $2, 21
        data_mem[3]  = 16'h6340;            // LHI $3, 64
        data_mem[4]  = 16'hf01c;            // WWD $0
        data_mem[5]  = 16'hf41c;            // WWD $1
        data_mem[6]  = 16'hf81c;            // WWD $2
        data_mem[7]  = 16'hfc1c;            // WWD $3
        data_mem[8]  = 16'hf000;            // ADD $0, $0, $0
        data_mem[9]  = 16'hfa40;            // ADD $1, $2, $2
        data_mem[10] = 16'hf01c;            // WWD $0
        data_mem[11] = 16'hf41c;            // WWD $1
        data_mem[12] = 16'h60ff;            // LHI $0, 255       // (255 or 0xffff stands for -1)
        data_mem[13] = 16'hf440;            // ADD $1, $1, $0
        data_mem[14] = 16'hf880;            // ADD $2, $2, $0
        data_mem[15] = 16'hf41c;            // WWD $1
        data_mem[16] = 16'hf81c;            // WWD $2
        data_mem[17] = 16'hfc1c;            // WWD $3
        // Expected Outputs Initialization
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
    /*
    task Program3;
    begin
        $display("\n:: EXECUTING PROGRAM 3 ::");
        
        // Instruction Memory Initialization (Register Initialization)
        inst_mem[16'h0]  = ;  // LHI $0, 0x0
        inst_mem[16'h1]  = ;  // LHI $1, 0x1
        inst_mem[16'h2]  = ;  // LHI $2, 0x2
        inst_mem[16'h3]  = ;  // LHI $3, 0x3

        // Arithmetic Operations (ADD, SUB, AND, ORR)
        inst_mem[16'h4]  = ;  // ADD $0, $1, $1
        inst_mem[16'h5]  = ;  // WWD $0         

        inst_mem[16'h6]  = ;  // SUB $0, $0, $1 
        inst_mem[16'h7]  = ;  // WWD $0         
        
        inst_mem[16'h8]  = ;  // AND $1, $2, $2 
        inst_mem[16'h9]  = ;  // WWD $1         

        inst_mem[16'hA]  = ;  // ORR $1, $3, $3
        inst_mem[16'hB]  = ;  // WWD $1         

        inst_mem[16'hC]  = ;  // NOT $0, $1
        inst_mem[16'hD]  = ;  // TCP $0, $2
        inst_mem[16'hE]  = ;  // SHL $0, $1
        inst_mem[16'hF]  = ;  // SHR $1, $0

        // Load/Store Instructions
        inst_mem[16'h10] = ;  // LHI $0, 0x0
        inst_mem[16'h11] = ;  // SWD $3, $0, 0x40
        inst_mem[16'h12] = ;  // LWD $1, $0, 0x40
        inst_mem[16'h13] = ;  // WWD $1

        // Shift Operations
        inst_mem[16'h14] = ;  // SHL $1, $0
        inst_mem[16'h15] = ;  // WWD $1

        inst_mem[16'h16] = ;  // SHR $1, $1
        inst_mem[16'h17] = ;  // WWD $1

        // TCP (Two's Complement)
        inst_mem[16'h18] = ;  // TCP $2, $2     
        inst_mem[16'h19] = ;  // WWD $2         

        // Logical NOT
        inst_mem[16'h1A] = ;  // NOT $3, $3     
        inst_mem[16'h1B] = ;  // WWD $3         

        // Branch Instructions
        inst_mem[16'h1C] = ;  // BNE $0, $1, 0x1A
        inst_mem[16'h1D] = ;  // BEQ $1, $2, 0x1C
        inst_mem[16'h1E] = ;  // BLZ $0, 0x1F
        inst_mem[16'h1F] = ;  // BGZ $1, 0x20

        // Conditional WWD Outputs Based on Branches
        inst_mem[16'h20] = ;  // WWD $0
        inst_mem[16'h21] = ;  // WWD $1 

        // Another Arithmetic Section After Jump/Branch Check
        inst_mem[16'h22] = ;  // ADD $0, $1, $1
        inst_mem[16'h23] = ;  // WWD $0

        inst_mem[16'h24] = ;  // JMP to 0x75
        inst_mem[16'h25] = ;  // SUB $0, $0, $1 
        inst_mem[16'h26] = ;  // WWD $0         

        // Jump Destination
        inst_mem[16'h75] = ;  // WWD $0 (Jump target at 0x75)
        inst_mem[16'h76] = ;  // JMP to 0x7F (Program end)
        inst_mem[16'h7F] = ;  // WWD $0 (End signal)
        
        // Reference Messages for Interrupt Handler - Expected Outputs
        ir_msg_reference[0]  = ;  // WWD $0 after ADD
        ir_msg_reference[1]  = ;  // WWD $0 after SUB
        ir_msg_reference[2]  = ;  // WWD $1 after AND
        ir_msg_reference[3]  = ;  // WWD $1 after ORR
        ir_msg_reference[4]  = ;  // WWD $1 after LWD (loaded from mem[1])
        ir_msg_reference[5]  = ;  // WWD $1 after SHL
        ir_msg_reference[6]  = ;  // WWD $1 after SHR
        ir_msg_reference[7]  = ;  // WWD $2 after TCP (Two's Complement)
        ir_msg_reference[8]  = ;  // WWD $3 after NOT
        ir_msg_reference[9]  = ;  // WWD $0 after BEQ
        ir_msg_reference[10] = ;  // WWD $1 after BEQ
        ir_msg_reference[11] = ;  // WWD $0 after ADD (post-branch arithmetic)
        ir_msg_reference[12] = ;  // WWD $0 after SUB (post-jump arithmetic)
        ir_msg_reference[13] = ;  // WWD $0 (Jump target at 0x75)
        ir_msg_reference[14] = ;  // WWD $0 (End signal at 0x7F)
        
        ExecuteProgram(14);  // execute until interrupt cursor ends up to 7
    end
    endtask
    */
    task Program4;
    begin
        $display("\n:: EXECUTING PROGRAM 4 ::");
        // Program Initialization
        data_mem[16'h0]  = 16'h9023;
        data_mem[16'h1]  = 16'h1;
        data_mem[16'h2]  = 16'hffff;
        data_mem[16'h3]  = 16'h0;
        data_mem[16'h4]  = 16'h0;
        data_mem[16'h5]  = 16'h0;
        data_mem[16'h6]  = 16'h0;
        data_mem[16'h7]  = 16'h0;
        data_mem[16'h8]  = 16'h0;
        data_mem[16'h9]  = 16'h0;
        data_mem[16'ha]  = 16'h0;
        data_mem[16'hb]  = 16'h0;
        data_mem[16'hc]  = 16'h0;
        data_mem[16'hd]  = 16'h0;
        data_mem[16'he]  = 16'h0;
        data_mem[16'hf]  = 16'h0;
        data_mem[16'h10] = 16'h0;
        data_mem[16'h11] = 16'h0;
        data_mem[16'h12] = 16'h0;
        data_mem[16'h13] = 16'h0;
        data_mem[16'h14] = 16'h0;
        data_mem[16'h15] = 16'h0;
        data_mem[16'h16] = 16'h0;
        data_mem[16'h17] = 16'h0;
        data_mem[16'h18] = 16'h0;
        data_mem[16'h19] = 16'h0;
        data_mem[16'h1a] = 16'h0;
        data_mem[16'h1b] = 16'h0;
        data_mem[16'h1c] = 16'h0;
        data_mem[16'h1d] = 16'h0;
        data_mem[16'h1e] = 16'h0;
        data_mem[16'h1f] = 16'h0;
        data_mem[16'h20] = 16'h0;
        data_mem[16'h21] = 16'h0;
        data_mem[16'h22] = 16'h0;
        data_mem[16'h23] = 16'h6000;
        data_mem[16'h24] = 16'hf01c;    // WWD $0 - 0
        data_mem[16'h25] = 16'h6100;
        data_mem[16'h26] = 16'hf41c;    // WWD $1 - 1
        data_mem[16'h27] = 16'h6200;
        data_mem[16'h28] = 16'hf81c;    // WWD $2 - 2
        data_mem[16'h29] = 16'h6300;
        data_mem[16'h2a] = 16'hfc1c;    // WWD $3 - 3
        data_mem[16'h2b] = 16'h4401;
        data_mem[16'h2c] = 16'hf01c;    // WWD $0 - 4
        data_mem[16'h2d] = 16'h4001;
        data_mem[16'h2e] = 16'hf01c;    // WWD $0 - 5
        data_mem[16'h2f] = 16'h5901;
        data_mem[16'h30] = 16'hf41c;    // WWD $1 - 6
        data_mem[16'h31] = 16'h5502;
        data_mem[16'h32] = 16'hf41c;    // WWD $1 - 7
        data_mem[16'h33] = 16'h5503;
        data_mem[16'h34] = 16'hf41c;    // WWD $1 - 8
        data_mem[16'h35] = 16'hf2c0;
        data_mem[16'h36] = 16'hfc1c;    // WWD $3 - 9
        data_mem[16'h37] = 16'hf6c0;
        data_mem[16'h38] = 16'hfc1c;    // WWD $3 - 10
        data_mem[16'h39] = 16'hf1c0;
        data_mem[16'h3a] = 16'hfc1c;    // WWD $3 - 11
        data_mem[16'h3b] = 16'hf2c1;
        data_mem[16'h3c] = 16'hfc1c;    // WWD $3 - 12
        data_mem[16'h3d] = 16'hf8c1;
        data_mem[16'h3e] = 16'hfc1c;    // WWD $3 - 13
        data_mem[16'h3f] = 16'hf6c1;
        data_mem[16'h40] = 16'hfc1c;    // WWD $3 - 14
        data_mem[16'h41] = 16'hf9c1;
        data_mem[16'h42] = 16'hfc1c;    // WWD $3 - 15
        data_mem[16'h43] = 16'hf1c1;
        data_mem[16'h44] = 16'hfc1c;    // WWD $3 - 16
        data_mem[16'h45] = 16'hf4c1;
        data_mem[16'h46] = 16'hfc1c;    // WWD $3 - 17
        data_mem[16'h47] = 16'hf2c2;
        data_mem[16'h48] = 16'hfc1c;    // WWD $3 - 18
        data_mem[16'h49] = 16'hf6c2;
        data_mem[16'h4a] = 16'hfc1c;    // WWD $3 - 19
        data_mem[16'h4b] = 16'hf1c2;
        data_mem[16'h4c] = 16'hfc1c;    // WWD $3 - 20
        data_mem[16'h4d] = 16'hf2c3;
        data_mem[16'h4e] = 16'hfc1c;    // WWD $3 - 21
        data_mem[16'h4f] = 16'hf6c3;
        data_mem[16'h50] = 16'hfc1c;    // WWD $3 - 22
        data_mem[16'h51] = 16'hf1c3;
        data_mem[16'h52] = 16'hfc1c;    // WWD $3 - 23
        data_mem[16'h53] = 16'hf0c4;
        data_mem[16'h54] = 16'hfc1c;    // WWD $3 - 24
        data_mem[16'h55] = 16'hf4c4;
        data_mem[16'h56] = 16'hfc1c;    // WWD $3 - 25
        data_mem[16'h57] = 16'hf8c4;
        data_mem[16'h58] = 16'hfc1c;    // WWD $3 - 26
        data_mem[16'h59] = 16'hf0c5;
        data_mem[16'h5a] = 16'hfc1c;    // WWD $3 - 27
        data_mem[16'h5b] = 16'hf4c5;
        data_mem[16'h5c] = 16'hfc1c;    // WWD $3 - 28
        data_mem[16'h5d] = 16'hf8c5;
        data_mem[16'h5e] = 16'hfc1c;    // WWD $3 - 29
        data_mem[16'h5f] = 16'hf0c6;
        data_mem[16'h60] = 16'hfc1c;    // WWD $3 - 30
        data_mem[16'h61] = 16'hf4c6;
        data_mem[16'h62] = 16'hfc1c;    // WWD $3 - 31
        data_mem[16'h63] = 16'hf8c6;
        data_mem[16'h64] = 16'hfc1c;    // WWD $3 - 32
        data_mem[16'h65] = 16'hf0c7;    
        data_mem[16'h66] = 16'hfc1c;    // WWD $3 - 33
        data_mem[16'h67] = 16'hf4c7;    
        data_mem[16'h68] = 16'hfc1c;    
        data_mem[16'h69] = 16'hf8c7;     
        data_mem[16'h6a] = 16'hfc1c;    
        data_mem[16'h6b] = 16'h7801;    
        data_mem[16'h6c] = 16'hf01c;    // WWD $0 - 36
        data_mem[16'h6d] = 16'h7902;
        data_mem[16'h6e] = 16'hf41c;    // WWD $1 - 37 
        data_mem[16'h6f] = 16'h8901;    
        data_mem[16'h70] = 16'h8802;    
        data_mem[16'h71] = 16'h7801;    
        data_mem[16'h72] = 16'hf01c;    // WWD $0 - 38
        data_mem[16'h73] = 16'h7902;    
        data_mem[16'h74] = 16'hf41c;    // WWD $1 - 39 
        data_mem[16'h75] = 16'h9076;    
        data_mem[16'h76] = 16'hf01c;    // WWD $0 - 40 
        data_mem[16'h77] = 16'h9079;    
        data_mem[16'h78] = 16'hf01d;    
        data_mem[16'h79] = 16'hf41c;    // WWD $1 - 41 
        data_mem[16'h7a] = 16'h0b01;    
        data_mem[16'h7b] = 16'h907d;    
        data_mem[16'h7c] = 16'hf01d;    
        data_mem[16'h7d] = 16'hf01c;    // WWD $0 - 42 
        data_mem[16'h7e] = 16'h0601;    
        data_mem[16'h7f] = 16'hf01d;    
        data_mem[16'h80] = 16'hf41c;    // WWD $1 - 43 
        data_mem[16'h81] = 16'h1601;    
        data_mem[16'h82] = 16'h9084;    
        data_mem[16'h83] = 16'hf01d;    
        data_mem[16'h84] = 16'hf01c;    // WWD $0 - 44 
        data_mem[16'h85] = 16'h1b01;    
        data_mem[16'h86] = 16'hf01d;    
        data_mem[16'h87] = 16'hf41c;    // WWD $1 - 45 
        data_mem[16'h88] = 16'h2001;    
        data_mem[16'h89] = 16'h908b;    
        data_mem[16'h8a] = 16'hf01d;    
        data_mem[16'h8b] = 16'hf01c;    // WWD $0 - 46 
        data_mem[16'h8c] = 16'h2401;    
        data_mem[16'h8d] = 16'hf01d;    
        data_mem[16'h8e] = 16'hf41c;    // WWD $1 - 47 
        data_mem[16'h8f] = 16'h2801;    
        data_mem[16'h90] = 16'h9092;    
        data_mem[16'h91] = 16'hf01d;    
        data_mem[16'h92] = 16'hf01c;    // WWD $0 - 48 
        data_mem[16'h93] = 16'h3001;    
        data_mem[16'h94] = 16'hf01d;    
        data_mem[16'h95] = 16'hf41c;    // WWD $1 - 49 
        data_mem[16'h96] = 16'h3401;    
        data_mem[16'h97] = 16'h9099;    
        data_mem[16'h98] = 16'hf01d;    
        data_mem[16'h99] = 16'hf01c;    // WWD $0 - 50 
        data_mem[16'h9a] = 16'h3801;    
        data_mem[16'h9b] = 16'h909d;
        data_mem[16'h9c] = 16'hf01d;
        data_mem[16'h9d] = 16'hf41c;    // WWD $1 - 51 
        data_mem[16'h9e] = 16'ha0af;
        data_mem[16'h9f] = 16'hf01c;    // WWD $0 - 52 
        data_mem[16'ha0] = 16'ha0ae;
        data_mem[16'ha1] = 16'hf01d;
        data_mem[16'ha2] = 16'hf41c;    // WWD $1 - 53 
        data_mem[16'ha3] = 16'h6300;
        data_mem[16'ha4] = 16'h5f03;
        data_mem[16'ha5] = 16'h6000;
        data_mem[16'ha6] = 16'h4005;
        data_mem[16'ha7] = 16'ha0b2;
        data_mem[16'ha8] = 16'hf01c;    // WWD $0 - 54 
        data_mem[16'ha9] = 16'h90b1;
        data_mem[16'haa] = 16'h4900;
        data_mem[16'hab] = 16'hf41a;
        data_mem[16'hac] = 16'hf01c;    // WWD $0 - 55 
        data_mem[16'had] = 16'hf01d;    // HLT
        data_mem[16'hae] = 16'h4a01;
        data_mem[16'haf] = 16'hf819;
        data_mem[16'hb0] = 16'hf01d;    // HLT
        data_mem[16'hb1] = 16'ha0aa;
        data_mem[16'hb2] = 16'h41ff;
        data_mem[16'hb3] = 16'h2404;
        data_mem[16'hb4] = 16'h6000;
        data_mem[16'hb5] = 16'h5001;
        data_mem[16'hb6] = 16'hf819;
        data_mem[16'hb7] = 16'hf01d;    // HLT
        data_mem[16'hb8] = 16'h8e00;
        data_mem[16'hb9] = 16'h8c01;
        data_mem[16'hba] = 16'h4f02;
        data_mem[16'hbb] = 16'h40fe;
        data_mem[16'hbc] = 16'ha0b2;
        data_mem[16'hbd] = 16'h7dff;
        data_mem[16'hbe] = 16'h8cff;
        data_mem[16'hbf] = 16'h44ff;
        data_mem[16'hc0] = 16'ha0b2;
        data_mem[16'hc1] = 16'h7dff;
        data_mem[16'hc2] = 16'h7efe;
        data_mem[16'hc3] = 16'hf100;
        data_mem[16'hc4] = 16'h4ffe;
        data_mem[16'hc5] = 16'hf819;
        data_mem[16'hc6] = 16'hf01d;    // HLT
        // Expected output
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
        ExecuteProgram(55);
    end
    endtask
    
endmodule