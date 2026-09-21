module SequenceDetector (
	input      clk,        // global positive edge triggered clock
    input      reset_n,    // asynchronous negative triggered reset
    input      d_in,       // data input
    output reg d_out       // data output
);

// 추가
parameter S_IDLE = 2'd0,  // STATE: 유효한 패턴 접두사가 없는 초기 상태
          S_1    = 2'd1,  // STATE: "1"
          S_10   = 2'd2,  // STATE: "10"
          S_101  = 2'd3;  // STATE: "101" / d_out = 1

reg [1:0] state;      // 상태 레지스터 (D-FF으로 모델링)
reg [1:0] state_nxt;  // 다음 상태 (조합 논리 결과)

//BLOCK 1: State Transition (조합 논리)
always @(d_in or state) begin
    case (state)
        S_IDLE: begin
            // "1"이 들어와야 패턴이 시작
            if (d_in == 1'b1) state_nxt = S_1;
            else              state_nxt = S_IDLE;
        end
        S_1: begin
            // "1" 다음 "0" → "10"까지 진행 / "1"이 또 오면 마지막 "1"만 남음
            if (d_in == 1'b1) state_nxt = S_1;
            else              state_nxt = S_10;
        end
        S_10: begin
            // "10" 다음 "1" → "101" 검출 완료 / "0"이면 처음부터 다시
            if (d_in == 1'b1) state_nxt = S_101;
            else              state_nxt = S_IDLE;
        end
        S_101: begin
            // 겹침 검출: 직전 "101"의 뒷부분을 재활용
            //   "101" + "1" = "1011" → 유효 접미사 "1"  → S_1
            //   "101" + "0" = "1010" → 유효 접미사 "10" → S_10
            if (d_in == 1'b1) state_nxt = S_1;
            else              state_nxt = S_10;
        end
        default: state_nxt = S_IDLE;
    endcase
end

//BLOCK 2: Data Output (조합 논리)
always @(state) begin
    case (state)
        S_IDLE:  d_out = 1'b0;
        S_1:     d_out = 1'b0;
        S_10:    d_out = 1'b0;
        S_101:   d_out = 1'b1;
        default: d_out = 1'b0;
    endcase
end

//BLOCK 3: Register Modeling (순차 논리) - D 플립플롭
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= S_IDLE;
    end else begin
        state <= state_nxt;
    end
end

// 추가

endmodule
