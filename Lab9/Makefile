########################################################
# Makefile: DMA & Arbiter (Lab 9)
########################################################
#
# Based on the Lab 8 makefile (Seongwook Kim)
#
# Make Targets
#   run_d_cache: build and run data cache testbench
#   run_i_cache: build and run instruction cache testbench
#   run_dma    : build and run DMA-only testbench (I$ + D$ + EXT_DEV + DMA + ARBITER + Memory)
#   run_cpu    : build and run CPU testbench (CPU extension: CPU + I$/D$ + EXT_DEV + DMA_CPU + ARBITER + Memory)
#
# Usage
#   make [build target]
#   ex) make run_dma
#
# Note
#   - VCD files will be created at the 'vcd' directory (cpu_tb dumps to ./dump.vcd)


CC=iverilog
CFLAGS=-I srcs

all: run_d_cache run_i_cache run_dma run_cpu

dirs:
	@mkdir -p bin vcd

build_d_cache: dirs
	$(CC) $(CFLAGS) -o ./bin/d_cache ./srcs/memory.v ./srcs/d_cache.v ./srcs/d_cache_tb.v

build_i_cache: dirs
	$(CC) $(CFLAGS) -o ./bin/i_cache ./srcs/memory.v ./srcs/i_cache.v ./srcs/i_cache_tb.v

build_dma: dirs
	$(CC) $(CFLAGS) -o ./bin/dma ./srcs/memory.v ./srcs/i_cache.v ./srcs/d_cache.v ./srcs/ex_dev.v ./srcs/dma.v ./srcs/arbiter.v ./srcs/dma_tb.v ./srcs/dma_dump.v

build_cpu: dirs
	$(CC) $(CFLAGS) -o ./bin/cpu ./srcs/cpu.v ./srcs/alu.v ./srcs/opcodes.v ./srcs/register_file.v ./srcs/control_unit.v ./srcs/i_cache.v ./srcs/d_cache.v ./srcs/memory.v ./srcs/ex_dev.v ./srcs/dma.v ./srcs/arbiter.v ./srcs/cpu_tb.v

run_d_cache: build_d_cache
	vvp ./bin/d_cache

run_i_cache: build_i_cache
	vvp ./bin/i_cache

run_dma: build_dma
	vvp ./bin/dma

run_cpu: build_cpu
	vvp ./bin/cpu

.PHONY: all dirs build_d_cache build_i_cache build_dma build_cpu run_d_cache run_i_cache run_dma run_cpu
