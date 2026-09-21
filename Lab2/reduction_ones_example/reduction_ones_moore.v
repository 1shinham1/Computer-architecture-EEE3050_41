module ReductionOnesMoore (
    input      clk,        // global positive edge triggered clock
    input      reset_n,    // asynchronous negative triggered reset
    input      d_in,       // data input
    output reg d_out       // data output
);

parameter ZERO      = 0,   // STATE: ZERO      -> zero is detected
          FIRST_ONE = 1,   // STATE: FIRST_ONE -> one is detected and previous input is zero
          ONES      = 2;   // STATE: ONES      -> one is detected and previously ones are detected

reg [1:0] state;      // state register (modeled as D-FF)
reg [1:0] state_nxt;  // next state

/*
 * BLOCK: State Transition
 *   - This block determines the transition of the state
 *   - The next state is determined by the current state and the input data
 */
always @(d_in or state) begin
    case (state)
        ZERO: begin
            if (d_in == 1) state_nxt = FIRST_ONE;
            else state_nxt = ZERO;
        end
        FIRST_ONE: begin
            if (d_in == 1) state_nxt = ONES;
            else state_nxt = ZERO;
        end
        ONES: begin
            if (d_in == 1) state_nxt = ONES;
            else state_nxt = ZERO;
        end
        default: state_nxt = ZERO;
    endcase
end

/*
 * BLOCK: Data Output
 *   - This block determines the output of the FSM
 *   - Since this module is a Moore machine, the output is solely determined by the state register
 */
always @(state) begin
    case (state)
        ZERO:      d_out = 0;
        FIRST_ONE: d_out = 0;
        ONES:      d_out = 1;
        default:   d_out = 0;
    endcase
end

/*
 * BLOCK: Register Modeling
 *   - State Register
 */
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= ZERO;
    end else begin
        state <= state_nxt;    
    end
end

endmodule
