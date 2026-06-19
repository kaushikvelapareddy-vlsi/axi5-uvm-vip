// -----------------------------------------------------------------------------
// axi5_base_seq.svh : base sequence with common helpers.
// -----------------------------------------------------------------------------
`ifndef AXI5_BASE_SEQ_SVH
`define AXI5_BASE_SEQ_SVH

class axi5_base_seq extends uvm_sequence #(axi5_seq_item);
  `uvm_object_utils(axi5_base_seq)

  // Address window the sequence targets (kept inside slave memory range).
  rand bit [63:0] base_addr = 64'h0000_0000;
  rand bit [63:0] addr_span = 64'h0000_1000;
  rand int unsigned num_txns = 10;

  constraint c_defaults {
    soft num_txns inside {[1:64]};
    soft addr_span inside {[64:64'h1_0000]};
  }

  function new(string name = "axi5_base_seq");
    super.new(name);
  endfunction

  // Convenience: issue a single fully-constrained write.
  task automatic do_write(bit [63:0] addr, bit [7:0] len, bit [2:0] size,
                          axi5_burst_e burst = AXI5_INCR);
    axi5_seq_item it = axi5_seq_item::type_id::create("wr");
    start_item(it);
    if (!it.randomize() with {
          dir   == AXI5_WRITE;
          it.addr  == local::addr;
          it.len   == local::len;
          it.size  == local::size;
          it.burst == local::burst;
          lock  == AXI5_NORMAL;
          atop  == AXI5_ATOP_NONE;
        })
      `uvm_error(get_type_name(), "do_write randomize failed")
    finish_item(it);
  endtask

  // Convenience: issue a single fully-constrained read.
  task automatic do_read(bit [63:0] addr, bit [7:0] len, bit [2:0] size,
                         axi5_burst_e burst = AXI5_INCR);
    axi5_seq_item it = axi5_seq_item::type_id::create("rd");
    start_item(it);
    if (!it.randomize() with {
          dir   == AXI5_READ;
          it.addr  == local::addr;
          it.len   == local::len;
          it.size  == local::size;
          it.burst == local::burst;
          lock  == AXI5_NORMAL;
        })
      `uvm_error(get_type_name(), "do_read randomize failed")
    finish_item(it);
  endtask

  // Blocking write: issue and wait until the B response is observed.
  task automatic do_write_blocking(bit [63:0] addr, bit [7:0] len,
                                   bit [2:0] size,
                                   axi5_burst_e burst = AXI5_INCR);
    axi5_seq_item it = axi5_seq_item::type_id::create("wrb");
    start_item(it);
    if (!it.randomize() with {
          dir == AXI5_WRITE; it.addr == local::addr; it.len == local::len; it.size == local::size;
          it.burst == local::burst; lock == AXI5_NORMAL; atop == AXI5_ATOP_NONE;
        })
      `uvm_error(get_type_name(), "do_write_blocking randomize failed")
    finish_item(it);
    wait (it.completed == 1);
  endtask

  // Blocking read: issue and wait until RLAST is observed.
  task automatic do_read_blocking(bit [63:0] addr, bit [7:0] len,
                                  bit [2:0] size,
                                  axi5_burst_e burst = AXI5_INCR);
    axi5_seq_item it = axi5_seq_item::type_id::create("rdb");
    start_item(it);
    if (!it.randomize() with {
          dir == AXI5_READ; it.addr == local::addr; it.len == local::len; it.size == local::size;
          it.burst == local::burst; lock == AXI5_NORMAL;
        })
      `uvm_error(get_type_name(), "do_read_blocking randomize failed")
    finish_item(it);
    wait (it.completed == 1);
  endtask

endclass

`endif // AXI5_BASE_SEQ_SVH
