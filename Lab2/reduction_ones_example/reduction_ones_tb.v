`timescale 1ns / 100ps

module FSM_tb();

parameter  CLOCK_PS  = 10;
parameter  HCLOCK_PS = 5;

reg  clk;
reg  reset_n;
reg  d_in;
wire d_out_moore;
wire d_out_mealy;

ReductionOnesMoore top_moore (
	.clk(clk), .reset_n(reset_n), .d_in(d_in), .d_out(d_out_moore)
);

ReductionOnesMealy top_mealy (
	.clk(clk), .reset_n(reset_n), .d_in(d_in), .d_out(d_out_mealy)
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
reg [15:0] in_seq  = 16'b1010_1111_0111_1100;  // input sequence
reg [15:0] ref_res = 16'b0000_1110_0111_1000;  // reference result

reg [15:0] test_res_moore = 16'd0;  // test result (moore)
reg [15:0] test_res_mealy = 16'd0;  // test result (mealy)

integer i;

initial begin
    $display("\n:: INITIALIZATION STAGE ::");

    reset_n = 1'b0;
	d_in    = 1'b0;

    #CLOCK_PS;
    reset_n = 1'b1;

	$display("\n:: TEST ::");

	for (i = 0; i < 16; i = i + 1) begin
		d_in = in_seq[i];

		#CLOCK_PS;
		
		test_res_moore[i] = d_out_moore;
		test_res_mealy[i] = d_out_mealy;
	end
    
	$display("reference result: %b", ref_res);
	$display("moore result:     %b", test_res_moore);
	$display("mealy result:     %b", test_res_mealy);

    $finish;
end
	 
endmodule
 