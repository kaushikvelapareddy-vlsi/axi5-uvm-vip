// -----------------------------------------------------------------------------
// axi5_corner_seqs.svh : library of corner-case sequences exercising the AXI5
// legal-but-tricky transaction space. Each sequence targets a specific corner.
// -----------------------------------------------------------------------------
`ifndef AXI5_CORNER_SEQS_SVH
`define AXI5_CORNER_SEQS_SVH

// ---- 1. Narrow / unaligned transfers ---------------------------------------
class axi5_narrow_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_narrow_seq)
  function new(string name = "axi5_narrow_seq"); super.new(name); endfunction
  task body();
    for (int i = 0; i < num_txns; i++) begin
      axi5_seq_item it = axi5_seq_item::type_id::create($sformatf("nw%0d", i));
      start_item(it);
      // Force size smaller than the bus to create narrow transfers.
      if (!it.randomize() with {
            dir   == AXI5_WRITE;
            atop  == AXI5_ATOP_NONE;
            lock  == AXI5_NORMAL;
            size  inside {0, 1};
            burst == AXI5_INCR;
            addr inside {[base_addr : base_addr + addr_span - 1]};
          })
        `uvm_error(get_type_name(), "narrow randomize failed")
      finish_item(it);
    end
  endtask
endclass

// ---- 2. WRAP bursts at all legal lengths -----------------------------------
class axi5_wrap_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_wrap_seq)
  function new(string name = "axi5_wrap_seq"); super.new(name); endfunction
  task body();
    bit [7:0] lens[4] = '{1, 3, 7, 15};
    foreach (lens[k]) begin
      axi5_seq_item it = axi5_seq_item::type_id::create($sformatf("wp%0d", k));
      start_item(it);
      if (!it.randomize() with {
            dir   == AXI5_WRITE;
            atop  == AXI5_ATOP_NONE;
            lock  == AXI5_NORMAL;
            burst == AXI5_WRAP;
            it.len == lens[k];
            addr inside {[base_addr : base_addr + addr_span - 1]};
          })
        `uvm_error(get_type_name(), "wrap randomize failed")
      finish_item(it);
    end
  endtask
endclass

// ---- 3. Maximum-length INCR bursts (256 beats) -----------------------------
class axi5_maxlen_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_maxlen_seq)
  function new(string name = "axi5_maxlen_seq"); super.new(name); endfunction
  task body();
    axi5_seq_item it = axi5_seq_item::type_id::create("maxlen");
    start_item(it);
    if (!it.randomize() with {
          dir   == AXI5_WRITE;
          atop  == AXI5_ATOP_NONE;
          lock  == AXI5_NORMAL;
          burst == AXI5_INCR;
          it.len  == 8'd255;
          it.size == 0;                 // keep within 4KB with small size
          addr == base_addr;
        })
      `uvm_error(get_type_name(), "maxlen randomize failed")
    finish_item(it);
  endtask
endclass

// ---- 4. Single-beat (len==0) transfers -------------------------------------
class axi5_single_beat_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_single_beat_seq)
  function new(string name = "axi5_single_beat_seq"); super.new(name); endfunction
  task body();
    for (int i = 0; i < num_txns; i++) begin
      do_write(base_addr + (i*8), 8'd0, 3);
      do_read (base_addr + (i*8), 8'd0, 3);
    end
  endtask
endclass

// ---- 5. 4KB-boundary edge bursts -------------------------------------------
class axi5_4kb_edge_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_4kb_edge_seq)
  function new(string name = "axi5_4kb_edge_seq"); super.new(name); endfunction
  task body();
    // End exactly on the 4KB boundary: addr = boundary - total_bytes.
    bit [63:0] boundary = (base_addr & ~64'hFFF) + 64'h1000;
    bit [2:0]  size = 3;            // 8 bytes
    bit [7:0]  len  = 8'd7;         // 8 beats * 8 = 64 bytes
    bit [63:0] a    = boundary - 64;
    do_write(a, len, size, AXI5_INCR);
    do_read (a, len, size, AXI5_INCR);
  endtask
endclass

// ---- 6. Exclusive access pass / fail pair ----------------------------------
class axi5_exclusive_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_exclusive_seq)
  function new(string name = "axi5_exclusive_seq"); super.new(name); endfunction
  task body();
    bit [63:0] a = base_addr & ~64'h7; // 8-byte aligned
    // Exclusive read followed by an exclusive write to the SAME id and address.
    // The shared id is required for the reservation to hold so the write earns
    // EXOKAY (the exclusive monitor keys the reservation on the transaction id).
    bit [`AXI5_ID_WIDTH-1:0] xid = 'h3;
    begin
      axi5_seq_item er = axi5_seq_item::type_id::create("excl_rd");
      start_item(er);
      if (!er.randomize() with {
            dir == AXI5_READ; lock == AXI5_EXCLUSIVE; er.id == xid;
            burst == AXI5_INCR; er.addr == a; er.len == 0; er.size == 3;
          })
        `uvm_error(get_type_name(), "excl read randomize failed")
      finish_item(er);
      wait (er.completed == 1);
    end
    begin
      axi5_seq_item ew = axi5_seq_item::type_id::create("excl_wr");
      start_item(ew);
      if (!ew.randomize() with {
            dir == AXI5_WRITE; lock == AXI5_EXCLUSIVE; atop == AXI5_ATOP_NONE;
            ew.id == xid;
            burst == AXI5_INCR; ew.addr == a; ew.len == 0; ew.size == 3;
          })
        `uvm_error(get_type_name(), "excl write randomize failed")
      finish_item(ew);
      wait (ew.completed == 1);
    end
  endtask
