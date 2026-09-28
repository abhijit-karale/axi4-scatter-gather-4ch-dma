// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: axi_if.sv
// Description: SystemVerilog interface for AXI4 Master-to-Slave memory bus.
// ============================================================================

`timescale 1ns / 1ps

interface axi_if #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter int ID_WIDTH   = 4
)(
  input logic clk,
  input logic rst_n
);

  localparam int STRB_WIDTH = DATA_WIDTH / 8;

  // Read Address Channel
  logic [ID_WIDTH-1:0]   arid;
  logic [ADDR_WIDTH-1:0] araddr;
  logic [7:0]            arlen;
  logic [2:0]            arsize;
  logic [1:0]            arburst;
  logic                  arlock;
  logic [3:0]            arcache;
  logic [2:0]            arprot;
  logic                  arvalid;
  logic                  arready;

  // Read Data Channel
  logic [ID_WIDTH-1:0]   rid;
  logic [DATA_WIDTH-1:0] rdata;
  logic [1:0]            rresp;
  logic                  rlast;
  logic                  rvalid;
  logic                  rready;

  // Write Address Channel
  logic [ID_WIDTH-1:0]   awid;
  logic [ADDR_WIDTH-1:0] awaddr;
  logic [7:0]            awlen;
  logic [2:0]            awsize;
  logic [1:0]            awburst;
  logic                  awlock;
  logic [3:0]            awcache;
  logic [2:0]            awprot;
  logic                  awvalid;
  logic                  awready;

  // Write Data Channel
  logic [DATA_WIDTH-1:0] wdata;
  logic [STRB_WIDTH-1:0] wstrb;
  logic                  wlast;
  logic                  wvalid;
  logic                  wready;

  // Write Response Channel
  logic [ID_WIDTH-1:0]   bid;
  logic [1:0]            bresp;
  logic                  bvalid;
  logic                  bready;

  // Modport for Slave memory VIP (DUT is Master, VIP is Slave)
  modport slave (
    input  clk, rst_n,
    input  arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arvalid,
    output arready,
    output rid, rdata, rresp, rlast, rvalid,
    input  rready,
    input  awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awvalid,
    output awready,
    input  wdata, wstrb, wlast, wvalid,
    output wready,
    output bid, bresp, bvalid,
    input  bready
  );

  // Modport for Passive Monitor
  modport monitor (
    input clk, rst_n,
    input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arvalid, arready,
    input rid, rdata, rresp, rlast, rvalid, rready,
    input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awvalid, awready,
    input wdata, wstrb, wlast, wvalid, wready,
    input bid, bresp, bvalid, bready
  );

endinterface
