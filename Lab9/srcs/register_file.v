module RegisterFile #(
    parameter WORD_SIZE = 16,
    parameter REG_BITS  = 2
)
(
    input  wire clk,
    input  wire reset_n,
    input  wire wr_enable,

    input  wire [REG_BITS-1:0] rd_reg1,
    input  wire [REG_BITS-1:0] rd_reg2,
    input  wire [REG_BITS-1:0] rd_reg3,     // Lab9 추가: 3번째 읽기 포트 (CPU extension - DMA length용 $3)
    input  wire [REG_BITS-1:0] wr_reg,

    output wire [WORD_SIZE-1:0] rd_data1,
    output wire [WORD_SIZE-1:0] rd_data2,
    output wire [WORD_SIZE-1:0] rd_data3,   // Lab9 추가
    input  wire [WORD_SIZE-1:0] wr_data
);

    // COPY AND PASTE YOUR CODE HERE!
    // 추가 시작 (Lab7 Register File 코드 붙여넣기 - write 는 negedge)
    localparam REG_NUM = 1 << REG_BITS;  // 레지스터 개수 = 2^REG_BITS (기본 4개)

    // 레지스터 파일
    // packed(1 레지스터의 bit 폭)(16bit) /unpacked(레지스터 개수)(4개)
    reg [WORD_SIZE-1:0] register_file [0:REG_NUM-1];
    integer i;

    //BLOCK 1: Asynchronous Read (조합)
    assign rd_data1 = register_file[rd_reg1];
    assign rd_data2 = register_file[rd_reg2];
    assign rd_data3 = register_file[rd_reg3];   // Lab9 추가: ID 단계의 포트 1, 2와 독립적으로 읽음

    //BLOCK 2: Register Modeling - Synchronous Write (negedge) / Asynchronous Reset
    always @(negedge clk or negedge reset_n) begin
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