endclass

// ---- 7. Atomic transactions (AXI5) -----------------------------------------
// Seeds a known value, applies an atomic op, then reads back so the scoreboard
// (which models the same ALU independently) can verify the memory effect.
class axi5_atomic_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_atomic_seq)
  function new(string name = "axi5_atomic_seq"); super.new(name); endfunction

  // Issue an atomic write with an explicit operand (and swap value for
  // Compare), then block until its B response is observed.
  task automatic atomic_op(bit [63:0] a, axi5_atop_e op,
                           bit [63:0] operand, bit [63:0] swap_val,
                           bit [2:0] sz = 3'd3);
    bit [7:0] alen = (op == AXI5_ATOP_COMPARE) ? 8'd1 : 8'd0;
    axi5_seq_item it = axi5_seq_item::type_id::create("atomic");
    start_item(it);
    if (!it.randomize() with {
          dir == AXI5_WRITE; lock == AXI5_NORMAL; burst == AXI5_INCR;
          atop == op; it.addr == a; it.size == local::sz; it.len == alen;
        })
      `uvm_error(get_type_name(), "atomic randomize failed")
    it.data[0] = operand;                 // operand / compare value (8B aligned)
    if (alen > 0) it.data[1] = swap_val;  // swap value for AtomicCompare
    begin // strobe only the active byte lanes within each beat
      int nb   = (1 << sz);
      int lane0 = a % (`AXI5_DATA_WIDTH/8);
      foreach (it.strb[b]) it.strb[b] = (((1 << nb) - 1) << lane0);
    end
    finish_item(it);
    wait (it.completed == 1);
  endtask

  // Seed a fully-defined value (active byte window) with all strobes set. A
  // partially-strobed (random) seed would leave bytes uninitialised (X) in the
  // DUT memory, which then poisons arithmetic atomics (ADD/min/max) via carry/
  // comparison across the whole word. A full-width known seed makes the
  // atomic operate on a defined value so the model and DUT agree.
  task automatic seed_write(bit [63:0] a, bit [63:0] val, bit [2:0] sz = 3'd3);
    axi5_seq_item it = axi5_seq_item::type_id::create("seed");
    start_item(it);
    if (!it.randomize() with {
          dir == AXI5_WRITE; lock == AXI5_NORMAL; atop == AXI5_ATOP_NONE;
          burst == AXI5_INCR; it.addr == a; it.size == local::sz; it.len == 0;
        })
      `uvm_error(get_type_name(), "seed randomize failed")
    it.data[0] = val;
    begin // strobe only the active byte lanes within each beat
      int nb   = (1 << sz);
      int lane0 = a % (`AXI5_DATA_WIDTH/8);
      foreach (it.strb[b]) it.strb[b] = (((1 << nb) - 1) << lane0);
    end
    finish_item(it);
    wait (it.completed == 1);
  endtask

  task body();
    // Full opcode sweep: every AtomicStore/AtomicLoad variant plus Swap and
    // Compare, so cp_atop (and x_atop_size) is fully exercised.
    axi5_atop_e ops[] = '{AXI5_ATOP_STORE_ADD,  AXI5_ATOP_STORE_CLR,
                          AXI5_ATOP_STORE_EOR,  AXI5_ATOP_STORE_SET,
                          AXI5_ATOP_STORE_SMAX, AXI5_ATOP_STORE_SMIN,
                          AXI5_ATOP_STORE_UMAX, AXI5_ATOP_STORE_UMIN,
                          AXI5_ATOP_LOAD_ADD,   AXI5_ATOP_LOAD_CLR,
                          AXI5_ATOP_LOAD_EOR,   AXI5_ATOP_LOAD_SET,
                          AXI5_ATOP_LOAD_SMAX,  AXI5_ATOP_LOAD_SMIN,
                          AXI5_ATOP_LOAD_UMAX,  AXI5_ATOP_LOAD_UMIN,
                          AXI5_ATOP_SWAP,       AXI5_ATOP_COMPARE};
    foreach (ops[k]) begin
      bit [63:0] a       = (base_addr + (k*16)) & ~64'h7; // 8B aligned, spaced
      bit [63:0] operand = 64'h0000_0000_0000_0010 + k;
      // Seed a known, fully-defined value via a normal write (all strobes set).
      seed_write(a, 64'hA5A5_0000_0000_1234 + (k << 8));
      // Apply the atomic op (swap value only used by AtomicCompare).
      atomic_op(a, ops[k], operand, ~operand);
      // Read back so the scoreboard verifies the post-atomic memory.
      do_read_blocking(a, 8'd0, 3'd3);
    end

    // Atomic size sweep: exercise every opcode at 1/2/4-byte sizes too, so the
    // x_atop_size cross (atop x size) is fully closed. Each uses an aligned
    // address, a size-appropriate seed, and a read-back for end-to-end check.
    for (int s = 0; s <= 2; s++) begin
      foreach (ops[k]) begin
        bit [2:0]  sz = s[2:0];
        int        nb = (1 << s);
        bit [63:0] a  = (base_addr + 64'h200 + (k*16)) & ~(64'(nb) - 1);
        bit [63:0] operand = (64'h11 + k) & ((64'h1 << (nb*8)) - 1);
        seed_write(a, (64'h5A + (k << 4)) & ((64'h1 << (nb*8)) - 1), sz);
        atomic_op(a, ops[k], operand, ~operand, sz);
        do_read_blocking(a, 8'd0, sz);
      end
    end
  endtask
endclass

// ---- 7b. Exclusive-fail: an intervening normal write clears the reservation,
//          so the following exclusive write must return OKAY (not EXOKAY). ----
class axi5_exclusive_fail_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_exclusive_fail_seq)
  function new(string name = "axi5_exclusive_fail_seq"); super.new(name); endfunction
  task body();
    bit [63:0] a = base_addr & ~64'h7; // 8-byte aligned
    // Exclusive read installs the reservation.
    begin
      axi5_seq_item er = axi5_seq_item::type_id::create("xf_rd");
      start_item(er);
      if (!er.randomize() with {
            dir == AXI5_READ; lock == AXI5_EXCLUSIVE;
            burst == AXI5_INCR; er.addr == a; er.len == 0; er.size == 3;
          })
        `uvm_error(get_type_name(), "excl-fail read randomize failed")
      finish_item(er);
      wait (er.completed == 1);
    end
    // Intervening NORMAL write to the same address clears the reservation.
    do_write_blocking(a, 8'd0, 3'd3);
    // Exclusive write now must fail (OKAY). Scoreboard checks the response.
    begin
      axi5_seq_item ew = axi5_seq_item::type_id::create("xf_wr");
      start_item(ew);
      if (!ew.randomize() with {
            dir == AXI5_WRITE; lock == AXI5_EXCLUSIVE; atop == AXI5_ATOP_NONE;
            burst == AXI5_INCR; ew.addr == a; ew.len == 0; ew.size == 3;
          })
        `uvm_error(get_type_name(), "excl-fail write randomize failed")
      finish_item(ew);
      wait (ew.completed == 1);
    end
  endtask
