// -----------------------------------------------------------------------------
// axi5_read_seq.svh : randomized read traffic within an address window.
// -----------------------------------------------------------------------------
`ifndef AXI5_READ_SEQ_SVH
`define AXI5_READ_SEQ_SVH

class axi5_read_seq extends axi5_base_seq;
  `uvm_object_utils(axi5_read_seq)

  function new(string name = "axi5_read_seq");
    super.new(name);
  endfunction

  task body();
    for (int i = 0; i < num_txns; i++) begin
      axi5_seq_item it = axi5_seq_item::type_id::create($sformatf("rd%0d", i));
      start_item(it);
      if (!it.randomize() with {
            dir == AXI5_READ;
            lock == AXI5_NORMAL;
            addr inside {[base_addr : base_addr + addr_span - 1]};
          })
        `uvm_error(get_type_name(), "read randomize failed")
      finish_item(it);
    end
  endtask

endclass

`endif // AXI5_READ_SEQ_SVH
