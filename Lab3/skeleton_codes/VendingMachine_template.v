module vending_machine #(
	parameter TOT_BITS    = 32,     // Total bits of the money, price, coin value, etc...
	parameter ITEM_BITS   = 8,      // Total bits of the item
	parameter NUM_ITEMS   = 4,      // Total types of items
	parameter COIN_BITS   = 8,      // Total bits of the coin
	parameter NUM_COINS   = 3,      // Total types of coins (100, 500, 1000)

	// 추가 시작 (Extra Credit)
	// 초기 재고 / 초기 거스름돈 개수. i번째 칸 = [i*BITS +: BITS]
	// 기본값: item 재고 최대(255개씩), 동전 127개씩 → 기본 테스트벤치에서는 사실상 무한과 동일하게 동작
	parameter [NUM_ITEMS*ITEM_BITS-1:0] INIT_ITEM_NUM = {NUM_ITEMS{{ITEM_BITS{1'b1}}}},
	parameter [NUM_COINS*COIN_BITS-1:0] INIT_COIN_NUM = {NUM_COINS{{1'b0, {(COIN_BITS-1){1'b1}}}}}
	// 추가 끝
)
(
	// Ports Declaration
	input   wire                        clk,                // Clock signal
	input   wire                        reset_n,            // Reset signal (active-low)

	input   wire    [NUM_COINS-1:0]     input_coin_i,       // coin is inserted.
	input   wire    [NUM_ITEMS-1:0]     select_item_i,      // item is selected.
	input   wire                        trigger_return_i,   // change-return is triggered

	output  wire    [NUM_ITEMS-1:0]     available_item_o,   // Sign of the item availability
	output  wire    [NUM_ITEMS-1:0]     output_item_o,      // Sign of the item withdrawal
	output  wire    [NUM_COINS-1:0]     return_coin_o,      // Sign of the coin return
	output  wire    [TOT_BITS-1:0]      total_o             // Sign of the current total money
);

	// Net constant values (prefix kk & CamelCase)
	wire [TOT_BITS:0] kkItemPrice [NUM_ITEMS-1:0];	// Price of each item (400, 500, 1000, 2000)
	assign kkItemPrice[0] = 400;
	assign kkItemPrice[1] = 500;
	assign kkItemPrice[2] = 1000;
	assign kkItemPrice[3] = 2000;

	wire [TOT_BITS:0] kkCoinValue [NUM_COINS-1:0];	// Value of each coin (100, 500, 1000)
	assign kkCoinValue[0] = 100;
	assign kkCoinValue[1] = 500;
	assign kkCoinValue[2] = 1000;


	// TODO: You may add your own reg variables (state, total, ...)
	// 추가 시작
	localparam S_IDLE     = 2'd0,  // STATE: 입력 대기 (동전 투입 / item 선택 / 반환 버튼)
	           S_DISPENSE = 2'd1,  // STATE: item 배출 (1 cycle)
	           S_RETURN   = 2'd2;  // STATE: 잔돈 반환 (1 cycle에 동전 1개씩)

	localparam [COIN_BITS-1:0] kkCoinFull = {COIN_BITS{1'b1}};  // 동전 통 최대 용량 (Extra Credit)

	reg [1:0]           state;                 // 상태 레지스터
	reg [1:0]           state_nxt;
	reg [TOT_BITS-1:0]  current_total;         // 현재 투입 총액
	reg [TOT_BITS-1:0]  current_total_nxt;

	reg [ITEM_BITS-1:0] num_items     [0:NUM_ITEMS-1];  // item별 남은 재고 (Extra Credit)
	reg [ITEM_BITS-1:0] num_items_nxt [0:NUM_ITEMS-1];
	reg [COIN_BITS-1:0] num_coins     [0:NUM_COINS-1];  // 동전별 보유 개수 (Extra Credit)
	reg [COIN_BITS-1:0] num_coins_nxt [0:NUM_COINS-1];

	reg [NUM_ITEMS-1:0] output_item;           // 배출 item (registered, 1 cycle pulse)
	reg [NUM_ITEMS-1:0] output_item_nxt;
	reg [NUM_COINS-1:0] return_coin;           // 반환 동전 (registered, 1 cycle pulse)
	reg [NUM_COINS-1:0] return_coin_nxt;

	reg [NUM_ITEMS-1:0] buyable;               // 가격 <= 투입액 && 재고 > 0
	reg [NUM_ITEMS-1:0] o_available_item;
	reg [NUM_ITEMS-1:0] o_output_item;
	reg [NUM_COINS-1:0] o_return_coin;
	reg                 coin_found;            // 반환할 동전을 찾았는지
	integer             i;

	assign available_item_o = o_available_item;
	assign output_item_o    = o_output_item;
	assign return_coin_o    = o_return_coin;
	assign total_o          = current_total;

	// 구매 가능 여부 (combinational logic)
	always @(*) begin
		for (i = 0; i < NUM_ITEMS; i = i + 1) begin
			buyable[i] = (kkItemPrice[i] <= current_total) && (num_items[i] != 0);
		end
	end
	// 추가 끝

	// Sequential circuit to reset or update the states
	always @(posedge clk) begin
		if (!reset_n) begin
			// TODO: reset all states.
			// 추가 시작
			state         <= S_IDLE;
			current_total <= {TOT_BITS{1'b0}};
			output_item   <= {NUM_ITEMS{1'b0}};
			return_coin   <= {NUM_COINS{1'b0}};
			for (i = 0; i < NUM_ITEMS; i = i + 1) num_items[i] <= INIT_ITEM_NUM[i*ITEM_BITS +: ITEM_BITS];
			for (i = 0; i < NUM_COINS; i = i + 1) num_coins[i] <= INIT_COIN_NUM[i*COIN_BITS +: COIN_BITS];
			// 추가 끝
		end
		else begin
			// TODO: update all states.
			// 추가 시작
			state         <= state_nxt;
			current_total <= current_total_nxt;
			output_item   <= output_item_nxt;
			return_coin   <= return_coin_nxt;
			for (i = 0; i < NUM_ITEMS; i = i + 1) num_items[i] <= num_items_nxt[i];
			for (i = 0; i < NUM_COINS; i = i + 1) num_coins[i] <= num_coins_nxt[i];
			// 추가 끝
		end
	end

	// Combinational circuit for the next states
	always @(*) begin
		// 추가 시작
		// 기본값: 현재 상태 유지, 출력 pulse 없음
		state_nxt         = state;
		current_total_nxt = current_total;
		output_item_nxt   = {NUM_ITEMS{1'b0}};
		return_coin_nxt   = {NUM_COINS{1'b0}};
		for (i = 0; i < NUM_ITEMS; i = i + 1) num_items_nxt[i] = num_items[i];
		for (i = 0; i < NUM_COINS; i = i + 1) num_coins_nxt[i] = num_coins[i];
		coin_found = 1'b0;

		case (state)
			S_IDLE: begin
				if (trigger_return_i) begin
					// 3.c 반환 버튼 → 반환 상태로
					state_nxt = S_RETURN;
				end
				else if (|input_coin_i) begin
					// TODO: current_total_nxt
					// 3.a 동전 투입 → 총액 증가, 동전 통에 보관
					for (i = 0; i < NUM_COINS; i = i + 1) begin
						if (input_coin_i[i]) begin
							if (num_coins[i] != kkCoinFull) begin
								current_total_nxt = current_total + kkCoinValue[i];
								// TODO: num_coins_nxt
								num_coins_nxt[i]  = num_coins[i] + 1'b1;
							end
							else begin
								// (Extra Credit) 동전 통이 가득 참 → 투입된 동전을 그대로 돌려줌
								return_coin_nxt[i] = 1'b1;
							end
						end
					end
				end
				else if (|select_item_i) begin
					// 3.b 선택 → 구매 가능하면 배출, 아니면 (가격 부족 / 품절) 아무 일도 없음
					for (i = 0; i < NUM_ITEMS; i = i + 1) begin
						if (select_item_i[i] && buyable[i]) begin
							current_total_nxt  = current_total - kkItemPrice[i];
							// TODO: num_items_nxt
							num_items_nxt[i]   = num_items[i] - 1'b1;
							output_item_nxt[i] = 1'b1;
							state_nxt          = S_DISPENSE;
						end
					end
				end
			end

			S_DISPENSE: begin
				// item 배출 1 cycle 후 다시 대기
				state_nxt = S_IDLE;
			end

			S_RETURN: begin
				// 큰 동전부터: (동전 가치 <= 남은 총액) && (보유 개수 > 0) 인 동전 1개 반환
				// 100 | 500 | 1000 이 서로 배수 관계이므로 보유량이 제한돼도 greedy가 최적
				for (i = NUM_COINS - 1; i >= 0; i = i - 1) begin
					if (!coin_found && (kkCoinValue[i] <= current_total) && (num_coins[i] != 0)) begin
						coin_found         = 1'b1;
						current_total_nxt  = current_total - kkCoinValue[i];
						num_coins_nxt[i]   = num_coins[i] - 1'b1;
						return_coin_nxt[i] = 1'b1;
					end
				end
				// 더 이상 줄 수 있는 동전이 없음 (총액 0 또는 거스름돈 부족)
				// → 남은 금액은 total_o에 그대로 남기고 대기 상태로
				if (!coin_found) state_nxt = S_IDLE;
			end

			default: state_nxt = S_IDLE;
		endcase
		// 추가 끝
	end

	// Combinational circuit for the outputs
	always @(*) begin
		// TODO: o_available_item
		// 추가 시작
		// 대기 상태에서만 구매 가능 item 표시 (배출/반환 중에는 0)
		o_available_item = (state == S_IDLE) ? buyable : {NUM_ITEMS{1'b0}};

		// TODO: o_output_item
		o_output_item = output_item;

		// TODO: o_return_coin
		o_return_coin = return_coin;
		// 추가 끝
	end

endmodule
