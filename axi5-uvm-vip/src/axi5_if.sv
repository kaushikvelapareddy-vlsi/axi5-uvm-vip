// -----------------------------------------------------------------------------
// axi5_if.sv : AXI5 SystemVerilog interface with master/slave/monitor clocking
// blocks. Parameterized address/data/id/user widths.
// -----------------------------------------------------------------------------
`ifndef AXI5_IF_SV
`define AXI5_IF_SV

interface axi5_if #(
  parameter int ADDR_WIDTH = 64,
  parameter int DATA_WIDTH = 64,
  parameter int ID_WIDTH   = 4,
  parameter int USER_WIDTH = 4,
  parameter int AWUSER_WIDTH = USER_WIDTH,
  parameter int WUSER_WIDTH  = USER_WIDTH,
  parameter int BUSER_WIDTH  = USER_WIDTH,
  parameter int ARUSER_WIDTH = USER_WIDTH,
  parameter int RUSER_WIDTH  = USER_WIDTH
) (
  input logic aclk,
  input logic aresetn
);

  localparam int STRB_WIDTH = DATA_WIDTH/8;

  // ---- Write address channel (AW) -------------------------------------------
  logic [ID_WIDTH-1:0]      awid;
  logic [ADDR_WIDTH-1:0]    awaddr;
  logic [7:0]               awlen;
  logic [2:0]               awsize;
  logic [1:0]               awburst;
  logic                     awlock;
  logic [3:0]               awcache;
  logic [2:0]               awprot;
  logic [3:0]               awqos;
  logic [3:0]               awregion;
  logic [5:0]               awatop;     // AXI5 atomic operation
  logic [AWUSER_WIDTH-1:0]  awuser;
  logic                     awunique;   // AXI5 (coherency hint, optional)
  logic                     awtrace;    // AXI5 trace signal
  logic [3:0]               awloop;     // AXI5 loopback tag (optional)
  logic                     awmmuvalid; // AXI5 MMU/MPAM (optional sideband)
  logic                     awvalid;
  logic                     awready;

  // ---- Write data channel (W) -----------------------------------------------
  logic [DATA_WIDTH-1:0]    wdata;
  logic [STRB_WIDTH-1:0]    wstrb;
  logic                     wlast;
  logic [WUSER_WIDTH-1:0]   wuser;
  logic                     wtrace;
  logic                     wvalid;
  logic                     wready;

  // ---- Write response channel (B) -------------------------------------------
  logic [ID_WIDTH-1:0]      bid;
  logic [1:0]               bresp;
  logic [BUSER_WIDTH-1:0]   buser;
  logic                     btrace;
  logic [3:0]               bloop;
  logic                     bvalid;
  logic                     bready;

  // ---- Read address channel (AR) --------------------------------------------
  logic [ID_WIDTH-1:0]      arid;
  logic [ADDR_WIDTH-1:0]    araddr;
  logic [7:0]               arlen;
  logic [2:0]               arsize;
  logic [1:0]               arburst;
  logic                     arlock;
  logic [3:0]               arcache;
  logic [2:0]               arprot;
  logic [3:0]               arqos;
  logic [3:0]               arregion;
  logic [ARUSER_WIDTH-1:0]  aruser;
  logic                     artrace;
  logic [3:0]               arloop;
  logic                     armmuvalid;
  logic                     arvalid;
  logic                     arready;

  // ---- Read data channel (R) ------------------------------------------------
  logic [ID_WIDTH-1:0]      rid;
  logic [DATA_WIDTH-1:0]    rdata;
  logic [1:0]               rresp;
  logic                     rlast;
  logic [RUSER_WIDTH-1:0]   ruser;
  logic                     rtrace;
  logic [3:0]               rloop;
  logic                     rvalid;
  logic                     rready;

  // ---- Low-power / wake-up (AXI5) -------------------------------------------
  logic                     awakeup;

  // ---------------------------------------------------------------------------
  // Clocking blocks
  // ---------------------------------------------------------------------------
  clocking master_cb @(posedge aclk);
    default input #1step output #1;
    // AW
    output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot,
           awqos, awregion, awatop, awuser, awunique, awtrace, awloop,
           awmmuvalid, awvalid;
    input  awready;
    // W
    output wdata, wstrb, wlast, wuser, wtrace, wvalid;
    input  wready;
    // B
    input  bid, bresp, buser, btrace, bloop, bvalid;
    output bready;
    // AR
    output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot,
           arqos, arregion, aruser, artrace, arloop, armmuvalid, arvalid;
    input  arready;
    // R
    input  rid, rdata, rresp, rlast, ruser, rtrace, rloop, rvalid;
    output rready;
    output awakeup;
  endclocking

  clocking slave_cb @(posedge aclk);
    default input #1step output #1;
    // AW
    input  awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot,
           awqos, awregion, awatop, awuser, awunique, awtrace, awloop,
           awmmuvalid, awvalid;
    output awready;
    // W
    input  wdata, wstrb, wlast, wuser, wtrace, wvalid;
    output wready;
    // B
    output bid, bresp, buser, btrace, bloop, bvalid;
    input  bready;
    // AR
    input  arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot,
           arqos, arregion, aruser, artrace, arloop, armmuvalid, arvalid;
    output arready;
    // R
    output rid, rdata, rresp, rlast, ruser, rtrace, rloop, rvalid;
    input  rready;
    input  awakeup;
  endclocking

  clocking mon_cb @(posedge aclk);
    default input #1step;
    input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot,
          awqos, awregion, awatop, awuser, awunique, awtrace, awloop,
          awmmuvalid, awvalid, awready;
    input wdata, wstrb, wlast, wuser, wtrace, wvalid, wready;
    input bid, bresp, buser, btrace, bloop, bvalid, bready;
    input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot,
          arqos, arregion, aruser, artrace, arloop, armmuvalid, arvalid, arready;
    input rid, rdata, rresp, rlast, ruser, rtrace, rloop, rvalid, rready;
    input awakeup;
  endclocking

  modport master  (clocking master_cb, input aclk, aresetn);
  modport slave   (clocking slave_cb,  input aclk, aresetn);
  modport monitor (clocking mon_cb,    input aclk, aresetn);

endinterface

// The protocol-checker module (axi5_sva_checker) is bound to the interface
// instance from the testbench top (tb/axi5_tb_top.sv) because a module may not
// be instantiated inside an interface. Disable with +define+AXI5_NO_SVA.

`endif // AXI5_IF_SV
