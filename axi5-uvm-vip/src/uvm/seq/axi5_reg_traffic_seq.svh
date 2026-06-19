// -----------------------------------------------------------------------------
// axi5_reg_traffic_seq.svh : write-then-read-back data-integrity traffic.
// Writes a randomized burst, then reads the same region back so the scoreboard
// can verify data integrity end-to-end.
// -----------------------------------------------------------------------------
`ifndef AXI5_REG_TRAFFIC_SEQ_SVH
`define AXI5_REG_TRAFFIC_SEQ_SVH

class axi5_reg_traffic_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_reg_traffic_seq)

  function new(string name = "axi5_reg_traffic_seq");
    super.new(name);
  endfunction

  task body();
    for (int i = 0; i < num_txns; i++) begin
      bit [63:0] a;
      bit [7:0]  len;
      bit [2:0]  size;
      axi5_seq_item wr = axi5_seq_item::type_id::create($sformatf("wr%0d", i));
      start_item(wr);
      if (!wr.randomize() with {
            dir == AXI5_WRITE;
            atop == AXI5_ATOP_NONE;
            lock == AXI5_NORMAL;
            burst == AXI5_INCR;
            addr inside {[base_addr : base_addr + addr_span - 1]};
          })
        `uvm_error(get_type_name(), "reg write randomize failed")
      finish_item(wr);
      // Wait for the write to fully complete (B response) before reading the
      // same region. This enforces a strict happens-before so the read-back
      // observes the just-written data and avoids read-after-write hazards
      // against later overlapping transactions in this pipelined master.
      wait (wr.completed == 1);

      // Read the exact same region back.
      a = wr.addr; len = wr.len; size = wr.size;
      begin
        axi5_seq_item rd = axi5_seq_item::type_id::create($sformatf("rd%0d", i));
        start_item(rd);
        // NOTE: use local:: scope resolution so these reference the local
        // variables and not the seq_item's identically-named fields (addr/len/
        // size). Without local:: an unqualified name resolves to the object's
        // member, making constraints like (len == len) vacuously true.
        if (!rd.randomize() with {
              dir == AXI5_READ;
              lock == AXI5_NORMAL;
              burst == AXI5_INCR;
              addr == local::a;
              len  == local::len;
              size == local::size;
            })
          `uvm_error(get_type_name(), "reg read randomize failed")
        finish_item(rd);
        // Wait for the read-back to complete before issuing the next write so
        // overlapping regions cannot be overwritten mid read-burst.
        wait (rd.completed == 1);
      end
    end
  endtask

endclass

`endif // AXI5_REG_TRAFFIC_SEQ_SVH
