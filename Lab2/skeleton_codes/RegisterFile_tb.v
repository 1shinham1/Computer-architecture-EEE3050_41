`timescale 1ns / 100ps

module RegisterFileTb ();

parameter  CLOCK_PS  = 10;
parameter  HCLOCK_PS = 5;

localparam WORD_SIZE = 16;
localparam REG_BITS  = 2;
localparam REG_NUM   = REG_BITS ** 2;

reg clk;
reg reset_n;
reg wr_enable;

reg [REG_BITS-1:0] rd_reg1;
reg [REG_BITS-1:0] rd_reg2;
reg [REG_BITS-1:0] wr_reg;

wire [WORD_SIZE-1:0] rd_data1;
wire [WORD_SIZE-1:0] rd_data2;
reg  [WORD_SIZE-1:0] wr_data;

RegisterFile #(
    .WORD_SIZE(WORD_SIZE), .REG_BITS(REG_BITS)
) top (
    .clk(clk), .reset_n(reset_n), .wr_enable(wr_enable),
    .rd_reg1(rd_reg1), .rd_reg2(rd_reg2), .wr_reg(wr_reg),
    .rd_data1(rd_data1), .rd_data2(rd_data2), .wr_data(wr_data)
);

// Clock signal generation
integer timestamp;

initial begin : CLOCK_GENERATOR
    clk = 1'b0;
    timestamp = 0;
    forever
        #HCLOCK_PS clk = ~clk;
end

always @(posedge clk) begin
    timestamp = timestamp + 1;
end

// Test
reg [31:0] i;

reg [WORD_SIZE-1:0] ref_container [0:REG_NUM-1];

initial begin
    $dumpfile("vcd/reg_file.vcd");
    $dumpvars(0, top);
    
    $display("\n:: INITIALIZATION STAGE ::");

    reset_n   = 1'b0;
    wr_enable = 1'b0;

    rd_reg1 = 'd0;
    rd_reg2 = 'd1;
    wr_reg  = 'd0;

    wr_data = 'd0;

    #CLOCK_PS;
    reset_n = 1'b1;

    for (i = 0; i < (2 ** REG_BITS) / 2; i = i + 1) begin
        rd_reg1 = 2 * i;
        rd_reg2 = 2 * i + 1;
        
        #HCLOCK_PS;

        $display("#%3d \treg[%2d] = %d  reg[%2d] = %d  (%s)", 
            timestamp, rd_reg1, rd_data1, rd_reg2, rd_data2, 
            ((rd_data1 == 'd0) && (rd_data2 == 'd0)) ? "passed" : "failed");

        #HCLOCK_PS;
    end

    $display("\n:: WRITE REGISTER FILE ::");

    wr_enable = 1'b1;

    for (i = 0; i < 2 ** REG_BITS; i = i + 1) begin
        wr_reg  = i;
        wr_data = $random;
        ref_container[i] = wr_data;
        
        #HCLOCK_PS;

        $display("#%3d \treg[%2d] = %d", timestamp, wr_reg, wr_data);

        #HCLOCK_PS;
    end

    $display("\n:: READ REGISTER FILE ::");

    wr_enable = 1'b0;

    for (i = 0; i < (2 ** REG_BITS) / 2; i = i + 1) begin
        rd_reg1 = 2 * i;
        rd_reg2 = 2 * i + 1;
        
        #HCLOCK_PS;

        $display("#%3d \treg[%2d] = %d  reg[%2d] = %d  (%s)", 
            timestamp, rd_reg1, rd_data1, rd_reg2, rd_data2, 
            ((rd_data1 == ref_container[2*i]) && (rd_data2 == ref_container[2*i+1])) ? "passed" : "failed");

        #HCLOCK_PS;
    end

    $finish;
end
    
endmodule