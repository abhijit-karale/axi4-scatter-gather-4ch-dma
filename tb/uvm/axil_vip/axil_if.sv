// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: axil_if.sv
// Description: SystemVerilog interface for AXI4-Lite CSR Host-to-Device bus.
// ============================================================================

`timescale 1ns / 1ps

interface axil_if #(
  parameter int ADDR_WIDTH = 12,
  parameter int DATA_WIDTH = 32
)(
  input logic clk,
  input logic rst_n
);

  localparam int STRB_WIDTH = DATA_WIDTH / 8;

  // Write Address Channel
  logic [ADDR_WIDTH-1:0] awaddr;
  logic [2:0]            awprot;
  logic                  awvalid;
  logic                  awready;

  // Write Data Channel
  logic [DATA_WIDTH-1:0] wdata;
  logic [STRB_WIDTH-1:0] wstrb;
  logic                  wvalid;
  logic                  wready;

  // Write Response Channel
  logic [1:0]            bresp;
  logic                  bvalid;
  logic                  bready;

  // Read Address Channel
  logic [ADDR_WIDTH-1:0] araddr;
  logic [2:0]            arprot;
  logic                  arvalid;
  logic                  arready;

  // Read Data Channel
  logic [DATA_WIDTH-1:0] rdata;
  logic [1:0]            rresp;
  logic                  rvalid;
  logic                  rready;

  // Modport for Master VIP (VIP is Master, DUT is Slave)
  modport master (
    input  clk, rst_n,
    output awaddr, awprot, awvalid,
    input  awready,
    output wdata, wstrb, wvalid,
    input  wready,
    input  bresp, bvalid,
    output bready,
    output araddr, arprot, arvalid,
    input  arready,
    input  rdata, rresp, rvalid,
    output rready
  );

  // Modport for Passive Monitor
  modport monitor (
    input clk, rst_n,
    input awaddr, awprot, awvalid, awready,
    input wdata, wstrb, wvalid, wready,
    input bresp, bvalid, bready,
    input araddr, arprot, arvalid, arready,
    input rdata, rresp, rvalid, rready
  );

endinterface
