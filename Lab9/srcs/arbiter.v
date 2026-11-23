module ARBITER #(
    parameter WORD_SIZE = 16,
    parameter MEM_LATENCY = 8
)
(
    input   wire clk,
    input   wire reset_n,
    
    // Cache IF
    input   wire    [WORD_SIZE-1:0]     dc_mem_addr_i,      // address given to the memory (from cache)
    output  wire    [WORD_SIZE-1:0]     dc_mem_rd_data_o,   // memory read data
    input   wire                        dc_mem_rd_req_i,    // memory read request
    output  wire                        dc_mem_rd_ack_o,    // memory read acknowledge
    input   wire    [WORD_SIZE-1:0]     dc_mem_wr_data_i,   // memory write data (from cache)
    input   wire                        dc_mem_wr_req_i,    // memory write request (from cache)
    output  wire                        dc_mem_wr_ack_o,    // memory write acknowledge (to cache)
    
    // DMA IF
    input   wire    [WORD_SIZE-1:0]     dma_mem_rw_addr_i,  // write address (from dma)
    input   wire    [WORD_SIZE-1:0]     dma_mem_wr_data_i,  // write data (from dma)
    input   wire                        dma_mem_wr_req_i,   // write request (from dma)
    output  wire                        dma_mem_wr_ack_o,   // write acknowledge (to dma)
    
    input   wire                        bus_req_i,          // bus grant request (from dma)
    output  wire                        bus_ack_o,          // bus acknowledge (to dma)
    
    // Memory IF
    output  wire    [WORD_SIZE-1:0]     mem_rw_addr_o,      // write address (to memory)
    input   wire    [WORD_SIZE-1:0]     mem_rd_data_i,      // memory read data    
    output  wire                        mem_rd_req_o,       // memory read request
    input   wire                        mem_rd_ack_i,       // memory read acknowledge
    output  wire    [WORD_SIZE-1:0]     mem_wr_data_o,      // write data (to memory)
    output  wire                        mem_wr_req_o,       // write request (to memory)
    input   wire                        mem_wr_ack_i        // write acknowledge (from memory)  
);

    /*******************************************************
     * Project: Arbiter
     *******************************************************
    
    Description
        * This project is to build a Arbiter controller
        * Arbiter, in this lab, is a unit that controls the bus access between the cache and the DMA 
        * Arbiter get the bus request from the DMA and grant the bus to the DMA. 
        * Otherwise, it grants the bus to the cache.
        
    Note
        * We provided some skeleton code that may be helpful for you to complete this project
        * If you want to make your own design, you may not follow the steps and instructions given below
    */
    
    
    /*******************************************************
     * STEP #1: Define Parameters for DMA
     *******************************************************
    
    How can we get into this step?
        * This part is to specify the parameters of Arbiter
        * You may think about the output signals of the Arbiter
        * Then, think about the operation of arbiter
    */

    // 추가 시작
    // 버스 소유자 상태
    //   S_CACHE : D-cache가 RW 채널 사용 (기본)
    //   S_DMA   : DMA가 RW 채널 사용 (DMA 우선, D-cache 요청은 막아서 대기시킴)
    localparam S_CACHE = 1'b0;
    localparam S_DMA   = 1'b1;

    reg state, state_nxt;
    // 추가 끝


    /*******************************************************
     * STEP #2: Arbiter Controller
     *******************************************************
    
    How can we get into this step?
        * This part is implementing the arbiter
        * It has no exact rule to implement the arbiter, but it is easy to use the state machine 
        * You can easily image that this arbiter just need several muxes to control the bus access
        * But, you need to consider the previous request before granting the bus to the DMA
    */

    // 추가 시작
    // 이전 요청 고려 : D-cache 요청이 memory에서 처리 중(latency 카운트 중)일 때 버스를 뺏으면
    //   memory의 acc_cnt가 이어서 세므로 DMA가 8 cycle보다 일찍 ack를 받는 문제가 생김
    //   -> D-cache 요청이 없거나, 이번 cycle에 한 워드가 끝난(ack) 워드 경계에서만 DMA에게 넘김
    //   (ack cycle에 acc_cnt가 7 -> 0으로 wrap 하므로 DMA 요청은 정확히 MEM_LATENCY cycle 걸림)
    //   D-cache는 ack가 올 때까지 req를 유지하고 기다리므로 막아도 수정할 필요 없음
    wire dc_busy = dc_mem_rd_req_i | dc_mem_wr_req_i;   // D-cache 요청 진행 중 (읽거나 쓰거나)
    wire dc_done = mem_rd_ack_i    | mem_wr_ack_i;      // S_CACHE 에서의 ack = D-cache 한 워드 완료

    // Next state logic
    always @(*) begin
        state_nxt = state;
        case (state)
            S_CACHE: if (bus_req_i && (!dc_busy || dc_done)) state_nxt = S_DMA;    // 워드 경계에서 grant
            S_DMA:   if (!bus_req_i)                         state_nxt = S_CACHE;  // DMA가 버스 반납
            default:                                         state_nxt = S_CACHE;
        endcase
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) state <= S_CACHE;
        else          state <= state_nxt;
    end

    // Bus MUX : 등록된 state로만 선택 (bus_ack_o도 registered -> DMA가 조합으로 써도 loop 없음)
    wire dma_own = (state == S_DMA);

    // Memory IF
    assign mem_rw_addr_o    = dma_own ? dma_mem_rw_addr_i : dc_mem_addr_i;
    assign mem_wr_data_o    = dma_own ? dma_mem_wr_data_i : dc_mem_wr_data_i;
    assign mem_wr_req_o     = dma_own ? dma_mem_wr_req_i  : dc_mem_wr_req_i;
    assign mem_rd_req_o     = dma_own ? 1'b0              : dc_mem_rd_req_i;   // DMA는 write만 사용

    // Cache IF : DMA가 버스를 가진 동안 ack = 0 -> D-cache는 req 유지한 채 대기
    assign dc_mem_rd_data_o = mem_rd_data_i;
    assign dc_mem_rd_ack_o  = dma_own ? 1'b0 : mem_rd_ack_i;
    assign dc_mem_wr_ack_o  = dma_own ? 1'b0 : mem_wr_ack_i;

    // DMA IF
    assign dma_mem_wr_ack_o = dma_own ? mem_wr_ack_i : 1'b0;
    assign bus_ack_o        = dma_own;
    // 추가 끝

endmodule