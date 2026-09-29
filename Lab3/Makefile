# Lab3: Icarus Verilog
# Usage: make run_vm / make all
# Add more .v files to the compile commands below when needed.

CC  = iverilog
SRC = ./skeleton_codes

all: run_vm

# ── Assign 3: Vending Machine (+ Extra Credit tests in the same testbench) ──
build_vm:
	mkdir -p bin vcd
	$(CC) -g2012 -s vending_machine_tb -o ./bin/vending_machine -I $(SRC) $(SRC)/VendingMachine_template.v $(SRC)/VendingMachine_tb.v

run_vm: build_vm
	vvp ./bin/vending_machine

wave_vm: run_vm
	gtkwave ./vcd/vending_machine.vcd

clean:
	rm -f ./bin/vending_machine ./vcd/vending_machine.vcd
