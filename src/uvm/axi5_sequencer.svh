// -----------------------------------------------------------------------------
// axi5_sequencer.svh : UVM sequencer for AXI5 transactions.
// -----------------------------------------------------------------------------
`ifndef AXI5_SEQUENCER_SVH
`define AXI5_SEQUENCER_SVH

class axi5_sequencer extends uvm_sequencer #(axi5_seq_item);
  `uvm_component_utils(axi5_sequencer)

  axi5_config cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi5_config)::get(this, "", "cfg", cfg))
      `uvm_fatal(get_type_name(), "axi5_config not set for sequencer")
  endfunction
endclass

`endif // AXI5_SEQUENCER_SVH
