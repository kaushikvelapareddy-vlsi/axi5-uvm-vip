// -----------------------------------------------------------------------------
// axi5_seq_item.svh : the AXI5 transaction object.
// One item models a full burst (address phase + N data beats + response).
// -----------------------------------------------------------------------------
`ifndef AXI5_SEQ_ITEM_SVH
`define AXI5_SEQ_ITEM_SVH

class axi5_seq_item extends uvm_sequence_item;

  // ---- Direction ------------------------------------------------------------
  rand axi5_dir_e               dir;

  // ---- Address-phase attributes (AW/AR) -------------------------------------
  rand bit [63:0]               addr;
  rand bit [`AXI5_ID_WIDTH-1:0] id;
  rand bit [7:0]                len;        // beats-1 (0..255)
  rand bit [2:0]                size;       // 0..7 -> 1..128 bytes
  rand axi5_burst_e             burst;
  rand axi5_lock_e              lock;
  rand bit [3:0]                cache;
  rand bit [2:0]                prot;
  rand bit [3:0]                qos;
  rand bit [3:0]                region;
  rand axi5_atop_e              atop;       // write only
  rand bit                      unique_hint;
  rand bit                      trace;
  rand bit [3:0]                loop_tag;

  // ---- Data payload (per beat) ----------------------------------------------
  rand bit [`AXI5_DATA_WIDTH-1:0]   data[];
  rand bit [`AXI5_DATA_WIDTH/8-1:0] strb[];   // write strobes per beat

  // ---- Response -------------------------------------------------------------
  axi5_resp_e                   resp;        // B (write) or last-beat R
  axi5_resp_e                   rresp_beat[]; // per-beat read response

  // Completion flag: set by the master driver's response collector when the
  // B (write) or final R (read) response has been received. Sequences that
  // require a strict happens-before (e.g. write-then-read-back integrity
  // checks) can wait on this after finish_item().
  bit                           completed;

  // ---- User sidebands -------------------------------------------------------
  rand bit [`AXI5_USER_WIDTH-1:0] awuser;
  rand bit [`AXI5_USER_WIDTH-1:0] aruser;
  rand bit [`AXI5_USER_WIDTH-1:0] wuser[];
  bit      [`AXI5_USER_WIDTH-1:0] buser;
  bit      [`AXI5_USER_WIDTH-1:0] ruser[];

  // ---- Timing controls (driver back-pressure) -------------------------------
  rand int unsigned             addr_delay;   // cycles of valid stall, addr ch
  rand int unsigned             data_delay[]; // per-beat data valid stall
  rand int unsigned             resp_ready_delay;

  `uvm_object_utils_begin(axi5_seq_item)
    `uvm_field_enum(axi5_dir_e, dir, UVM_ALL_ON)
    `uvm_field_int (addr,   UVM_ALL_ON | UVM_HEX)
    `uvm_field_int (id,     UVM_ALL_ON)
    `uvm_field_int (len,    UVM_ALL_ON)
    `uvm_field_int (size,   UVM_ALL_ON)
    `uvm_field_enum(axi5_burst_e, burst, UVM_ALL_ON)
    `uvm_field_enum(axi5_lock_e,  lock,  UVM_ALL_ON)
    `uvm_field_int (cache,  UVM_ALL_ON)
    `uvm_field_int (prot,   UVM_ALL_ON)
    `uvm_field_int (qos,    UVM_ALL_ON)
    `uvm_field_int (region, UVM_ALL_ON)
    `uvm_field_enum(axi5_atop_e, atop, UVM_ALL_ON)
    `uvm_field_array_int(data, UVM_ALL_ON | UVM_HEX)
    `uvm_field_array_int(strb, UVM_ALL_ON | UVM_HEX)
    `uvm_field_enum(axi5_resp_e, resp, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "axi5_seq_item");
    super.new(name);
  endfunction

  // ---------------------------------------------------------------------------
  // Constraints encoding the AXI5 legal transaction space.
  // ---------------------------------------------------------------------------
  // Size must not exceed the data-bus width.
  constraint c_size_bus {
    (1 << size) <= (`AXI5_DATA_WIDTH/8);
  }

  // Burst-length rules.
  constraint c_len {
    // FIXED and WRAP: max 16 beats. INCR: up to 256.
    (burst == AXI5_FIXED) -> (len inside {[0:15]});
    (burst == AXI5_WRAP)  -> (len inside {1, 3, 7, 15}); // WRAP: 2,4,8,16 beats
    (burst == AXI5_INCR)  -> (len inside {[0:255]});
    burst != AXI5_BURST_RSVD;
  }

  // WRAP bursts must be aligned to the transfer size.
  constraint c_wrap_align {
    (burst == AXI5_WRAP) -> ((addr % (1 << size)) == 0);
  }

  // INCR bursts must not cross a 4KB boundary (A3.4.1).
  constraint c_4kb {
    (burst == AXI5_INCR) ->
      ((addr & 64'hFFF) + ((1 << size) * (len + 1)) <= 64'h1000);
  }

  // Exclusive-access constraints (A7.2): power-of-two length, <= 128 bytes
  // total, address aligned to the total number of bytes.
  constraint c_exclusive {
    (lock == AXI5_EXCLUSIVE) -> (burst != AXI5_FIXED);
    (lock == AXI5_EXCLUSIVE) -> (len inside {0, 1, 3, 7, 15});
    (lock == AXI5_EXCLUSIVE) -> (((1 << size) * (len + 1)) <= 128);
    (lock == AXI5_EXCLUSIVE) ->
      ((addr % ((1 << size) * (len + 1))) == 0);
    // Atomics cannot be exclusive.
    (lock == AXI5_EXCLUSIVE) -> (atop == AXI5_ATOP_NONE);
  }

  // Atomic-operation rules (E1.1): atomics are writes; AtomicStore has no read
  // data; AtomicLoad/Swap/Compare return data. Atomic bursts are single-INCR.
  constraint c_atomic {
    (atop != AXI5_ATOP_NONE) -> (dir == AXI5_WRITE);
    (atop != AXI5_ATOP_NONE) -> (burst == AXI5_INCR);
    (atop != AXI5_ATOP_NONE) -> (lock == AXI5_NORMAL);
    // AtomicCompare carries double the data (compare + swap), modeled via len.
    (atop == AXI5_ATOP_COMPARE) -> (len inside {1, 3, 7});
  }

  // Reads never carry AWATOP or strobes.
  constraint c_read {
    (dir == AXI5_READ) -> (atop == AXI5_ATOP_NONE);
  }

  // Keep delays bounded so tests terminate.
  constraint c_delays {
    addr_delay       inside {[0:8]};
    resp_ready_delay inside {[0:8]};
    data_delay.size() == (len + 1);
    foreach (data_delay[i]) data_delay[i] inside {[0:8]};
  }

  // Size the dynamic payload arrays to the beat count.
  constraint c_arrays {
    data.size() == (len + 1);
    strb.size() == (len + 1);
    wuser.size() == (len + 1);
  }

  // ---------------------------------------------------------------------------
  // Post-randomize: default all-ones strobes for fully-defined beats unless a
  // sequence overrides; compute per-beat addresses are derived in the driver.
  // ---------------------------------------------------------------------------
  function void post_randomize();
    if (dir == AXI5_WRITE) begin
      int unsigned bus_bytes = `AXI5_DATA_WIDTH/8;
      int unsigned nb        = (1 << size);
      foreach (strb[i]) begin
        bit [`AXI5_DATA_WIDTH/8-1:0] mask;
        int unsigned lane0 = beat_addr(i) % bus_bytes; // active byte lane
        // Legal-lane mask: only [lane0 .. lane0+nb-1] may be asserted.
        mask = '0;
        for (int l = lane0; l < lane0 + nb; l++)
          if (l < bus_bytes) mask[l] = 1'b1;
        if (strb[i] === 'x) strb[i] = mask;       // default: full active window
        else                strb[i] = strb[i] & mask; // clamp to legal lanes
      end
    end
  endfunction

  // Number of beats in this burst.
  function int num_beats();
    return int'(len) + 1;
  endfunction

  // Total bytes transferred.
  function int total_bytes();
    return num_beats() * (1 << size);
  endfunction

  // Compute the byte address of beat `n` per AXI address arithmetic.
  function bit [63:0] beat_addr(int n);
    int unsigned nb     = (1 << size);
    bit [63:0] aligned  = (addr / nb) * nb;
    case (burst)
      AXI5_FIXED: beat_addr = addr;
      AXI5_INCR : beat_addr = aligned + (n * nb);
      AXI5_WRAP : begin
        int unsigned total = nb * num_beats();
        bit [63:0] lower   = (addr / total) * total;
        bit [63:0] upper   = lower + total;
        bit [63:0] cand    = aligned + (n * nb);
        beat_addr = (cand >= upper) ? (cand - total) : cand;
      end
      default: beat_addr = addr;
    endcase
  endfunction

  function string convert2str();
    return $sformatf(
      "%s id=0x%0h addr=0x%0h len=%0d size=%0d(%0dB) burst=%s lock=%s atop=%s qos=%0d resp=%s beats=%0d",
      dir.name(), id, addr, len, size, (1<<size), burst.name(), lock.name(),
      atop.name(), qos, resp.name(), num_beats());
  endfunction

endclass

`endif // AXI5_SEQ_ITEM_SVH
