module EXT_DEV #(
    parameter WORD_SIZE     = 16,       // each word is 16 bits by default
    parameter WORD_NUM_LG2  = 6         // address is 6-bit, 64 words in the device
)
(
    input   wire clk,
    input   wire reset_n,
    
    // DMA IF
    input   wire [WORD_NUM_LG2-1:0]     dev_rd_addr_i,  // read address (from dma)
    output  wire [WORD_SIZE-1:0]        dev_rd_data_o,  // read data (to dma)
    input   wire                        dev_ir_ack_i,   // interrupt acknowledge (from dma)
    output  wire                        dev_ir_req_o    // interrupt request (to dma)
);

    // Local parameters
    integer i;
    localparam  WORD_NUM = 2**WORD_NUM_LG2;
    localparam  S_IDLE      = 1'b0,
                S_PENDING   = 1'b1;
    
    // State signals
    reg                     dev_state, dev_state_nxt;
    reg [WORD_NUM_LG2-1:0]  dev_cnt, dev_cnt_nxt; 
    reg [WORD_SIZE-1:0]     dev_mem     [0:WORD_NUM-1];
    reg [WORD_SIZE-1:0]     dev_mem_nxt [0:WORD_NUM-1];
    
    // Control signals
    reg                     dev_ir_req;
    reg [WORD_SIZE-1:0]     dev_rd_data;
    
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            dev_state   <= S_IDLE;
            dev_cnt     <= 'd0;
            for (i=0; i<WORD_NUM; i=i+1) begin
                dev_mem[i]  <= 'd0;
            end
        end
        else begin
            dev_state   <= dev_state_nxt;
            dev_cnt     <= dev_cnt_nxt;
            for (i=0; i<WORD_NUM; i=i+1) begin
                dev_mem[i]  <= dev_mem_nxt[i];
            end
        end
    end
    
    always @(*) begin
        // State signals
        dev_state_nxt   = dev_state;
        dev_cnt_nxt     = dev_cnt;
        for (i=0; i<WORD_NUM; i=i+1) begin
            dev_mem_nxt[i]  = dev_mem[i];
        end
        // Control signals
        dev_ir_req      = 1'b0;
        dev_rd_data     = 'd0;
        
        case (dev_state)
            S_IDLE: begin
                // Randomly fill memory every IDLE cycles
                dev_cnt_nxt             = dev_cnt + 'd1;
                dev_mem_nxt[dev_cnt]    = $random;
                
                // Fully filled, go to pending state
                if (dev_cnt==WORD_NUM-'d1) begin
                    dev_state_nxt = S_PENDING;
                end
            end
            S_PENDING: begin
                // Pending state, occur interrupt, read data 
                dev_ir_req  = 1'b1;
                dev_rd_data = dev_mem[dev_rd_addr_i];
                // Acknowledge comes, go back to IDLE state, reset mem
                if (dev_ir_ack_i) begin
                    dev_state_nxt   = S_IDLE;
                    dev_cnt_nxt     = 'd0;
                    for (i=0; i<WORD_NUM; i=i+1) begin
                        dev_mem_nxt[i]  = 'd0;
                    end
                end
            end
            default: begin
                // do nothing
                $display("Error: Invalid state at EXT_DEV: %d", dev_state);
            end
        endcase    
    end

    // Output assignments
    assign dev_ir_req_o     = dev_ir_req;
    assign dev_rd_data_o    = dev_rd_data;

endmodule