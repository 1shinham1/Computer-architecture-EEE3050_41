module DataCache_DM #(
    parameter WORD_SIZE  = 16,  // each word is 16 bits by default
    parameter BLOCK_SIZE = 4,   // each cache line has 4 words by default
    parameter BLOCK_NUM  = 16   // the cache contains 16 blocks by default
) (
    input   wire                         clk,
    input   wire                         reset_n,

    // CPU IF
    input   wire    [WORD_SIZE-1:0]     cpu_addr_i,     // address from the cpu
    output  wire    [WORD_SIZE-1:0]     cpu_rd_data_o,  // cpu read data
    input   wire                        cpu_rd_req_i,   // cpu read request (from master)
    output  wire                        cpu_rd_ack_o,   // cpu read acknowledge (to master)
    input   wire    [WORD_SIZE-1:0]     cpu_wr_data_i,  // cpu write data
    input   wire                        cpu_wr_req_i,   // cpu write request (from master)
    output  wire                        cpu_wr_ack_o,   // cpu write acknowledge (to master)

    // Memory IF
    output  wire    [WORD_SIZE-1:0]     mem_addr_o,     // address given to the memory
    input   wire    [WORD_SIZE-1:0]     mem_rd_data_i,  // memory read data
    output  wire                        mem_rd_req_o,   // memory read request (to slave)
    input   wire                        mem_rd_ack_i,   // memory read acknowledge (from slave)
    output  wire    [WORD_SIZE-1:0]     mem_wr_data_o,  // memory write data
    output  wire                        mem_wr_req_o,   // memory write request (to slave)
    input   wire                        mem_wr_ack_i    // memory write acknowledge (from slave)
);  

    /*******************************************************
     * Project: Data Cache
     *******************************************************

     Description
       * This project is to build a data cache
       * Data cache is attatched to the read-write channel of the memory
     
     Note
       * We provided some skeleton code that may be helpful for you to complete this project
       * If you want to make your own design, you may not follow the steps and instructions given below
       * But, you should follow the design specification provided as the lab material as well as the predefined interfaces

     */

    /*******************************************************
     * STEP #1: Extending Instruction Cache to Data Cache
     *******************************************************

     How can we get into this step?
       1) First, copy and paste your instruction cache code below
       2) Reconnect the cache read channel to the read-write channel
       3) Think about is there any additional states required to control write channel of the memory
       4) Modify the FSM
       5) Extend the control logic to support write channel of the memory

     */

     // COPY AND PASTE YOUR INSTRUCTION CACHE CODE HERE
    // 추가 시작

    // cache parameters
    localparam OFST_SIZE = $clog2(BLOCK_SIZE);                // block offset size  (4 words -> 2bit)
    localparam SET_SIZE  = $clog2(BLOCK_NUM);                 // set index size     (16 sets -> 4bit, direct-mapped)
    localparam TAG_SIZE  = WORD_SIZE - SET_SIZE - OFST_SIZE;  // tag size           (16 - 4 - 2 = 10bit)
    localparam MDAT_SIZE = 2;                                 // 3) metadata = {valid, dirty} (write-back -> dirty 필요)
    localparam TENT_SIZE = TAG_SIZE + MDAT_SIZE;              // tag entry size = {valid, dirty, tag} = 12bit

    // cache entries
    reg [WORD_SIZE-1:0] data_entries [0:BLOCK_NUM-1][0:BLOCK_SIZE-1];
    reg [TENT_SIZE-1:0] tag_entries  [0:BLOCK_NUM-1];

    // parsed address : addr = [ tag (15:6) | set (5:2) | offset (1:0) ]
    wire [TAG_SIZE -1:0] parsed_tag;
    wire [SET_SIZE -1:0] parsed_set;
    wire [OFST_SIZE-1:0] parsed_offset;

    assign parsed_tag    = cpu_addr_i[WORD_SIZE-1         : SET_SIZE+OFST_SIZE];
    assign parsed_set    = cpu_addr_i[SET_SIZE+OFST_SIZE-1 : OFST_SIZE];
    assign parsed_offset = cpu_addr_i[OFST_SIZE-1          : 0];

    // FSM 상태 (4) 2개 -> 3개로 확장)
    //   S_IDLE : 요청 대기 + tag 비교. hit 이면 같은 사이클에 ack,
    //            miss 이면 dirty 여부에 따라 S_WB (dirty) / S_FILL (clean)
    //   S_WB   : 쫓겨날 dirty 블록(4 words)을 memory에 write-back
    //   S_FILL : memory read 채널로 새 블록(4 words)을 읽어 cache line 채움
    localparam S_IDLE = 2'd0;
    localparam S_WB   = 2'd1;
    localparam S_FILL = 2'd2;

    reg [1:0]           state, state_nxt;
    reg [OFST_SIZE-1:0] cnt;                // WB / FILL 중 몇 번째 워드를 처리하는지 (0 ~ BLOCK_SIZE-1)

    // Tag 비교 : tag entry = {valid, dirty, tag}
    wire [TENT_SIZE-1:0] cur_tent  = tag_entries[parsed_set];
    wire                 cur_valid = cur_tent[TENT_SIZE-1];
    wire                 cur_dirty = cur_tent[TENT_SIZE-2];   // 3) 1이면 쫓겨나기 전에 write-back 필요
    wire [TAG_SIZE-1:0]  cur_tag   = cur_tent[TAG_SIZE-1:0];  //    (write-back 주소 = 이 블록의 원래 tag)
    wire                 hit       = cur_valid && (cur_tag == parsed_tag);
    wire                 cpu_req   = cpu_rd_req_i || cpu_wr_req_i;  // 4) read / write 모두 miss 처리 (write-allocate)

    // CPU IF : hit 이면 같은 사이클에 data + ack (조합)
    assign cpu_rd_ack_o  = (state == S_IDLE) && cpu_rd_req_i && hit;
    assign cpu_wr_ack_o  = (state == S_IDLE) && cpu_wr_req_i && hit;   // 5) write hit도 같은 사이클에 ack
    assign cpu_rd_data_o = data_entries[parsed_set][parsed_offset];

    // Memory IF : 블록 주소 + cnt 번째 워드 (WB / FILL 동안 req 유지)
    // 2) read-only 채널(mem_ro_*) -> read-write 채널(mem_rd_* / mem_wr_*)으로 다시 연결
    //   WB   : 쫓겨날 블록의 원래 tag(cur_tag)로 write
    //   FILL : 새 요청의 tag(parsed_tag)로 read
    assign mem_addr_o    = (state == S_WB) ? {cur_tag, parsed_set, cnt} : {parsed_tag, parsed_set, cnt};
    assign mem_rd_req_o  = (state == S_FILL);
    assign mem_wr_req_o  = (state == S_WB);                            // 5) write 채널 연결
    assign mem_wr_data_o = data_entries[parsed_set][cnt];              // 5) write-back 할 워드

    // Next state logic
    always @(*) begin
        state_nxt = state;
        case (state)
            S_IDLE: if (cpu_req && !hit)                                   // 4) miss -> dirty 면 먼저 write-back
                        state_nxt = (cur_valid && cur_dirty) ? S_WB : S_FILL;
            S_WB:   if (mem_wr_ack_i && (cnt == BLOCK_SIZE-1))             state_nxt = S_FILL;  // 4) write-back 끝
            S_FILL: if (mem_rd_ack_i && (cnt == BLOCK_SIZE-1))             state_nxt = S_IDLE;
            default:                                                       state_nxt = S_IDLE;
        endcase
    end

    // State / cache line update
    integer i;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_IDLE;
            cnt   <= 'd0;
            for (i = 0; i < BLOCK_NUM; i = i + 1)
                tag_entries[i] <= 'd0;                                     // 모든 valid = 0
        end else begin
            state <= state_nxt;
            case (state)
                S_IDLE: if (cpu_wr_req_i && hit) begin                     // 5) write hit
                    data_entries[parsed_set][parsed_offset] <= cpu_wr_data_i;
                    tag_entries[parsed_set] <= {1'b1, 1'b1, cur_tag};      //    D = 1 (memory와 달라짐)
                end
                S_WB: if (mem_wr_ack_i)                                    // 4) 한 워드 write-back 완료
                    cnt <= cnt + 1'b1;                                     //    마지막 워드 후 0으로 wrap -> FILL은 0부터
                S_FILL: if (mem_rd_ack_i) begin
                    data_entries[parsed_set][cnt] <= mem_rd_data_i;        // 받은 워드 저장
                    cnt <= cnt + 1'b1;                                     // 마지막 워드 후 0으로 wrap
                    if (cnt == BLOCK_SIZE-1) begin                         // 블록 완성 -> V=1, tag
                        tag_entries[parsed_set] <= {1'b1, cpu_wr_req_i, parsed_tag};  // D = write miss 이면 1
                        if (cpu_wr_req_i)                                  // 5) write miss: 대기 중인 쓰기를 여기서 반영
                            data_entries[parsed_set][parsed_offset] <= cpu_wr_data_i;  // (ack 전에 쓰기 완료)
                    end
                end
                default: ;
            endcase
        end
    end
    // 추가 끝

endmodule