// -----------------------------------------------------------------------------
// axi5_coverage.svh : functional coverage collector.
// Subscribes to the monitor's analysis port and samples per-transaction
// covergroups with corner-case bins and cross-coverage.
// -----------------------------------------------------------------------------
`ifndef AXI5_COVERAGE_SVH
`define AXI5_COVERAGE_SVH

class axi5_coverage extends uvm_subscriber #(axi5_seq_item);
  `uvm_component_utils(axi5_coverage)

  axi5_config   cfg;
  axi5_seq_item tr;

  // Strobe classification of the sampled write transaction (computed in write):
  //   0 = all lanes disabled, 1 = all active lanes enabled (full),
  //   2 = partial / sparse (strobe holes).
  bit [1:0]     strb_class;

  // ---- Address-phase coverage -----------------------------------------------
  covergroup cg_addr_phase;
    option.per_instance = 1;

    cp_dir   : coverpoint tr.dir;
    cp_len   : coverpoint tr.len {
      bins single        = {0};
      bins short_len[4]  = {[1:15]};
      bins mid_len[4]    = {[16:127]};
      bins long_len[4]   = {[128:254]};
      bins max_incr      = {255};
    }
    cp_size  : coverpoint tr.size {
      bins b1   = {0};  bins b2   = {1};  bins b4  = {2};  bins b8 = {3};
      bins b16  = {4};  bins b32  = {5};  bins b64 = {6};  bins b128 = {7};
      // Transfer sizes wider than the data bus are illegal (forbidden by the
      // item constraints and SVA); ignore the unreachable upper bins so the
      // score reflects the configured bus width.
      ignore_bins too_wide = {[$clog2(`AXI5_DATA_WIDTH/8)+1 : 7]};
    }
    cp_burst : coverpoint tr.burst {
      bins fixed = {AXI5_FIXED};
      bins incr  = {AXI5_INCR};
      bins wrap  = {AXI5_WRAP};
      illegal_bins rsvd = {AXI5_BURST_RSVD};
    }
    // WRAP burst legal lengths (awlen in {1,3,7,15} => 2/4/8/16 beats). Only
    // meaningful when burst==WRAP; crossed below.
    cp_wrap_len : coverpoint tr.len iff (tr.burst == AXI5_WRAP) {
      bins wrap2  = {1};
      bins wrap4  = {3};
      bins wrap8  = {7};
      bins wrap16 = {15};
    }
    cp_lock  : coverpoint tr.lock;
    cp_atop  : coverpoint tr.atop {
      bins none      = {AXI5_ATOP_NONE};
      bins store[]   = {[AXI5_ATOP_STORE_ADD:AXI5_ATOP_STORE_UMIN]};
      bins load[]    = {[AXI5_ATOP_LOAD_ADD:AXI5_ATOP_LOAD_UMIN]};
      bins swap      = {AXI5_ATOP_SWAP};
      bins compare   = {AXI5_ATOP_COMPARE};
    }
    cp_qos   : coverpoint tr.qos {
      bins low  = {[0:3]};
      bins med  = {[4:11]};
      bins high = {[12:15]};
    }
    cp_region: coverpoint tr.region;
    cp_id    : coverpoint tr.id;

    // 4KB-edge corner: INCR transfers that end exactly on a 4KB boundary.
    cp_4kb_edge : coverpoint
      ((tr.addr & 64'hFFF) + tr.total_bytes() == 64'h1000) {
      bins on_edge  = {1};
      bins off_edge = {0};
    }
    // Unaligned start address.
    cp_unaligned : coverpoint ((tr.addr % tr.total_bytes()) != 0) {
      bins aligned   = {0};
      bins unaligned = {1};
    }

    // Write-strobe pattern coverage (writes only): full vs sparse vs none.
    cp_strb : coverpoint strb_class iff (tr.dir == AXI5_WRITE) {
      bins all_zero = {0};
      bins full     = {1};
      bins partial  = {2};
    }

    // ---- Cross coverage -----------------------------------------------------
    x_len_size_burst : cross cp_len, cp_size, cp_burst {
      // FIXED bursts are limited to 16 beats (AxLEN 0..15); any encoded length
      // of 16 beats or more is illegal for a FIXED burst (AXI5 A3.4.1).
      illegal_bins fixed_len_too_long =
          binsof(cp_burst.fixed) && binsof(cp_len) intersect {[16:255]};
      // WRAP bursts only permit 2/4/8/16-beat transfers, i.e. AxLEN in
      // {1,3,7,15} (AXI5 A3.4.1). len==0, len in {4,5,6}, and any len >= 16 are
      // illegal for WRAP. (Lengths 2 / 8,9 / 10..14 share auto-bins with the
      // legal 1,3 / 7 / 15 values, so those bins stay in the legal cross.)
      illegal_bins wrap_len_illegal =
          binsof(cp_burst.wrap) &&
          binsof(cp_len) intersect {0, [4:6], [16:255]};
    }
    x_dir_lock       : cross cp_dir, cp_lock;
    x_atop_size      : cross cp_atop, cp_size;
    x_burst_size     : cross cp_burst, cp_size;
    x_strb_size      : cross cp_strb, cp_size;
  endgroup

  // ---- Response-phase coverage ----------------------------------------------
  covergroup cg_resp;
    option.per_instance = 1;
    cp_resp : coverpoint tr.resp {
      bins okay   = {AXI5_OKAY};
      bins exokay = {AXI5_EXOKAY};
      bins slverr = {AXI5_SLVERR};
      bins decerr = {AXI5_DECERR};
    }
    cp_dir  : coverpoint tr.dir;
    cp_lock : coverpoint tr.lock;
    // Exclusive responses: EXOKAY only legal for exclusive accesses.
    x_resp_lock : cross cp_resp, cp_lock {
      // EXOKAY on a non-exclusive (NORMAL) access is illegal -> unreachable.
      ignore_bins exokay_normal =
        binsof(cp_resp.exokay) && binsof(cp_lock) intersect {AXI5_NORMAL};
    }
    x_resp_dir  : cross cp_resp, cp_dir;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_addr_phase = new();
    cg_resp       = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db#(axi5_config)::get(this, "", "cfg", cfg));
  endfunction

  function void write(axi5_seq_item t);
    tr = t;
    // Classify the write-strobe pattern across all beats for cp_strb.
    if (t.dir == AXI5_WRITE && t.strb.size() > 0) begin
      int unsigned nb        = (1 << t.size);
      bit          any_zero  = 0;
      bit          any_one   = 0;
      foreach (t.strb[b]) begin
        int lane0 = t.beat_addr(b) % (`AXI5_DATA_WIDTH/8);
        for (int i = 0; i < nb; i++) begin
          int lane = lane0 + i;
          if (lane < (`AXI5_DATA_WIDTH/8)) begin
            if (t.strb[b][lane]) any_one = 1; else any_zero = 1;
          end
        end
      end
      strb_class = !any_one ? 2'd0 : (any_zero ? 2'd2 : 2'd1);
    end
    else strb_class = 2'd0;
    cg_addr_phase.sample();
    cg_resp.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf(
      "Coverage: addr_phase=%0.2f%% resp=%0.2f%%",
      cg_addr_phase.get_inst_coverage(),
      cg_resp.get_inst_coverage()), UVM_LOW)
  endfunction

endclass

`endif // AXI5_COVERAGE_SVH
