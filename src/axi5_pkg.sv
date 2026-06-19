// -----------------------------------------------------------------------------
// axi5_pkg.sv : the AXI5 UVM VIP package. Includes all class-based components
// in dependency order. Compile axi5_defines.svh and axi5_if.sv before this,
// and axi5_sva_checker.sv standalone (it is a module, bound into the interface).
// -----------------------------------------------------------------------------
`ifndef AXI5_PKG_SV
`define AXI5_PKG_SV

`include "axi5_defines.svh"

package axi5_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Types and transaction.
  `include "axi5_types.svh"
  `include "axi5_seq_item.svh"

  // Configuration and infrastructure.
  `include "axi5_config.svh"
  `include "axi5_ref_mem.svh"
  `include "axi5_sequencer.svh"
  `include "axi5_driver.svh"
  `include "axi5_monitor.svh"
  `include "axi5_coverage.svh"
  `include "axi5_protocol_checker.svh"
  `include "axi5_scoreboard.svh"
  `include "axi5_agent.svh"
  `include "axi5_env.svh"

  // Sequence library.
  `include "seq/axi5_base_seq.svh"
  `include "seq/axi5_write_seq.svh"
  `include "seq/axi5_read_seq.svh"
  `include "seq/axi5_reg_traffic_seq.svh"
  `include "seq/axi5_corner_seqs.svh"

  // Test library.
  `include "test/axi5_base_test.svh"
  `include "test/axi5_smoke_test.svh"
  `include "test/axi5_corner_test.svh"

endpackage : axi5_pkg

`endif // AXI5_PKG_SV
