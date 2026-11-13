module DataMemory #(
    parameter WORD_SIZE = 16,
    parameter MEM_SIZE  = 256
)(
    input   wire                     clk,         
    input   wire                     dmem_read_i,   
    input   wire                     dmem_write_i,  
    input   wire [WORD_SIZE-1:0]     dmem_addr_i,       
    input   wire [WORD_SIZE-1:0]     dmem_wdata_i,  
    output  wire [WORD_SIZE-1:0]     dmem_rdata_o   
);
    
    // Data Memory (Read/Write)
    reg [WORD_SIZE-1:0] data_mem [0:MEM_SIZE-1];
        
    // Memory Initialize
    integer i;
    initial begin
        for (i = 0; i < MEM_SIZE; i = i + 1) begin
            data_mem[i] = {WORD_SIZE{1'b0}};
        end
        // Initialize some data for program4
        data_mem[1] = 16'h0001;
        data_mem[2] = 16'hffff;
    end

    // Read Operation
    reg [WORD_SIZE-1:0] dmem_rdata;
    always @(*) begin
        if (dmem_read_i) begin
            dmem_rdata = data_mem[dmem_addr_i];  
        end else begin
            dmem_rdata = {WORD_SIZE{1'b0}}; // read disabled, return 0
        end
    end

    // Write Operation
    always @(posedge clk) begin
        if (dmem_write_i) begin
            data_mem[dmem_addr_i] = dmem_wdata_i;
        end
    end
    
    assign dmem_rdata_o = dmem_rdata;

endmodule