module ReductionOnesMealy (
    input      clk,        // global positive edge triggered clock
    input      reset_n,    // asynchronous negative triggered reset
    input      d_in,       // data input
    output reg d_out       // data output
);

parameter ZERO = 0,   // STATE: ZERO -> zero is detected
          ONES = 1;   // STATE: ONES -> one is detected

reg state;
reg state_nxt;

reg d_out_nxt;

/*
 * BLOCK: State Transition and Data Output
 *   - This block determines the transition of the state and the output data
 *   - The next state is determined by the current state and the input data
 *   - Since this module is a Mealy machine, the output is determined by both the current state and the input
 */
always @(d_in or state) begin
    case (state)
        ZERO: begin
            d_out_nxt = 0;
            if (d_in == 1) begin
                state_nxt = ONES;
            end else begin
                state_nxt = ZERO;
            end 
        end
        ONES: begin
            if (d_in == 1) begin
                d_out_nxt = 1;
                state_nxt = ONES;
            end else begin
                d_out_nxt = 0;
                state_nxt = ZERO;
            end
        end
    endcase
end

/*
 * BLOCK: Register Modeling
 *   - State Register
 *   - Data Output (for stability, synchronize the output with the clock)
 */
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= 1'b0;
        d_out <= 1'b0;
    end else begin
        state <= state_nxt;
        d_out <= d_out_nxt;    
    end
end

endmodule
