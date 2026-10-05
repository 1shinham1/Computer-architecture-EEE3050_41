`timescale 1ns / 100ps

module CPU_W16_R4_tb ();

parameter  CLOCK_PS  = 10;
parameter  HCLOCK_PS = 5;

localparam WORD_SIZE = 16;
localparam REG_BITS  = 2;

reg clk;
reg reset_n;

reg  [15:0] rd_inst;
wire [15:0] inst_addr;

// reg  [15:0] rd_data;  
// wire [15:0] wr_data;  
// wire        mem_read; 
// wire        mem_write;
// wire [15:0] data_addr;

reg         ir_ack;
wire        ir_req;
wire [15:0] ir_msg;

CPU_W16_R4 top (
    .clk(clk), .reset_n(reset_n), 
    .rd_inst(rd_inst), .inst_addr(inst_addr),
    // .rd_data(rd_data), .wr_data(wr_data), .mem_read(mem_read), .mem_write(mem_write), .data_addr(data_addr),
    .ir_ack(ir_ack), .ir_req(ir_req), .ir_msg(ir_msg)
);

integer i;

// Clock Signal Generation
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

// Instruction Memory
reg [15:0] inst_mem [0:127];

initial begin
    for (i = 0; i < 128; i = i + 1) begin
        inst_mem[i] = 16'd0;
    end
end

always @(*) begin
    rd_inst = inst_mem[inst_addr];
end

// // Data Memory
// reg [15:0] data_mem [0:127];

// initial begin
//     for (i = 0; i < 128; i = i + 1) begin
//         data_mem[i] = 16'd0;
//     end
// end

// always @(*) begin
//     rd_data = mem_read ? data_mem[data_addr] : 16'd0;
// end

// always @(posedge clk) begin
//     if (mem_write)
//         data_mem[data_addr] = wr_data;
// end

// Interrupt Handler
reg [31:0] ir_passed, ir_cursor;
reg [15:0] ir_msg_reference [0:127];

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        ir_ack <= 1'b0;
        ir_passed <= 'd0;
        ir_cursor <= 'd0;
    end else if (ir_req && (!ir_ack)) begin
        ir_ack <= 1'b1;
        ir_cursor <= ir_cursor + 1;

        if (ir_msg == ir_msg_reference[ir_cursor]) begin
            $display("test #%2d succeed with message: %1d", ir_cursor, ir_msg);
            ir_passed <= ir_passed + 1;
        end else begin
            $display("test #%2d failed since output message (%3d) is not the same with the reference (%3d)", ir_cursor, ir_msg, ir_msg_reference[ir_cursor]);
        end
    end else begin
        ir_ack <= 1'b0;
    end
end

integer iter_cnt;

initial begin
    $dumpfile("vcd/cpu_tb.vcd");
    $dumpvars(0, top);

    Program1;
    Program2;

    $finish();
end

task ExecuteProgram;
    input [31:0] cursor_limit;
begin
    reset_n = 'd0;
    #CLOCK_PS;
    reset_n = 'd1;

    iter_cnt = 0;

    while ((ir_cursor <= cursor_limit) && (iter_cnt < 128)) begin
        #CLOCK_PS;
        iter_cnt = iter_cnt + 1;
    end

    $display("%1d succeed out of %1d tests in total", ir_passed, ir_cursor);
end
endtask

task Program2;
begin
    $display("\n:: EXECUTING PROGRAM 2 ::");

    inst_mem[0]  = 16'h6005;  // LHI $0, 5
	inst_mem[1]  = 16'h610d;  // LHI $1, 13
 	inst_mem[2]  = 16'h6215;  // LHI $2, 21
	inst_mem[3]  = 16'h6340;  // LHI $3, 64
    inst_mem[4]  = 16'hf01c;  // WWD $0
	inst_mem[5]  = 16'hf41c;  // WWD $1
	inst_mem[6]  = 16'hf81c;  // WWD $2
	inst_mem[7]  = 16'hfc1c;  // WWD $3
    inst_mem[8]  = 16'hf000;  // ADD $0, $0, $0
    inst_mem[9]  = 16'hfa40;  // ADD $1, $2, $2
    inst_mem[10] = 16'hf01c;  // WWD $0
	inst_mem[11] = 16'hf41c;  // WWD $1
    inst_mem[12] = 16'h60ff;  // LHI $0, 255       // (255 or 0xffff stands for -1)
    inst_mem[13] = 16'hf440;  // ADD $1, $1, $0
    inst_mem[14] = 16'hf880;  // ADD $2, $2, $0
    inst_mem[15] = 16'hf41c;  // WWD $1
	inst_mem[16] = 16'hf81c;  // WWD $2

    ir_msg_reference[0] = 16'd1280;   // $0 = 5  * 256 = 1280
    ir_msg_reference[1] = 16'd3328;   // $1 = 13 * 256 = 3328
    ir_msg_reference[2] = 16'd5376;   // $2 = 21 * 256 = 5376
    ir_msg_reference[3] = 16'd16384;  // $3 = 64 * 256 = 16384
    ir_msg_reference[4] = 16'd2560;   // $0 = $0 + $0  = 2560
    ir_msg_reference[5] = 16'd10752;  // $1 = $2 + $2  = 10752
                                      // $0 = -1 * 256 = -256  
    ir_msg_reference[6] = 16'd10496;  // $1 = $1 + $0  = 10752 + (-256) = 10496
    ir_msg_reference[7] = 16'd5120;   // $2 = $1 + $0  = 5376  + (-256) = 5120

    ExecuteProgram(7);  // execute until interrupt cursor ends up to 7
end
endtask

task Program1;
begin
    $display("\n:: EXECUTING PROGRAM 1 ::");

    inst_mem[0]  = 16'h6000;	//	LHI $0, 0
	inst_mem[1]  = 16'h6101;	//	LHI $1, 1
 	inst_mem[2]  = 16'h6202;	//	LHI $2, 2
	inst_mem[3]  = 16'h6303;	//	LHI $3, 3
	inst_mem[4]  = 16'hf01c;	//	WWD $0
	inst_mem[5]  = 16'hf41c;	//	WWD $1
	inst_mem[6]  = 16'hf81c;	//	WWD $2
	inst_mem[7]  = 16'hfc1c;	//	WWD $3
	inst_mem[8]  = 16'h4204;	//	ADI $2, $0, 4
	inst_mem[9]  = 16'h47fc;	//	ADI $3, $1, -4
	inst_mem[10] = 16'hf81c;	//	WWD $2
	inst_mem[11] = 16'hfc1c;	//	WWD $3
	inst_mem[12] = 16'hf6c0;	//	ADD $3, $1, $2
	inst_mem[13] = 16'hf180;	//	ADD $2, $0, $1
	inst_mem[14] = 16'hf81c;	//	WWD $2
	inst_mem[15] = 16'hfc1c;	//	WWD $3
	inst_mem[16] = 16'h9015;	//	JMP 21
	inst_mem[17] = 16'hf01c;	//	WWD $0
	inst_mem[18] = 16'hf180;	//	ADD $2, $0, $1
	inst_mem[19] = 16'hf180;	//	ADD $2, $0, $1
	inst_mem[20] = 16'hf180;	//	ADD $2, $0, $1
	inst_mem[21] = 16'h6000;	//	LHI $0, 0
	inst_mem[22] = 16'h4000;	//	ADI $0, $0, 0
	inst_mem[23] = 16'hfd80;	//	ADD $2, $3, $1
	inst_mem[24] = 16'hf01c;	//	WWD $0
	inst_mem[25] = 16'hf41c;	//	WWD $1
	inst_mem[26] = 16'hf81c;	//	WWD $2
	inst_mem[27] = 16'hfc1c;	//	WWD $3

    ir_msg_reference[0]  = 16'd0;
    ir_msg_reference[1]  = 16'd256;
    ir_msg_reference[2]  = 16'd512;
    ir_msg_reference[3]  = 16'd768;
    ir_msg_reference[4]  = 16'd4;
    ir_msg_reference[5]  = 16'd252;
    ir_msg_reference[6]  = 16'd256;
    ir_msg_reference[7]  = 16'd260;
    ir_msg_reference[8]  = 16'd0;
    ir_msg_reference[9]  = 16'd256;
    ir_msg_reference[10] = 16'd516;
    ir_msg_reference[11] = 16'd260;

    ExecuteProgram(11);  // execute until interrupt cursor ends up to 11
end
endtask
    
endmodule