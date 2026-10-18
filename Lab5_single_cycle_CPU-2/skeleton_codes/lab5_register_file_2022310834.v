module RegisterFile #(
    parameter WORD_SIZE = 16,
    parameter REG_BITS  = 2
) (
    input clk,
    input reset_n,

    input wr_enable,

    input [REG_BITS-1:0] rd_reg1,
    input [REG_BITS-1:0] rd_reg2,
    input [REG_BITS-1:0] wr_reg,

    output [WORD_SIZE-1:0] rd_data1,
    output [WORD_SIZE-1:0] rd_data2,
    input  [WORD_SIZE-1:0] wr_data
);

// COPY AND PASTE YOUR REGISTER FILE CODE HERE!
// 추가 시작 (Lab2 Register File 코드 붙여넣기)
localparam REG_NUM = 1 << REG_BITS;  // 레지스터 개수 = 2^REG_BITS (기본 4개)

// 레지스터 파일
// packed(1 레지스터의 bit 폭)(16bit) /unpacked(레지스터 개수)(4개)
reg [WORD_SIZE-1:0] register_file [0:REG_NUM-1];
integer i;

//BLOCK 1: Asynchronous Read (조합)
assign rd_data1 = register_file[rd_reg1];
assign rd_data2 = register_file[rd_reg2];

//BLOCK 2: Register Modeling - Synchronous Write / Asynchronous Reset
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        for (i = 0; i < REG_NUM; i = i + 1) begin
            register_file[i] <= {WORD_SIZE{1'b0}};
        end
    end else if (wr_enable) begin
        register_file[wr_reg] <= wr_data;
    end
end
// 추가 끝

endmodule