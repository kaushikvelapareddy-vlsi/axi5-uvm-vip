// -----------------------------------------------------------------------------
// axi5_tb_top.sv : top-level testbench. Generates clock/reset, instantiates the
// AXI5 interface and the RTL slave DUT, publishes the virtual interface to the
// UVM config DB, and launches the selected test via run_test().
// -----------------------------------------------------------------------------
`include "axi5_defines.svh"

module axi5_tb_top;
  import uvm_pkg::*;
  import axi5_pkg::*;
  `include "uvm_macros.svh"

  // ---- Clock and reset ------------------------------------------------------
  logic aclk;
  logic aresetn;

  initial begin
    aclk = 0;
    forever #5ns aclk = ~aclk; // 100 MHz
  end

  initial begin
    aresetn = 0;
    repeat (5) @(posedge aclk);
    aresetn = 1;
  end

  // ---- Interface ------------------------------------------------------------
  axi5_if #(
    .ADDR_WIDTH(`AXI5_ADDR_WIDTH),
    .DATA_WIDTH(`AXI5_DATA_WIDTH),
    .ID_WIDTH  (`AXI5_ID_WIDTH),
    .USER_WIDTH(`AXI5_USER_WIDTH)
  ) axi_if (.aclk(aclk), .aresetn(aresetn));

  // ---- Protocol-checker instance --------------------------------------------
  // The SVA checker takes the interface as a port (a module may not be
  // instantiated inside an interface). Disable with +define+AXI5_NO_SVA.
`ifndef AXI5_NO_SVA
  axi5_sva_checker #(
    .ADDR_WIDTH(`AXI5_ADDR_WIDTH),
    .DATA_WIDTH(`AXI5_DATA_WIDTH),
    .ID_WIDTH  (`AXI5_ID_WIDTH)
  ) u_sva (.vif(axi_if));
`endif

  // ---- DUT (RTL slave memory) ----------------------------------------------
  axi5_slave_mem #(
    .ADDR_WIDTH(`AXI5_ADDR_WIDTH),
    .DATA_WIDTH(`AXI5_DATA_WIDTH),
    .ID_WIDTH  (`AXI5_ID_WIDTH),
    .MEM_BYTES (1 << 16)
  ) u_dut (
    .aclk    (aclk),
    .aresetn (aresetn),
    .s       (axi_if)
  );

  // ---- UVM run --------------------------------------------------------------
  initial begin
    uvm_config_db#(virtual axi5_if)::set(null, "uvm_test_top", "vif", axi_if);
    run_test();
  end

  // ---- Global watchdog ------------------------------------------------------
  initial begin
    #2ms;
    `uvm_fatal("TB_TOP", "Global timeout reached")
  end

  // ---- Waveform dump (optional) ---------------------------------------------
  initial begin
    if ($test$plusargs("DUMP")) begin
      $dumpfile("axi5_tb.vcd");
      $dumpvars(0, axi5_tb_top);
    end
  end

endmodule
