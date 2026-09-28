// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: axi_types.sv
// Description: Common types, enums, and constants for AXI VIP.
// ============================================================================

`timescale 1ns / 1ps

package axi_vip_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum logic [1:0] {
    AXI_BURST_FIXED    = 2'b00,
    AXI_BURST_INCR     = 2'b01,
    AXI_BURST_WRAP     = 2'b10,
    AXI_BURST_RESERVED = 2'b11
  } axi_burst_enum_t;

  typedef enum logic [1:0] {
    AXI_RESP_OKAY   = 2'b00,
    AXI_RESP_EXOKAY = 2'b01,
    AXI_RESP_SLVERR = 2'b10,
    AXI_RESP_DECERR = 2'b11
  } axi_resp_enum_t;

  typedef enum {
    AXI_TRANS_READ,
    AXI_TRANS_WRITE
  } axi_trans_type_e;

endpackage: axi_vip_pkg
