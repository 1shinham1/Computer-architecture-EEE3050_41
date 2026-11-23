`timescale 1ns / 100ps

module CPU_W16_R4_tb ();

    // Parameter Definitions
    parameter  CLOCK_PS     = 10;   // clock period
    parameter  HCLOCK_PS    = 5;    // half clock period
    localparam WORD_SIZE    = 16;   // 16-bit word size (16-bit = 2B)
    localparam REG_BITS     = 2;    // 16-bit register file with 4 registers (2B x 4 = 8B)
    localparam MEM_SIZE     = 256;  // 16-bit aligned memory (2B x 256 = 512B)
 
    localparam BLOCK_SIZE   = 4;     // 
    localparam BLOCK_NUM    = 16;    // 
    localparam WORD_NUM     = 8192;  //

    // Lab9 추가: External Device / DMA parameters (CPU extension)
    localparam DEV_NUM_LG2  = 6;     // external device : 2^6 = 64 words
    localparam DMA_NUM_LG2  = 6;     // DMA buffer      : 2^6 = 64 words (max DMA length)

    // Global Signals
    reg clk;
    reg reset_n;
    
    // Interrupt Handler IF (For debugging purpose)
    reg                         ir_ack;             // interrupt acknowledge signal
    wire                        ir_req;             // interrupt request 
    reg     [WORD_SIZE-1:0]     ir_msg_to_cpu;      // handler -> cpu (for RWD, not used) 
    wire    [WORD_SIZE-1:0]     ir_msg_to_handler;  // cpu -> handler (for WWD)

    // Instruction Cache IF
    wire    [WORD_SIZE-1:0]     icache_addr;     // address from the cpu
    wire    [WORD_SIZE-1:0]     icache_rd_data;  // cpu read data
    wire                        icache_rd_req;   // cpu read request (from master)
    wire                        icache_rd_ack;   // cpu read acknowledge (to master)

    // Data Cache IF
    wire    [WORD_SIZE-1:0]     dcache_addr;     // address from the cpu
    wire    [WORD_SIZE-1:0]     dcache_rd_data;  // cpu read data
    wire                        dcache_rd_req;   // cpu read request (from master)
    wire                        dcache_rd_ack;   // cpu read acknowledge (to master)
    wire    [WORD_SIZE-1:0]     dcache_wr_data;  // cpu write data
    wire                        dcache_wr_req;   // cpu write request (from master)
    wire                        dcache_wr_ack;   // cpu write acknowledge (to master)

    // Memory IF
    wire    [WORD_SIZE-1:0]     mem_rw_addr;  // address given to the memory
    wire    [WORD_SIZE-1:0]     mem_rd_data;  // memory read data
    wire                        mem_rd_req;   // memory read request (to slave)
    wire                        mem_rd_ack;   // memory read acknowledge (from slave)
    wire    [WORD_SIZE-1:0]     mem_wr_data;  // memory write data
    wire                        mem_wr_req;   // memory write request (to slave)
    wire                        mem_wr_ack;   // memory write acknowledge (from slave)
    wire    [WORD_SIZE-1:0]     mem_ro_addr;  // address given to the memory
    wire    [WORD_SIZE-1:0]     mem_ro_data;  // memory read data
    wire                        mem_ro_req;   // memory read request (to slave)
    wire                        mem_ro_ack;   // memory read acknowledge (from slave)
    
    // Lab9 추가: D-cache <-> Arbiter (D-cache는 이제 memory가 아니라 arbiter에 연결)
    wire    [WORD_SIZE-1:0]     dc_mem_addr;     // address from the D-cache
    wire    [WORD_SIZE-1:0]     dc_mem_rd_data;  // memory read data (to D-cache)
    wire                        dc_mem_rd_req;   // memory read request (from D-cache)
    wire                        dc_mem_rd_ack;   // memory read acknowledge (to D-cache)
    wire    [WORD_SIZE-1:0]     dc_mem_wr_data;  // memory write data (from D-cache)
    wire                        dc_mem_wr_req;   // memory write request (from D-cache)
    wire                        dc_mem_wr_ack;   // memory write acknowledge (to D-cache)

    // Lab9 추가: DMA <-> Arbiter
    wire    [WORD_SIZE-1:0]     dma_mem_rw_addr; // write address (from DMA)
    wire    [WORD_SIZE-1:0]     dma_mem_wr_data; // write data (from DMA)
    wire                        dma_mem_wr_req;  // write request (from DMA)
    wire                        dma_mem_wr_ack;  // write acknowledge (to DMA)
    wire                        bus_req;         // bus request (DMA -> arbiter)
    wire                        bus_ack;         // bus grant   (arbiter -> DMA)

    // Lab9 추가: External Device <-> DMA (data path)
    wire    [DEV_NUM_LG2-1:0]   dev_rd_addr;     // device read address (from DMA)
    wire    [WORD_SIZE-1:0]     dev_rd_data;     // device read data (to DMA)

    // Lab9 추가: Interrupt / DMA configuration (device <-> CPU <-> DMA)
    wire                        dev_ir_req;      // device -> CPU : interrupt request
    wire                        dev_ir_ack;      // CPU -> device : interrupt acknowledge
    wire                        dma_ir_req;      // CPU -> DMA    : wake up
    wire    [WORD_SIZE-1:0]     dma_len;         // CPU -> DMA    : length (words)
    wire    [WORD_SIZE-1:0]     dma_addr;        // CPU -> DMA    : start address
    wire                        dma_ir_ack;      // DMA -> CPU    : finished

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

        .icache_addr_o     (icache_addr),
        .icache_rd_data_i  (icache_rd_data),
        .icache_rd_req_o   (icache_rd_req),
        .icache_rd_ack_i   (icache_rd_ack),

        .dcache_addr_o     (dcache_addr),
        .dcache_rd_data_i  (dcache_rd_data),
        .dcache_rd_req_o   (dcache_rd_req),
        .dcache_rd_ack_i   (dcache_rd_ack),
        .dcache_wr_data_o  (dcache_wr_data),
        .dcache_wr_req_o   (dcache_wr_req),
        .dcache_wr_ack_i   (dcache_wr_ack),

        // Lab9 추가: DMA IF / EXT_DEV IF
        .dma_ir_req_o      (dma_ir_req),
        .dma_len_o         (dma_len),
        .dma_addr_o        (dma_addr),
        .dma_ir_ack_i      (dma_ir_ack),
        .dev_ir_req_i      (dev_ir_req),
        .dev_ir_ack_o      (dev_ir_ack)
    );

    // Instruction Cache Instance
    InstrCache_DM #(
        .WORD_SIZE      (WORD_SIZE),
        .BLOCK_SIZE     (BLOCK_SIZE),
        .BLOCK_NUM      (BLOCK_NUM)
    ) i_cache (
        .clk            (clk),
        .reset_n        (reset_n),
        .cpu_addr_i     (icache_addr),
        .cpu_rd_data_o  (icache_rd_data),
        .cpu_rd_req_i   (icache_rd_req),
        .cpu_rd_ack_o   (icache_rd_ack),
        .mem_addr_o     (mem_ro_addr),
        .mem_ro_data_i  (mem_ro_data),
        .mem_ro_req_o   (mem_ro_req),
        .mem_ro_ack_i   (mem_ro_ack)
    );

    // Data Cache Instance
    DataCache_DM #(
        .WORD_SIZE      (WORD_SIZE),
        .BLOCK_SIZE     (BLOCK_SIZE),
        .BLOCK_NUM      (BLOCK_NUM)
    ) d_cache (
        .clk            (clk),
        .reset_n        (reset_n),
        .cpu_addr_i     (dcache_addr),
        .cpu_rd_data_o  (dcache_rd_data),
        .cpu_rd_req_i   (dcache_rd_req),
        .cpu_rd_ack_o   (dcache_rd_ack),
        .cpu_wr_data_i  (dcache_wr_data),
        .cpu_wr_req_i   (dcache_wr_req),
        .cpu_wr_ack_o   (dcache_wr_ack),
        .mem_addr_o     (dc_mem_addr),      // Lab9 수정: memory -> arbiter
        .mem_rd_data_i  (dc_mem_rd_data),
        .mem_rd_req_o   (dc_mem_rd_req),
        .mem_rd_ack_i   (dc_mem_rd_ack),
        .mem_wr_data_o  (dc_mem_wr_data),
        .mem_wr_req_o   (dc_mem_wr_req),
        .mem_wr_ack_i   (dc_mem_wr_ack)
    );

    // Memory Instance
    Memory #(
        .WORD_SIZE      (WORD_SIZE),
        .WORD_NUM       (WORD_NUM)
    ) mem_inst (
        .clk            (clk),
        .reset_n        (reset_n),
        .rw_addr_i      (mem_rw_addr),
        .rd_data_o      (mem_rd_data),
        .rd_req_i       (mem_rd_req),
        .rd_ack_o       (mem_rd_ack),
        .wr_data_i      (mem_wr_data),
        .wr_req_i       (mem_wr_req),
        .wr_ack_o       (mem_wr_ack), 
        .ro_addr_i      (mem_ro_addr),  
        .ro_data_o      (mem_ro_data),
        .ro_req_i       (mem_ro_req),
        .ro_ack_o       (mem_ro_ack)
    );
    

    // Lab9 추가: External Device Instance
    EXT_DEV #(
        .WORD_SIZE      (WORD_SIZE),
        .WORD_NUM_LG2   (DEV_NUM_LG2)
    ) ext_dev (
        .clk            (clk),
        .reset_n        (reset_n),
        .dev_rd_addr_i  (dev_rd_addr),
        .dev_rd_data_o  (dev_rd_data),
        .dev_ir_ack_i   (dev_ir_ack),      // ack comes from the CPU
        .dev_ir_req_o   (dev_ir_req)       // interrupt goes to the CPU
    );

    // Lab9 추가: DMA Instance (CPU_EXT = 1 : CPU가 설정, device 인터럽트 경로 사용 안 함)
    DMA #(
        .WORD_SIZE      (WORD_SIZE),
        .DEV_NUM_LG2    (DEV_NUM_LG2),
        .DMA_NUM_LG2    (DMA_NUM_LG2),
        .CPU_EXT        (1)
    ) dma (
        .clk            (clk),
        .reset_n        (reset_n),
        .dev_rd_addr_o  (dev_rd_addr),
        .dev_rd_data_i  (dev_rd_data),
        .dev_ir_ack_o   (),                // not used (CPU acknowledges the device)
        .dev_ir_req_i   (1'b0),            // not used (device interrupts the CPU)
        .mem_rw_addr_o  (dma_mem_rw_addr),
        .mem_wr_data_o  (dma_mem_wr_data),
        .mem_wr_req_o   (dma_mem_wr_req),
        .mem_wr_ack_i   (dma_mem_wr_ack),
        .bus_req_o      (bus_req),
        .bus_ack_i      (bus_ack),
        .dma_ir_req_i   (dma_ir_req),
        .dma_len_i      (dma_len),
        .dma_addr_i     (dma_addr),
        .dma_ir_ack_o   (dma_ir_ack)
    );

    // Lab9 추가: Arbiter Instance (D-cache / DMA -> memory RW channel)
    ARBITER #(
        .WORD_SIZE          (WORD_SIZE)
    ) arbiter (
        .clk                (clk),
        .reset_n            (reset_n),
        .dc_mem_addr_i      (dc_mem_addr),
        .dc_mem_rd_data_o   (dc_mem_rd_data),
        .dc_mem_rd_req_i    (dc_mem_rd_req),
        .dc_mem_rd_ack_o    (dc_mem_rd_ack),
        .dc_mem_wr_data_i   (dc_mem_wr_data),
        .dc_mem_wr_req_i    (dc_mem_wr_req),
        .dc_mem_wr_ack_o    (dc_mem_wr_ack),
        .dma_mem_rw_addr_i  (dma_mem_rw_addr),
        .dma_mem_wr_data_i  (dma_mem_wr_data),
        .dma_mem_wr_req_i   (dma_mem_wr_req),
        .dma_mem_wr_ack_o   (dma_mem_wr_ack),
        .bus_req_i          (bus_req),
        .bus_ack_o          (bus_ack),
        .mem_rw_addr_o      (mem_rw_addr),
        .mem_rd_data_i      (mem_rd_data),
        .mem_rd_req_o       (mem_rd_req),
        .mem_rd_ack_i       (mem_rd_ack),
        .mem_wr_data_o      (mem_wr_data),
        .mem_wr_req_o       (mem_wr_req),
        .mem_wr_ack_i       (mem_wr_ack)
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
                $display("[TIME:%6dns] test #%2d succeed with message: %1d", $time, ir_cursor, ir_msg_to_handler);
                ir_passed <= ir_passed + 1;
            end else begin
                $display("[TIME:%6dns] test #%2d failed since output message (%5d) is not the same with the reference (%5d)", $time, ir_cursor, ir_msg_to_handler, ir_msg_reference[ir_cursor]);
            end
        end 
        else if (!ir_req) begin
            ir_ack <= 1'b0;
        end
    end


    // ==================================================================
    // Lab9 추가: DMA Monitor (CPU extension 검증)
    // - dma_ir_req (IR_CONFIG) : device 데이터 snapshot + 설정(len, addr) 기록
    // - dev_ir_ack (전송 완료)  : memory[addr + j] == snapshot[j] (j < len) 비교 -> PASS / FAIL
    // - bus 통계               : DMA가 bus를 가진 cycle / 그 동안 D-cache가 막혀 기다린 cycle
    // ==================================================================
    localparam DMA_NUM = 1 << DMA_NUM_LG2;
    reg     [WORD_SIZE-1:0]     dma_snap [0:DMA_NUM-1];
    reg     [WORD_SIZE-1:0]     dma_chk_addr, dma_chk_end;
    integer dma_chk_len, dma_t0, dma_busy, dma_bad, k;
    integer dma_rounds, dma_passed, dma_bus_cycles, dc_blocked_cycles;
    integer dma_len8, dma_len16, dma_len32, dma_len64;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            dma_busy = 0;  dma_rounds = 0;  dma_passed = 0;
            dma_bus_cycles = 0;  dc_blocked_cycles = 0;
            dma_len8 = 0;  dma_len16 = 0;  dma_len32 = 0;  dma_len64 = 0;
        end else begin
            if (bus_ack)                                     dma_bus_cycles    = dma_bus_cycles + 1;
            if (bus_ack && (dc_mem_rd_req || dc_mem_wr_req)) dc_blocked_cycles = dc_blocked_cycles + 1;

            if (dma_ir_req) begin                                           // CPU -> DMA 설정
                for (k = 0; k < DMA_NUM; k = k + 1) dma_snap[k] = ext_dev.dev_mem[k];
                dma_chk_len  = (dma_len > DMA_NUM) ? DMA_NUM : dma_len;
                dma_chk_addr = dma_addr;
                dma_t0       = timestamp;
                dma_busy     = 1;
                $display("[TIME:%6dns] DMA start : $3=%h -> len=%2d, PC=%h -> addr=%h",
                         $time, top.ir_r3_data, dma_len, top.pc, dma_addr);
            end

            if (dev_ir_ack && dma_busy) begin                               // DMA 완료 -> device ack
                dma_bad = 0;
                for (k = 0; k < dma_chk_len; k = k + 1)
                    if (mem_inst.memory[dma_chk_addr + k] !== dma_snap[k]) dma_bad = dma_bad + 1;
                dma_rounds  = dma_rounds + 1;
                dma_chk_end = dma_chk_addr + dma_chk_len - 1;
                if (dma_bad == 0) dma_passed = dma_passed + 1;
                case (dma_chk_len)
                    8:  dma_len8  = dma_len8  + 1;
                    16: dma_len16 = dma_len16 + 1;
                    32: dma_len32 = dma_len32 + 1;
                    64: dma_len64 = dma_len64 + 1;
                endcase
                $display("[TIME:%6dns] DMA done  : %s %2d/%2d words, memory[%h~%h], %0d cycles",
                         $time, (dma_bad == 0) ? "PASS" : "FAIL", dma_chk_len - dma_bad, dma_chk_len,
                         dma_chk_addr, dma_chk_end, timestamp - dma_t0 + 1);
                dma_busy = 0;
            end
        end
    end


    /*******************************************************
     * PART 5: Test Sequence
     *******************************************************/

    integer iter_cnt;
    initial begin
        ir_msg_to_cpu = 'd0;
        // $dumpfile("vcd/cpu_tb.vcd");
        $dumpvars(0);
        Program1;
        Program2;
        Program3;
        $finish();
    end

    task ExecuteProgram;
        input [31:0] cursor_limit;
    begin
        iter_cnt = 0;
        while ((ir_cursor <= cursor_limit) && (iter_cnt < 16384)) begin
            #CLOCK_PS;
            iter_cnt = iter_cnt + 1;
        end
        $display("* %1d passed out of %1d tests in total", ir_passed, ir_cursor);
        $display("* simulated execution time: %1d cycles", iter_cnt);
        // Lab9 추가: DMA summary
        $display("* DMA: %0d passed out of %0d transfers (len 8:%0d, 16:%0d, 32:%0d, 64:%0d)",
                 dma_passed, dma_rounds, dma_len8, dma_len16, dma_len32, dma_len64);
        if (dma_busy) $display("*      (1 more transfer was still in progress when the program ended)");
        $display("* DMA held the bus for %0d cycles, D-cache waited %0d cycles for the bus",
                 dma_bus_cycles, dc_blocked_cycles);
    end
    endtask

    task Program1;
    begin
        reset_n = 'd0;
        #CLOCK_PS;
        reset_n = 'd1;

        $display("\n:: EXECUTING PROGRAM 1 ::");
        // Program Initialization
        mem_inst.memory[0]  = 16'h6000;            //	LHI $0, 0
        mem_inst.memory[1]  = 16'h6101;            //	LHI $1, 1
        mem_inst.memory[2]  = 16'h6202;            //   LHI $2, 2
        mem_inst.memory[3]  = 16'h6303;            //	LHI $3, 3
        mem_inst.memory[4]  = 16'hf01c;            //	WWD $0  -> 0 
        mem_inst.memory[5]  = 16'hf41c;            //	WWD $1  -> 256
        mem_inst.memory[6]  = 16'hf81c;            //	WWD $2  -> 512
        mem_inst.memory[7]  = 16'hfc1c;            //	WWD $3  -> 768
        mem_inst.memory[8]  = 16'h4204;            //	ADI $2, $0, 4
        mem_inst.memory[9]  = 16'h47fc;            //	ADI $3, $1, -4
        mem_inst.memory[10] = 16'hf81c;            //	WWD $2  -> 4
        mem_inst.memory[11] = 16'hfc1c;            //	WWD $3  -> 252
        mem_inst.memory[12] = 16'hf6c0;            //	ADD $3, $1, $2
        mem_inst.memory[13] = 16'hf180;            //	ADD $2, $0, $1
        mem_inst.memory[14] = 16'hf81c;            //	WWD $2  -> 256
        mem_inst.memory[15] = 16'hfc1c;            //	WWD $3  -> 260
        mem_inst.memory[16] = 16'h9015;            //	JMP 21
        mem_inst.memory[17] = 16'hf01c;            //	WWD $0  -> 0    -> not occur
        mem_inst.memory[18] = 16'hf180;            //	ADD $2, $0, $1  -> not occur
        mem_inst.memory[19] = 16'hf180;            //	ADD $2, $0, $1  -> not occur
        mem_inst.memory[20] = 16'hf180;            //	ADD $2, $0, $1  -> not occur
        mem_inst.memory[21] = 16'h6000;            //	LHI $0, 0
        mem_inst.memory[22] = 16'h4000;            //	ADI $0, $0, 0
        mem_inst.memory[23] = 16'hfd80;            //	ADD $2, $3, $1
        mem_inst.memory[24] = 16'hf01c;            //	WWD $0 -> 0
        mem_inst.memory[25] = 16'hf41c;            //	WWD $1 -> 256
        mem_inst.memory[26] = 16'hf81c;            //	WWD $2 -> 256 + 260 = 516
        mem_inst.memory[27] = 16'hfc1c;            //	WWD $3 -> 260
        // Expected Outputs Initialization
        ir_msg_reference[0]  = 16'd0;       // mem_inst.memory[4]
        ir_msg_reference[1]  = 16'd256;     // mem_inst.memory[5]
        ir_msg_reference[2]  = 16'd512;     // mem_inst.memory[6]
        ir_msg_reference[3]  = 16'd768;     // mem_inst.memory[7]
        ir_msg_reference[4]  = 16'd4;       // mem_inst.memory[10]
        ir_msg_reference[5]  = 16'd252;     // mem_inst.memory[11]
        ir_msg_reference[6]  = 16'd256;     // mem_inst.memory[14]
        ir_msg_reference[7]  = 16'd260;     // mem_inst.memory[15]
        ir_msg_reference[8]  = 16'd0;       // mem_inst.memory[17]     
        ir_msg_reference[9]  = 16'd256;     // mem_inst.memory[24]     
        ir_msg_reference[10] = 16'd516;     // mem_inst.memory[25]
        ir_msg_reference[11] = 16'd260;     // mem_inst.memory[26]
        // Execution
        ExecuteProgram(11);  // execute until interrupt cursor ends up to 11
    end
    endtask

    task Program2;
    begin
        reset_n = 'd0;
        #CLOCK_PS;
        reset_n = 'd1;

        $display("\n:: EXECUTING PROGRAM 2 ::");
        // Program Initialization
        mem_inst.memory[0]  = 16'h6005;            // LHI $0, 5
        mem_inst.memory[1]  = 16'h610d;            // LHI $1, 13
        mem_inst.memory[2]  = 16'h6215;            // LHI $2, 21
        mem_inst.memory[3]  = 16'h6340;            // LHI $3, 64
        mem_inst.memory[4]  = 16'hf01c;            // WWD $0
        mem_inst.memory[5]  = 16'hf41c;            // WWD $1
        mem_inst.memory[6]  = 16'hf81c;            // WWD $2
        mem_inst.memory[7]  = 16'hfc1c;            // WWD $3
        mem_inst.memory[8]  = 16'hf000;            // ADD $0, $0, $0
        mem_inst.memory[9]  = 16'hfa40;            // ADD $1, $2, $2
        mem_inst.memory[10] = 16'hf01c;            // WWD $0
        mem_inst.memory[11] = 16'hf41c;            // WWD $1
        mem_inst.memory[12] = 16'h60ff;            // LHI $0, 255       // (255 or 0xffff stands for -1)
        mem_inst.memory[13] = 16'hf440;            // ADD $1, $1, $0
        mem_inst.memory[14] = 16'hf880;            // ADD $2, $2, $0
        mem_inst.memory[15] = 16'hf41c;            // WWD $1
        mem_inst.memory[16] = 16'hf81c;            // WWD $2
        mem_inst.memory[17] = 16'hfc1c;            // WWD $3
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
    
    task Program3;
    begin
        reset_n = 'd0;
        #CLOCK_PS;
        reset_n = 'd1;

        $display("\n:: EXECUTING PROGRAM 4 ::");
        // Program Initialization
        mem_inst.memory[16'h0]  = 16'h9023;
        mem_inst.memory[16'h1]  = 16'h1;
        mem_inst.memory[16'h2]  = 16'hffff;
        mem_inst.memory[16'h3]  = 16'h0;
        mem_inst.memory[16'h4]  = 16'h0;
        mem_inst.memory[16'h5]  = 16'h0;
        mem_inst.memory[16'h6]  = 16'h0;
        mem_inst.memory[16'h7]  = 16'h0;
        mem_inst.memory[16'h8]  = 16'h0;
        mem_inst.memory[16'h9]  = 16'h0;
        mem_inst.memory[16'ha]  = 16'h0;
        mem_inst.memory[16'hb]  = 16'h0;
        mem_inst.memory[16'hc]  = 16'h0;
        mem_inst.memory[16'hd]  = 16'h0;
        mem_inst.memory[16'he]  = 16'h0;
        mem_inst.memory[16'hf]  = 16'h0;
        mem_inst.memory[16'h10] = 16'h0;
        mem_inst.memory[16'h11] = 16'h0;
        mem_inst.memory[16'h12] = 16'h0;
        mem_inst.memory[16'h13] = 16'h0;
        mem_inst.memory[16'h14] = 16'h0;
        mem_inst.memory[16'h15] = 16'h0;
        mem_inst.memory[16'h16] = 16'h0;
        mem_inst.memory[16'h17] = 16'h0;
        mem_inst.memory[16'h18] = 16'h0;
        mem_inst.memory[16'h19] = 16'h0;
        mem_inst.memory[16'h1a] = 16'h0;
        mem_inst.memory[16'h1b] = 16'h0;
        mem_inst.memory[16'h1c] = 16'h0;
        mem_inst.memory[16'h1d] = 16'h0;
        mem_inst.memory[16'h1e] = 16'h0;
        mem_inst.memory[16'h1f] = 16'h0;
        mem_inst.memory[16'h20] = 16'h0;
        mem_inst.memory[16'h21] = 16'h0;
        mem_inst.memory[16'h22] = 16'h0;
        mem_inst.memory[16'h23] = 16'h6000;
        mem_inst.memory[16'h24] = 16'hf01c;    // WWD $0 - 0
        mem_inst.memory[16'h25] = 16'h6100;
        mem_inst.memory[16'h26] = 16'hf41c;    // WWD $1 - 1
        mem_inst.memory[16'h27] = 16'h6200;
        mem_inst.memory[16'h28] = 16'hf81c;    // WWD $2 - 2
        mem_inst.memory[16'h29] = 16'h6300;
        mem_inst.memory[16'h2a] = 16'hfc1c;    // WWD $3 - 3
        mem_inst.memory[16'h2b] = 16'h4401;
        mem_inst.memory[16'h2c] = 16'hf01c;    // WWD $0 - 4
        mem_inst.memory[16'h2d] = 16'h4001;
        mem_inst.memory[16'h2e] = 16'hf01c;    // WWD $0 - 5
        mem_inst.memory[16'h2f] = 16'h5901;
        mem_inst.memory[16'h30] = 16'hf41c;    // WWD $1 - 6
        mem_inst.memory[16'h31] = 16'h5502;
        mem_inst.memory[16'h32] = 16'hf41c;    // WWD $1 - 7
        mem_inst.memory[16'h33] = 16'h5503;
        mem_inst.memory[16'h34] = 16'hf41c;    // WWD $1 - 8
        mem_inst.memory[16'h35] = 16'hf2c0;
        mem_inst.memory[16'h36] = 16'hfc1c;    // WWD $3 - 9
        mem_inst.memory[16'h37] = 16'hf6c0;
        mem_inst.memory[16'h38] = 16'hfc1c;    // WWD $3 - 10
        mem_inst.memory[16'h39] = 16'hf1c0;
        mem_inst.memory[16'h3a] = 16'hfc1c;    // WWD $3 - 11
        mem_inst.memory[16'h3b] = 16'hf2c1;
        mem_inst.memory[16'h3c] = 16'hfc1c;    // WWD $3 - 12
        mem_inst.memory[16'h3d] = 16'hf8c1;
        mem_inst.memory[16'h3e] = 16'hfc1c;    // WWD $3 - 13
        mem_inst.memory[16'h3f] = 16'hf6c1;
        mem_inst.memory[16'h40] = 16'hfc1c;    // WWD $3 - 14
        mem_inst.memory[16'h41] = 16'hf9c1;
        mem_inst.memory[16'h42] = 16'hfc1c;    // WWD $3 - 15
        mem_inst.memory[16'h43] = 16'hf1c1;
        mem_inst.memory[16'h44] = 16'hfc1c;    // WWD $3 - 16
        mem_inst.memory[16'h45] = 16'hf4c1;
        mem_inst.memory[16'h46] = 16'hfc1c;    // WWD $3 - 17
        mem_inst.memory[16'h47] = 16'hf2c2;
        mem_inst.memory[16'h48] = 16'hfc1c;    // WWD $3 - 18
        mem_inst.memory[16'h49] = 16'hf6c2;
        mem_inst.memory[16'h4a] = 16'hfc1c;    // WWD $3 - 19
        mem_inst.memory[16'h4b] = 16'hf1c2;
        mem_inst.memory[16'h4c] = 16'hfc1c;    // WWD $3 - 20
        mem_inst.memory[16'h4d] = 16'hf2c3;
        mem_inst.memory[16'h4e] = 16'hfc1c;    // WWD $3 - 21
        mem_inst.memory[16'h4f] = 16'hf6c3;
        mem_inst.memory[16'h50] = 16'hfc1c;    // WWD $3 - 22
        mem_inst.memory[16'h51] = 16'hf1c3;
        mem_inst.memory[16'h52] = 16'hfc1c;    // WWD $3 - 23
        mem_inst.memory[16'h53] = 16'hf0c4;
        mem_inst.memory[16'h54] = 16'hfc1c;    // WWD $3 - 24
        mem_inst.memory[16'h55] = 16'hf4c4;
        mem_inst.memory[16'h56] = 16'hfc1c;    // WWD $3 - 25
        mem_inst.memory[16'h57] = 16'hf8c4;
        mem_inst.memory[16'h58] = 16'hfc1c;    // WWD $3 - 26
        mem_inst.memory[16'h59] = 16'hf0c5;
        mem_inst.memory[16'h5a] = 16'hfc1c;    // WWD $3 - 27
        mem_inst.memory[16'h5b] = 16'hf4c5;
        mem_inst.memory[16'h5c] = 16'hfc1c;    // WWD $3 - 28
        mem_inst.memory[16'h5d] = 16'hf8c5;
        mem_inst.memory[16'h5e] = 16'hfc1c;    // WWD $3 - 29
        mem_inst.memory[16'h5f] = 16'hf0c6;
        mem_inst.memory[16'h60] = 16'hfc1c;    // WWD $3 - 30
        mem_inst.memory[16'h61] = 16'hf4c6;
        mem_inst.memory[16'h62] = 16'hfc1c;    // WWD $3 - 31
        mem_inst.memory[16'h63] = 16'hf8c6;
        mem_inst.memory[16'h64] = 16'hfc1c;    // WWD $3 - 32
        mem_inst.memory[16'h65] = 16'hf0c7;    
        mem_inst.memory[16'h66] = 16'hfc1c;    // WWD $3 - 33
        mem_inst.memory[16'h67] = 16'hf4c7;    
        mem_inst.memory[16'h68] = 16'hfc1c;    // 34  
        mem_inst.memory[16'h69] = 16'hf8c7;     
        mem_inst.memory[16'h6a] = 16'hfc1c;    // 35
        mem_inst.memory[16'h6b] = 16'h7801;    
        mem_inst.memory[16'h6c] = 16'hf01c;    // WWD $0 - 36
        mem_inst.memory[16'h6d] = 16'h7902;
        mem_inst.memory[16'h6e] = 16'hf41c;    // WWD $1 - 37 
        mem_inst.memory[16'h6f] = 16'h8901;    
        mem_inst.memory[16'h70] = 16'h8802;    
        mem_inst.memory[16'h71] = 16'h7801;    
        mem_inst.memory[16'h72] = 16'hf01c;    // WWD $0 - 38
        mem_inst.memory[16'h73] = 16'h7902;    
        mem_inst.memory[16'h74] = 16'hf41c;    // WWD $1 - 39 
        mem_inst.memory[16'h75] = 16'h9076;    
        mem_inst.memory[16'h76] = 16'hf01c;    // WWD $0 - 40 
        mem_inst.memory[16'h77] = 16'h9079;    
        mem_inst.memory[16'h78] = 16'hf01d;    
        mem_inst.memory[16'h79] = 16'hf41c;    // WWD $1 - 41 
        mem_inst.memory[16'h7a] = 16'h0b01;    
        mem_inst.memory[16'h7b] = 16'h907d;    
        mem_inst.memory[16'h7c] = 16'hf01d;    
        mem_inst.memory[16'h7d] = 16'hf01c;    // WWD $0 - 42 
        mem_inst.memory[16'h7e] = 16'h0601;    
        mem_inst.memory[16'h7f] = 16'hf01d;    
        mem_inst.memory[16'h80] = 16'hf41c;    // WWD $1 - 43 
        mem_inst.memory[16'h81] = 16'h1601;    
        mem_inst.memory[16'h82] = 16'h9084;    
        mem_inst.memory[16'h83] = 16'hf01d;    
        mem_inst.memory[16'h84] = 16'hf01c;    // WWD $0 - 44 
        mem_inst.memory[16'h85] = 16'h1b01;    
        mem_inst.memory[16'h86] = 16'hf01d;    
        mem_inst.memory[16'h87] = 16'hf41c;    // WWD $1 - 45 
        mem_inst.memory[16'h88] = 16'h2001;    
        mem_inst.memory[16'h89] = 16'h908b;    
        mem_inst.memory[16'h8a] = 16'hf01d;    
        mem_inst.memory[16'h8b] = 16'hf01c;    // WWD $0 - 46 
        mem_inst.memory[16'h8c] = 16'h2401;    
        mem_inst.memory[16'h8d] = 16'hf01d;    
        mem_inst.memory[16'h8e] = 16'hf41c;    // WWD $1 - 47 
        mem_inst.memory[16'h8f] = 16'h2801;    
        mem_inst.memory[16'h90] = 16'h9092;    
        mem_inst.memory[16'h91] = 16'hf01d;    
        mem_inst.memory[16'h92] = 16'hf01c;    // WWD $0 - 48 
        mem_inst.memory[16'h93] = 16'h3001;    
        mem_inst.memory[16'h94] = 16'hf01d;    
        mem_inst.memory[16'h95] = 16'hf41c;    // WWD $1 - 49 
        mem_inst.memory[16'h96] = 16'h3401;    
        mem_inst.memory[16'h97] = 16'h9099;    
        mem_inst.memory[16'h98] = 16'hf01d;    
        mem_inst.memory[16'h99] = 16'hf01c;    // WWD $0 - 50 
        mem_inst.memory[16'h9a] = 16'h3801;    
        mem_inst.memory[16'h9b] = 16'h909d;
        mem_inst.memory[16'h9c] = 16'hf01d;
        mem_inst.memory[16'h9d] = 16'hf41c;    // WWD $1 - 51 
        mem_inst.memory[16'h9e] = 16'ha0af;
        mem_inst.memory[16'h9f] = 16'hf01c;    // WWD $0 - 52 
        mem_inst.memory[16'ha0] = 16'ha0ae;
        mem_inst.memory[16'ha1] = 16'hf01d;
        mem_inst.memory[16'ha2] = 16'hf41c;    // WWD $1 - 53 
        mem_inst.memory[16'ha3] = 16'h6300;
        mem_inst.memory[16'ha4] = 16'h5f03;
        mem_inst.memory[16'ha5] = 16'h6000;
        mem_inst.memory[16'ha6] = 16'h4005;
        mem_inst.memory[16'ha7] = 16'ha0b2;
        mem_inst.memory[16'ha8] = 16'hf01c;    // WWD $0 - 54 
        mem_inst.memory[16'ha9] = 16'h90b1;
        mem_inst.memory[16'haa] = 16'h4900;
        mem_inst.memory[16'hab] = 16'hf41a;
        mem_inst.memory[16'hac] = 16'hf01c;    // WWD $0 - 55 
        mem_inst.memory[16'had] = 16'hf01d;    // HLT
        mem_inst.memory[16'hae] = 16'h4a01;
        mem_inst.memory[16'haf] = 16'hf819;
        mem_inst.memory[16'hb0] = 16'hf01d;    // HLT
        mem_inst.memory[16'hb1] = 16'ha0aa;
        mem_inst.memory[16'hb2] = 16'h41ff;
        mem_inst.memory[16'hb3] = 16'h2404;
        mem_inst.memory[16'hb4] = 16'h6000;
        mem_inst.memory[16'hb5] = 16'h5001;
        mem_inst.memory[16'hb6] = 16'hf819;
        mem_inst.memory[16'hb7] = 16'hf01d;    // HLT
        mem_inst.memory[16'hb8] = 16'h8e00;
        mem_inst.memory[16'hb9] = 16'h8c01;
        mem_inst.memory[16'hba] = 16'h4f02;
        mem_inst.memory[16'hbb] = 16'h40fe;
        mem_inst.memory[16'hbc] = 16'ha0b2;
        mem_inst.memory[16'hbd] = 16'h7dff;
        mem_inst.memory[16'hbe] = 16'h8cff;
        mem_inst.memory[16'hbf] = 16'h44ff;
        mem_inst.memory[16'hc0] = 16'ha0b2;
        mem_inst.memory[16'hc1] = 16'h7dff;
        mem_inst.memory[16'hc2] = 16'h7efe;
        mem_inst.memory[16'hc3] = 16'hf100;
        mem_inst.memory[16'hc4] = 16'h4ffe;
        mem_inst.memory[16'hc5] = 16'hf819;
        mem_inst.memory[16'hc6] = 16'hf01d;    // HLT
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