// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem
// File: dma_formal_bind.sv
// Description: Formal bind wrapper connecting dma_sva_props to the DUT.
// Target Node & Clock: SkyWater 130nm @ 200 MHz
// Engineer: Abhijit Karale
// ============================================================================

`timescale 1ns / 1ps

module dma_formal_bind;

  bind dma_subsystem_top dma_sva_props #(
    .NUM_CH         (NUM_CH),
    .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
    .AXI_ID_WIDTH   (AXI_ID_WIDTH)
  ) u_sva_checker (
    .clk            (clk),
    .rst_n          (sys_rst_n),
    .m_axi_araddr   (m_axi_araddr),
    .m_axi_arlen    (m_axi_arlen),
    .m_axi_arsize   (m_axi_arsize),
    .m_axi_arvalid  (m_axi_arvalid),
    .m_axi_arready  (m_axi_arready),
    .m_axi_awaddr   (m_axi_awaddr),
    .m_axi_awlen    (m_axi_awlen),
    .m_axi_awsize   (m_axi_awsize),
    .m_axi_awvalid  (m_axi_awvalid),
    .m_axi_awready  (m_axi_awready),
    .m_axi_wdata    (m_axi_wdata),
    .m_axi_wlast    (m_axi_wlast),
    .m_axi_wvalid   (m_axi_wvalid),
    .m_axi_wready   (m_axi_wready),
    .m_axi_rvalid   (m_axi_rvalid),
    .m_axi_rready   (m_axi_rready),
    .m_axi_rlast    (m_axi_rlast),
    .m_axi_bvalid   (m_axi_bvalid),
    .m_axi_bready   (m_axi_bready),
    .arb_grant      (arb_grant),
    .arb_grant_valid(arb_grant_valid),
    .arb_xfer_busy  (arb_xfer_busy),
    .arb_xfer_done  (arb_xfer_done),
    .ch_busy        (ch_busy),
    .ch_done        (ch_done),
    .ch_error       (ch_error),
    .irq_ch         (irq_ch),
    .irq_global     (irq_global)
  );

endmodule
