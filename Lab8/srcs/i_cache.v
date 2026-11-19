module InstrCache_DM #(
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

    // Memory IF
    output  wire    [WORD_SIZE-1:0]     mem_addr_o,     // address given to the memory
    input   wire    [WORD_SIZE-1:0]     mem_ro_data_i,  // memory read data
    output  wire                        mem_ro_req_o,   // memory read request (to slave)
    input   wire                        mem_ro_ack_i    // memory read acknowledge (from slave)
);
    /*******************************************************
     * Project: Instruction Cache
     *******************************************************

     Description
       * This project is to build an instruction cache
       * Instruction cache is essentially a read-only cache that is attatched to the read-only channel of the memory
     
     Note
       * We provided some skeleton code that may be helpful for you to complete this project
       * If you want to make your own design, you may not follow the steps and instructions given below
       * But, you should follow the design specification provided as the lab material as well as the predefined interfaces

     */


    /*******************************************************
     * STEP #1: Define Parameters for Instruction Cache
     *******************************************************

     How can we get into this step?
       * This part is to specify the parameters of intruction cache
       * Note that instruction caches are READ ONLY!!
         In that case, what kind of metadata should we maintain in the tag entry?
       * Note that default configurations are provided as the module parameters
         - WORD_SIZE:  size of each word (default: 16)
         - BLOCK_SIZE: the number of words for each block (default: 4)
         - BLOCK_NUM:  the number of blocks that the cache can have (default: 16)
       * Maybe you want to use $clog2() function in Verilog!
         e.g., a = $clog2(16)  // a = 4
     
     Parameters
       * OFST_SIZE: size of the block offset (note that we are generating the address based on the 2B word addressing scheme)
       * SET_SIZE:  size of the set index parsed from the memory address
       * TAG_SIZE:  size of the tag parsed from the memory address
       * MDAT_SIZE: size of the metadata inside the tag entry of the cache
       * TENT_SIZE: size of the tag entry = size of the metadata + size of the tag

     Cache Configuration
       * There are two predefined arrays in this module
         - data_entries: 2D unpacked array storing data words
         - tag_entries:  1D unpacked array storing tag entries
       * You don't have to specify the size or dimension of the array if you properly set the cache parameters!

     */

    // cache parameters
    localparam OFST_SIZE = $clog2(BLOCK_SIZE);                // block offset size  (4 words -> 2bit)
    localparam SET_SIZE  = $clog2(BLOCK_NUM);                 // set index size     (16 sets -> 4bit, direct-mapped)
    localparam TAG_SIZE  = WORD_SIZE - SET_SIZE - OFST_SIZE;  // tag size           (16 - 4 - 2 = 10bit)
    localparam MDAT_SIZE = 1;                                 // metadata = valid bit (read-only -> dirty 불필요)
    localparam TENT_SIZE = TAG_SIZE + MDAT_SIZE;              // tag entry size = {valid, tag} = 11bit

    // cache entries
    reg [WORD_SIZE-1:0] data_entries [0:BLOCK_NUM-1][0:BLOCK_SIZE-1];
    reg [TENT_SIZE-1:0] tag_entries  [0:BLOCK_NUM-1];


    /*******************************************************
     * STEP #2: Address Parsing
     *******************************************************

     How can we get into this step?
       * This part is to parse the address given from the CPU and create tag / set index / block offset
       * Note that the block offset indicates the word, not Byte (different to the RISC-V or MIPS!)
     
     Wires to be set?
       * parsed_tag:    tag field from the CPU address
       * parsed_set:    set index field from the CPU address
       * parsed_offset: block offset field from the CPU address

     */

    // parsed address
    wire [TAG_SIZE -1:0] parsed_tag;
    wire [SET_SIZE -1:0] parsed_set;
    wire [OFST_SIZE-1:0] parsed_offset;

    // addr = [ tag (15:6) | set (5:2) | offset (1:0) ]
    assign parsed_tag    = cpu_addr_i[WORD_SIZE-1         : SET_SIZE+OFST_SIZE];
    assign parsed_set    = cpu_addr_i[SET_SIZE+OFST_SIZE-1 : OFST_SIZE];
    assign parsed_offset = cpu_addr_i[OFST_SIZE-1          : 0];


    /*******************************************************
     * STEP #3: Finite State Machine and Control Logics
     *******************************************************

     How can we get into this step?
       1) Figure out which state do we need to implement instruction cache
       2) Draw the block diagram of the instruction cache
       3) Implement the FSM based on the states determined at 1)
       4) Complete your design by creating control logics required for the instruction cache

     */

    // ADD YOUR CODE HERE
    // 추가 시작
    // FSM 상태
    //   S_IDLE : 요청 대기 + tag 비교. hit 이면 같은 사이클에 ack, miss 이면 S_FILL
    //   S_FILL : memory read-only 채널로 블록(4 words)을 한 워드씩 읽어 cache line 채움
    localparam S_IDLE = 1'b0;
    localparam S_FILL = 1'b1;

    reg                 state, state_nxt;
    reg [OFST_SIZE-1:0] fill_cnt;           // FILL 중 몇 번째 워드를 읽는지 (0 ~ BLOCK_SIZE-1)

    // Tag 비교 : tag entry = {valid, tag}
    wire [TENT_SIZE-1:0] cur_tent  = tag_entries[parsed_set];
    wire                 cur_valid = cur_tent[TENT_SIZE-1]; // [10] = valid
    wire [TAG_SIZE-1:0]  cur_tag   = cur_tent[TAG_SIZE-1:0]; // [9:0] = tag
    wire                 hit       = cur_valid && (cur_tag == parsed_tag);

    // CPU IF : hit 이면 같은 사이클에 data + ack (조합)
    assign cpu_rd_ack_o  = (state == S_IDLE) && cpu_rd_req_i && hit;
    assign cpu_rd_data_o = data_entries[parsed_set][parsed_offset];

    // Memory IF : 블록 시작 주소 + fill_cnt 번째 워드 요청 (FILL 동안 req 유지)
    assign mem_addr_o    = {parsed_tag, parsed_set, fill_cnt};
    assign mem_ro_req_o  = (state == S_FILL);

    // Next state logic
    always @(*) begin
        state_nxt = state;
        case (state)
            S_IDLE: if (cpu_rd_req_i && !hit)                              state_nxt = S_FILL;
            S_FILL: if (mem_ro_ack_i && (fill_cnt == BLOCK_SIZE-1))        state_nxt = S_IDLE;
            default:                                                       state_nxt = S_IDLE;
        endcase
    end

    // State / cache line update
    integer i;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state    <= S_IDLE;
            fill_cnt <= 'd0;
            for (i = 0; i < BLOCK_NUM; i = i + 1)
                tag_entries[i] <= 'd0;                                     // 모든 valid = 0
        end else begin
            state <= state_nxt;
            if ((state == S_FILL) && mem_ro_ack_i) begin
                data_entries[parsed_set][fill_cnt] <= mem_ro_data_i;       // 받은 워드 저장
                fill_cnt <= fill_cnt + 1'b1;                               // 마지막 워드 후 0으로 wrap
                if (fill_cnt == BLOCK_SIZE-1)
                    tag_entries[parsed_set] <= {1'b1, parsed_tag};         // 블록 완성 -> valid + tag 기록
            end
        end
    end
    // 추가 끝

endmodule