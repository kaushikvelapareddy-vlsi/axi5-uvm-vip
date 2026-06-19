// -----------------------------------------------------------------------------
// axi5_slave_mem.sv : a simple synthesizable-style AXI5 slave memory DUT.
// Serves as the device-under-test so the VIP master agent has a real responder
// to drive. Supports INCR/FIXED/WRAP bursts, write strobes, and EXOKAY for
// exclusive accesses (single-monitor model). Not a full ACE/coherent slave.
// -----------------------------------------------------------------------------
`ifndef AXI5_SLAVE_MEM_SV
`define AXI5_SLAVE_MEM_SV

module axi5_slave_mem #(
  parameter int ADDR_WIDTH = 64,
  parameter int DATA_WIDTH = 64,
  parameter int ID_WIDTH   = 4,
  parameter int MEM_BYTES  = 1 << 16   // 64 KB
) (
  input logic aclk,
  input logic aresetn,
  axi5_if s    // full interface: behavioral model drives slave signals directly
);

  localparam int STRB_WIDTH = DATA_WIDTH/8;

  // Error-injection window: in-range accesses whose start address falls in the
  // top 256 bytes of memory return SLVERR (vs DECERR for out-of-range). Lets
  // tests exercise the SLVERR response path with the RTL DUT. Normal corner
  // sequences keep clear of this region.
  localparam logic [ADDR_WIDTH-1:0] SLVERR_BASE = MEM_BYTES - 'h100;

  // Resolve the response code for an access: DECERR if out of range, SLVERR in
  // the error window, otherwise EXOKAY (exclusive hit) or OKAY.
  function automatic logic [1:0] resp_code(input logic [ADDR_WIDTH-1:0] addr,
                                           input logic excl_hit);
    if (addr >= MEM_BYTES)        resp_code = 2'b11;  // DECERR
    else if (addr >= SLVERR_BASE) resp_code = 2'b10;  // SLVERR
    else if (excl_hit)            resp_code = 2'b01;  // EXOKAY
    else                          resp_code = 2'b00;  // OKAY
  endfunction

  // Byte-addressable memory.
  logic [7:0] mem [0:MEM_BYTES-1];

  // ---- Exclusive monitor (single reservation) -------------------------------
  logic                  excl_valid;
  logic [ADDR_WIDTH-1:0] excl_addr;
  logic [ID_WIDTH-1:0]   excl_id;

  // Beat-address arithmetic.
  function automatic logic [ADDR_WIDTH-1:0] beat_addr(
      input logic [ADDR_WIDTH-1:0] addr, input logic [2:0] size,
      input logic [1:0] burst, input logic [7:0] len, input int n);
    int unsigned nb      = (1 << size);
    logic [ADDR_WIDTH-1:0] aligned = (addr / nb) * nb;
    case (burst)
      2'b00: beat_addr = addr;                 // FIXED
      2'b01: beat_addr = aligned + (n * nb);   // INCR
      2'b10: begin                             // WRAP
        int unsigned total = nb * (int'(len) + 1);
        logic [ADDR_WIDTH-1:0] lower = (addr / total) * total;
        logic [ADDR_WIDTH-1:0] upper = lower + total;
        logic [ADDR_WIDTH-1:0] cand  = aligned + (n * nb);
        beat_addr = (cand >= upper) ? (cand - total) : cand;
      end
      default: beat_addr = addr;
    endcase
  endfunction

  // ---------------------------------------------------------------------------
  // Configurable slave READY back-pressure (wait-states). Enabled with the
  // plusarg +SLAVE_READY_MAXWAIT=<n>; each handshake inserts 0..n idle cycles
  // with the corresponding *READY held low.
  // ---------------------------------------------------------------------------
  int unsigned ready_maxwait = 0;
  initial begin
    if (!$value$plusargs("SLAVE_READY_MAXWAIT=%d", ready_maxwait))
      ready_maxwait = 0;
  end
  function automatic int unsigned rdy_wait();
    rdy_wait = (ready_maxwait == 0) ? 0 : ($urandom % (ready_maxwait + 1));
  endfunction

  // ---- Atomic ALU helpers (AXI5 AWATOP) -------------------------------------
  // Sign-extend an nbytes-wide value to 64 bits.
  function automatic logic [63:0] sext(input logic [63:0] v, input int nbytes);
    logic [63:0] m;
    if (nbytes >= 8) return v;
    m = (64'h1 << (nbytes*8)) - 1;
    return v[nbytes*8-1] ? (v | ~m) : (v & m);
  endfunction

  // Arithmetic/logical atomic op: op[2:0] selects ADD/CLR/EOR/SET/SMAX/SMIN/
  // UMAX/UMIN. Returns the new (masked) memory value.
  function automatic logic [63:0] atop_alu(input logic [5:0] op,
                                           input logic [63:0] oldv,
                                           input logic [63:0] newv,
                                           input int nbytes);
    logic [63:0] m  = (nbytes >= 8) ? '1 : ((64'h1 << (nbytes*8)) - 1);
    logic [63:0] o  = oldv & m;
    logic [63:0] n  = newv & m;
    logic signed [63:0] so = sext(o, nbytes);
    logic signed [63:0] sn = sext(n, nbytes);
    logic [63:0] r;
    case (op[2:0])
      3'd0: r = o + n;                 // ADD
      3'd1: r = o & ~n;                // CLR (bit clear)
      3'd2: r = o ^ n;                 // EOR
      3'd3: r = o | n;                 // SET (bit set)
      3'd4: r = (so >= sn) ? o : n;    // SMAX
      3'd5: r = (so <= sn) ? o : n;    // SMIN
      3'd6: r = (o  >= n)  ? o : n;    // UMAX
      3'd7: r = (o  <= n)  ? o : n;    // UMIN
      default: r = n;
    endcase
    return r & m;
  endfunction

  // Read/write an nbytes little-endian value at a byte address.
  function automatic logic [63:0] mem_read_val(input logic [ADDR_WIDTH-1:0] a,
                                               input int nbytes);
    logic [63:0] v = '0;
    for (int i = 0; i < nbytes && i < 8; i++)
      if ((a+i) < MEM_BYTES) v[i*8 +: 8] = mem[a+i];
    return v;
  endfunction
  task automatic mem_write_val(input logic [ADDR_WIDTH-1:0] a,
                               input logic [63:0] v, input int nbytes);
    for (int i = 0; i < nbytes && i < 8; i++)
      if ((a+i) < MEM_BYTES) mem[a+i] = v[i*8 +: 8];
  endtask
  // Extract the nbytes operand from a data beat at the given byte lane.
  function automatic logic [63:0] lane_val(input logic [DATA_WIDTH-1:0] beat,
                                           input int lane0, input int nbytes);
    logic [63:0] v = '0;
    for (int i = 0; i < nbytes && i < 8; i++)
      if ((lane0+i) < STRB_WIDTH) v[i*8 +: 8] = beat[(lane0+i)*8 +: 8];
    return v;
  endfunction

  // ---------------------------------------------------------------------------
  // Initialise outputs and reservation.
  // ---------------------------------------------------------------------------
  task automatic init_outputs();
    s.awready <= 0; s.wready <= 0; s.bvalid <= 0; s.bid <= 0; s.bresp <= 0;
    s.buser <= 0; s.btrace <= 0; s.bloop <= 0;
    s.arready <= 0; s.rvalid <= 0; s.rid <= 0; s.rdata <= 0; s.rresp <= 0;
    s.rlast <= 0; s.ruser <= 0; s.rtrace <= 0; s.rloop <= 0;
    excl_valid <= 0;
  endtask

  // ---------------------------------------------------------------------------
  // Write path.
  // ---------------------------------------------------------------------------
  initial begin
    init_outputs();
    forever begin
      // X-safe reset guard: treat unknown reset as asserted so the response
      // channel is never driven before reset is cleanly released.
      while (aresetn !== 1'b1) begin init_outputs(); @(posedge aclk); end
      do_write();
    end
  end

  task automatic do_write();
    logic [ID_WIDTH-1:0]   awid;
    logic [ADDR_WIDTH-1:0] awaddr;
    logic [7:0]            awlen;
    logic [2:0]            awsize;
    logic [1:0]            awburst;
    logic                  awlock;
    logic [5:0]            awatop;
    logic [ADDR_WIDTH-1:0] ba;
    logic                  excl_ok;
    int                    nb;
    int                    total;
    // Per-beat operand buffer (used for atomic transactions).
    logic [DATA_WIDTH-1:0] wbuf [0:255];

    // Accept the write address (with optional ready wait-states).
    repeat (rdy_wait()) begin s.awready <= 0; @(posedge aclk); end
    s.awready <= 1;
    @(posedge aclk);
    while (s.awvalid !== 1'b1) @(posedge aclk);
    awid    = s.awid;   awaddr  = s.awaddr; awlen  = s.awlen;
    awsize  = s.awsize; awburst = s.awburst; awlock = s.awlock;
    awatop  = s.awatop;
    s.awready <= 0;
    nb    = (1 << awsize);
    total = nb * (int'(awlen) + 1);

    // Accept the write-data beats.
    for (int beat = 0; beat <= awlen; beat++) begin
      repeat (rdy_wait()) begin s.wready <= 0; @(posedge aclk); end
      s.wready <= 1;
      @(posedge aclk);
      while (s.wvalid !== 1'b1) @(posedge aclk);
      wbuf[beat] = s.wdata;
      // Plain (non-atomic) writes commit immediately, honouring strobes.
      if (awatop == 6'h00) begin
        ba = beat_addr(awaddr, awsize, awburst, awlen, beat);
        for (int b = 0; b < (1 << awsize); b++) begin
          int lane = (ba % STRB_WIDTH) + b;
          if (lane < STRB_WIDTH && s.wstrb[lane] && ((ba + b) < MEM_BYTES))
            mem[ba + b] = s.wdata[lane*8 +: 8];
        end
      end
    end
    s.wready <= 0;

    // -------------------------------------------------------------------------
    // Atomic transaction memory effects (AWATOP != 0). The operand(s) come from
    // the buffered write data at the addressed byte lane. AtomicStore/Load apply
    // an ALU op; Swap overwrites; Compare conditionally swaps (beat0 = compare
    // value, beat1 = swap value). Driver tracks atomics by their B response.
    // -------------------------------------------------------------------------
    if (awatop != 6'h00) begin
      int lane0 = beat_addr(awaddr, awsize, awburst, awlen, 0) % STRB_WIDTH;
      logic [ADDR_WIDTH-1:0] a0 = beat_addr(awaddr, awsize, awburst, awlen, 0);
      logic [63:0] oldv = mem_read_val(a0, nb);
      logic [63:0] m    = (nb >= 8) ? 64'hFFFF_FFFF_FFFF_FFFF
                                    : ((64'h1 << (nb*8)) - 1);
      case (awatop[5:4])
        2'b01, 2'b10: begin                 // AtomicStore / AtomicLoad
          logic [63:0] opnd = lane_val(wbuf[0], lane0, nb);
          mem_write_val(a0, atop_alu(awatop, oldv, opnd, nb), nb);
        end
        2'b11: begin                         // Swap (0x30) / Compare (0x31)
          if (awatop == 6'h31) begin         // AtomicCompare
            logic [63:0] cmp = lane_val(wbuf[0], lane0, nb);
            logic [63:0] swp = lane_val(wbuf[1], lane0, nb);
            if ((oldv & m) == (cmp & m)) mem_write_val(a0, swp, nb);
          end
          else begin                         // AtomicSwap
            mem_write_val(a0, lane_val(wbuf[0], lane0, nb), nb);
          end
        end
        default: ;
      endcase
    end

    // Resolve exclusive write against the reservation.
    excl_ok = awlock && excl_valid && (excl_id == awid) &&
              (excl_addr == awaddr);
    if (awlock) excl_valid <= 0; // any exclusive write clears the reservation
    // A normal (non-exclusive) write to a reserved location also clears it,
    // so a subsequent exclusive write must return OKAY rather than EXOKAY.
    else if (excl_valid && (excl_addr >= awaddr) &&
             (excl_addr < (awaddr + total)))
      excl_valid <= 0;

    // Issue the write response.
    repeat (rdy_wait()) @(posedge aclk);
    s.bid   <= awid;
    s.bresp <= resp_code(awaddr, awlock && excl_ok);   // DECERR/SLVERR/EXOKAY/OKAY
    s.bvalid <= 1;
    @(posedge aclk);
    while (s.bready !== 1'b1) @(posedge aclk);
    s.bvalid <= 0;
  endtask

  // ---------------------------------------------------------------------------
  // Read path.
  // ---------------------------------------------------------------------------
  initial begin
    forever begin
      // X-safe reset guard (see write path).
      while (aresetn !== 1'b1) @(posedge aclk);
      do_read();
    end
  end

  task automatic do_read();
    logic [ID_WIDTH-1:0]   arid;
    logic [ADDR_WIDTH-1:0] araddr;
    logic [7:0]            arlen;
    logic [2:0]            arsize;
    logic [1:0]            arburst;
    logic                  arlock;
    logic [ADDR_WIDTH-1:0] ba;

    repeat (rdy_wait()) begin s.arready <= 0; @(posedge aclk); end
    s.arready <= 1;
    @(posedge aclk);
    while (s.arvalid !== 1'b1) @(posedge aclk);
    arid = s.arid; araddr = s.araddr; arlen = s.arlen;
    arsize = s.arsize; arburst = s.arburst; arlock = s.arlock;
    s.arready <= 0;

    // Set the exclusive reservation on an exclusive read.
    if (arlock) begin
      excl_valid <= 1;
      excl_addr  <= araddr;
      excl_id    <= arid;
    end

    for (int beat = 0; beat <= arlen; beat++) begin
      logic [DATA_WIDTH-1:0] word = '0;
      ba = beat_addr(araddr, arsize, arburst, arlen, beat);
      for (int b = 0; b < (1 << arsize); b++) begin
        int lane = (ba % STRB_WIDTH) + b;
        if (lane < STRB_WIDTH && ((ba + b) < MEM_BYTES))
          word[lane*8 +: 8] = mem[ba + b];
      end
      @(posedge aclk);
      s.rid   <= arid;
      s.rdata <= word;
      s.rresp <= resp_code(araddr, arlock);   // DECERR/SLVERR/EXOKAY/OKAY
      s.rlast <= (beat == arlen);
      s.rvalid <= 1;
      @(posedge aclk);
      while (s.rready !== 1'b1) @(posedge aclk);
      s.rvalid <= 0;
    end
    s.rlast <= 0;
  endtask

endmodule

`endif // AXI5_SLAVE_MEM_SV
