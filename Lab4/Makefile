# Lab4: Icarus Verilog
# Usage: make run_cpu / make all
# Add more .v files to the compile command below when needed.

CC  = iverilog
SRC = ./srcs

all: run_cpu

# ── Assign 4: Single Cycle CPU ───────────────────────────────────────────────
build_cpu:
	mkdir -p bin vcd
	$(CC) -g2012 -s CPU_W16_R4_tb -o ./bin/cpu -I $(SRC) $(SRC)/alu.v $(SRC)/register_file.v $(SRC)/control_unit.v $(SRC)/cpu.v $(SRC)/cpu_tb.v

run_cpu: build_cpu
	vvp ./bin/cpu

wave_cpu: run_cpu
	gtkwave ./vcd/cpu_tb.vcd

clean:
	rm -f ./bin/cpu ./vcd/cpu_tb.vcd