endclass

// ---- 8. Write-strobe holes (sparse strobes) --------------------------------
class axi5_strobe_holes_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_strobe_holes_seq)
  function new(string name = "axi5_strobe_holes_seq"); super.new(name); endfunction
  task body();
    for (int i = 0; i < num_txns; i++) begin
      axi5_seq_item it = axi5_seq_item::type_id::create($sformatf("sh%0d", i));
      start_item(it);
      if (!it.randomize() with {
            dir   == AXI5_WRITE;
            atop  == AXI5_ATOP_NONE;
            lock  == AXI5_NORMAL;
            burst == AXI5_INCR;
            it.size == 3;
            addr inside {[base_addr : base_addr + addr_span - 1]};
          })
        `uvm_error(get_type_name(), "strobe-holes randomize failed")
      // Punch holes: clear alternate strobe bits.
      foreach (it.strb[b]) it.strb[b] &= (`AXI5_DATA_WIDTH/8)'('h55);
      finish_item(it);
    end
  endtask
endclass

// ---- 8b. Error responses: SLVERR (error window) and DECERR (out of range) --
// Exercises the response-error paths for both reads and writes, and for both
// normal and exclusive accesses, to close the response-coverage crosses.
class axi5_error_resp_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_error_resp_seq)
  function new(string name = "axi5_error_resp_seq"); super.new(name); endfunction

  // Issue one exclusive access (read or write) to a fixed address and block.
  task automatic excl_access(axi5_dir_e d, bit [63:0] a);
    axi5_seq_item it = axi5_seq_item::type_id::create("excl_err");
    start_item(it);
    if (!it.randomize() with {
          dir == local::d; lock == AXI5_EXCLUSIVE; atop == AXI5_ATOP_NONE;
          burst == AXI5_INCR; it.addr == a; it.len == 0; it.size == 3;
        })
      `uvm_error(get_type_name(), "excl-error randomize failed")
    finish_item(it);
    wait (it.completed == 1);
  endtask

  task body();
    // SLVERR window = top 256 bytes of the DUT's 64 KB memory; out-of-range
    // addresses return DECERR. (Mirror of axi5_slave_mem SLVERR_BASE/MEM_BYTES.)
    bit [63:0] slverr_a = 64'h0000_FF00;  // in range, error window -> SLVERR
    bit [63:0] decerr_a = 64'h0001_0000;  // beyond 64 KB         -> DECERR

    // SLVERR: normal write/read then exclusive read/write.
    do_write_blocking(slverr_a, 8'd0, 3'd3);
    do_read_blocking (slverr_a, 8'd0, 3'd3);
    excl_access(AXI5_READ,  slverr_a);
    excl_access(AXI5_WRITE, slverr_a);

    // DECERR: normal write/read then exclusive read/write.
    do_write_blocking(decerr_a, 8'd0, 3'd3);
    do_read_blocking (decerr_a, 8'd0, 3'd3);
    excl_access(AXI5_READ,  decerr_a);
    excl_access(AXI5_WRITE, decerr_a);
  endtask
endclass

// ---- 8c. Miscellaneous coverage closers ------------------------------------
// Closes three residual coverage bins:
//   * cp_burst.fixed   -> FIXED-burst reads (issued to a fresh, never-written
//                         address so the scoreboard skips data comparison and
//                         the result is independent of DUT FIXED data ordering),
//                         swept across sizes to also fill x_burst_size cells.
//   * cp_strb.all_zero -> a write with every strobe lane cleared (commits no
//                         bytes; no scoreboard mismatch).
//   * cp_4kb_edge.on_edge -> extra INCR bursts that end exactly on a 4 KB
//                         boundary, at several size/len combinations.
class axi5_misc_cover_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_misc_cover_seq)
  function new(string name = "axi5_misc_cover_seq"); super.new(name); endfunction
  task body();
    bit [63:0] boundary = (base_addr & ~64'hFFF) + 64'h1000;

    // FIXED-burst reads across all legal sizes (fresh address region).
    for (int s = 0; s <= 3; s++) begin
      axi5_seq_item it = axi5_seq_item::type_id::create($sformatf("fix%0d", s));
      start_item(it);
      if (!it.randomize() with {
            dir   == AXI5_READ;
            burst == AXI5_FIXED;
            lock  == AXI5_NORMAL;
            it.size == local::s;
            it.len  == 8'd1;
            it.addr == (base_addr + 64'h800);
          })
        `uvm_error(get_type_name(), "fixed-read randomize failed")
      finish_item(it);
    end

    // All-strobes-zero write (commits nothing, exercises cp_strb.all_zero).
    begin
      axi5_seq_item it = axi5_seq_item::type_id::create("azw");
      start_item(it);
      if (!it.randomize() with {
            dir   == AXI5_WRITE;
            atop  == AXI5_ATOP_NONE;
            lock  == AXI5_NORMAL;
            burst == AXI5_INCR;
            it.size == 3;
            it.len  == 8'd1;
            it.addr == base_addr;
          })
        `uvm_error(get_type_name(), "all-zero-strobe randomize failed")
      foreach (it.strb[b]) it.strb[b] = '0;
      finish_item(it);
    end

    // WRAP burst at 8-byte size to close x_burst_size[wrap][b8]. WRAP needs a
    // power-of-two beat count and an address aligned to the total byte count
    // (2 beats * 8 B = 16 B -> 16-byte-aligned address).
    begin
      axi5_seq_item it = axi5_seq_item::type_id::create("wrap8");
      start_item(it);
      if (!it.randomize() with {
            dir   == AXI5_READ;
            burst == AXI5_WRAP;
            lock  == AXI5_NORMAL;
            it.size == 3;
            it.len  == 8'd1;                       // 2 beats
            it.addr == ((base_addr + 64'h200) & ~64'hF);
          })
        `uvm_error(get_type_name(), "wrap8 randomize failed")
      finish_item(it);
    end

    // Strobe x size sweep: a full-strobe and an all-zero-strobe write at each
    // of the narrow sizes (1/2/4 B) to close the x_strb_size cross cells
    // [full,all_zero] x [b1,b2,b4]. All-zero writes commit nothing; full
    // writes commit but are not read back, so neither perturbs the scoreboard.
    for (int s = 0; s <= 2; s++) begin
      bit [63:0] sa = (base_addr + 64'h300 + (s * 64'h20)) & ~((64'h1 << s) - 1);
      // full-strobe write (all active lanes in the size window set)
      begin
        axi5_seq_item it = axi5_seq_item::type_id::create($sformatf("full%0d", s));
        start_item(it);
        if (!it.randomize() with {
              dir == AXI5_WRITE; atop == AXI5_ATOP_NONE; lock == AXI5_NORMAL;
              burst == AXI5_INCR; it.size == local::s; it.len == 8'd0;
              it.addr == local::sa;
            })
          `uvm_error(get_type_name(), "full-strb randomize failed")
        begin // set every active byte lane in the size window (true "full")
          int nb    = (1 << s);
          int lane0 = sa % (`AXI5_DATA_WIDTH/8);
          foreach (it.strb[b]) it.strb[b] = (((1 << nb) - 1) << lane0);
        end
        finish_item(it);
      end
      // all-zero-strobe write
      begin
        axi5_seq_item it = axi5_seq_item::type_id::create($sformatf("zero%0d", s));
        start_item(it);
        if (!it.randomize() with {
              dir == AXI5_WRITE; atop == AXI5_ATOP_NONE; lock == AXI5_NORMAL;
              burst == AXI5_INCR; it.size == local::s; it.len == 8'd0;
              it.addr == local::sa;
            })
          `uvm_error(get_type_name(), "zero-strb randomize failed")
        foreach (it.strb[b]) it.strb[b] = '0;
        finish_item(it);
      end
    end

    // Extra on-edge INCR bursts ending exactly on the 4 KB boundary.
    do_read(boundary - 64'd64, 8'd7, 3'd3, AXI5_INCR); // 8x8B
    do_read(boundary - 64'd8,  8'd0, 3'd3, AXI5_INCR); // 1x8B
    do_read(boundary - 64'd4,  8'd0, 3'd2, AXI5_INCR); // 1x4B
  endtask
endclass

// ---- 8d. Burst matrix: directed FIXED and WRAP bursts across every legal
//          length-bin x size combination, to close the x_len_size_burst cross
//          cells for the non-INCR bursts (INCR is already saturated by the
//          random/4KB/single traffic). All are reads to a fresh, never-written
//          address region so the scoreboard skips data comparison and no false
//          mismatches arise.
class axi5_burst_matrix_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_burst_matrix_seq)
  function new(string name = "axi5_burst_matrix_seq"); super.new(name); endfunction
  task body();
    // One representative length per cp_len short-bin: 0=single, 2=[01:03],
    // 5=[04:06], 8=[07:09], 12=[0a:0f]. FIXED permits any AxLEN 0..15.
    int fixed_lens[] = '{0, 2, 5, 8, 12};
    // WRAP only permits AxLEN {1,3,7,15} (2/4/8/16 beats); 1 and 3 share the
    // short_len[01:03] bin, so {1,7,15} reaches all three wrap-able len bins.
    int wrap_lens[]  = '{1, 7, 15};

    // FIXED sweep: every (length-bin x size) cell.
    foreach (fixed_lens[i]) begin
      for (int s = 0; s <= 3; s++) begin
        int        ln = fixed_lens[i];
        bit [63:0] a  = (base_addr + (i * 64'h40) + (s * 64'h8))
                        & ~((64'h1 << s) - 1);          // align to transfer size
        axi5_seq_item it =
          axi5_seq_item::type_id::create($sformatf("fx_l%0d_s%0d", ln, s));
        start_item(it);
        if (!it.randomize() with {
              dir == AXI5_READ; burst == AXI5_FIXED; lock == AXI5_NORMAL;
              atop == AXI5_ATOP_NONE;
              it.size == local::s; it.len == local::ln; it.addr == local::a;
            })
          `uvm_error(get_type_name(), "fixed-matrix randomize failed")
        finish_item(it);
      end
    end

    // WRAP sweep: every (wrap length-bin x size) cell. Aligning the address to
    // the total transfer size (beats * bytes) keeps the wrap region well-formed.
    foreach (wrap_lens[i]) begin
      for (int s = 0; s <= 3; s++) begin
        int        ln    = wrap_lens[i];
        int        total = (1 << s) * (ln + 1);
        bit [63:0] a     = (base_addr + 64'h800 + (i * 64'h200) + (s * 64'h80))
                           & ~(64'(total) - 1);
        axi5_seq_item it =
          axi5_seq_item::type_id::create($sformatf("wr_l%0d_s%0d", ln, s));
        start_item(it);
        if (!it.randomize() with {
              dir == AXI5_READ; burst == AXI5_WRAP; lock == AXI5_NORMAL;
              atop == AXI5_ATOP_NONE;
              it.size == local::s; it.len == local::ln; it.addr == local::a;
            })
          `uvm_error(get_type_name(), "wrap-matrix randomize failed")
        finish_item(it);
      end
    end

    // INCR sweep: directed (len,size) pairs that the random INCR traffic does
    // not reliably hit, closing the remaining x_len_size_burst INCR cells. All
    // start 4KB-aligned at base_addr so (addr & 0xFFF)+total <= 4KB holds.
    begin
      int incr_len[]  = '{255, 255, 56, 112, 8, 12, 12, 5, 5, 5, 5};
      int incr_size[] = '{3,   1,   1,  0,   2,  2,  0,  0, 1, 2, 3};
      foreach (incr_len[i]) begin
        int        ln = incr_len[i];
        int        sz = incr_size[i];
        axi5_seq_item it =
          axi5_seq_item::type_id::create($sformatf("in_l%0d_s%0d", ln, sz));
        start_item(it);
        if (!it.randomize() with {
              dir == AXI5_READ; burst == AXI5_INCR; lock == AXI5_NORMAL;
              atop == AXI5_ATOP_NONE;
              it.size == local::sz; it.len == local::ln;
              it.addr == local::base_addr;          // 4KB-aligned region base
            })
          `uvm_error(get_type_name(), "incr-matrix randomize failed")
        finish_item(it);
      end
    end
  endtask
endclass

// ---- 9. Back-to-back zero-delay traffic ------------------------------------
class axi5_zero_delay_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_zero_delay_seq)
  function new(string name = "axi5_zero_delay_seq"); super.new(name); endfunction
  task body();
    for (int i = 0; i < num_txns; i++) begin
      axi5_seq_item it = axi5_seq_item::type_id::create($sformatf("zd%0d", i));
      start_item(it);
      if (!it.randomize() with {
            dir   == AXI5_WRITE;
            atop  == AXI5_ATOP_NONE;
            lock  == AXI5_NORMAL;
            burst == AXI5_INCR;
            addr_delay == 0;
            foreach (data_delay[j]) data_delay[j] == 0;
            addr inside {[base_addr : base_addr + addr_span - 1]};
          })
        `uvm_error(get_type_name(), "zero-delay randomize failed")
      finish_item(it);
    end
  endtask
endclass

// ---- 10. Interleaved multi-ID outstanding traffic --------------------------
class axi5_interleaved_id_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_interleaved_id_seq)
  function new(string name = "axi5_interleaved_id_seq"); super.new(name); endfunction
  task body();
    for (int i = 0; i < num_txns; i++) begin
      axi5_seq_item it = axi5_seq_item::type_id::create($sformatf("il%0d", i));
      start_item(it);
      if (!it.randomize() with {
            dir   == AXI5_WRITE;
            atop  == AXI5_ATOP_NONE;
            lock  == AXI5_NORMAL;
            burst == AXI5_INCR;
            it.id  == (i % (1 << `AXI5_ID_WIDTH));
            addr inside {[base_addr : base_addr + addr_span - 1]};
          })
        `uvm_error(get_type_name(), "interleaved-id randomize failed")
      finish_item(it);
    end
  endtask
endclass

`endif // AXI5_CORNER_SEQS_SVH
