// -----------------------------------------------------------------------------
// axi5_driver.svh : AXI5 master driver.
// Drives independent AW/W/AR address & data channels with configurable
// back-pressure, collects B/R responses, and returns them on the seq_item.
// Supports multiple outstanding transactions via fork/join_none per channel.
// -----------------------------------------------------------------------------
`ifndef AXI5_DRIVER_SVH
`define AXI5_DRIVER_SVH

class axi5_driver extends uvm_driver #(axi5_seq_item);
  `uvm_component_utils(axi5_driver)

  virtual axi5_if vif;
  axi5_config     cfg;

  // Response routing: queues of in-flight items keyed by id.
  axi5_seq_item   write_outstanding[bit [`AXI5_ID_WIDTH-1:0]][$];
  axi5_seq_item   read_outstanding [bit [`AXI5_ID_WIDTH-1:0]][$];

  // Number of transactions issued whose response has not yet been received.
  // Throttled against cfg.max_outstanding so the master never exceeds the
  // configured request-issue depth.
  int unsigned    outstanding_count;

  semaphore       aw_lock, w_lock, ar_lock;

  // Slave-role reference memory (built when role == AXI5_SLAVE).
  axi5_ref_mem    slv_mem;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    aw_lock = new(1);
    w_lock  = new(1);
    ar_lock = new(1);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi5_config)::get(this, "", "cfg", cfg))
      `uvm_fatal(get_type_name(), "axi5_config not set for driver")
    vif = cfg.vif;
    if (cfg.role == AXI5_SLAVE)
      slv_mem = axi5_ref_mem::type_id::create("slv_mem");
  endfunction

  task run_phase(uvm_phase phase);
    if (cfg.role == AXI5_SLAVE) begin
      run_slave();
    end
    else begin
      reset_signals();
      @(posedge vif.aresetn);
      fork
        b_response_collector();
        r_response_collector();
      join_none
      forever begin
        seq_item_port.get_next_item(req);
        // Throttle to the configured outstanding depth before issuing.
        wait (outstanding_count < cfg.max_outstanding);
        outstanding_count++;
        drive_item(req);
        seq_item_port.item_done();
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  task reset_signals();
    vif.master_cb.awvalid <= 0;
    vif.master_cb.wvalid  <= 0;
    vif.master_cb.arvalid <= 0;
    vif.master_cb.bready  <= 0;
    vif.master_cb.rready  <= 0;
    vif.master_cb.awakeup <= 1;
    vif.master_cb.awmmuvalid <= 0;
    vif.master_cb.armmuvalid <= 0;
  endtask

  // ---------------------------------------------------------------------------
  // Drive one transaction. Address & data phases are forked so multiple
  // outstanding transactions can overlap.
  // ---------------------------------------------------------------------------
  task drive_item(axi5_seq_item item);
    if (item.dir == AXI5_WRITE) begin
      write_outstanding[item.id].push_back(item);
      fork
        drive_aw(item);
        drive_w(item);
      join
    end
    else begin
      read_outstanding[item.id].push_back(item);
      drive_ar(item);
    end
  endtask

  // ---- AW channel -----------------------------------------------------------
  task drive_aw(axi5_seq_item item);
    aw_lock.get();
    repeat (item.addr_delay) @(vif.master_cb);
    vif.master_cb.awid     <= item.id;
    vif.master_cb.awaddr   <= item.addr;
    vif.master_cb.awlen    <= item.len;
    vif.master_cb.awsize   <= item.size;
    vif.master_cb.awburst  <= item.burst;
    vif.master_cb.awlock   <= item.lock;
    vif.master_cb.awcache  <= item.cache;
    vif.master_cb.awprot   <= item.prot;
    vif.master_cb.awqos    <= item.qos;
    vif.master_cb.awregion <= item.region;
    vif.master_cb.awatop   <= item.atop;
    vif.master_cb.awuser   <= item.awuser;
    vif.master_cb.awunique <= item.unique_hint;
    vif.master_cb.awtrace  <= item.trace;
    vif.master_cb.awloop   <= item.loop_tag;
    vif.master_cb.awvalid  <= 1;
    do @(vif.master_cb); while (!vif.master_cb.awready);
    vif.master_cb.awvalid  <= 0;
    aw_lock.put();
  endtask

  // ---- W channel ------------------------------------------------------------
  task drive_w(axi5_seq_item item);
    w_lock.get();
    for (int b = 0; b < item.num_beats(); b++) begin
      // Insert any inter-beat delay with WVALID LOW. A beat is transferred on
      // every cycle WVALID && WREADY are both high, so WVALID must be
      // deasserted during stall gaps or the slave will over-count beats.
      if (item.data_delay[b] > 0) begin
        vif.master_cb.wvalid <= 0;
        repeat (item.data_delay[b]) @(vif.master_cb);
      end
      vif.master_cb.wdata <= item.data[b];
      vif.master_cb.wstrb <= item.strb[b];
      vif.master_cb.wuser <= item.wuser[b];
      vif.master_cb.wlast <= (b == item.num_beats()-1);
      vif.master_cb.wtrace <= item.trace;
      vif.master_cb.wvalid <= 1;
      do @(vif.master_cb); while (!vif.master_cb.wready);
    end
    vif.master_cb.wvalid <= 0;
    vif.master_cb.wlast  <= 0;
    w_lock.put();
  endtask

  // ---- AR channel -----------------------------------------------------------
  task drive_ar(axi5_seq_item item);
    ar_lock.get();
    repeat (item.addr_delay) @(vif.master_cb);
    vif.master_cb.arid     <= item.id;
    vif.master_cb.araddr   <= item.addr;
    vif.master_cb.arlen    <= item.len;
    vif.master_cb.arsize   <= item.size;
    vif.master_cb.arburst  <= item.burst;
    vif.master_cb.arlock   <= item.lock;
    vif.master_cb.arcache  <= item.cache;
    vif.master_cb.arprot   <= item.prot;
    vif.master_cb.arqos    <= item.qos;
    vif.master_cb.arregion <= item.region;
    vif.master_cb.aruser   <= item.aruser;
    vif.master_cb.artrace  <= item.trace;
    vif.master_cb.arloop   <= item.loop_tag;
    vif.master_cb.arvalid  <= 1;
    do @(vif.master_cb); while (!vif.master_cb.arready);
    vif.master_cb.arvalid  <= 0;
    ar_lock.put();
  endtask

  // ---- B response collector -------------------------------------------------
  task b_response_collector();
    forever begin
      // Optional BREADY back-pressure bubble.
      if (cfg.master_ready_bubbles) begin
        int unsigned d = $urandom_range(0, cfg.master_max_ready_delay);
        if (d > 0) begin
          vif.master_cb.bready <= 0;
          repeat (d) @(vif.master_cb);
        end
      end
      vif.master_cb.bready <= 1;
      @(vif.master_cb);
      if (vif.master_cb.bvalid) begin
        bit [`AXI5_ID_WIDTH-1:0] id = vif.master_cb.bid;
        if (write_outstanding.exists(id) && write_outstanding[id].size() > 0) begin
          axi5_seq_item it = write_outstanding[id].pop_front();
          it.resp  = axi5_resp_e'(vif.master_cb.bresp);
          it.buser = vif.master_cb.buser;
          it.completed = 1;
          if (outstanding_count > 0) outstanding_count--;
          `uvm_info(get_type_name(),
            $sformatf("B resp id=0x%0h %s", id, it.resp.name()), UVM_HIGH)
        end
      end
    end
  endtask

  // ---- R response collector -------------------------------------------------
  task r_response_collector();
    bit [`AXI5_ID_WIDTH-1:0] id;
    int beat_idx[bit [`AXI5_ID_WIDTH-1:0]];
    forever begin
      // Optional RREADY back-pressure bubble.
      if (cfg.master_ready_bubbles) begin
        int unsigned d = $urandom_range(0, cfg.master_max_ready_delay);
        if (d > 0) begin
          vif.master_cb.rready <= 0;
          repeat (d) @(vif.master_cb);
        end
      end
      vif.master_cb.rready <= 1;
      @(vif.master_cb);
      if (vif.master_cb.rvalid) begin
        id = vif.master_cb.rid;
        if (read_outstanding.exists(id) && read_outstanding[id].size() > 0) begin
          axi5_seq_item it = read_outstanding[id][0];
          if (it.rresp_beat.size() == 0) begin
            it.rresp_beat = new[it.num_beats()];
            it.ruser      = new[it.num_beats()];
            beat_idx[id]  = 0;
          end
          it.data[beat_idx[id]]       = vif.master_cb.rdata;
          it.rresp_beat[beat_idx[id]] = axi5_resp_e'(vif.master_cb.rresp);
          it.ruser[beat_idx[id]]      = vif.master_cb.ruser;
          beat_idx[id]++;
          if (vif.master_cb.rlast) begin
            it.resp = axi5_resp_e'(vif.master_cb.rresp);
            it.completed = 1;
            if (outstanding_count > 0) outstanding_count--;
            void'(read_outstanding[id].pop_front());
            beat_idx[id] = 0;
            `uvm_info(get_type_name(),
              $sformatf("R last id=0x%0h %s", id, it.resp.name()), UVM_HIGH)
          end
        end
      end
    end
  endtask

  // ===========================================================================
  // SLAVE ROLE
  // Responds to AW/W with B, and AR with R, serving data from a local
  // reference memory. Configurable back-pressure and optional error injection.
  // ===========================================================================
  task run_slave();
    slave_reset();
    @(posedge vif.aresetn);
    fork
      slave_write_handler();
      slave_read_handler();
    join
  endtask

  task slave_reset();
    vif.slave_cb.awready <= 0;
    vif.slave_cb.wready  <= 0;
    vif.slave_cb.bvalid  <= 0;
    vif.slave_cb.arready <= 0;
    vif.slave_cb.rvalid  <= 0;
  endtask

  function int unsigned rand_wait();
    int unsigned w;
    if (cfg.slave_max_wait <= cfg.slave_min_wait) return cfg.slave_min_wait;
    w = cfg.slave_min_wait +
        ({$random} % (cfg.slave_max_wait - cfg.slave_min_wait + 1));
    return w;
  endfunction

  function axi5_resp_e pick_resp(bit [63:0] a, bit exclusive);
    if (!cfg.addr_in_range(a)) return AXI5_DECERR;
    if (cfg.slave_inject_errors && (({$random} % 16) == 0)) return AXI5_SLVERR;
    return exclusive ? AXI5_EXOKAY : AXI5_OKAY;
  endfunction

  // ---- Slave write path -----------------------------------------------------
  task slave_write_handler();
    forever begin
      bit [`AXI5_ID_WIDTH-1:0] awid;
      bit [63:0]               awaddr;
      bit [7:0]                awlen;
      bit [2:0]                awsize;
      bit [1:0]                awburst;
      bit                      awlock;
      // Accept an address.
      vif.slave_cb.awready <= 1;
      do @(vif.slave_cb); while (!vif.slave_cb.awvalid);
      awid    = vif.slave_cb.awid;
      awaddr  = vif.slave_cb.awaddr;
      awlen   = vif.slave_cb.awlen;
      awsize  = vif.slave_cb.awsize;
      awburst = vif.slave_cb.awburst;
      awlock  = vif.slave_cb.awlock;
      vif.slave_cb.awready <= 0;

      // Accept the write-data beats.
      vif.slave_cb.wready <= 1;
      for (int b = 0; b <= awlen; b++) begin
        repeat (rand_wait()) begin
          vif.slave_cb.wready <= 0; @(vif.slave_cb);
        end
        vif.slave_cb.wready <= 1;
        do @(vif.slave_cb); while (!vif.slave_cb.wvalid);
        // Commit to memory using beat address arithmetic.
        if (slv_mem != null) begin
          bit [63:0] ba = slave_beat_addr(awaddr, awsize, awburst, awlen, b);
          slv_mem.apply_write_beat(ba, vif.slave_cb.wdata,
                                   vif.slave_cb.wstrb, awsize);
        end
        if (vif.slave_cb.wlast) break;
      end
      vif.slave_cb.wready <= 0;

      // Issue the write response.
      repeat (rand_wait()) @(vif.slave_cb);
      vif.slave_cb.bid    <= awid;
      vif.slave_cb.bresp  <= pick_resp(awaddr, awlock);
      vif.slave_cb.bvalid <= 1;
      do @(vif.slave_cb); while (!vif.slave_cb.bready);
      vif.slave_cb.bvalid <= 0;
    end
  endtask

  // ---- Slave read path ------------------------------------------------------
  task slave_read_handler();
    forever begin
      bit [`AXI5_ID_WIDTH-1:0] arid;
      bit [63:0]               araddr;
      bit [7:0]                arlen;
      bit [2:0]                arsize;
      bit [1:0]                arburst;
      bit                      arlock;
      vif.slave_cb.arready <= 1;
      do @(vif.slave_cb); while (!vif.slave_cb.arvalid);
      arid    = vif.slave_cb.arid;
      araddr  = vif.slave_cb.araddr;
      arlen   = vif.slave_cb.arlen;
      arsize  = vif.slave_cb.arsize;
      arburst = vif.slave_cb.arburst;
      arlock  = vif.slave_cb.arlock;
      vif.slave_cb.arready <= 0;

      for (int b = 0; b <= arlen; b++) begin
        bit [63:0] ba = slave_beat_addr(araddr, arsize, arburst, arlen, b);
        repeat (rand_wait()) @(vif.slave_cb);
        vif.slave_cb.rid   <= arid;
        vif.slave_cb.rdata <= (slv_mem != null) ?
                                slv_mem.predict_read_beat(ba, arsize) : '0;
        vif.slave_cb.rresp <= pick_resp(araddr, arlock);
        vif.slave_cb.rlast <= (b == arlen);
        vif.slave_cb.rvalid <= 1;
        do @(vif.slave_cb); while (!vif.slave_cb.rready);
        vif.slave_cb.rvalid <= 0;
      end
      vif.slave_cb.rlast <= 0;
    end
  endtask

  // Beat-address arithmetic mirroring axi5_seq_item::beat_addr.
  function bit [63:0] slave_beat_addr(bit [63:0] addr, bit [2:0] size,
                                      bit [1:0] burst, bit [7:0] len, int n);
    int unsigned nb     = (1 << size);
    bit [63:0]   aligned = (addr / nb) * nb;
    case (burst)
      2'b00: slave_beat_addr = addr;                 // FIXED
      2'b01: slave_beat_addr = aligned + (n * nb);   // INCR
      2'b10: begin                                   // WRAP
        int unsigned total = nb * (int'(len) + 1);
        bit [63:0] lower   = (addr / total) * total;
        bit [63:0] upper   = lower + total;
        bit [63:0] cand    = aligned + (n * nb);
        slave_beat_addr = (cand >= upper) ? (cand - total) : cand;
      end
      default: slave_beat_addr = addr;
    endcase
  endfunction

endclass

`endif // AXI5_DRIVER_SVH
