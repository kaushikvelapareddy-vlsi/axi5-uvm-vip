# -----------------------------------------------------------------------------
# filelist.f : compile order for the AXI5 UVM VIP.
# Paths are relative to the PROJECT ROOT (run vcs/xrun/vlog from there, which is
# what the Makefile does). Compile defines + interface + SVA module first, then
# the package, then the TB.
# -----------------------------------------------------------------------------
+incdir+src
+incdir+src/uvm
+incdir+src/uvm/seq
+incdir+src/uvm/test

# Width defines (compiled standalone so macros are visible to the interface).
src/uvm/axi5_defines.svh

# Standalone modules.
src/axi5_sva_checker.sv
src/axi5_if.sv

# RTL DUT.
rtl/axi5_slave_mem.sv

# UVM package (includes all class files in dependency order).
src/axi5_pkg.sv

# Testbench top.
tb/axi5_tb_top.sv
