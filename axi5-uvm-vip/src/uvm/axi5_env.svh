// -----------------------------------------------------------------------------
// axi5_env.svh : top-level UVM environment.
// Instantiates a master agent (active) and optionally a slave agent, plus a
// shared scoreboard fed by the master monitor's write/read analysis ports.
// -----------------------------------------------------------------------------
`ifndef AXI5_ENV_SVH
`define AXI5_ENV_SVH

class axi5_env_config extends uvm_object;
  `uvm_object_utils(axi5_env_config)

  axi5_config master_cfg;
  axi5_config slave_cfg;
  bit         has_slave_agent = 1;
  bit         enable_scoreboard = 1;

  function new(string name = "axi5_env_config");
    super.new(name);
  endfunction
endclass

class axi5_env extends uvm_env;
  `uvm_component_utils(axi5_env)

  axi5_env_config  env_cfg;
  axi5_agent       master;
  axi5_agent       slave;
  axi5_scoreboard  scoreboard;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi5_env_config)::get(this, "", "env_cfg", env_cfg))
      `uvm_fatal(get_type_name(), "axi5_env_config not set")

    // Master agent.
    uvm_config_db#(axi5_config)::set(this, "master", "cfg", env_cfg.master_cfg);
    master = axi5_agent::type_id::create("master", this);

    // Optional slave agent.
    if (env_cfg.has_slave_agent) begin
      uvm_config_db#(axi5_config)::set(this, "slave", "cfg", env_cfg.slave_cfg);
      slave = axi5_agent::type_id::create("slave", this);
    end

    if (env_cfg.enable_scoreboard) begin
      uvm_config_db#(axi5_config)::set(this, "scoreboard", "cfg",
                                       env_cfg.master_cfg);
      scoreboard = axi5_scoreboard::type_id::create("scoreboard", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (env_cfg.enable_scoreboard) begin
      master.wr_ap.connect(scoreboard.wr_imp);
      master.rd_ap.connect(scoreboard.rd_imp);
    end
  endfunction

endclass

`endif // AXI5_ENV_SVH
