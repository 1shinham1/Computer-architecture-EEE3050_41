`timescale 1ns / 100ps

module SequenceDetector_tb();

parameter  CLOCK_PS  = 10;
parameter  HCLOCK_PS = 5;

reg  clk;
reg  reset_n;
reg  d_in;
wire d_out;

SequenceDetector top (
	.clk(clk), .reset_n(reset_n), .d_in(d_in), .d_out(d_out)
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
reg [15:0] in_seq   = 16'b0010_0101_0110_1010;  // input sequence
reg [15:0] ref_res  = 16'b0000_0101_0010_1000;  // reference result
reg [15:0] test_res = 16'd0;                    // test result

integer i;

initial begin
    $dumpfile("vcd/fsm.vcd");
    $dumpvars(0, top);
    
    $display("\n:: INITIALIZATION STAGE ::");

    reset_n = 1'b0;
	d_in    = 1'b0;

    #CLOCK_PS;
    reset_n = 1'b1;

	$display("#%3d \td_out = %b  (%s)", timestamp, d_out, (d_out == 1'b0) ? "passed" : "failed");

	$display("\n:: TEST ::");

	for (i = 0; i < 16; i = i + 1) begin
		d_in = in_seq[i];

		#CLOCK_PS;
		
		test_res[i] = d_out;
	end
    
	$display("#%3d \ttest %s", timestamp, (test_res == ref_res) ? "passed" : "failed");
	$display("reference result: %b", ref_res);
	$display("test result:      %b", test_res);

    $finish;
end
	 
endmodule
 