// -----------------------------------------------------------------------------
// axi5_types.svh : AXI5 enumerations, parameters, and helper functions.
// AMBA AXI5 (ARM IHI 0022H).
// -----------------------------------------------------------------------------
`ifndef AXI5_TYPES_SVH
`define AXI5_TYPES_SVH

// ---- Burst types (AxBURST[1:0]) --------------------------------------------
typedef enum bit [1:0] {
  AXI5_FIXED = 2'b00,
  AXI5_INCR  = 2'b01,
  AXI5_WRAP  = 2'b10,
  AXI5_BURST_RSVD = 2'b11
} axi5_burst_e;

// ---- Response (xRESP[1:0]) --------------------------------------------------
typedef enum bit [1:0] {
  AXI5_OKAY   = 2'b00,
  AXI5_EXOKAY = 2'b01,
  AXI5_SLVERR = 2'b10,
  AXI5_DECERR = 2'b11
} axi5_resp_e;

// ---- Lock (AxLOCK) : AXI4/5 is 1 bit -- normal vs exclusive -----------------
typedef enum bit {
  AXI5_NORMAL    = 1'b0,
  AXI5_EXCLUSIVE = 1'b1
} axi5_lock_e;

// ---- AWATOP[5:0] atomic operations (AXI5) -----------------------------------
//   [5:4] : 00 NonAtomic, 01 AtomicStore, 10 AtomicLoad, 11 Swap/Compare
//   [3]   : endianness for arithmetic ops
//   [2:0] : arithmetic op for Store/Load (ADD, CLR, EOR, SET, SMAX, SMIN, UMAX, UMIN)
typedef enum bit [5:0] {
  AXI5_ATOP_NONE        = 6'h00,
  AXI5_ATOP_STORE_ADD   = 6'h10,
  AXI5_ATOP_STORE_CLR   = 6'h11,
  AXI5_ATOP_STORE_EOR   = 6'h12,
  AXI5_ATOP_STORE_SET   = 6'h13,
  AXI5_ATOP_STORE_SMAX  = 6'h14,
  AXI5_ATOP_STORE_SMIN  = 6'h15,
  AXI5_ATOP_STORE_UMAX  = 6'h16,
  AXI5_ATOP_STORE_UMIN  = 6'h17,
  AXI5_ATOP_LOAD_ADD    = 6'h20,
  AXI5_ATOP_LOAD_CLR    = 6'h21,
  AXI5_ATOP_LOAD_EOR    = 6'h22,
  AXI5_ATOP_LOAD_SET    = 6'h23,
  AXI5_ATOP_LOAD_SMAX   = 6'h24,
  AXI5_ATOP_LOAD_SMIN   = 6'h25,
  AXI5_ATOP_LOAD_UMAX   = 6'h26,
  AXI5_ATOP_LOAD_UMIN   = 6'h27,
  AXI5_ATOP_SWAP        = 6'h30,
  AXI5_ATOP_COMPARE     = 6'h31
} axi5_atop_e;

// ---- Transaction kind -------------------------------------------------------
typedef enum bit {
  AXI5_WRITE = 1'b0,
  AXI5_READ  = 1'b1
} axi5_dir_e;

// ---- AxSIZE legal values 0..7 -> 1..128 bytes/beat --------------------------
function automatic int axi5_size_bytes(bit [2:0] size);
  return (1 << size);
endfunction

// ---- AxLEN -> number of beats (AXI4/5: LEN+1, max 256 for INCR) -------------
function automatic int axi5_num_beats(bit [7:0] len);
  return int'(len) + 1;
endfunction

// Aligned address for a beat, per spec address arithmetic (A3.4.1).
function automatic longint unsigned axi5_aligned_addr(
    longint unsigned addr, bit [2:0] size);
  int unsigned nb = axi5_size_bytes(size);
  return (addr / nb) * nb;
endfunction

// Wrap boundary (lower address of the wrap window) for a WRAP burst.
function automatic longint unsigned axi5_wrap_boundary(
    longint unsigned addr, bit [2:0] size, bit [7:0] len);
  int unsigned nb        = axi5_size_bytes(size);
  int unsigned beats     = axi5_num_beats(len);
  longint unsigned total = nb * beats;
  return (addr / total) * total;
endfunction

`endif // AXI5_TYPES_SVH
