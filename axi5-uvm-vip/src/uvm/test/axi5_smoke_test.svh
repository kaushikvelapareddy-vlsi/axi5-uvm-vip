// -----------------------------------------------------------------------------
// axi5_smoke_test.svh : minimal write/read-back sanity test.
// -----------------------------------------------------------------------------
`ifndef AXI5_SMOKE_TEST_SVH
`define AXI5_SMOKE_TEST_SVH

class axi5_smoke_test extends axi5_base_test;
  `uvm_component_utils(axi5_smoke_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    axi5_reg_traffic_seq seq;
    super.run_phase(phase);
    phase.raise_objection(this, "smoke test running");
    seq = axi5_reg_traffic_seq::type_id::create("seq");
    if (!seq.randomize() with {
          base_addr == 64'h0000_0100;
          addr_span == 64'h0000_0800;
          num_txns  == 20;
        })
      `uvm_error(get_type_name(), "smoke seq randomize failed")
    seq.start(env.master.sequencer);
    phase.drop_objection(this, "smoke test done");
  endtask

endclass

`endif // AXI5_SMOKE_TEST_SVH
