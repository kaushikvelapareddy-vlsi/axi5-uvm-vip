// -----------------------------------------------------------------------------
// axi5_ref_mem.svh : sparse reference memory model (byte addressable).
// Used by the scoreboard to predict read data and by the slave responder.
// -----------------------------------------------------------------------------
`ifndef AXI5_REF_MEM_SVH
`define AXI5_REF_MEM_SVH

class axi5_ref_mem extends uvm_object;
  `uvm_object_utils(axi5_ref_mem)

  // Sparse storage: byte address -> byte value.
  protected byte unsigned mem [bit [63:0]];

  function new(string name = "axi5_ref_mem");
    super.new(name);
  endfunction

  function void write_byte(bit [63:0] a, byte unsigned d);
    mem[a] = d;
  endfunction

  function byte unsigned read_byte(bit [63:0] a);
    return mem.exists(a) ? mem[a] : 8'h00;
  endfunction

  function bit exists(bit [63:0] a);
    return mem.exists(a);
  endfunction

  // Apply a write burst beat, honouring strobes.
  function void apply_write_beat(bit [63:0] beat_addr,
                                 bit [`AXI5_DATA_WIDTH-1:0] data,
                                 bit [`AXI5_DATA_WIDTH/8-1:0] strb,
                                 int size);
    int nb = (1 << size);
    // Byte lane within the bus that this transfer occupies.
    int lane0 = beat_addr % (`AXI5_DATA_WIDTH/8);
    for (int b = 0; b < nb; b++) begin
      int lane = lane0 + b;
      if (lane < (`AXI5_DATA_WIDTH/8) && strb[lane])
        write_byte(beat_addr + b, data[lane*8 +: 8]);
    end
  endfunction

  // ---- Atomic model (mirrors the DUT ALU for end-to-end checking) -----------
  function bit [63:0] sext(bit [63:0] v, int nbytes);
    bit [63:0] m;
    if (nbytes >= 8) return v;
    m = (64'h1 << (nbytes*8)) - 1;
    return v[nbytes*8-1] ? (v | ~m) : (v & m);
  endfunction

  function bit [63:0] atop_alu(bit [5:0] op, bit [63:0] oldv,
                               bit [63:0] newv, int nbytes);
    bit [63:0] m = (nbytes >= 8) ? '1 : ((64'h1 << (nbytes*8)) - 1);
    bit [63:0] o = oldv & m;
    bit [63:0] n = newv & m;
    bit signed [63:0] so = sext(o, nbytes);
    bit signed [63:0] sn = sext(n, nbytes);
    bit [63:0] r;
    case (op[2:0])
      3'd0: r = o + n;              // ADD
      3'd1: r = o & ~n;             // CLR
      3'd2: r = o ^ n;              // EOR
      3'd3: r = o | n;              // SET
      3'd4: r = (so >= sn) ? o : n; // SMAX
      3'd5: r = (so <= sn) ? o : n; // SMIN
      3'd6: r = (o  >= n)  ? o : n; // UMAX
      3'd7: r = (o  <= n)  ? o : n; // UMIN
      default: r = n;
    endcase
    return r & m;
  endfunction

  function bit [63:0] mem_read_val(bit [63:0] a, int nbytes);
    bit [63:0] v = '0;
    for (int i = 0; i < nbytes && i < 8; i++) v[i*8 +: 8] = read_byte(a + i);
    return v;
  endfunction
  function void mem_write_val(bit [63:0] a, bit [63:0] v, int nbytes);
    for (int i = 0; i < nbytes && i < 8; i++) write_byte(a + i, v[i*8 +: 8]);
  endfunction
  function bit [63:0] lane_val(bit [`AXI5_DATA_WIDTH-1:0] beat,
                               int lane0, int nbytes);
    bit [63:0] v = '0;
    for (int i = 0; i < nbytes && i < 8; i++)
      if ((lane0+i) < (`AXI5_DATA_WIDTH/8)) v[i*8 +: 8] = beat[(lane0+i)*8 +: 8];
    return v;
  endfunction

  // Apply an atomic transaction's memory effect. `a0` is beat-0 address;
  // beat0/beat1 are the first two write-data beats (beat1 used by Compare).
  function void apply_atomic(bit [63:0] a0, bit [5:0] atop, int size,
                             bit [`AXI5_DATA_WIDTH-1:0] beat0,
                             bit [`AXI5_DATA_WIDTH-1:0] beat1);
    int nb       = (1 << size);
    int lane0    = a0 % (`AXI5_DATA_WIDTH/8);
    bit [63:0] oldv = mem_read_val(a0, nb);
    bit [63:0] m = (nb >= 8) ? '1 : ((64'h1 << (nb*8)) - 1);
    case (atop[5:4])
      2'b01, 2'b10: begin                 // AtomicStore / AtomicLoad
        mem_write_val(a0,
          atop_alu(atop, oldv, lane_val(beat0, lane0, nb), nb), nb);
      end
      2'b11: begin
        if (atop == 6'h31) begin
          bit [63:0] cmp = lane_val(beat0, lane0, nb);
          bit [63:0] swp = lane_val(beat1, lane0, nb);
          if ((oldv & m) == (cmp & m)) mem_write_val(a0, swp, nb);
        end
        else mem_write_val(a0, lane_val(beat0, lane0, nb), nb);
      end
      default: ;
    endcase
  endfunction

  // Predict a read beat's data word from memory.
  function bit [`AXI5_DATA_WIDTH-1:0] predict_read_beat(bit [63:0] beat_addr,
                                                        int size);
    bit [`AXI5_DATA_WIDTH-1:0] word = '0;
    int nb    = (1 << size);
    int lane0 = beat_addr % (`AXI5_DATA_WIDTH/8);
    for (int b = 0; b < nb; b++) begin
      int lane = lane0 + b;
      if (lane < (`AXI5_DATA_WIDTH/8))
        word[lane*8 +: 8] = read_byte(beat_addr + b);
    end
    return word;
  endfunction

endclass

`endif // AXI5_REF_MEM_SVH
