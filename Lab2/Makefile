# Lab2: Icarus Verilog
# Usage: make run_fsm / make run_reg / make all
# Add more .v files to the compile commands below when needed.

CC  = iverilog
SRC = ./skeleton_codes

all: run_fsm run_reg

# ── Assign 2-1: 101 Sequence Detector ────────────────────────────────────────
build_fsm:
	mkdir -p bin vcd
	$(CC) -g2012 -s SequenceDetector_tb -o ./bin/fsm -I $(SRC) $(SRC)/SequenceDetector.v $(SRC)/SequenceDetector_tb.v

run_fsm: build_fsm
	vvp ./bin/fsm

wave_fsm: run_fsm
	gtkwave ./vcd/fsm.vcd

# ── Assign 2-2: Register File ────────────────────────────────────────────────
build_reg:
	mkdir -p bin vcd
	$(CC) -g2012 -s RegisterFileTb -o ./bin/reg_file -I $(SRC) $(SRC)/RegisterFile.v $(SRC)/RegisterFile_tb.v

run_reg: build_reg
	vvp ./bin/reg_file

wave_reg: run_reg
	gtkwave ./vcd/reg_file.vcd

clean:
	rm -f ./bin/fsm ./bin/reg_file ./vcd/fsm.vcd ./vcd/reg_file.vcd
