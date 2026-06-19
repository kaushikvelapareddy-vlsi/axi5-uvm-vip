// -----------------------------------------------------------------------------
// axi5_base_test.svh : base test. Builds the env, wires the virtual interface,
// and provides config defaults shared by all tests.
// -----------------------------------------------------------------------------
`ifndef AXI5_BASE_TEST_SVH
`define AXI5_BASE_TEST_SVH

class axi5_base_test extends uvm_test;
  `uvm_component_utils(axi5_base_test)

  axi5_env            env;
  axi5_env_config     env_cfg;
  axi5_config         master_cfg;
  axi5_config         slave_cfg;
  virtual axi5_if     vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual axi5_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "virtual axi5_if not set in config DB")

    // Master configuration.
    master_cfg        = axi5_config::type_id::create("master_cfg");
    master_cfg.vif    = vif;
    master_cfg.role   = AXI5_MASTER;
    master_cfg.active = UVM_ACTIVE;
    master_cfg.mem_base = 64'h0000_0000;
    master_cfg.mem_size = 64'h0001_0000;

    // Slave configuration. PASSIVE by default because the RTL DUT
    // (axi5_slave_mem) is the real responder in the testbench. Set active to
    // use the VIP's built-in slave responder instead (DUT-less bring-up).
    slave_cfg         = axi5_config::type_id::create("slave_cfg");
    slave_cfg.vif     = vif;
    slave_cfg.role    = AXI5_SLAVE;
    slave_cfg.active  = UVM_PASSIVE;
    slave_cfg.enable_coverage     = 0;
    slave_cfg.enable_protocol_chk = 0;
    slave_cfg.mem_base = master_cfg.mem_base;
    slave_cfg.mem_size = master_cfg.mem_size;
    configure_slave(slave_cfg);

    // Environment configuration.
    env_cfg                  = axi5_env_config::type_id::create("env_cfg");
    env_cfg.master_cfg       = master_cfg;
    env_cfg.slave_cfg        = slave_cfg;
    env_cfg.has_slave_agent  = 1;
    env_cfg.enable_scoreboard = 1;
    uvm_config_db#(axi5_env_config)::set(this, "env", "env_cfg", env_cfg);

    env = axi5_env::type_id::create("env", this);
  endfunction

  // Hook for derived tests to tweak the slave (back-pressure, errors).
  virtual function void configure_slave(axi5_config c);
    c.slave_min_wait = 0;
    c.slave_max_wait = 3;
    c.slave_inject_errors = 0;
  endfunction

  // Run-phase objection management with a drain time.
  task run_phase(uvm_phase phase);
    phase.phase_done.set_drain_time(this, 200ns);
  endtask

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

endclass

`endif // AXI5_BASE_TEST_SVH
