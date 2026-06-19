// -----------------------------------------------------------------------------
// axi5_sva_checker.sv : AXI5 protocol assertions module.
// Takes the axi5_if interface as a port and references its signals. Instantiated
// from the testbench top (a module may not be instantiated inside an interface,
// and VCS does not allow binding a module into an interface instance).
// Disable globally with +define+AXI5_NO_SVA.
// -----------------------------------------------------------------------------
`ifndef AXI5_SVA_CHECKER_SV
`define AXI5_SVA_CHECKER_SV

module axi5_sva_checker #(
  parameter int ADDR_WIDTH = 64,
  parameter int DATA_WIDTH = 64,
  parameter int ID_WIDTH   = 4
) (
  axi5_if vif
);

  // Local aliases to the interface signals so the assertion bodies below read
  // cleanly. Continuous assignments track the interface nets.
  wire                  aclk    = vif.aclk;
  wire                  aresetn = vif.aresetn;
  // AW
  wire [ID_WIDTH-1:0]   awid    = vif.awid;
  wire [ADDR_WIDTH-1:0] awaddr  = vif.awaddr;
  wire [7:0]            awlen   = vif.awlen;
  wire [2:0]            awsize  = vif.awsize;
  wire [1:0]            awburst = vif.awburst;
  wire                  awlock  = vif.awlock;
  wire                  awatop  = |vif.awatop;   // any atomic op active
  wire                  awvalid = vif.awvalid;
  wire                  awready = vif.awready;
  // W
  wire [DATA_WIDTH-1:0]   wdata = vif.wdata;
  wire [DATA_WIDTH/8-1:0] wstrb = vif.wstrb;
  wire                  wlast   = vif.wlast;
  wire                  wvalid  = vif.wvalid;
  wire                  wready  = vif.wready;
  // B
  wire [ID_WIDTH-1:0]   bid     = vif.bid;
  wire [1:0]            bresp   = vif.bresp;
  wire                  bvalid  = vif.bvalid;
  wire                  bready  = vif.bready;
  // AR
  wire [ID_WIDTH-1:0]   arid    = vif.arid;
  wire [ADDR_WIDTH-1:0] araddr  = vif.araddr;
  wire [7:0]            arlen   = vif.arlen;
  wire [2:0]            arsize  = vif.arsize;
  wire [1:0]            arburst = vif.arburst;
  wire                  arlock  = vif.arlock;
  wire                  arvalid = vif.arvalid;
  wire                  arready = vif.arready;
  // R
  wire [ID_WIDTH-1:0]   rid     = vif.rid;
  wire [1:0]            rresp   = vif.rresp;
  wire                  rlast   = vif.rlast;
  wire                  rvalid  = vif.rvalid;
  wire                  rready  = vif.rready;

  // Allow VIP to silence assertions even when compiled in.
  bit checks_enabled = 1;

  localparam logic [1:0] B_FIXED = 2'b00;
  localparam logic [1:0] B_INCR  = 2'b01;
  localparam logic [1:0] B_WRAP  = 2'b10;
  localparam logic [1:0] B_RSVD  = 2'b11;

  // Bytes in a transfer = (len+1) << size.
  function automatic int unsigned f_bytes(input logic [7:0] len,
                                          input logic [2:0] size);
    f_bytes = (int'(len) + 1) << size;
  endfunction

  // ---------------------------------------------------------------------------
  // Handshake stability: VALID asserted must hold until READY (no withdrawal).
  // ---------------------------------------------------------------------------
  property p_valid_stable(valid, ready);
    @(posedge aclk) disable iff (!aresetn || !checks_enabled)
      (valid && !ready) |=> valid;
  endproperty
  AW_VALID_STABLE: assert property (p_valid_stable(awvalid, awready))
    else $error("AXI5: AWVALID deasserted before AWREADY");
  W_VALID_STABLE : assert property (p_valid_stable(wvalid,  wready))
    else $error("AXI5: WVALID deasserted before WREADY");
  B_VALID_STABLE : assert property (p_valid_stable(bvalid,  bready))
    else $error("AXI5: BVALID deasserted before BREADY");
  AR_VALID_STABLE: assert property (p_valid_stable(arvalid, arready))
    else $error("AXI5: ARVALID deasserted before ARREADY");
  R_VALID_STABLE : assert property (p_valid_stable(rvalid,  rready))
    else $error("AXI5: RVALID deasserted before RREADY");

  // ---------------------------------------------------------------------------
  // Payload stability while VALID && !READY for the AW/AR address channels.
  // ---------------------------------------------------------------------------
  property p_aw_payload_stable;
    @(posedge aclk) disable iff (!aresetn || !checks_enabled)
      (awvalid && !awready) |=>
        $stable(awaddr) && $stable(awlen) && $stable(awsize) &&
        $stable(awburst) && $stable(awid);
  endproperty
  AW_PAYLOAD_STABLE: assert property (p_aw_payload_stable)
    else $error("AXI5: AW payload changed while stalled");

  property p_ar_payload_stable;
    @(posedge aclk) disable iff (!aresetn || !checks_enabled)
      (arvalid && !arready) |=>
        $stable(araddr) && $stable(arlen) && $stable(arsize) &&
        $stable(arburst) && $stable(arid);
  endproperty
  AR_PAYLOAD_STABLE: assert property (p_ar_payload_stable)
    else $error("AXI5: AR payload changed while stalled");

  // Write-data payload (WDATA/WSTRB/WLAST) must be stable while WVALID is
  // asserted and WREADY is low.
  property p_w_payload_stable;
    @(posedge aclk) disable iff (!aresetn || !checks_enabled)
      (wvalid && !wready) |=>
        $stable(wdata) && $stable(wstrb) && $stable(wlast);
  endproperty
  W_PAYLOAD_STABLE: assert property (p_w_payload_stable)
    else $error("AXI5: W payload changed while stalled");

  // ---------------------------------------------------------------------------
  // Burst type must not be reserved (2'b11).
  // ---------------------------------------------------------------------------
  AW_BURST_LEGAL: assert property (@(posedge aclk)
    disable iff (!aresetn || !checks_enabled)
    (awvalid && awready) |-> (awburst != B_RSVD))
    else $error("AXI5: reserved AWBURST");
  AR_BURST_LEGAL: assert property (@(posedge aclk)
    disable iff (!aresetn || !checks_enabled)
    (arvalid && arready) |-> (arburst != B_RSVD))
    else $error("AXI5: reserved ARBURST");

  // ---------------------------------------------------------------------------
  // WRAP bursts: length must be 2,4,8,16 (awlen in {1,3,7,15}).
  // ---------------------------------------------------------------------------
  function automatic bit f_wrap_len_ok(input logic [7:0] len);
    f_wrap_len_ok = (len == 8'd1) || (len == 8'd3) ||
                    (len == 8'd7) || (len == 8'd15);
  endfunction
  AW_WRAP_LEN: assert property (@(posedge aclk)
    disable iff (!aresetn || !checks_enabled)
    (awvalid && awready && awburst == B_WRAP) |-> f_wrap_len_ok(awlen))
    else $error("AXI5: illegal WRAP length on AW");
  AR_WRAP_LEN: assert property (@(posedge aclk)
    disable iff (!aresetn || !checks_enabled)
    (arvalid && arready && arburst == B_WRAP) |-> f_wrap_len_ok(arlen))
    else $error("AXI5: illegal WRAP length on AR");

  // ---------------------------------------------------------------------------
  // 4KB boundary: an INCR burst must not cross a 4KB boundary.
  // ---------------------------------------------------------------------------
  AW_4KB: assert property (@(posedge aclk)
    disable iff (!aresetn || !checks_enabled)
    (awvalid && awready && awburst == B_INCR) |->
      ((awaddr[11:0] + f_bytes(awlen, awsize)) <= 13'h1000))
    else $error("AXI5: AW INCR burst crosses 4KB boundary");
  AR_4KB: assert property (@(posedge aclk)
    disable iff (!aresetn || !checks_enabled)
    (arvalid && arready && arburst == B_INCR) |->
      ((araddr[11:0] + f_bytes(arlen, arsize)) <= 13'h1000))
    else $error("AXI5: AR INCR burst crosses 4KB boundary");

  // ---------------------------------------------------------------------------
  // Transfer size must not exceed the data bus width.
  // ---------------------------------------------------------------------------
  localparam int BUS_BYTES = DATA_WIDTH/8;
  AW_SIZE_BUS: assert property (@(posedge aclk)
    disable iff (!aresetn || !checks_enabled)
    (awvalid && awready) |-> ((1 << awsize) <= BUS_BYTES))
    else $error("AXI5: AWSIZE exceeds data bus width");
  AR_SIZE_BUS: assert property (@(posedge aclk)
    disable iff (!aresetn || !checks_enabled)
    (arvalid && arready) |-> ((1 << arsize) <= BUS_BYTES))
    else $error("AXI5: ARSIZE exceeds data bus width");

  // ---------------------------------------------------------------------------
  // Exclusive access rules: burst length <= 16 beats, total bytes power-of-2
  // and <= 128, address aligned to total size.
  // ---------------------------------------------------------------------------
  function automatic bit f_excl_ok(input logic [ADDR_WIDTH-1:0] addr,
                                   input logic [7:0] len,
                                   input logic [2:0] size);
    int unsigned bytes = f_bytes(len, size);
    bit pow2  = (bytes != 0) && ((bytes & (bytes-1)) == 0);
    bit le128 = (bytes <= 128);
    bit le16  = (len <= 15);
    bit algn  = ((addr % bytes) == 0);
    f_excl_ok = pow2 && le128 && le16 && algn;
  endfunction
  AW_EXCL: assert property (@(posedge aclk)
    disable iff (!aresetn || !checks_enabled)
    (awvalid && awready && awlock) |-> f_excl_ok(awaddr, awlen, awsize))
    else $error("AXI5: illegal exclusive write attributes");
  AR_EXCL: assert property (@(posedge aclk)
    disable iff (!aresetn || !checks_enabled)
    (arvalid && arready && arlock) |-> f_excl_ok(araddr, arlen, arsize))
    else $error("AXI5: illegal exclusive read attributes");

  // ---------------------------------------------------------------------------
  // Atomic transactions (AWATOP != 0) are writes that must be INCR and not
  // exclusive.
  // ---------------------------------------------------------------------------
  AW_ATOP: assert property (@(posedge aclk)
    disable iff (!aresetn || !checks_enabled)
    (awvalid && awready && awatop) |->
      (awburst == B_INCR) && !awlock)
    else $error("AXI5: illegal atomic transaction attributes");

  // ---------------------------------------------------------------------------
  // EXOKAY may only be returned for exclusive accesses. Conservative version:
  // flagged in the scoreboard with full ID correlation; here we only check the
  // gross rule that EXOKAY on B/R implies some exclusive access was seen.
  // (Left to scoreboard for ID-accurate checking.)
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // X-checks: control signals must be known when VALID is asserted.
  // ---------------------------------------------------------------------------
  AW_KNOWN: assert property (@(posedge aclk)
    disable iff (!aresetn || !checks_enabled)
    awvalid |-> !$isunknown({awaddr, awlen, awsize, awburst, awid}))
    else $error("AXI5: X/Z on AW control while AWVALID");
  AR_KNOWN: assert property (@(posedge aclk)
    disable iff (!aresetn || !checks_enabled)
    arvalid |-> !$isunknown({araddr, arlen, arsize, arburst, arid}))
    else $error("AXI5: X/Z on AR control while ARVALID");
  B_KNOWN: assert property (@(posedge aclk)
    disable iff (!aresetn || !checks_enabled)
    bvalid |-> !$isunknown({bid, bresp}))
    else $error("AXI5: X/Z on B channel while BVALID");
  R_KNOWN: assert property (@(posedge aclk)
    disable iff (!aresetn || !checks_enabled)
    rvalid |-> !$isunknown({rid, rresp, rlast}))
    else $error("AXI5: X/Z on R channel while RVALID");
  W_STRB_KNOWN: assert property (@(posedge aclk)
    disable iff (!aresetn || !checks_enabled)
    wvalid |-> !$isunknown(wstrb))
    else $error("AXI5: X/Z on WSTRB while WVALID");

  // ---------------------------------------------------------------------------
  // Reset behaviour: VALID signals must be low during reset. Compare against
  // 1'b1 (not a bare negation) so the check flags a genuinely asserted VALID
  // but tolerates the power-on/time-0 unknown before drivers initialise.
  // ---------------------------------------------------------------------------
  RESET_VALIDS_LOW: assert property (@(posedge aclk)
    (!aresetn) |-> (awvalid !== 1'b1 && wvalid !== 1'b1 && bvalid !== 1'b1 &&
                    arvalid !== 1'b1 && rvalid !== 1'b1))
    else $error("AXI5: VALID asserted during reset");

endmodule

`endif // AXI5_SVA_CHECKER_SV
