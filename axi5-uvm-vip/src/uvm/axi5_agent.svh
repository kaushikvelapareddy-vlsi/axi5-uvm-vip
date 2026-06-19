// -----------------------------------------------------------------------------
// axi5_agent.svh : configurable AXI5 agent (master or slave).
// Active agents instantiate a sequencer + driver; all agents instantiate a
// monitor. Coverage and protocol checker are optionally connected.
// -----------------------------------------------------------------------------
`ifndef AXI5_AGENT_SVH
`define AXI5_AGENT_SVH

class axi5_agent extends uvm_agent;
  `uvm_component_utils(axi5_agent)

  axi5_config             cfg;
  axi5_sequencer          sequencer;
  axi5_driver             driver;
  axi5_monitor            monitor;
  axi5_coverage           coverage;
  axi5_protocol_checker   checker;

  // Exposed so the env can connect scoreboard/coverage at top level too.
  uvm_analysis_port #(axi5_seq_item) ap;
  uvm_analysis_port #(axi5_seq_item) wr_ap;
  uvm_analysis_port #(axi5_seq_item) rd_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi5_config)::get(this, "", "cfg", cfg))
      `uvm_fatal(get_type_name(), "axi5_config not set for agent")

    // Propagate config to children.
    uvm_config_db#(axi5_config)::set(this, "*", "cfg", cfg);

    monitor = axi5_monitor::type_id::create("monitor", this);

    if (cfg.active == UVM_ACTIVE) begin
      sequencer = axi5_sequencer::type_id::create("sequencer", this);
      driver    = axi5_driver::type_id::create("driver", this);
    end

    if (cfg.enable_coverage)
      coverage = axi5_coverage::type_id::create("coverage", this);
    if (cfg.enable_protocol_chk)
      checker  = axi5_protocol_checker::type_id::create("checker", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    ap    = monitor.ap;
    wr_ap = monitor.wr_ap;
    rd_ap = monitor.rd_ap;

    if (cfg.active == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);

    if (cfg.enable_coverage)
      monitor.ap.connect(coverage.analysis_export);
    if (cfg.enable_protocol_chk)
      monitor.ap.connect(checker.analysis_export);
  endfunction

endclass

`endif // AXI5_AGENT_SVH
