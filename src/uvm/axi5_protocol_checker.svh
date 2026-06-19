// -----------------------------------------------------------------------------
// axi5_protocol_checker.svh : UVM analysis-based protocol checker.
// Complements the bound SVA module (axi5_sva_checker.sv) with transaction-level
// checks that need reconstructed bursts and ID correlation (exclusive monitor,
// response legality, atomic semantics).
// -----------------------------------------------------------------------------
`ifndef AXI5_PROTOCOL_CHECKER_SVH
`define AXI5_PROTOCOL_CHECKER_SVH

class axi5_protocol_checker extends uvm_subscriber #(axi5_seq_item);
  `uvm_component_utils(axi5_protocol_checker)

  axi5_config cfg;

  int unsigned errors   = 0;
  int unsigned checks   = 0;

  // Exclusive monitor: addr -> last exclusive read seen (per id).
  bit [63:0] excl_addr [bit [`AXI5_ID_WIDTH-1:0]];
  bit        excl_open [bit [`AXI5_ID_WIDTH-1:0]];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db#(axi5_config)::get(this, "", "cfg", cfg));
  endfunction

  function void chk(bit cond, string msg);
    checks++;
    if (!cond) begin
      errors++;
      `uvm_error(get_type_name(), msg)
    end
  endfunction

  function void write(axi5_seq_item t);
    // Response legality: EXOKAY only on exclusive accesses.
    if (t.resp == AXI5_EXOKAY)
      chk(t.lock == AXI5_EXCLUSIVE,
          $sformatf("EXOKAY returned for non-exclusive %s id=0x%0h",
                    t.dir.name(), t.id));

    // DECERR/SLVERR are always permitted; OKAY on exclusive means the
    // exclusive access failed (allowed). No error.

    // Atomic transactions must be writes with INCR burst and no lock.
    if (t.atop != AXI5_ATOP_NONE) begin
      chk(t.dir == AXI5_WRITE,
          $sformatf("Atomic op %s issued on a read id=0x%0h",
                    t.atop.name(), t.id));
      chk(t.burst == AXI5_INCR,
          $sformatf("Atomic op %s with non-INCR burst id=0x%0h",
                    t.atop.name(), t.id));
      chk(t.lock != AXI5_EXCLUSIVE,
          $sformatf("Atomic op %s combined with exclusive id=0x%0h",
                    t.atop.name(), t.id));
    end

    // Exclusive sequence tracking (ID-accurate, best effort).
    if (t.lock == AXI5_EXCLUSIVE) begin
      if (t.dir == AXI5_READ) begin
        excl_addr[t.id] = t.addr;
        excl_open[t.id] = 1'b1;
      end
      else begin // exclusive write
        bit had_open = excl_open.exists(t.id) && excl_open[t.id];
        if (t.resp == AXI5_EXOKAY)
          chk(had_open && excl_addr[t.id] == t.addr,
              $sformatf("Exclusive write EXOKAY without matching exclusive read id=0x%0h", t.id));
        excl_open[t.id] = 1'b0;
      end
    end

    // Burst legality (defensive — also covered by SVA).
    chk(t.burst != AXI5_BURST_RSVD,
        $sformatf("Reserved burst type id=0x%0h", t.id));

    // Write-strobe lane legality (A3.4.3): for each beat, any asserted WSTRB
    // bit must fall within the active byte lanes determined by the beat
    // address and transfer size. Out-of-lane strobes are illegal.
    if (t.dir == AXI5_WRITE && t.atop == AXI5_ATOP_NONE) begin
      int nb = (1 << t.size);
      foreach (t.strb[b]) begin
        bit [63:0] ba = t.beat_addr(b);
        int lane0 = ba % (`AXI5_DATA_WIDTH/8);
        for (int lane = 0; lane < (`AXI5_DATA_WIDTH/8); lane++)
          if (t.strb[b][lane])
            chk((lane >= lane0) && (lane < lane0 + nb), $sformatf(
              "WSTRB lane %0d outside active [%0d:%0d] beat %0d id=0x%0h",
              lane, lane0, lane0+nb-1, b, t.id));
      end
    end
  endfunction

  function void report_phase(uvm_phase phase);
    if (errors == 0)
      `uvm_info(get_type_name(),
        $sformatf("Protocol checker: %0d checks passed, 0 errors", checks),
        UVM_LOW)
    else
      `uvm_warning(get_type_name(),
        $sformatf("Protocol checker: %0d errors out of %0d checks",
                  errors, checks))
  endfunction

endclass

`endif // AXI5_PROTOCOL_CHECKER_SVH
