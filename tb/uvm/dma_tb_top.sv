// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: dma_tb_top.sv
// Description: Top-level verification harness instantiating DUT, AXI/AXIL
//              interfaces, clock/reset generation, and kicking off UVM test.
// Target Node & Clock: SkyWater 130nm @ 200 MHz (5.0 ns period)
// Engineer: Abhijit Karale
// ============================================================================

`timescale 1ns / 1ps

module dma_tb_top;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import dma_pkg::*;
  import dma_uvm_pkg::*;

  // 200 MHz Clock Generation (5.0 ns clock period)
  logic clk;
  logic rst_n;

  initial begin
    clk = 1'b0;
    forever #2.5ns clk = ~clk; // 200 MHz
  end

  // Power-On Reset Generation
  initial begin
    rst_n = 1'b0;
    #25ns;
    rst_n = 1'b1;
  end

  // Subsystem Interrupt Lines
  logic [NUM_CHANNELS-1:0] irq_ch;
  logic                    irq_global;

  // AXI4-Lite CSR Interface
  axil_if #(
    .ADDR_WIDTH(AXIL_ADDR_WIDTH),
    .DATA_WIDTH(AXIL_DATA_WIDTH)
  ) u_axil_if (
    .clk  (clk),
    .rst_n(rst_n)
  );

  // AXI4 Master Memory Interface
  axi_if #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH),
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH  (AXI_ID_WIDTH)
  ) u_axi_if (
    .clk  (clk),
    .rst_n(rst_n)
  );

  // Instantiate Design Under Test (DUT)
  dma_subsystem_top #(
    .NUM_CH         (NUM_CHANNELS),
    .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
    .AXI_STRB_WIDTH (AXI_STRB_WIDTH),
    .AXI_ID_WIDTH   (AXI_ID_WIDTH),
    .AXIL_ADDR_WIDTH(AXIL_ADDR_WIDTH),
    .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH),
    .FIFO_DEPTH     (FIFO_DEPTH)
  ) u_dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .irq_ch         (irq_ch),
    .irq_global     (irq_global),

    // AXI4-Lite CSR Slave Interface
    .s_axil_awaddr  (u_axil_if.awaddr),
    .s_axil_awprot  (u_axil_if.awprot),
    .s_axil_awvalid (u_axil_if.awvalid),
    .s_axil_awready (u_axil_if.awready),
    .s_axil_wdata   (u_axil_if.wdata),
    .s_axil_wstrb   (u_axil_if.wstrb),
    .s_axil_wvalid  (u_axil_if.wvalid),
    .s_axil_wready  (u_axil_if.wready),
    .s_axil_bresp   (u_axil_if.bresp),
    .s_axil_bvalid  (u_axil_if.bvalid),
    .s_axil_bready  (u_axil_if.bready),
    .s_axil_araddr  (u_axil_if.araddr),
    .s_axil_arprot  (u_axil_if.arprot),
    .s_axil_arvalid (u_axil_if.arvalid),
    .s_axil_arready (u_axil_if.arready),
    .s_axil_rdata   (u_axil_if.rdata),
    .s_axil_rresp   (u_axil_if.rresp),
    .s_axil_rvalid  (u_axil_if.rvalid),
    .s_axil_rready  (u_axil_if.rready),

    // AXI4 Master Memory Interface
    .m_axi_arid     (u_axi_if.arid),
    .m_axi_araddr   (u_axi_if.araddr),
    .m_axi_arlen    (u_axi_if.arlen),
    .m_axi_arsize   (u_axi_if.arsize),
    .m_axi_arburst  (u_axi_if.arburst),
    .m_axi_arlock   (u_axi_if.arlock),
    .m_axi_arcache  (u_axi_if.arcache),
    .m_axi_arprot   (u_axi_if.arprot),
    .m_axi_arvalid  (u_axi_if.arvalid),
    .m_axi_arready  (u_axi_if.arready),
    .m_axi_rid      (u_axi_if.rid),
    .m_axi_rdata    (u_axi_if.rdata),
    .m_axi_rresp    (u_axi_if.rresp),
    .m_axi_rlast    (u_axi_if.rlast),
    .m_axi_rvalid   (u_axi_if.rvalid),
    .m_axi_rready   (u_axi_if.rready),
    .m_axi_awid     (u_axi_if.awid),
    .m_axi_awaddr   (u_axi_if.awaddr),
    .m_axi_awlen    (u_axi_if.awlen),
    .m_axi_awsize   (u_axi_if.awsize),
    .m_axi_awburst  (u_axi_if.awburst),
    .m_axi_awlock   (u_axi_if.awlock),
    .m_axi_awcache  (u_axi_if.awcache),
    .m_axi_awprot   (u_axi_if.awprot),
    .m_axi_awvalid  (u_axi_if.awvalid),
    .m_axi_awready  (u_axi_if.awready),
    .m_axi_wdata    (u_axi_if.wdata),
    .m_axi_wstrb    (u_axi_if.wstrb),
    .m_axi_wlast    (u_axi_if.wlast),
    .m_axi_wvalid   (u_axi_if.wvalid),
    .m_axi_wready   (u_axi_if.wready),
    .m_axi_bid      (u_axi_if.bid),
    .m_axi_bresp    (u_axi_if.bresp),
    .m_axi_bvalid   (u_axi_if.bvalid),
    .m_axi_bready   (u_axi_if.bready)
  );

  // UVM Test Execution
  initial begin
    // Pass virtual interfaces to UVM DB
    uvm_config_db#(virtual axil_if)::set(null, "*", "axil_vif", u_axil_if);
    uvm_config_db#(virtual axi_if)::set(null, "*", "axi_vif", u_axi_if);

    // Waveform Dump Setup
    if ($test$plusargs("DUMP_WAVEFORMS")) begin
      $dumpfile("dma_sim.vcd");
      $dumpvars(0, dma_tb_top);
    end

    // Run registered UVM test
    run_test();
  end

endmodule
