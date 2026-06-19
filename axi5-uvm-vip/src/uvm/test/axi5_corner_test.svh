// -----------------------------------------------------------------------------
// axi5_corner_test.svh : runs the full corner-case sequence library plus
// randomized traffic under back-pressure and error injection.
// -----------------------------------------------------------------------------
`ifndef AXI5_CORNER_TEST_SVH
`define AXI5_CORNER_TEST_SVH

class axi5_corner_test extends axi5_base_test;
  `uvm_component_utils(axi5_corner_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Stress the master with bounded outstanding depth and response back-pressure.
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    master_cfg.max_outstanding        = 8;
    master_cfg.master_ready_bubbles   = 1;
    master_cfg.master_max_ready_delay = 3;
  endfunction

  // Heavier back-pressure to stress the handshakes.
  virtual function void configure_slave(axi5_config c);
    c.slave_min_wait = 0;
    c.slave_max_wait = 6;
    c.slave_inject_errors = 0; // keep data-integrity deterministic
  endfunction

  task run_phase(uvm_phase phase);
    axi5_single_beat_seq    s_single;
    axi5_narrow_seq         s_narrow;
    axi5_wrap_seq           s_wrap;
    axi5_maxlen_seq         s_max;
    axi5_4kb_edge_seq       s_4kb;
    axi5_misc_cover_seq     s_misc;
    axi5_burst_matrix_seq   s_bmat;
    axi5_exclusive_seq      s_excl;
    axi5_exclusive_fail_seq s_excl_fail;
    axi5_atomic_seq         s_atom;
    axi5_strobe_holes_seq   s_strb;
    axi5_error_resp_seq     s_err;
    axi5_zero_delay_seq     s_zero;
    axi5_interleaved_id_seq s_il;
    axi5_reg_traffic_seq    s_reg;

    super.run_phase(phase);
    phase.raise_objection(this, "corner test running");

    `uvm_info(get_type_name(), "Running corner-case sequence library", UVM_LOW)

    s_reg = axi5_reg_traffic_seq::type_id::create("s_reg");
    void'(s_reg.randomize() with { base_addr == 64'h200; addr_span == 64'h800;
                                   num_txns == 16; });
    s_reg.start(env.master.sequencer);

    s_single = axi5_single_beat_seq::type_id::create("s_single");
    void'(s_single.randomize() with { base_addr == 64'h1000; num_txns == 8; });
    s_single.start(env.master.sequencer);

    s_narrow = axi5_narrow_seq::type_id::create("s_narrow");
    void'(s_narrow.randomize() with { base_addr == 64'h2000; addr_span == 64'h400;
                                      num_txns == 10; });
    s_narrow.start(env.master.sequencer);

    s_wrap = axi5_wrap_seq::type_id::create("s_wrap");
    void'(s_wrap.randomize() with { base_addr == 64'h3000; addr_span == 64'h400; });
    s_wrap.start(env.master.sequencer);

    s_max = axi5_maxlen_seq::type_id::create("s_max");
    void'(s_max.randomize() with { base_addr == 64'h4000; });
    s_max.start(env.master.sequencer);

    s_4kb = axi5_4kb_edge_seq::type_id::create("s_4kb");
    void'(s_4kb.randomize() with { base_addr == 64'h5000; });
    s_4kb.start(env.master.sequencer);

    s_excl = axi5_exclusive_seq::type_id::create("s_excl");
    void'(s_excl.randomize() with { base_addr == 64'h6000; });
    s_excl.start(env.master.sequencer);

    s_excl_fail = axi5_exclusive_fail_seq::type_id::create("s_excl_fail");
    void'(s_excl_fail.randomize() with { base_addr == 64'h6800; });
    s_excl_fail.start(env.master.sequencer);

    s_atom = axi5_atomic_seq::type_id::create("s_atom");
    void'(s_atom.randomize() with { base_addr == 64'h7000; addr_span == 64'h400; });
    s_atom.start(env.master.sequencer);

    s_strb = axi5_strobe_holes_seq::type_id::create("s_strb");
    void'(s_strb.randomize() with { base_addr == 64'h8000; addr_span == 64'h400;
                                    num_txns == 10; });
    s_strb.start(env.master.sequencer);

    // Error-response paths (SLVERR window + out-of-range DECERR).
    s_err = axi5_error_resp_seq::type_id::create("s_err");
    void'(s_err.randomize());
    s_err.start(env.master.sequencer);

    // Residual coverage closers (FIXED burst, all-zero strobe, 4KB on-edge).
    s_misc = axi5_misc_cover_seq::type_id::create("s_misc");
    void'(s_misc.randomize() with { base_addr == 64'hB000; });
    s_misc.start(env.master.sequencer);

    // FIXED/WRAP length x size matrix (closes x_len_size_burst non-INCR cells).
    s_bmat = axi5_burst_matrix_seq::type_id::create("s_bmat");
    void'(s_bmat.randomize() with { base_addr == 64'hC000; });
    s_bmat.start(env.master.sequencer);

    s_zero = axi5_zero_delay_seq::type_id::create("s_zero");
    void'(s_zero.randomize() with { base_addr == 64'h9000; addr_span == 64'h400;
                                    num_txns == 16; });
    s_zero.start(env.master.sequencer);

    s_il = axi5_interleaved_id_seq::type_id::create("s_il");
    void'(s_il.randomize() with { base_addr == 64'hA000; addr_span == 64'h400;
                                  num_txns == 24; });
    s_il.start(env.master.sequencer);

    phase.drop_objection(this, "corner test done");
  endtask

endclass

`endif // AXI5_CORNER_TEST_SVH
