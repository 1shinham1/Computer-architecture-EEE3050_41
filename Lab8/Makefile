########################################################
# Makefile: I/D Cache and CPU makefile
########################################################
# 
# Author: Seongwook Kim
# Date:   2024-11-07
#
# Description
#   This makefile is a automated build script for lab session 8 of EEE3050-42 in SKKU
#
# Prerequisites
#   Install Icarus Verilog and GNU make to your environment before running this script
#   Use links below to install if you are using Windows
#   - GNU Make:       https://gnuwin32.sourceforge.net/packages/make.htm
#   - Icarus Verilog: https://bleyer.org/icarus/
#   If you are using Ubuntu, you can install 'make' and 'iverilog' using apt command e.g., sudo apt install make iverilog
#
# Make Targets
#   run_d_cache: build and run data cache testbench
#   run_i_cache: build and run instruction cache testbench
#   run_cpu    : build and run CPU testbench
#
# Usage
#   make [build target]
#   ex) make run_d_cache
#
# Note
#   - VCD files will be created at the 'vcd' directory


CC=iverilog

all: run_d_cache run_i_cache run_cpu

build_d_cache: 
	$(CC) -o ./bin/d_cache -I srcs ./srcs/memory.v ./srcs/d_cache.v ./srcs/d_cache_tb.v

build_i_cache: 
	$(CC) -o ./bin/i_cache -I srcs ./srcs/memory.v ./srcs/i_cache.v ./srcs/i_cache_tb.v

build_cpu: 
	$(CC) -o ./bin/cpu -I srcs ./srcs/cpu.v ./srcs/alu.v ./srcs/opcodes.v ./srcs/register_file.v ./srcs/control_unit.v  ./srcs/i_cache.v ./srcs/d_cache.v ./srcs/memory.v ./srcs/cpu_tb.v

run_d_cache: build_d_cache
	vvp ./bin/d_cache

run_i_cache: build_i_cache
	vvp ./bin/i_cache

run_cpu: build_cpu
	vvp ./bin/cpu
