// -----------------------------------------------------------------------------
// axi5_config.svh : agent/env configuration object.
// -----------------------------------------------------------------------------
`ifndef AXI5_CONFIG_SVH
`define AXI5_CONFIG_SVH

typedef enum { AXI5_MASTER, AXI5_SLAVE } axi5_agent_role_e;

class axi5_config extends uvm_object;

  // Virtual interface handle (set by the test/top).
  virtual axi5_if vif;

  // Role and activity.
  axi5_agent_role_e role        = AXI5_MASTER;
  uvm_active_passive_enum active = UVM_ACTIVE;

  // Component enables.
  bit enable_coverage     = 1;
  bit enable_protocol_chk = 1;
  bit enable_scoreboard   = 1;

  // Slave behaviour.
  int unsigned slave_min_wait = 0;   // min cycles of back-pressure
  int unsigned slave_max_wait = 4;   // max cycles of back-pressure
  bit          slave_inject_errors = 0; // randomly return SLVERR/DECERR

  // Address space the reference memory/slave responds to.
  bit [63:0]   mem_base = 64'h0000_0000;
  bit [63:0]   mem_size = 64'h0001_0000; // 64 KB

  // Outstanding transaction limits.
  // The master driver will not issue more than `max_outstanding` transactions
  // (writes + reads) whose response has not yet been received. This models a
  // bounded request-issue depth.
  int unsigned max_outstanding = 16;

  // Master response-channel back-pressure (BREADY/RREADY bubbles). When
  // enabled the driver randomly deasserts B/RREADY for up to
  // `master_max_ready_delay` cycles between accepting responses, exercising
  // the slave's VALID-stable behaviour.
  bit          master_ready_bubbles   = 0;
  int unsigned master_max_ready_delay = 3;

  `uvm_object_utils_begin(axi5_config)
    `uvm_field_enum(axi5_agent_role_e, role, UVM_ALL_ON)
    `uvm_field_int(enable_coverage, UVM_ALL_ON)
    `uvm_field_int(enable_protocol_chk, UVM_ALL_ON)
    `uvm_field_int(enable_scoreboard, UVM_ALL_ON)
    `uvm_field_int(mem_base, UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(mem_size, UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(max_outstanding, UVM_ALL_ON)
    `uvm_field_int(master_ready_bubbles, UVM_ALL_ON)
    `uvm_field_int(master_max_ready_delay, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "axi5_config");
    super.new(name);
  endfunction

  function bit addr_in_range(bit [63:0] a);
    return (a >= mem_base) && (a < (mem_base + mem_size));
  endfunction

endclass

`endif // AXI5_CONFIG_SVH
