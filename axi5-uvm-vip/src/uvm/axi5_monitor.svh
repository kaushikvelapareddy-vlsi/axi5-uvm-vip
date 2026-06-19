// -----------------------------------------------------------------------------
// axi5_monitor.svh : passive AXI5 monitor.
// Reconstructs full-burst transactions from the five channels and publishes
// them on analysis ports (separate write/read for scoreboard convenience, plus
// a combined port for coverage/checker).
// -----------------------------------------------------------------------------
`ifndef AXI5_MONITOR_SVH
`define AXI5_MONITOR_SVH

class axi5_monitor extends uvm_monitor;
  `uvm_component_utils(axi5_monitor)

  virtual axi5_if vif;
  axi5_config     cfg;

  uvm_analysis_port #(axi5_seq_item) ap;         // all transactions
  uvm_analysis_port #(axi5_seq_item) wr_ap;      // writes
  uvm_analysis_port #(axi5_seq_item) rd_ap;      // reads

  // Address-phase captures awaiting their data/response phases.
  // aw_q[id]   : per-ID write queue, used to match the B response (B is in
  //              order within an ID but may be reordered across IDs).
  // wdata_q    : single global queue in AW-issue order, used to associate the
  //              write-data beats (AXI requires write data in AW-issue order).
  axi5_seq_item aw_q[bit [`AXI5_ID_WIDTH-1:0]][$];
  axi5_seq_item wdata_q[$];
  axi5_seq_item ar_q[bit [`AXI5_ID_WIDTH-1:0]][$];
  axi5_seq_item w_active;                          // current write-data burst

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap    = new("ap", this);
    wr_ap = new("wr_ap", this);
    rd_ap = new("rd_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi5_config)::get(this, "", "cfg", cfg))
      `uvm_fatal(get_type_name(), "axi5_config not set for monitor")
    vif = cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    @(posedge vif.aresetn);
    fork
      mon_aw();
      mon_w();
      mon_b();
      mon_ar();
      mon_r();
    join
  endtask

  // ---- AW capture -----------------------------------------------------------
  task mon_aw();
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.awvalid && vif.mon_cb.awready) begin
        axi5_seq_item t = axi5_seq_item::type_id::create("aw");
        t.dir    = AXI5_WRITE;
        t.id     = vif.mon_cb.awid;
        t.addr   = vif.mon_cb.awaddr;
        t.len    = vif.mon_cb.awlen;
        t.size   = vif.mon_cb.awsize;
        t.burst  = axi5_burst_e'(vif.mon_cb.awburst);
        t.lock   = axi5_lock_e'(vif.mon_cb.awlock);
        t.cache  = vif.mon_cb.awcache;
        t.prot   = vif.mon_cb.awprot;
        t.qos    = vif.mon_cb.awqos;
        t.region = vif.mon_cb.awregion;
        t.atop   = axi5_atop_e'(vif.mon_cb.awatop);
        t.awuser = vif.mon_cb.awuser;
        t.unique_hint = vif.mon_cb.awunique;
        t.data = new[t.num_beats()];
        t.strb = new[t.num_beats()];
        t.wuser = new[t.num_beats()];
        aw_q[t.id].push_back(t);
        wdata_q.push_back(t);       // global write-data order
      end
    end
  endtask

  // ---- W capture (in-order data interleaving not allowed in AXI4/5) ---------
  task mon_w();
    int beat = 0;
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.wvalid && vif.mon_cb.wready) begin
        // Write data follows AW-issue order globally; take the oldest AW whose
        // data has not yet completed from the global queue.
        if (w_active == null && wdata_q.size() > 0)
          w_active = wdata_q.pop_front();
        if (w_active != null) begin
          w_active.data[beat] = vif.mon_cb.wdata;
          w_active.strb[beat] = vif.mon_cb.wstrb;
          w_active.wuser[beat]= vif.mon_cb.wuser;
          beat++;
          if (vif.mon_cb.wlast) begin
            beat = 0;
            w_active = null;
          end
        end
      end
    end
  endtask

  // ---- B capture -> publish complete write ---------------------------------
  task mon_b();
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.bvalid && vif.mon_cb.bready) begin
        bit [`AXI5_ID_WIDTH-1:0] id = vif.mon_cb.bid;
        if (aw_q.exists(id) && aw_q[id].size() > 0) begin
          axi5_seq_item t = aw_q[id].pop_front();
          t.resp  = axi5_resp_e'(vif.mon_cb.bresp);
          t.buser = vif.mon_cb.buser;
          ap.write(t);
          wr_ap.write(t);
        end
      end
    end
  endtask

  // ---- AR capture -----------------------------------------------------------
  task mon_ar();
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
        axi5_seq_item t = axi5_seq_item::type_id::create("ar");
        t.dir    = AXI5_READ;
        t.id     = vif.mon_cb.arid;
        t.addr   = vif.mon_cb.araddr;
        t.len    = vif.mon_cb.arlen;
        t.size   = vif.mon_cb.arsize;
        t.burst  = axi5_burst_e'(vif.mon_cb.arburst);
        t.lock   = axi5_lock_e'(vif.mon_cb.arlock);
        t.cache  = vif.mon_cb.arcache;
        t.prot   = vif.mon_cb.arprot;
        t.qos    = vif.mon_cb.arqos;
        t.region = vif.mon_cb.arregion;
        t.aruser = vif.mon_cb.aruser;
        t.data = new[t.num_beats()];
        t.rresp_beat = new[t.num_beats()];
        t.ruser = new[t.num_beats()];
        ar_q[t.id].push_back(t);
      end
    end
  endtask

  // ---- R capture -> publish complete read on RLAST -------------------------
  task mon_r();
    int beat[bit [`AXI5_ID_WIDTH-1:0]];
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.rvalid && vif.mon_cb.rready) begin
        bit [`AXI5_ID_WIDTH-1:0] id = vif.mon_cb.rid;
        if (ar_q.exists(id) && ar_q[id].size() > 0) begin
          axi5_seq_item t = ar_q[id][0];
          t.data[beat[id]]       = vif.mon_cb.rdata;
          t.rresp_beat[beat[id]] = axi5_resp_e'(vif.mon_cb.rresp);
          t.ruser[beat[id]]      = vif.mon_cb.ruser;
          beat[id]++;
          if (vif.mon_cb.rlast) begin
            t.resp = axi5_resp_e'(vif.mon_cb.rresp);
            void'(ar_q[id].pop_front());
            beat[id] = 0;
            ap.write(t);
            rd_ap.write(t);
          end
        end
      end
    end
  endtask

endclass

`endif // AXI5_MONITOR_SVH
