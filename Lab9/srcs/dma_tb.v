`timescale 1ns / 1ps

module DMA_tb ();

    /*******************************************************
     * PART 1: Testbench Header
     *******************************************************/

    // Parameter Definitions
    parameter  CLOCK_PS     = 100;                  // clock period
    parameter  HCLOCK_PS    = CLOCK_PS / 2;         // half clock period
    localparam TIMEOUT = 999_999;                   // timestamp that is considered as timeout
 
    localparam WORD_SIZE    = 16;                   // Word = 16-bit 
    localparam WORD_NUM     = 8192;                 // 8K words of memory
    localparam MEM_LATENCY  = 8;                    // 8 cycles fixed latency 
    
    localparam BLOCK_SIZE   = 4;                    // 4 words per block 
    localparam BLOCK_NUM    = 16;                   // 16 blocks of cache
    
    localparam DEV_NUM_LG2  = 6;                    // 64 words in the device
    localparam DMA_NUM_LG2  = 4;                    // 16 words in the DMA
    localparam DEFAULT_ADDR = 512;                  // default address to write 
    
    integer i;
    
    // Global Signals
    reg                         clk;
    reg                         reset_n;
    
    // Instruction Cache IF
    reg     [WORD_SIZE-1:0]     icache_addr;        // address from the cpu
    wire    [WORD_SIZE-1:0]     icache_rd_data;     // cpu read data
    reg                         icache_rd_req;      // cpu read request (from master)
    wire                        icache_rd_ack;      // cpu read acknowledge (to master)
    
    // Data Cache IF
    reg     [WORD_SIZE-1:0]     dcache_addr;        // address from the cpu
    wire    [WORD_SIZE-1:0]     dcache_rd_data;     // cpu read data
    reg                         dcache_rd_req;      // cpu read request (from master)
    wire                        dcache_rd_ack;      // cpu read acknowledge (to master)
    reg     [WORD_SIZE-1:0]     dcache_wr_data;     // cpu write data
    reg                         dcache_wr_req;      // cpu write request (from master)
    wire                        dcache_wr_ack;      // cpu write acknowledge (to master)
    
    // EXT_DEV IF
    wire    [DEV_NUM_LG2-1:0]   dev_rd_addr;        // device read address
    wire    [WORD_SIZE-1:0]     dev_rd_data;        // device read data
    wire                        dev_ir_ack;         // interrupt acknowledge from dma
    wire                        dev_ir_req;         // interrupt request to dma
    
    // Arbiter IF
    wire    [WORD_SIZE-1:0]     dc_mem_addr;        // address given to the memory
    wire    [WORD_SIZE-1:0]     dc_mem_rd_data;
    wire                        dc_mem_rd_req;
    wire                        dc_mem_rd_ack;
    
    wire    [WORD_SIZE-1:0]     dc_mem_wr_data;     // memory write data
    wire                        dc_mem_wr_req;      // memory write request
    wire                        dc_mem_wr_ack;      // memory write acknowledge
    
    wire    [WORD_SIZE-1:0]     dma_mem_rw_addr;    // address given to the memory
    wire    [WORD_SIZE-1:0]     dma_mem_wr_data;    // memory write data
    wire                        dma_mem_wr_req;     // memory write request
    wire                        dma_mem_wr_ack;     // memory write acknowledge
    
    wire                        bus_req;            // bus grant request
    wire                        bus_ack;            // bus acknowledge 

    // Memory IF
    wire    [WORD_SIZE-1:0]     mem_rw_addr;        // address to the memory (by D$ or DMA)
    wire    [WORD_SIZE-1:0]     mem_rd_data;        // memory read data
    wire                        mem_rd_req;         // memory read request (to slave)
    wire                        mem_rd_ack;         // memory read acknowledge (from slave)
    wire    [WORD_SIZE-1:0]     mem_wr_data;        // memory write data
    wire                        mem_wr_req;         // memory write request (to slave)
    wire                        mem_wr_ack;         // memory write acknowledge (from slave)
    wire    [WORD_SIZE-1:0]     mem_ro_addr;        // address given to the memory
    wire    [WORD_SIZE-1:0]     mem_ro_data;        // memory read data
    wire                        mem_ro_req;         // memory read request (to slave)
    wire                        mem_ro_ack;         // memory read acknowledge (from slave)


    // Instruction Cache Instance
    InstrCache_DM #(
        .WORD_SIZE          (WORD_SIZE),
        .BLOCK_SIZE         (BLOCK_SIZE),
        .BLOCK_NUM          (BLOCK_NUM)
    ) i_cache (
        .clk                (clk),
        .reset_n            (reset_n),
        .cpu_addr_i         (icache_addr),
        .cpu_rd_data_o      (icache_rd_data),
        .cpu_rd_req_i       (icache_rd_req),
        .cpu_rd_ack_o       (icache_rd_ack),
        .mem_addr_o         (mem_ro_addr),
        .mem_ro_data_i      (mem_ro_data),
        .mem_ro_req_o       (mem_ro_req),
        .mem_ro_ack_i       (mem_ro_ack)
    );

    // Data Cache Instance
    DataCache_DM #(
        .WORD_SIZE          (WORD_SIZE),
        .BLOCK_SIZE         (BLOCK_SIZE),
        .BLOCK_NUM          (BLOCK_NUM)
    )u_DataCache_DM(
        .clk                (clk),
        .reset_n            (reset_n),
        .cpu_addr_i         (dcache_addr),
        .cpu_rd_data_o      (dcache_rd_data),
        .cpu_rd_req_i       (dcache_rd_req),
        .cpu_rd_ack_o       (dcache_rd_ack),
        .cpu_wr_data_i      (dcache_wr_data),
        .cpu_wr_req_i       (dcache_wr_req),
        .cpu_wr_ack_o       (dcache_wr_ack),
        .mem_addr_o         (dc_mem_addr),
        .mem_rd_data_i      (dc_mem_rd_data),
        .mem_rd_req_o       (dc_mem_rd_req),
        .mem_rd_ack_i       (dc_mem_rd_ack),
        .mem_wr_data_o      (dc_mem_wr_data),
        .mem_wr_req_o       (dc_mem_wr_req),
        .mem_wr_ack_i       (dc_mem_wr_ack)
    );

    // EXT_DEV Instance
    EXT_DEV #(
        .WORD_SIZE          (WORD_SIZE),
        .WORD_NUM_LG2       (DEV_NUM_LG2)
    )u_EXT_DEV(
        .clk                (clk),
        .reset_n            (reset_n),
        .dev_rd_addr_i      (dev_rd_addr),
        .dev_rd_data_o      (dev_rd_data),
        .dev_ir_ack_i       (dev_ir_ack),
        .dev_ir_req_o       (dev_ir_req)
    );
    
    DMA #(
        .WORD_SIZE          (WORD_SIZE),
        .DEV_NUM_LG2        (DEV_NUM_LG2),
        .DMA_NUM_LG2        (DMA_NUM_LG2),
        .DEFAULT_ADDR       (DEFAULT_ADDR)
    )u_DMA(
        .clk                (clk),
        .reset_n            (reset_n),
        .dev_rd_addr_o      (dev_rd_addr),
        .dev_rd_data_i      (dev_rd_data),
        .dev_ir_ack_o       (dev_ir_ack),
        .dev_ir_req_i       (dev_ir_req),
        .mem_rw_addr_o      (dma_mem_rw_addr),
        .mem_wr_data_o      (dma_mem_wr_data),
        .mem_wr_req_o       (dma_mem_wr_req),
        .mem_wr_ack_i       (dma_mem_wr_ack),
        .bus_req_o          (bus_req),
        .bus_ack_i          (bus_ack)
    );

    // Arbiter Instance
    ARBITER #(
        .WORD_SIZE          (WORD_SIZE),
        .MEM_LATENCY        (MEM_LATENCY)
    )u_ARBITER(
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

    // Memory Instance
    Memory #(
        .WORD_SIZE          (WORD_SIZE),
        .WORD_NUM           (WORD_NUM),
        .MEM_LATENCY        (MEM_LATENCY)
    )u_Memory(
        .clk                (clk),
        .reset_n            (reset_n),
        .rw_addr_i          (mem_rw_addr),
        .rd_data_o          (mem_rd_data),
        .rd_req_i           (mem_rd_req),
        .rd_ack_o           (mem_rd_ack),
        .wr_data_i          (mem_wr_data),
        .wr_req_i           (mem_wr_req),
        .wr_ack_o           (mem_wr_ack),
        .ro_addr_i          (mem_ro_addr),
        .ro_data_o          (mem_ro_data),
        .ro_req_i           (mem_ro_req),
        .ro_ack_o           (mem_ro_ack)
    );
    
    /*******************************************************
     * PART 2: Clock Generation
     *******************************************************/

    integer timestamp;
    
    initial begin : CLOCK_GENERATOR
        clk = 1'b0;
        timestamp = 0;
        forever #HCLOCK_PS clk = ~clk;
    end

    always @(posedge clk) begin
        timestamp = timestamp + 1;
    end
    
    initial begin
        while (timestamp < TIMEOUT)
            #CLOCK_PS;

        $display("The simulation terminated with timeout. Change the TIMEOUT parameter of the testbench from '%1d' to the larger value.", TIMEOUT);
        $finish();
    end
    
    /*******************************************************
     * PART 3: Simple Test Degug
     *******************************************************/
    
    localparam DMA_NUM = 2**DMA_NUM_LG2;
    reg [WORD_SIZE-1:0] buf_1 [0:DMA_NUM-1];
    reg [WORD_SIZE-1:0] buf_2 [0:DMA_NUM-1];
    integer j;
    
    initial begin
        j = 0;
        for (j=0; j<DMA_NUM; j=j+1) begin
            buf_1[j] = 'h0;
            buf_2[j] = 'h0;
        end
        
        while (timestamp < TIMEOUT) begin
            if (dev_ir_req == 1'b1) begin
                for (j=0; j<DMA_NUM; j=j+1) begin
                    buf_1[j] = u_EXT_DEV.dev_mem[j];
                end
            end
                
            if (dev_ir_ack == 1'b1) begin
                $display("Device Interrupt Acknowledged: timestamp=%d", timestamp);
                for (j=0; j<DMA_NUM; j=j+1) begin
                    buf_2[j] = u_Memory.memory[j+DEFAULT_ADDR];
                end
                for (j=0; j<DMA_NUM; j=j+1) begin
                    $display("Migration: EXT_NUM[%d]=%h -> Memory[%d]=%h", j, buf_1[j], j+DEFAULT_ADDR,buf_2[j]);
                end
            end
            #CLOCK_PS;
        end
    end
    
    
    /*******************************************************
     * PART 4: Test Sequence
     *******************************************************/
    initial begin
        
        icache_addr    = 'd0;
        icache_rd_req  = 'd0;

        dcache_addr    = 'd0;
        dcache_rd_req  = 'd0;
        dcache_wr_data = 'd0;
        dcache_wr_req  = 'd0;
        
        reset_n = 'd0;
        #CLOCK_PS;
        reset_n = 'd1;
        
        TestDefault;
        #CLOCK_PS;
        #CLOCK_PS;
        #CLOCK_PS;
        #CLOCK_PS;

        $finish();
    end

    /*******************************************************
     * PART 5: Task Definition
     *******************************************************/

    
    task TestDefault;
    begin
        $display("\nTest #1: Simultaneous Icache and Dcache Read and Write");


        for (i = 0; i < 32; i = i + 1) begin
            IcacheReadWithAddress(i);
        end

        for (i = 0; i < 128; i = i + 1) begin
            WriteWithAddress(i, 'hffff);
            ReadWithAddress(i + 128);
        end
        
        for (i = 0; i < 32; i = i + 1) begin
            IcacheReadWithAddress(i);
        end
    end
    endtask
    
    task TestTemplate;
    begin
        $display("\nCustom Test");

        IcacheReadWithAddress(0);
        WriteWithAddress(0, 'hffff);
        ReadWithAddress(0);

    end
    endtask

    task IcacheReadWithAddress;
        input [WORD_SIZE-1:0] addr;
        begin
            icache_addr   = addr;
            icache_rd_req = 1'b1;
            #CLOCK_PS;
            while (icache_rd_ack == 1'b0)
                #CLOCK_PS;
            icache_rd_req = 1'b0;
        end
    endtask
    
    task ReadWithAddress;
        input [WORD_SIZE-1:0] addr;
        begin
            dcache_addr   = addr;
            dcache_rd_req = 1'b1;
            #CLOCK_PS;
            while (dcache_rd_ack == 1'b0)
                #CLOCK_PS;
            dcache_rd_req = 1'b0;
        end
    endtask
    
    task WriteWithAddress;
        input [WORD_SIZE-1:0] addr;
        input [WORD_SIZE-1:0] wr_data;
        begin
            dcache_addr    = addr;
            dcache_wr_data = wr_data;
            dcache_wr_req  = 1'b1;
            #CLOCK_PS;
            while (dcache_wr_ack == 1'b0)
                #CLOCK_PS;
            dcache_wr_req = 1'b0;
        end
    endtask
    
    
endmodule