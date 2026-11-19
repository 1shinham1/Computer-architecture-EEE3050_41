module Memory #(
    parameter WORD_SIZE   = 16,     // each word is 16 bits by default
    parameter WORD_NUM    = 65536,  // address is 16bit = 65536 words in the memory
    parameter MEM_LATENCY = 8       // 8 cycles fixed latency for each memory access
) ( 
    input clk,
    input reset_n,

    input  wire    [WORD_SIZE-1:0]     rw_addr_i,  // address given to the memory (integrated read and write channel)
    output wire    [WORD_SIZE-1:0]     rd_data_o,  // memory read data
    input  wire                        rd_req_i,   // memory read request 
    output wire                        rd_ack_o,   // memory read acknowledge
    input  wire    [WORD_SIZE-1:0]     wr_data_i,  // memory write data
    input  wire                        wr_req_i,   // memory write request
    output wire                        wr_ack_o,   // memory write acknowledge

    input  wire    [WORD_SIZE-1:0]     ro_addr_i,  // address given to the memory (read-only channel)
    output wire    [WORD_SIZE-1:0]     ro_data_o,  // memory read-only data
    input  wire                        ro_req_i,   // memory read-only request 
    output wire                        ro_ack_o    // memory read-only acknowledge
);

    // local parameters
    localparam CNT_WIDTH = $clog2(MEM_LATENCY);

    // output signals
    reg [WORD_SIZE-1:0] rd_data;
    reg                 rd_ack;
    reg                 wr_ack;
    reg [WORD_SIZE-1:0] ro_data;
    reg                 ro_ack;

    // container
    reg [WORD_SIZE-1:0] memory [0:WORD_NUM-1];

    // control signals
    reg                 wr_enable;
    reg [CNT_WIDTH-1:0] acc_cnt1, acc_cnt1_nxt;
    reg [CNT_WIDTH-1:0] acc_cnt2, acc_cnt2_nxt;

    // iterators
    integer i;

    always @(*) begin
        if (rd_req_i) begin
            if (acc_cnt1 == MEM_LATENCY-1) begin
                rd_data     = memory[rw_addr_i];
                rd_ack      = 1'b1;
                wr_ack      = 1'b0;
                wr_enable   = 1'b0;
                acc_cnt1_nxt = acc_cnt1 + 1;
            end else begin
                rd_data     = 'd0;
                rd_ack      = 1'b0;
                wr_ack      = 1'b0;
                wr_enable   = 1'b0;
                acc_cnt1_nxt = acc_cnt1 + 1;
            end
        end else if (wr_req_i) begin
            if (acc_cnt1 == MEM_LATENCY-1) begin
                rd_data     = 'd0;
                rd_ack      = 1'b0;
                wr_ack      = 1'b1;
                wr_enable   = 1'b1;
                acc_cnt1_nxt = acc_cnt1 + 1;
            end else begin
                rd_data     = 'd0;
                rd_ack      = 1'b0;
                wr_ack      = 1'b0;
                wr_enable   = 1'b0;
                acc_cnt1_nxt = acc_cnt1 + 1;
            end
        end else begin
            rd_data     = 'd0;
            rd_ack      = 1'b0;
            wr_ack      = 1'b0;
            wr_enable   = 1'b0;
            acc_cnt1_nxt = 'd0;
        end
    end

    always @(*) begin
        if (ro_req_i) begin
            if (acc_cnt2 == MEM_LATENCY-1) begin
                ro_data     = memory[ro_addr_i];
                ro_ack      = 1'b1;
                acc_cnt2_nxt = acc_cnt2 + 1;
            end else begin
                ro_data     = 'd0;
                ro_ack      = 1'b0;
                acc_cnt2_nxt = acc_cnt2 + 1;
            end
        end  else begin
            ro_data      = 'd0;
            ro_ack       = 1'b0;
            acc_cnt2_nxt = 'd0;
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            acc_cnt1 <= 'd0;
            acc_cnt2 <= 'd0;
        end else begin
            acc_cnt1 <= acc_cnt1_nxt;
            acc_cnt2 <= acc_cnt2_nxt;
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < WORD_NUM; i = i + 1) begin
                memory[i] <= 'd0;
            end
        end else if (wr_enable) begin
            memory[rw_addr_i] <= wr_data_i;
        end
    end

    assign rd_data_o = rd_data;
    assign rd_ack_o  = rd_ack & rd_req_i;
    assign wr_ack_o  = wr_ack & wr_req_i;
    assign ro_data_o = ro_data;
    assign ro_ack_o  = ro_ack & ro_req_i;
    
endmodule