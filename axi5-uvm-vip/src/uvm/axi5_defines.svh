// -----------------------------------------------------------------------------
// axi5_defines.svh : compile-time width macros for the AXI5 VIP.
// Override any of these on the command line, e.g. +define+AXI5_DATA_WIDTH=128,
// BEFORE this file is compiled. The interface parameters and the package use
// these consistently so the whole VIP scales together.
// -----------------------------------------------------------------------------
`ifndef AXI5_DEFINES_SVH
`define AXI5_DEFINES_SVH

`ifndef AXI5_ADDR_WIDTH
  `define AXI5_ADDR_WIDTH 64
`endif

`ifndef AXI5_DATA_WIDTH
  `define AXI5_DATA_WIDTH 64
`endif

`ifndef AXI5_ID_WIDTH
  `define AXI5_ID_WIDTH 4
`endif

`ifndef AXI5_USER_WIDTH
  `define AXI5_USER_WIDTH 4
`endif

`define AXI5_STRB_WIDTH (`AXI5_DATA_WIDTH/8)

`endif // AXI5_DEFINES_SVH
