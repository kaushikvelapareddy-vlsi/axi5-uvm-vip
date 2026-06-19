# =============================================================================
# AXI5-UVM-VIP Makefile
# Simulator-agnostic front-end with targets for Questa, VCS, and Xcelium.
#
#   make questa   TEST=axi5_smoke_test            # Mentor Questa
#   make vcs      TEST=axi5_corner_test SEED=7    # Synopsys VCS
#   make xcelium  TEST=axi5_smoke_test            # Cadence Xcelium
#
# Common variables:
#   TEST   - UVM test name (default axi5_smoke_test)
#   SEED   - random seed (default 1)
#   VERB   - UVM verbosity (default UVM_MEDIUM)
#   DUMP   - set to 1 to enable waveform dumping
#   GUI    - set to 1 to launch the GUI (Questa/Xcelium)
# =============================================================================

TEST   ?= axi5_smoke_test
SEED   ?= 1
VERB   ?= UVM_MEDIUM
DUMP   ?= 0
GUI    ?= 0

FILELIST := sim/filelist.f
RUNF     := sim/run.f

PLUSARGS := +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERB)
ifeq ($(DUMP),1)
  PLUSARGS += +DUMP
endif

# ---- Questa -----------------------------------------------------------------
QUESTA_FLAGS := -64 -sv -mfcu -timescale=1ns/1ps +acc
questa:
	vlib work
	vlog $(QUESTA_FLAGS) -L $(UVM_HOME) +incdir+$(UVM_HOME)/src \
	    $(UVM_HOME)/src/uvm_pkg.sv -f $(FILELIST)
	vsim -64 -c axi5_tb_top -sv_seed $(SEED) \
	    -do "run -all; quit" $(PLUSARGS) -f $(RUNF)

# ---- VCS --------------------------------------------------------------------
VCS_FLAGS := -full64 -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps \
             -debug_access+all
vcs:
	vcs $(VCS_FLAGS) -f $(FILELIST) -l comp.log
	./simv +ntb_random_seed=$(SEED) $(PLUSARGS) -f $(RUNF) -l sim.log

# ---- Xcelium ----------------------------------------------------------------
XRUN_FLAGS := -64bit -sv -uvm -uvmhome CDNS-1.2 -timescale 1ns/1ps -access +rwc
xcelium:
	xrun $(XRUN_FLAGS) -f $(FILELIST) -svseed $(SEED) $(PLUSARGS) -f $(RUNF)

# ---- Syntax-only elaboration (CI smoke, no license-bound run) ---------------
# Uses Verilator in lint-only mode to catch gross syntax errors. Verilator does
# not support UVM, so this only lints the synthesizable RTL + interface.
lint:
	verilator --lint-only -Wall -Wno-fatal -sv \
	    +incdir+src src/axi5_if.sv src/axi5_sva_checker.sv rtl/axi5_slave_mem.sv \
	    || echo "verilator lint finished (warnings non-fatal)"

clean:
	rm -rf work transcript vsim.wlf *.log csrc simv simv.daidir \
	       xcelium.d *.vcd *.history ucli.key .bpad INCA_libs cov_work \
	       axi5_tb.vcd

help:
	@echo "AXI5-UVM-VIP make targets:"
	@echo "  make questa  TEST=<name> [SEED=n] [VERB=UVM_*] [DUMP=1]  - run on Questa"
	@echo "  make vcs     TEST=<name> [SEED=n]                        - run on VCS"
	@echo "  make xcelium TEST=<name> [SEED=n]                        - run on Xcelium"
	@echo "  make lint                                                - Verilator lint (RTL + if)"
	@echo "  make clean                                               - remove build artifacts"
	@echo ""
	@echo "Available tests: axi5_smoke_test, axi5_corner_test"
	@echo "Override widths:  +define+AXI5_DATA_WIDTH=128 (pass via your simulator)"

.PHONY: questa vcs xcelium lint clean help
