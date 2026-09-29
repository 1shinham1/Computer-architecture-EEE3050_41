`timescale 100ps / 100ps

module vending_machine_tb;

	parameter CLK_PERIOD  = 100;

	parameter TOT_BITS    = 32;
	parameter ITEM_BITS   = 8;
	parameter NUM_ITEMS   = 4;
	parameter COIN_BITS   = 8;
	parameter NUM_COINS   = 3;

	// 추가 시작 (Extra Credit)
	// UUT_EX1 초기 재고: item3(2000)=1, item2(1000)=0 (처음부터 품절), item1(500)=1, item0(400)=2
	parameter [NUM_ITEMS*ITEM_BITS-1:0] EX1_ITEM_NUM = {8'd1, 8'd0, 8'd1, 8'd2};
	// UUT_EX1 초기 동전: 1000원=252 (3개 더 받으면 가득 참), 500원=1, 100원=0 (거스름돈 없음)
	parameter [NUM_COINS*COIN_BITS-1:0] EX1_COIN_NUM = {8'd252, 8'd1, 8'd0};
	// UUT_EX2 초기 동전: 1000원=0, 500원=0, 100원=5 (재고는 기본값)
	parameter [NUM_COINS*COIN_BITS-1:0] EX2_COIN_NUM = {8'd0, 8'd0, 8'd5};
	// 추가 끝

	//Internal signal declaration
	reg     clk;
	reg     reset_n;

	reg     [NUM_COINS-1:0]     input_coin_i;
	reg     [NUM_ITEMS-1:0]     select_item_i;
	reg                         trigger_return_i;

	wire    [NUM_ITEMS-1:0]     available_item_o;
	wire    [NUM_ITEMS-1:0]     output_item_o;
	wire    [NUM_COINS-1:0]     return_coin_o;
	wire    [TOT_BITS-1:0]      total_o;

	// 추가 시작 (Extra Credit)
	// UUT     : 제공된 테스트 시퀀스 (기본 파라미터)
	// UUT_EX1 : [Extra 1] 재고 제한, [Extra 2-a/b] 거스름돈 제한
	// UUT_EX2 : [Extra 2-c] 1000원/500원이 없는 자판기
	// 초기 재고/동전 구성이 달라 인스턴스를 나눔. 입력은 공유하고 dut_sel로 고른 인스턴스만 reset을 풀어 동작시킴
	reg     [1:0]               dut_sel;
	wire    [NUM_ITEMS-1:0]     available_item_0, available_item_1, available_item_2;
	wire    [NUM_ITEMS-1:0]     output_item_0,    output_item_1,    output_item_2;
	wire    [NUM_COINS-1:0]     return_coin_0,    return_coin_1,    return_coin_2;
	wire    [TOT_BITS-1:0]      total_0,          total_1,          total_2;

	assign available_item_o = (dut_sel == 2'd0) ? available_item_0 : (dut_sel == 2'd1) ? available_item_1 : available_item_2;
	assign output_item_o    = (dut_sel == 2'd0) ? output_item_0    : (dut_sel == 2'd1) ? output_item_1    : output_item_2;
	assign return_coin_o    = (dut_sel == 2'd0) ? return_coin_0    : (dut_sel == 2'd1) ? return_coin_1    : return_coin_2;
	assign total_o          = (dut_sel == 2'd0) ? total_0          : (dut_sel == 2'd1) ? total_1          : total_2;

	integer ret_cnt [0:NUM_COINS-1];   // 반환된 동전 개수 (동전 종류별)
	integer err_cnt;
	integer k;
	// 추가 끝

	// Unit Under Test port map
	vending_machine #(
		.TOT_BITS           (TOT_BITS),
		.ITEM_BITS          (ITEM_BITS),
		.NUM_ITEMS          (NUM_ITEMS),
		.COIN_BITS          (COIN_BITS),
		.NUM_COINS          (NUM_COINS)
	)
	UUT (
		.clk                (clk),
		.reset_n            (reset_n && (dut_sel == 2'd0)),
		.input_coin_i       (input_coin_i),
		.select_item_i      (select_item_i),
		.trigger_return_i   (trigger_return_i),
		.available_item_o   (available_item_0),
		.output_item_o      (output_item_0),
		.return_coin_o      (return_coin_0),
		.total_o    (total_0)
	);

	// 추가 시작 (Extra Credit)
	vending_machine #(
		.TOT_BITS           (TOT_BITS),
		.ITEM_BITS          (ITEM_BITS),
		.NUM_ITEMS          (NUM_ITEMS),
		.COIN_BITS          (COIN_BITS),
		.NUM_COINS          (NUM_COINS),
		.INIT_ITEM_NUM      (EX1_ITEM_NUM),
		.INIT_COIN_NUM      (EX1_COIN_NUM)
	)
	UUT_EX1 (
		.clk                (clk),
		.reset_n            (reset_n && (dut_sel == 2'd1)),
		.input_coin_i       (input_coin_i),
		.select_item_i      (select_item_i),
		.trigger_return_i   (trigger_return_i),
		.available_item_o   (available_item_1),
		.output_item_o      (output_item_1),
		.return_coin_o      (return_coin_1),
		.total_o            (total_1)
	);

	vending_machine #(
		.TOT_BITS           (TOT_BITS),
		.ITEM_BITS          (ITEM_BITS),
		.NUM_ITEMS          (NUM_ITEMS),
		.COIN_BITS          (COIN_BITS),
		.NUM_COINS          (NUM_COINS),
		.INIT_COIN_NUM      (EX2_COIN_NUM)
	)
	UUT_EX2 (
		.clk                (clk),
		.reset_n            (reset_n && (dut_sel == 2'd2)),
		.input_coin_i       (input_coin_i),
		.select_item_i      (select_item_i),
		.trigger_return_i   (trigger_return_i),
		.available_item_o   (available_item_2),
		.output_item_o      (output_item_2),
		.return_coin_o      (return_coin_2),
		.total_o            (total_2)
	);

	// 재고/동전 개수 관찰용: 배열(num_items, num_coins)은 VCD에 기록되지 않으므로 wire로 꺼내서 dump
	wire    [ITEM_BITS-1:0]     ex1_num_items_0 = UUT_EX1.num_items[0];
	wire    [ITEM_BITS-1:0]     ex1_num_items_1 = UUT_EX1.num_items[1];
	wire    [ITEM_BITS-1:0]     ex1_num_items_2 = UUT_EX1.num_items[2];
	wire    [ITEM_BITS-1:0]     ex1_num_items_3 = UUT_EX1.num_items[3];
	wire    [COIN_BITS-1:0]     ex1_num_coins_0 = UUT_EX1.num_coins[0];
	wire    [COIN_BITS-1:0]     ex1_num_coins_1 = UUT_EX1.num_coins[1];
	wire    [COIN_BITS-1:0]     ex1_num_coins_2 = UUT_EX1.num_coins[2];
	wire    [COIN_BITS-1:0]     ex2_num_coins_0 = UUT_EX2.num_coins[0];
	wire    [COIN_BITS-1:0]     ex2_num_coins_1 = UUT_EX2.num_coins[1];
	wire    [COIN_BITS-1:0]     ex2_num_coins_2 = UUT_EX2.num_coins[2];

	// 반환 동전 카운트 (출력은 posedge에서 바뀜, TB 입력은 negedge에서 바뀜 → 1/4 cycle 지점에서 샘플링)
	always @(posedge clk) begin
		#(CLK_PERIOD/4);
		for (k = 0; k < NUM_COINS; k = k + 1)
			if (return_coin_o[k]) ret_cnt[k] = ret_cnt[k] + 1;
	end
	// 추가 끝

	// clock generation
	initial begin : CLOCK_GENERATOR
		clk     = 1'b0;
		forever #(CLK_PERIOD/2) clk = ~clk; // a clock cycle: # 100, a half cycle: # 50
	end

	// Test-bench
	initial begin
		$dumpfile("vcd/vending_machine.vcd");
		$dumpvars(0, UUT);
		// 추가 시작 (Extra Credit)
		$dumpvars(0, UUT_EX1);
		$dumpvars(0, UUT_EX2);
		$dumpvars(1, dut_sel,
		          ex1_num_items_0, ex1_num_items_1, ex1_num_items_2, ex1_num_items_3,
		          ex1_num_coins_0, ex1_num_coins_1, ex1_num_coins_2,
		          ex2_num_coins_0, ex2_num_coins_1, ex2_num_coins_2);
		dut_sel = 2'd0;
		err_cnt = 0;
		ClearRetCnt();
		// 추가 끝

		// Initialize input signals
		input_coin_i     = {NUM_COINS{1'b0}};
		select_item_i    = {NUM_ITEMS{1'b0}};
		trigger_return_i    = 1'b0;
		reset_n             = 1'b0;
		repeat (3) @(posedge clk); // Wait until the output signals are stable.
		reset_n             = 1'b1;
		repeat (3) @(posedge clk); // Wait until the output signals are stable.
	    #(CLK_PERIOD/2)     // Pushing signal after half cycle

		// Test cases
		$display("---------------------------------------------------");
        $display("Command Start");
        $display("---------------------------------------------------");
		Insert100Coin();
		Insert100Coin();
		Insert100Coin();
		Insert100Coin();
		Insert100Coin();

		Insert500Coin();
		Insert500Coin();    // 1500

		Insert1000Coin();
		Insert1000Coin();
		Insert1000Coin();
		Insert1000Coin();   // 5500

		Select1stItem();
		Select1stItem();    // 4700

		Select2ndItem();
		Select2ndItem();    // 3700

		Select3rdItem();    // 2700
		Select4thItem();    // 700

		Insert100Coin();
		Insert100Coin();
		Insert100Coin();
		Insert100Coin();    // 1100

		Insert500Coin();
		Insert500Coin();
		Insert500Coin();    // 2600

		Insert1000Coin();
		Insert1000Coin();
		Insert1000Coin();   // 5600

		TriggerReturn();    // 0 (1000 x 5 + 500 x 1)

		$display("---------------------------------------------------");
        $display("Command completed");
        $display("---------------------------------------------------");


		
		// 추가 시작 (Extra Credit)----------------------------------------------------
		#(CLK_PERIOD*10);                           // 위 반환이 끝날 때까지 대기
		dut_sel = 2'd1;                             // UUT는 reset, UUT_EX1 동작 시작
		#(CLK_PERIOD*3);

		$display("[Extra 1] Limit number of items (UUT_EX1)");
		$display("  init stock: item0=2, item1=1, item2=0, item3=1");
		$display("---------------------------------------------------");
		CheckIdle(0, 4'b0000);
		InsertCoin(2);  CheckIdle(1000, 4'b0011);   // item2(1000원)은 재고 0 → 표시 안 됨
		InsertCoin(2);  CheckIdle(2000, 4'b1011);
		InsertCoin(2);  CheckIdle(3000, 4'b1011);

		SelectItem(2, 4'b0000, 3000);               // 품절 item 선택 → 아무 일도 없음
		SelectItem(1, 4'b0010, 2500);               // item1 마지막 1개 구매
		CheckIdle(2500, 4'b1001);                   // item1 품절 → available에서 빠짐
		SelectItem(1, 4'b0000, 2500);               // 돈은 충분하지만 품절 → 아무 일도 없음
		SelectItem(3, 4'b1000, 500);                // item3 마지막 1개 구매
		CheckIdle(500, 4'b0001);
		SelectItem(0, 4'b0001, 100);                // item0 재고 2 → 1

		$display("---------------------------------------------------");
		$display("[Extra 2] Limit number of coins to return (UUT_EX1)");
		$display("  coins: 100 x0, 500 x1, 1000 x255 (full)");
		$display("---------------------------------------------------");
		InsertCoinRejected(2, 100);                 // 1000원 통 가득 참 → 투입 동전 즉시 반환
		Return(0, 0, 0, 100);                       // 100원이 없어 100원을 돌려줄 수 없음 → total 유지

		InsertCoin(1);  CheckIdle(600, 4'b0001);    // 500원 통: 2
		SelectItem(0, 4'b0001, 200);                // item0 마지막 1개 → 전 품목 품절
		InsertCoin(1);  CheckIdle(700, 4'b0000);    // 500원 통: 3, 돈이 있어도 전부 품절
		SelectItem(0, 4'b0000, 700);                // 품절 → 아무 일도 없음

		Return(0, 1, 0, 200);                       // 700 = 500 x1 반환, 100원 부족 → 200 남음

		InsertCoin(0);
		InsertCoin(0);  CheckIdle(400, 4'b0000);    // 100원 통: 2
		Return(2, 0, 0, 200);                       // 100원 2개만 반환 가능 → 200 남음

		InsertCoin(0);
		InsertCoin(0);
		InsertCoin(0);  CheckIdle(500, 4'b0000);    // 100원 통: 3
		Return(0, 1, 0, 0);                         // 500 x1 로 전액 반환 (500원 통: 1)

		InsertCoin(1);
		InsertCoin(1);  CheckIdle(1000, 4'b0000);   // 500원 통: 3
		Return(0, 0, 1, 0);                         // 1000 x1 로 전액 반환 (1000원 통: 254)

		$display("---------------------------------------------------");
		$display("[Extra 2-c] Coin types lacking (UUT_EX2)");
		$display("  coins: 100 x5, 500 x0, 1000 x0");
		$display("---------------------------------------------------");
		dut_sel = 2'd2;                             // UUT_EX1은 reset, UUT_EX2 동작 시작
		#(CLK_PERIOD*3);
		CheckIdle(0, 4'b0000);

		InsertCoin(1);
		InsertCoin(1);  CheckIdle(1000, 4'b0111);   // 500원 통: 2
		Return(0, 2, 0, 0);                         // 1000원이 없음 → 500 x2 로 대체

		InsertCoin(2);  CheckIdle(1000, 4'b0111);   // 1000원 통: 1
		SelectItem(0, 4'b0001, 600);
		Return(5, 0, 0, 100);                       // 500원이 없음 → 100 x5, 100원도 부족 → 100 남음

		InsertCoin(0);
		InsertCoin(0);
		InsertCoin(0);  CheckIdle(400, 4'b0001);    // 남은 100원은 사라지지 않고 다음 구매에 사용
		SelectItem(0, 4'b0001, 0);

		$display("---------------------------------------------------");
		if (err_cnt == 0) $display("Extra credit: ALL TESTS PASSED");
		else              $display("Extra credit: %0d TEST(S) FAILED", err_cnt);
		$display("---------------------------------------------------");
		// 추가 끝

		#10000
		$finish(0);
	end

// User's Action
task Insert100Coin;
begin
	#CLK_PERIOD input_coin_i[0]     = 1;
	#CLK_PERIOD input_coin_i[0]     = 0;	// After one cycle, deactivate the signal
	$display("Insert 100 Coin, Total: %d", total_o);
end
endtask

task Insert500Coin;
begin
	#CLK_PERIOD input_coin_i[1]     = 1;
	#CLK_PERIOD input_coin_i[1]     = 0;	// After one cycle, deactivate the signal
	$display("Insert 500 Coin, Total: %d", total_o);
end
endtask

task Insert1000Coin;
begin
	#CLK_PERIOD input_coin_i[2]     = 1;
	#CLK_PERIOD input_coin_i[2]     = 0;	// After one cycle, deactivate the signal
	$display("Insert 1000 Coin, Total: %d", total_o);
end
endtask

task Select1stItem;
begin
	#CLK_PERIOD select_item_i[0]    = 1;
	#CLK_PERIOD select_item_i[0]    = 0;	// After one cycle, deactivate the signal
	$display("Select 1st Item, Total: %d, Item: %b", total_o, output_item_o);
end
endtask

task Select2ndItem;
begin
	#CLK_PERIOD select_item_i[1]    = 1;
	#CLK_PERIOD select_item_i[1]    = 0;	// After one cycle, deactivate the signal
	$display("Select 2nd Item, Total: %d, Item: %b", total_o, output_item_o);
end
endtask

task Select3rdItem;
begin
	#CLK_PERIOD select_item_i[2]    = 1;
	#CLK_PERIOD select_item_i[2]    = 0;	// After one cycle, deactivate the signal
	$display("Select 3rd Item, Total: %d, Item: %b", total_o, output_item_o);
end
endtask

task Select4thItem;
begin
	#CLK_PERIOD select_item_i[3]    = 1;
	#CLK_PERIOD select_item_i[3]    = 0;   // After one cycle, deactivate the signal
	$display("Select 4th Item, Total: %d, Item: %b", total_o, output_item_o);
end
endtask

task TriggerReturn;
begin
	#CLK_PERIOD trigger_return_i    = 1;
	#CLK_PERIOD trigger_return_i    = 0;
	$display("Trigger Return\n");
end
endtask

// 추가 시작 (Extra Credit)
task InsertCoin(input integer idx);
begin
	#CLK_PERIOD input_coin_i[idx]   = 1;
	#CLK_PERIOD input_coin_i[idx]   = 0;
	$display("Insert %4d Coin, Total: %5d, Available: %b", UUT.kkCoinValue[idx], total_o, available_item_o);
end
endtask

// 동전 통이 가득 찬 상태에서 투입 → 같은 동전이 반환되고 total은 그대로
task InsertCoinRejected(input integer idx, input [TOT_BITS-1:0] exp_total);
begin
	#CLK_PERIOD input_coin_i[idx]   = 1;
	#CLK_PERIOD input_coin_i[idx]   = 0;
	$display("Insert %4d Coin (coin box full), Total: %5d, Return: %b", UUT.kkCoinValue[idx], total_o, return_coin_o);
	Check(total_o == exp_total && return_coin_o == (1 << idx), "coin rejected and returned");
end
endtask

task SelectItem(input integer idx, input [NUM_ITEMS-1:0] exp_item, input [TOT_BITS-1:0] exp_total);
begin
	#CLK_PERIOD select_item_i[idx]  = 1;
	#CLK_PERIOD select_item_i[idx]  = 0;
	$display("Select Item%0d, Total: %5d, Item: %b", idx, total_o, output_item_o);
	Check(output_item_o == exp_item && total_o == exp_total, "select item");
end
endtask

// 반환 버튼 → 반환이 끝날 때까지 대기 후, 동전 종류별 반환 개수와 남은 금액 확인
task Return(input integer exp100, input integer exp500, input integer exp1000, input [TOT_BITS-1:0] exp_total);
begin
	ClearRetCnt();
	#CLK_PERIOD trigger_return_i    = 1;
	#CLK_PERIOD trigger_return_i    = 0;
	#(CLK_PERIOD*10);
	$display("Trigger Return, Returned: 100 x%0d, 500 x%0d, 1000 x%0d, Remain: %5d",
	         ret_cnt[0], ret_cnt[1], ret_cnt[2], total_o);
	Check(ret_cnt[0] == exp100 && ret_cnt[1] == exp500 && ret_cnt[2] == exp1000 && total_o == exp_total,
	      "return change");
end
endtask

// 배출(DISPENSE) 1 cycle이 끝난 뒤 대기 상태에서 total / available 확인
task CheckIdle(input [TOT_BITS-1:0] exp_total, input [NUM_ITEMS-1:0] exp_avail);
begin
	#CLK_PERIOD;
	Check(total_o == exp_total && available_item_o == exp_avail, "total / available");
end
endtask

task Check(input cond, input [8*32-1:0] msg);
begin
	if (!cond) begin
		err_cnt = err_cnt + 1;
		$display("  -> FAIL (%0s) total=%0d avail=%b item=%b coin=%b",
		         msg, total_o, available_item_o, output_item_o, return_coin_o);
	end
end
endtask

task ClearRetCnt;
begin
	for (k = 0; k < NUM_COINS; k = k + 1) ret_cnt[k] = 0;
end
endtask
// 추가 끝

endmodule
