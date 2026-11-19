`timescale 1ns / 1ps

module InstrCache_DM_tb ();

    /*******************************************************
     * PART 1: Testbench Header
     *******************************************************/

    // Parameter Definitions
    parameter  CLOCK_PS     = 100;           // clock period
    parameter  HCLOCK_PS    = CLOCK_PS / 2;  // half clock period

    localparam WORD_SIZE    = 16;    // 
    localparam BLOCK_SIZE   = 4;     // 
    localparam BLOCK_NUM    = 16;    // 
    localparam WORD_NUM     = 8192;  //
    
    localparam TIMEOUT = 262_144;  // timestamp that is considered as timeout
    localparam VERBOSE = 0;        // if 1, the testbench code prints out the detailed log not only the error message, but also the informative messages

    // Global Signals
    reg                         clk;
    reg                         reset_n;
    
    // Instruction Cache IF
    reg     [WORD_SIZE-1:0]     icache_addr;     // address from the cpu
    wire    [WORD_SIZE-1:0]     icache_rd_data;  // cpu read data
    reg                         icache_rd_req;   // cpu read request (from master)
    wire                        icache_rd_ack;   // cpu read acknowledge (to master)

    // Data Cache IF
    reg     [WORD_SIZE-1:0]     dcache_addr;     // address from the cpu
    wire    [WORD_SIZE-1:0]     dcache_rd_data;  // cpu read data
    reg                         dcache_rd_req;   // cpu read request (from master)
    wire                        dcache_rd_ack;   // cpu read acknowledge (to master)
    reg     [WORD_SIZE-1:0]     dcache_wr_data;  // cpu write data
    reg                         dcache_wr_req;   // cpu write request (from master)
    wire                        dcache_wr_ack;   // cpu write acknowledge (to master)

    // Memory IF
    wire    [WORD_SIZE-1:0]     mem_rw_addr;     // address given to the memory
    wire    [WORD_SIZE-1:0]     mem_rd_data;  // memory read data
    wire                        mem_rd_req;   // memory read request (to slave)
    wire                        mem_rd_ack;   // memory read acknowledge (from slave)
    wire    [WORD_SIZE-1:0]     mem_wr_data;  // memory write data
    wire                        mem_wr_req;   // memory write request (to slave)
    wire                        mem_wr_ack;   // memory write acknowledge (from slave)
    wire    [WORD_SIZE-1:0]     mem_ro_addr;     // address given to the memory
    wire    [WORD_SIZE-1:0]     mem_ro_data;  // memory read data
    wire                        mem_ro_req;   // memory read request (to slave)
    wire                        mem_ro_ack;   // memory read acknowledge (from slave)

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
        .mem_addr_o     (mem_rw_addr),
        .mem_rd_data_i  (mem_rd_data),
        .mem_rd_req_o   (mem_rd_req),
        .mem_rd_ack_i   (mem_rd_ack),
        .mem_wr_data_o  (mem_wr_data),
        .mem_wr_req_o   (mem_wr_req),
        .mem_wr_ack_i   (mem_wr_ack)
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

    integer _iit;localparam _ppv1=BLOCK_SIZE,_ppv2=BLOCK_NUM,_pvv1=WORD_SIZE,_ssv1=$clog2(_ppv1),_ssv2=$clog2(_ppv2),_ssv3=_pvv1-_ssv2-_ssv1,_pvv2=WORD_NUM;reg[_pvv1-1:0]_ff_rrfm[0:_pvv2-1];reg[_ssv3:0]_ff_rrtm[0:_ppv2-1];initial begin;for(_iit=0;_iit<_pvv2;_iit=_iit+1)begin;_ff_rrfm[_iit]=0;end;for(_iit=0;_iit<_ppv2;_iit=_iit+1)begin;_ff_rrtm[_iit]='d0;end;end;reg[_pvv1-1:0]_ff_rpfm[0:_pvv2-1];reg[_ssv3:0]_ff_rptm[0:_ppv2-1];initial begin;for(_iit=0;_iit<_pvv2;_iit=_iit+1)begin;_ff_rpfm[_iit]=0;end;for(_iit=0;_iit<_ppv2;_iit=_iit+1)begin;_ff_rptm[_iit]='d0;end;end


    /*******************************************************
     * PART 3: Test Sequence
     *******************************************************/

    integer st, ed, flag, total_cnt, passed_cnt, i;
    reg     is_hit, ref_is_hit;

    initial begin
        $dumpfile("vcd/cache_tb.vcd");
        $dumpvars(0);

        icache_addr    = 'd0;
        icache_rd_req  = 'd0;

        dcache_addr    = 'd0;
        dcache_rd_req  = 'd0;
        dcache_wr_data = 'd0;
        dcache_wr_req  = 'd0;

        reset_n = 'd0;
        #CLOCK_PS;
        reset_n = 'd1;

        Test1;
        TestCustom;

        #CLOCK_PS;
        #CLOCK_PS;
        #CLOCK_PS;
        #CLOCK_PS;
        $finish();
    end


    task TestCustom;
    begin
        $display("\nCustom Test");

        // Initialize Counters
        total_cnt  = 0;
        passed_cnt = 0;

        // Test sequence is composed of multiple READ and WRITE operations
        //   * these operations will automatically validate your design whether it is correct or not
        IcacheReadWithAddress(0);       // READ a single word from the address 0

        // Display the Test Summary
        $display("  * test %-5s (%1d out of %1d succeed)", (total_cnt == passed_cnt) ? "passed" : "failed", passed_cnt, total_cnt);
    end
    endtask


    task Test1;
    begin
        $display("\nTest #1: Simultaneous Icache and Dcache Read and Write");
        total_cnt  = 0;
        passed_cnt = 0;

        for (i = 0; i < 128; i = i + 1) begin
            WriteWithAddress(i, 'hffff);
            // ReadWithAddress(i + 128);
        end

        for (i = 0; i < 64; i = i + 1) begin
            IcacheReadWithAddress(i);
        end

        // for (i = 0; i < 64; i = i + 1) begin
        //     IcacheReadWithAddress(i);
        // end

        $display("  * test %-5s (%1d out of %1d succeed)", (total_cnt == passed_cnt) ? "passed" : "failed", passed_cnt, total_cnt);
    end
    endtask


    task CheckIsHit;
        input  integer st;
        input  integer ed;
        output         is_hit;
    begin
        is_hit = (ed - st) < 5;
    end
    endtask


    task IcacheReadWithAddress;
        input [WORD_SIZE-1:0] addr;
    begin
        ref_is_hit=(_ff_rptm[addr[_ssv2+_ssv1-1:_ssv1]][_ssv3-1:0]==addr[_pvv1-1:_ssv2+_ssv1])&&_ff_rptm[addr[_ssv2+_ssv1-1:_ssv1]][_ssv3];_ff_rptm[addr[_ssv2+_ssv1-1:_ssv1]]={1'b1, addr[_pvv1-1:_ssv2+_ssv1]};

        st = timestamp;

        icache_addr   = addr;
        icache_rd_req = 1'b1;

        #CLOCK_PS;

        while (icache_rd_ack == 1'b0)
            #CLOCK_PS;

        ed = timestamp;

        CheckIsHit(st, ed, is_hit);

        total_cnt = total_cnt + 1;

        if ((icache_rd_data == _ff_rrfm[icache_addr]) && (is_hit ~^ ref_is_hit)) begin
            passed_cnt = passed_cnt + 1;
            
            if (VERBOSE)
                $display("[INFO : %-6dns] READ (ICACHE)  %-3d  cycles: %-3d  is_hit: %-5s  (ref) is_hit: %-5s  rd_data: %-5d  (mem) rd_data: %-5d  (ref) rd_data: %-5d", 
                    $time,
                    icache_addr,    // current address
                    (ed - st),   // elapsed time in cycles
                    is_hit ? "hit" : "miss",
                    ref_is_hit ? "hit" : "miss",
                    icache_rd_data,
                    mem_inst.memory[icache_addr],
                    _ff_rrfm[icache_addr]);
        end else begin
            $display("[ERROR: %-6dns] READ (ICACHE)  %-3d  cycles: %-3d  is_hit: %-5s  (ref) is_hit: %-5s  rd_data: %-5d  (mem) rd_data: %-5d  (ref) rd_data: %-5d", 
                $time,
                icache_addr,    // current address
                (ed - st),   // elapsed time in cycles
                is_hit ? "hit" : "miss",
                ref_is_hit ? "hit" : "miss",
                icache_rd_data,
                mem_inst.memory[icache_addr],
                _ff_rrfm[icache_addr]);
        end

        icache_rd_req = 1'b0;
    end
    endtask

    task ReadWithAddress;
        input [WORD_SIZE-1:0] addr;
    begin
        ref_is_hit=(_ff_rrtm[addr[_ssv2+_ssv1-1:_ssv1]][_ssv3-1:0]==addr[_pvv1-1:_ssv2+_ssv1])&&_ff_rrtm[addr[_ssv2+_ssv1-1:_ssv1]][_ssv3];_ff_rrtm[addr[_ssv2+_ssv1-1:_ssv1]]={1'b1, addr[_pvv1-1:_ssv2+_ssv1]};

        st = timestamp;

        dcache_addr   = addr;
        dcache_rd_req = 1'b1;

        #CLOCK_PS;

        while (dcache_rd_ack == 1'b0)
            #CLOCK_PS;

        ed = timestamp;

        CheckIsHit(st, ed, is_hit);

        total_cnt = total_cnt + 1;

        if ((dcache_rd_data == _ff_rrfm[dcache_addr]) && (is_hit ~^ ref_is_hit)) begin
            passed_cnt = passed_cnt + 1;
            
            if (VERBOSE)
                $display("[INFO : %-6dns] READ (DCACHE)  %-3d  cycles: %-3d  is_hit: %-5s  (ref) is_hit: %-5s  rd_data: %-5d  (mem) rd_data: %-5d  (ref) rd_data: %-5d", 
                    $time,
                    dcache_addr,    // current address
                    (ed - st),   // elapsed time in cycles
                    is_hit ? "hit" : "miss",
                    ref_is_hit ? "hit" : "miss",
                    dcache_rd_data,
                    mem_inst.memory[dcache_addr],
                    _ff_rrfm[dcache_addr]);
        end else begin
            $display("[ERROR: %-6dns] READ (DCACHE)  %-3d  cycles: %-3d  is_hit: %-5s  (ref) is_hit: %-5s  rd_data: %-5d  (mem) rd_data: %-5d  (ref) rd_data: %-5d", 
                $time,
                dcache_addr,    // current address
                (ed - st),   // elapsed time in cycles
                is_hit ? "hit" : "miss",
                ref_is_hit ? "hit" : "miss",
                dcache_rd_data,
                mem_inst.memory[dcache_addr],
                _ff_rrfm[dcache_addr]);
        end

        dcache_rd_req = 1'b0;
    end
    endtask


    task WriteWithAddress;
        input [WORD_SIZE-1:0] addr;
        input [WORD_SIZE-1:0] wr_data;
    begin
        _ff_rrfm[addr]=wr_data;ref_is_hit=(_ff_rrtm[addr[_ssv2+_ssv1-1:_ssv1]][_ssv3-1:0]==addr[_pvv1-1:_ssv2+_ssv1])&&_ff_rrtm[addr[_ssv2+_ssv1-1:_ssv1]][_ssv3];_ff_rrtm[addr[_ssv2+_ssv1-1:_ssv1]]={1'b1,addr[_pvv1-1:_ssv2+_ssv1]};
        
        st = timestamp;

        dcache_addr    = addr;
        dcache_wr_data = wr_data;
        dcache_wr_req  = 1'b1;

        #CLOCK_PS;

        while (dcache_wr_ack == 1'b0)
            #CLOCK_PS;

        ed = timestamp;

        CheckIsHit(st, ed, is_hit);

        total_cnt = total_cnt + 1;

        if (is_hit ~^ ref_is_hit) begin
            passed_cnt = passed_cnt + 1;

            if (VERBOSE)
                $display("[INFO : %-6dns] WRITE (DCACHE) %-3d  cycles: %-3d  is_hit: %-5s  (ref) is_hit: %-5s",
                    $time,
                    dcache_addr,    // current address
                    (ed - st),   // elapsed time in cycles
                    is_hit ? "hit" : "miss",
                    ref_is_hit ? "hit" : "miss");
        end else begin
            $display("[ERROR: %-6dns] WRITE (DCACHE) %-3d  cycles: %-3d  is_hit: %-5s  (ref) is_hit: %-5s",
                $time,
                dcache_addr,    // current address
                (ed - st),   // elapsed time in cycles
                is_hit ? "hit" : "miss",
                ref_is_hit ? "hit" : "miss");
        end

        dcache_wr_req = 1'b0;
    end
    endtask

endmodule