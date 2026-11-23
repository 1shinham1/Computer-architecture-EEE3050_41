module DMA #(
    parameter WORD_SIZE     = 16,
    parameter DEV_NUM_LG2   = 6,
    parameter DMA_NUM_LG2   = 6,
    parameter DEFAULT_ADDR  = 512,
    parameter CPU_EXT       = 0         // Lab9 추가: 0 = DMA-only (device가 직접 호출, dma_tb) / 1 = CPU extension (CPU가 설정, cpu_tb)
)
(
    input   wire clk,
    input   wire reset_n,
    
    // DEV IF
    output  wire [DEV_NUM_LG2-1:0]  dev_rd_addr_o,  // read address (to dev)
    input   wire [WORD_SIZE-1:0]    dev_rd_data_i,  // read data (from dev)
    
    output  wire                    dev_ir_ack_o,   // interrupt acknowledge (to dev)     
    input   wire                    dev_ir_req_i,   // interrupt request (from dev)
    
    // Memory IF
    output  wire [WORD_SIZE-1:0]    mem_rw_addr_o,  // write address (to memory)
    output  wire [WORD_SIZE-1:0]    mem_wr_data_o,  // write data (to memory)
    output  wire                    mem_wr_req_o,   // write request (to memory)
    input   wire                    mem_wr_ack_i,   // write acknowledge (from memory)
    
    // Arbiter IF
    output  wire                    bus_req_o,      // bus grant request (to arbiter)
    input   wire                    bus_ack_i,      // bus acknowledge (from arbiter)
    
    // CPU IF (Lab9 추가: CPU extension, CPU_EXT = 1 일 때만 사용)
    input   wire                    dma_ir_req_i,   // DMA wake up request (from CPU)
    input   wire [WORD_SIZE-1:0]    dma_len_i,      // number of words to migrate (from CPU)
    input   wire [WORD_SIZE-1:0]    dma_addr_i,     // memory start address (from CPU)
    output  wire                    dma_ir_ack_o    // DMA finished (to CPU)
);

    /*******************************************************
     * Project: DMA
     *******************************************************
    
    Description
        * This project is to build a DMA controller
        * DMA controller is essentially a state machine that grants the bus to the arbiter, 
          reads data from the device and writes it to the memory, and then sends an interrupt acknowledge to the device

    Note
        * We provided some skeleton code that may be helpful for you to complete this project
        * If you want to make your own design, you may not follow the steps and instructions given below
    */
    
    
    
    /*******************************************************
     * STEP #1: Define Parameters for DMA
     *******************************************************
    
    How can we get into this step?
        * This part is to specify the parameters of DMA controller
        * You may think about the output signals of the DMA controller
        * Then, think about the operation of DMA, refer part 3
    */

    // 추가 시작
    localparam DMA_NUM = 2**DMA_NUM_LG2;    // 버퍼 크기 = 기본 전송 길이 (TB: 2^4 = 16 words)
    localparam CNT_W   = DMA_NUM_LG2 + 1;   // 0 ~ DMA_NUM 까지 셀 수 있는 카운터 폭

    // DMA 상태
    //   S_IDLE     : device 인터럽트 대기
    //   S_TRANSFER : 버스 요청 + device read(버퍼 저장) + memory write 를 겹쳐서 진행
    //   S_DONE     : device에 ir_ack (1 cycle), 버스 반납
    localparam S_IDLE     = 2'd0;
    localparam S_TRANSFER = 2'd1;
    localparam S_DONE     = 2'd2;
    // 추가 끝


    /*******************************************************
     * STEP #2: DMA Container (Register file or other storage)
     *******************************************************
    
    How can we get into this step?
      * This part is implementing the container of the DMA controller
      * In this lab, we just assume that external device is a simple register with no latency for read operation
      * This stored data will be used to write data to the memory
    
    Just fill free. You might refer your register file implementation
    */

    // 추가 시작
    reg [WORD_SIZE-1:0] dma_buf [0:DMA_NUM-1];     // device에서 읽은 워드 저장 (16 x 16bit)

    // DMA 설정 레지스터 (인터럽트를 받으면 저장)
    reg [CNT_W-1:0]     len_r;                      // 전송 길이 (기본 DMA_NUM = 16 words)
    reg [WORD_SIZE-1:0] addr_r;                     // 시작 주소 (기본 DEFAULT_ADDR = 'd512)
    // 추가 끝






    /*******************************************************
     * STEP #3: DMA Controller
     *******************************************************
    
    How can we get into this step?
      * This part is to specify the parameters of DMA controller
      * You may need to draw some state diagrams to understand the operation of the DMA controller
      * There's no exact answer for the state machine, it's up to you to design.
      * This may decide the performance of the DMA controller, there's many parts to optimize! (Removing bubble!)
    
    Example flow: IDLE -> GRANT -> READ -> WRITE -> DONE -> IDLE
      * IDLE: wait for the device interrupt
      * GRANT: grant the bus to the device
      * READ: read data from the device
      * WRITE: write data to the memory
      * DONE: send interrupt acknowledge to the device
    
    Tips 
      * Use counter for the state transition, you can use counter value to counting the number of words to write
      * And also the address you are writing to the memory
      * In this lab, we just use default start address for write operation, one by one
      * write mem['d512], write mem['d513], ...
    */

    // 추가 시작
    // Bubble 제거
    //   1) TRANSFER 진입과 동시에 bus_req -> arbitration 대기를 device read와 겹침
    //   2) device read(1 cycle/word)가 write(8 cycle/word)보다 항상 앞서므로
    //      첫 워드를 읽은 다음 cycle부터 write 시작 (wr_cnt < rd_cnt 이면 쓸 데이터 있음)
    //   3) write 사이에 req를 내리지 않음 -> 워드마다 정확히 MEM_LATENCY cycle, 빈 cycle 없음
    //   4) 마지막 write ack 다음 cycle에 바로 버스 반납 + device ack
    reg [1:0]       state, state_nxt;
    reg [CNT_W-1:0] rd_cnt;                         // device에서 읽은 워드 수
    reg [CNT_W-1:0] wr_cnt;                         // memory에 쓴 워드 수

    wire rd_en    = (state == S_TRANSFER) && (rd_cnt < len_r);                     // 아직 읽을 워드 남음
    wire wr_valid = (state == S_TRANSFER) && bus_ack_i && (wr_cnt < rd_cnt);       // 버스 있음 + 쓸 데이터 있음
    wire wr_last  = wr_valid && mem_wr_ack_i && (wr_cnt == len_r - 1'b1);          // 마지막 워드 write 완료

    // Lab9 추가 (CPU extension): 누가 DMA를 깨우고, 설정값을 어디서 받을지 CPU_EXT로 선택
    //   CPU_EXT = 0 : device가 직접 호출, 길이/주소는 기본값 (DMA_NUM, DEFAULT_ADDR)
    //   CPU_EXT = 1 : CPU가 호출, 길이/주소는 CPU가 준 값 (길이는 버퍼 크기 DMA_NUM 이하로 제한)
    wire                 start_req = CPU_EXT ? dma_ir_req_i : dev_ir_req_i;
    wire [CNT_W-1:0]     cfg_len   = (CPU_EXT == 0)        ? DMA_NUM :
                                     (dma_len_i > DMA_NUM) ? DMA_NUM : dma_len_i[CNT_W-1:0];
    wire [WORD_SIZE-1:0] cfg_addr  = CPU_EXT ? dma_addr_i : DEFAULT_ADDR;

    // Next state logic
    always @(*) begin
        state_nxt = state;
        case (state)
            S_IDLE:     if (start_req)    state_nxt = S_TRANSFER;          // Lab9 수정: dev_ir_req_i -> start_req
            S_TRANSFER: if (wr_last)      state_nxt = S_DONE;
            S_DONE:                       state_nxt = S_IDLE;
            default:                      state_nxt = S_IDLE;
        endcase
    end

    // State / counter / buffer update
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state  <= S_IDLE;
            rd_cnt <= 'd0;
            wr_cnt <= 'd0;
            len_r  <= DMA_NUM;
            addr_r <= DEFAULT_ADDR;
        end else begin
            state <= state_nxt;
            case (state)
                S_IDLE: begin
                    rd_cnt <= 'd0;
                    wr_cnt <= 'd0;
                    if (start_req) begin                                    // 인터럽트 -> DMA 설정 저장 (Lab9 수정)
                        len_r  <= cfg_len;                                  //   길이: 기본 16 words / CPU가 준 값
                        addr_r <= cfg_addr;                                 //   주소: 기본 'd512 / CPU가 준 값
                    end
                end
                S_TRANSFER: begin
                    if (rd_en) begin                                        // device -> buffer
                        dma_buf[rd_cnt[DMA_NUM_LG2-1:0]] <= dev_rd_data_i;
                        rd_cnt <= rd_cnt + 1'b1;
                    end
                    if (wr_valid && mem_wr_ack_i)                           // buffer -> memory 한 워드 완료
                        wr_cnt <= wr_cnt + 1'b1;
                end
                default: ;
            endcase
        end
    end

    // DEV IF
    assign dev_rd_addr_o = rd_cnt[DMA_NUM_LG2-1:0];
    assign dev_ir_ack_o  = (CPU_EXT == 0) && (state == S_DONE);             // 1 cycle pulse (DMA-only: device에 ack)

    // Memory IF (arbiter를 거쳐 memory RW 채널로)
    assign mem_rw_addr_o = addr_r + wr_cnt;                                 // 512, 513, ...
    assign mem_wr_data_o = dma_buf[wr_cnt[DMA_NUM_LG2-1:0]];
    assign mem_wr_req_o  = wr_valid;

    // Arbiter IF
    assign bus_req_o     = (state == S_TRANSFER);

    // CPU IF (Lab9 추가)
    assign dma_ir_ack_o  = (CPU_EXT != 0) && (state == S_DONE);             // 1 cycle pulse (CPU extension: CPU에 ack)
    // 추가 끝









endmodule