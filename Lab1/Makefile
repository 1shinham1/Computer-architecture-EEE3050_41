# Lab1: Icarus Verilog
# Usage: make run_alu
# Add more .v files to the compile command below when needed.

CC = iverilog

all: run_alu

build_alu:
	mkdir -p bin vcd
	$(CC) -g2012 -s ALU_TB -o ./bin/alu -I ./src ./src/ALU_Template.v ./src/ALU_TB.v

run_alu: build_alu
	vvp ./bin/alu

wave_alu: run_alu
	gtkwave ./vcd/ALU_TB.vcd

clean:
	rm -f ./bin/alu ./vcd/ALU_TB.vcd
