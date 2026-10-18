module InstructionMemory #(
    parameter WORD_SIZE = 16,
    parameter MEM_SIZE  = 256
)(
    input   wire [WORD_SIZE-1:0]    imem_addr_i,
    output  wire [WORD_SIZE-1:0]    imem_rdata_o    
);

    // Instruction Memory
    reg [WORD_SIZE-1:0] inst_mem [0:MEM_SIZE-1];
    
    // Memory Intialize
    integer i;
    initial begin
        for (i = 0; i < MEM_SIZE; i = i + 1) begin
            inst_mem[i] = {WORD_SIZE{1'b0}};
        end
    end

    // Read Opeartion
    reg [WORD_SIZE-1:0] imem_rdata;
    always @(*) begin
        imem_rdata = inst_mem[imem_addr_i]; // 16-bit aligned memory
    end
    
    assign imem_rdata_o = imem_rdata;

endmodule
