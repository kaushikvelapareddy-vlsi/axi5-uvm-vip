// -----------------------------------------------------------------------------
// axi5_write_seq.svh : randomized write traffic within an address window.
// -----------------------------------------------------------------------------
`ifndef AXI5_WRITE_SEQ_SVH
`define AXI5_WRITE_SEQ_SVH

class axi5_write_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_write_seq)

  function new(string name = "axi5_write_seq");
    super.new(name);
  endfunction

  task body();
    for (int i = 0; i < num_txns; i++) begin
      axi5_seq_item it = axi5_seq_item::type_id::create($sformatf("wr%0d", i));
      start_item(it);
      if (!it.randomize() with {
            dir == AXI5_WRITE;
            atop == AXI5_ATOP_NONE;
            lock == AXI5_NORMAL;
            addr inside {[base_addr : base_addr + addr_span - 1]};
          })
        `uvm_error(get_type_name(), "write randomize failed")
      finish_item(it);
    end
  endtask

endclass

`endif // AXI5_WRITE_SEQ_SVH
