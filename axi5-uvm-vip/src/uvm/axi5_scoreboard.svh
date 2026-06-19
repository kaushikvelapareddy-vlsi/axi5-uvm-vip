// -----------------------------------------------------------------------------
// axi5_scoreboard.svh : data-integrity scoreboard.
// Observes completed write and read transactions from the monitor, maintains a
// reference memory, and checks that read data matches previously written data.
// Handles per-beat addressing for FIXED/INCR/WRAP and write strobes.
// -----------------------------------------------------------------------------
`ifndef AXI5_SCOREBOARD_SVH
`define AXI5_SCOREBOARD_SVH

`uvm_analysis_imp_decl(_wr)
`uvm_analysis_imp_decl(_rd)

class axi5_scoreboard extends uvm_component;
  `uvm_component_utils(axi5_scoreboard)

  uvm_analysis_imp_wr #(axi5_seq_item, axi5_scoreboard) wr_imp;
  uvm_analysis_imp_rd #(axi5_seq_item, axi5_scoreboard) rd_imp;

  axi5_config   cfg;
  axi5_ref_mem  ref_mem;

  int unsigned writes_seen = 0;
  int unsigned reads_seen  = 0;
  int unsigned mismatches  = 0;
  int unsigned matched     = 0;
  int unsigned excl_checked = 0;
  int unsigned excl_resp_err = 0;

  // Exclusive-monitor model: a single outstanding reservation, set by an
  // exclusive read and cleared by any write to the reserved address.
  bit          excl_valid = 0;
  bit [63:0]   excl_addr  = 0;
  bit [`AXI5_ID_WIDTH-1:0] excl_id = 0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    wr_imp = new("wr_imp", this);
    rd_imp = new("rd_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db#(axi5_config)::get(this, "", "cfg", cfg));
    ref_mem = axi5_ref_mem::type_id::create("ref_mem");
  endfunction

  // ---- Write observed: update reference memory ------------------------------
  function void write_wr(axi5_seq_item t);
    writes_seen++;
    // Only model successful writes into reference memory.
    if (t.resp == AXI5_SLVERR || t.resp == AXI5_DECERR) return;

    // Exclusive-write response checking against the modelled reservation.
    if (t.lock == AXI5_EXCLUSIVE) begin
      axi5_resp_e exp = (excl_valid && excl_id == t.id && excl_addr == t.addr)
                          ? AXI5_EXOKAY : AXI5_OKAY;
      excl_checked++;
      if (t.resp != exp) begin
        excl_resp_err++;
        `uvm_error(get_type_name(), $sformatf(
          "EXCLUSIVE RESP MISMATCH id=0x%0h addr=0x%0h exp=%s got=%s",
          t.id, t.addr, exp.name(), t.resp.name()))
      end
      excl_valid = 0; // exclusive write clears the reservation
    end
    else begin
      // A normal write to the reserved location clears the reservation.
      if (excl_valid && excl_addr >= t.addr &&
          excl_addr < (t.addr + t.total_bytes()))
        excl_valid = 0;
    end

    // Atomic memory effects are modelled via the atomic ALU; plain writes use
    // strobed byte commits.
    if (t.atop != AXI5_ATOP_NONE) begin
      bit [63:0] a0 = t.beat_addr(0);
      ref_mem.apply_atomic(a0, t.atop, t.size, t.data[0],
                           (t.num_beats() > 1) ? t.data[1] : '0);
      return;
    end
    for (int b = 0; b < t.num_beats(); b++)
      ref_mem.apply_write_beat(t.beat_addr(b), t.data[b], t.strb[b], t.size);
  endfunction

  // ---- Read observed: compare against reference memory ----------------------
  function void write_rd(axi5_seq_item t);
    reads_seen++;
    if (t.resp == AXI5_SLVERR || t.resp == AXI5_DECERR) return;
    if (t.atop != AXI5_ATOP_NONE) return; // atomic read-back not modeled
    // An exclusive read installs a reservation.
    if (t.lock == AXI5_EXCLUSIVE) begin
      excl_valid = 1;
      excl_addr  = t.addr;
      excl_id    = t.id;
    end
    for (int b = 0; b < t.num_beats(); b++) begin
      bit [63:0] ba = t.beat_addr(b);
      // Only check bytes that have been previously written.
      int nb    = (1 << t.size);
      int lane0 = ba % (`AXI5_DATA_WIDTH/8);
      for (int byten = 0; byten < nb; byten++) begin
        bit [63:0] aa = ba + byten;
        int lane = lane0 + byten;
        if (lane >= (`AXI5_DATA_WIDTH/8)) continue;
        if (!ref_mem.exists(aa)) continue; // unknown -> skip
        begin
          byte unsigned exp = ref_mem.read_byte(aa);
          byte unsigned got = t.data[b][lane*8 +: 8];
          if (exp !== got) begin
            mismatches++;
            `uvm_error(get_type_name(), $sformatf(
              "READ DATA MISMATCH id=0x%0h addr=0x%0h beat=%0d byte=%0d exp=0x%02h got=0x%02h",
              t.id, aa, b, byten, exp, got))
          end
          else matched++;
        end
      end
    end
  endfunction

  function void report_phase(uvm_phase phase);
    if (mismatches == 0 && excl_resp_err == 0)
      `uvm_info(get_type_name(), $sformatf(
        "Scoreboard PASS: writes=%0d reads=%0d bytes_checked=%0d mismatches=0 excl_checked=%0d",
        writes_seen, reads_seen, matched, excl_checked), UVM_LOW)
    else
      `uvm_error(get_type_name(), $sformatf(
        "Scoreboard FAIL: %0d byte mismatches, %0d exclusive-resp errors (writes=%0d reads=%0d)",
        mismatches, excl_resp_err, writes_seen, reads_seen))
  endfunction

endclass

`endif // AXI5_SCOREBOARD_SVH
