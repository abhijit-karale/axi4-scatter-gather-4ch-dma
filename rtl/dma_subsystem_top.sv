// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem
// File: dma_subsystem_top.sv
// Description: Synthesizable top-level subsystem integrating 4 DMA channels,
//              central arbiter, AXI4 burst master, and AXI4-Lite CSR register bank.
// Target Node & Clock: SkyWater 130nm @ 200 MHz
// Engineer: Abhijit Karale
// ============================================================================

`timescale 1ns / 1ps

module dma_subsystem_top
  import dma_pkg::*;
#(
  parameter int NUM_CH         = NUM_CHANNELS,
  parameter int AXI_ADDR_WIDTH = 32,
  parameter int AXI_DATA_WIDTH = 32,
  parameter int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8,
  parameter int AXI_ID_WIDTH   = 4,
  parameter int AXIL_ADDR_WIDTH= 12,
  parameter int AXIL_DATA_WIDTH= 32,
  parameter int FIFO_DEPTH     = 64
)(
  input  logic                      clk,
  input  logic                      rst_n,

  // Interrupt Outputs
  output logic [NUM_CH-1:0]         irq_ch,
  output logic                      irq_global,

  // AXI4-Lite CSR Slave Interface
  input  logic [AXIL_ADDR_WIDTH-1:0] s_axil_awaddr,
  input  logic [2:0]                 s_axil_awprot,
  input  logic                      s_axil_awvalid,
  output logic                      s_axil_awready,

  input  logic [AXIL_DATA_WIDTH-1:0] s_axil_wdata,
  input  logic [3:0]                 s_axil_wstrb,
  input  logic                      s_axil_wvalid,
  output logic                      s_axil_wready,

  output logic [1:0]                 s_axil_bresp,
  output logic                      s_axil_bvalid,
  input  logic                      s_axil_bready,

  input  logic [AXIL_ADDR_WIDTH-1:0] s_axil_araddr,
  input  logic [2:0]                 s_axil_arprot,
  input  logic                      s_axil_arvalid,
  output logic                      s_axil_arready,

  output logic [AXIL_DATA_WIDTH-1:0] s_axil_rdata,
  output logic [1:0]                 s_axil_rresp,
  output logic                      s_axil_rvalid,
  input  logic                      s_axil_rready,

  // AXI4 Master Interface
  // Read Address Channel
  output logic [AXI_ID_WIDTH-1:0]   m_axi_arid,
  output logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr,
  output logic [7:0]                m_axi_arlen,
  output logic [2:0]                m_axi_arsize,
  output logic [1:0]                m_axi_arburst,
  output logic                      m_axi_arlock,
  output logic [3:0]                m_axi_arcache,
  output logic [2:0]                m_axi_arprot,
  output logic                      m_axi_arvalid,
  input  logic                      m_axi_arready,

  // Read Data Channel
  input  logic [AXI_ID_WIDTH-1:0]   m_axi_rid,
  input  logic [AXI_DATA_WIDTH-1:0] m_axi_rdata,
  input  logic [1:0]                m_axi_rresp,
  input  logic                      m_axi_rlast,
  input  logic                      m_axi_rvalid,
  output logic                      m_axi_rready,

  // Write Address Channel
  output logic [AXI_ID_WIDTH-1:0]   m_axi_awid,
  output logic [AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
  output logic [7:0]                m_axi_awlen,
  output logic [2:0]                m_axi_awsize,
  output logic [1:0]                m_axi_awburst,
  output logic                      m_axi_awlock,
  output logic [3:0]                m_axi_awcache,
  output logic [2:0]                m_axi_awprot,
  output logic                      m_axi_awvalid,
  input  logic                      m_axi_awready,

  // Write Data Channel
  output logic [AXI_DATA_WIDTH-1:0] m_axi_wdata,
  output logic [AXI_STRB_WIDTH-1:0] m_axi_wstrb,
  output logic                      m_axi_wlast,
  output logic                      m_axi_wvalid,
  input  logic                      m_axi_wready,

  // Write Response Channel
  input  logic [AXI_ID_WIDTH-1:0]   m_axi_bid,
  input  logic [1:0]                m_axi_bresp,
  input  logic                      m_axi_bvalid,
  output logic                      m_axi_bready
);

  localparam int CH_ID_WIDTH = $clog2(NUM_CH);

  // Global control & soft reset
  logic      global_dma_en;
  logic      global_soft_rst;
  arb_mode_t global_arb_mode;
  logic      sys_rst_n;

  assign sys_rst_n = rst_n & ~global_soft_rst;

  // CSR to Channel Controls
  logic [NUM_CH-1:0]         ch_en;
  logic [NUM_CH-1:0]         ch_start;
  logic [NUM_CH-1:0]         ch_abort;
  logic [NUM_CH-1:0]         ch_ring_mode;
  logic [NUM_CH-1:0]         ch_ie_done;
  logic [NUM_CH-1:0]         ch_ie_err;
  logic [NUM_CH-1:0]         ch_auto_wb;
  logic [AXI_ADDR_WIDTH-1:0] ch_head_desc_ptr [NUM_CH-1:0];
  logic [NUM_CH-1:0][1:0]    ch_priority;
  logic [NUM_CH-1:0]         ch_irq_clear_done;
  logic [NUM_CH-1:0]         ch_irq_clear_err;

  // Channel Status to CSR
  logic [NUM_CH-1:0]         ch_busy;
  logic [NUM_CH-1:0]         ch_done;
  logic [NUM_CH-1:0]         ch_error;
  logic [3:0]                ch_fsm_state         [NUM_CH-1:0];
  logic [AXI_ADDR_WIDTH-1:0] ch_curr_desc_ptr     [NUM_CH-1:0];
  logic [31:0]               ch_bytes_transferred [NUM_CH-1:0];
  logic [NUM_CH-1:0]         ch_irq_line;

  assign irq_ch = ch_irq_line;

  // Arbiter Request / Grant Signals
  logic [NUM_CH-1:0]         req_desc_fetch;
  logic [NUM_CH-1:0]         req_data_read;
  logic [NUM_CH-1:0]         req_data_write;
  logic [NUM_CH-1:0]         req_desc_wb;

  logic                      arb_xfer_busy;
  logic                      arb_xfer_done;
  logic                      arb_xfer_err;
  logic [NUM_CH-1:0]         arb_grant;
  logic [CH_ID_WIDTH-1:0]    arb_grant_id;
  logic                      arb_grant_valid;
  logic [1:0]                arb_grant_type;

  // Channel to AXI Master Engine Signals
  logic [AXI_ADDR_WIDTH-1:0] ch_araddr  [NUM_CH-1:0];
  logic [7:0]                ch_arlen   [NUM_CH-1:0];
  logic [2:0]                ch_arsize  [NUM_CH-1:0];
  logic [AXI_ADDR_WIDTH-1:0] ch_awaddr  [NUM_CH-1:0];
  logic [7:0]                ch_awlen   [NUM_CH-1:0];
  logic [2:0]                ch_awsize  [NUM_CH-1:0];

  logic [NUM_CH-1:0]         ch_fifo_wr_en;
  logic [AXI_DATA_WIDTH-1:0] ch_fifo_wr_data;
  logic [NUM_CH-1:0]         ch_fifo_rd_en;
  logic [AXI_DATA_WIDTH-1:0] ch_fifo_rd_data [NUM_CH-1:0];

  logic [NUM_CH-1:0]         ch_desc_rvalid;
  logic [AXI_DATA_WIDTH-1:0] ch_desc_rdata;
  logic                      ch_desc_rlast;
  logic [NUM_CH-1:0]         ch_desc_rerr;
  logic [AXI_DATA_WIDTH-1:0] ch_desc_wdata   [NUM_CH-1:0];
  logic [AXI_ADDR_WIDTH-1:0] ch_desc_wb_addr [NUM_CH-1:0];
  logic [NUM_CH-1:0]         ch_desc_wb_ack;

  logic [NUM_CH-1:0]         ch_read_beat_ack;
  logic [NUM_CH-1:0]         ch_write_beat_ack;
  logic [NUM_CH-1:0]         ch_burst_complete;

  // --------------------------------------------------------------------------
  // AXI4-Lite CSR Register Block
  // --------------------------------------------------------------------------
  dma_csr_axi_lite #(
    .NUM_CH         (NUM_CH),
    .AXIL_ADDR_WIDTH(AXIL_ADDR_WIDTH),
    .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH)
  ) u_csr (
    .clk                 (clk),
    .rst_n               (sys_rst_n),
    .s_axil_awaddr       (s_axil_awaddr),
    .s_axil_awprot       (s_axil_awprot),
    .s_axil_awvalid      (s_axil_awvalid),
    .s_axil_awready      (s_axil_awready),
    .s_axil_wdata        (s_axil_wdata),
    .s_axil_wstrb        (s_axil_wstrb),
    .s_axil_wvalid       (s_axil_wvalid),
    .s_axil_wready       (s_axil_wready),
    .s_axil_bresp        (s_axil_bresp),
    .s_axil_bvalid       (s_axil_bvalid),
    .s_axil_bready       (s_axil_bready),
    .s_axil_araddr       (s_axil_araddr),
    .s_axil_arprot       (s_axil_arprot),
    .s_axil_arvalid      (s_axil_arvalid),
    .s_axil_arready      (s_axil_arready),
    .s_axil_rdata        (s_axil_rdata),
    .s_axil_rresp        (s_axil_rresp),
    .s_axil_rvalid       (s_axil_rvalid),
    .s_axil_rready       (s_axil_rready),
    .global_dma_en       (global_dma_en),
    .global_soft_rst     (global_soft_rst),
    .global_arb_mode     (global_arb_mode),
    .global_irq          (irq_global),
    .ch_en               (ch_en),
    .ch_start            (ch_start),
    .ch_abort            (ch_abort),
    .ch_ring_mode        (ch_ring_mode),
    .ch_ie_done          (ch_ie_done),
    .ch_ie_err           (ch_ie_err),
    .ch_auto_wb          (ch_auto_wb),
    .ch_head_desc_ptr    (ch_head_desc_ptr),
    .ch_priority         (ch_priority),
    .ch_irq_clear_done   (ch_irq_clear_done),
    .ch_irq_clear_err    (ch_irq_clear_err),
    .ch_busy             (ch_busy),
    .ch_done             (ch_done),
    .ch_error            (ch_error),
    .ch_fsm_state        (ch_fsm_state),
    .ch_curr_desc_ptr    (ch_curr_desc_ptr),
    .ch_bytes_transferred(ch_bytes_transferred),
    .ch_irq_line         (ch_irq_line)
  );

  // --------------------------------------------------------------------------
  // Central Multi-Channel Arbiter
  // --------------------------------------------------------------------------
  dma_arbiter #(
    .NUM_CH(NUM_CH)
  ) u_arbiter (
    .clk           (clk),
    .rst_n         (sys_rst_n),
    .arb_mode      (global_arb_mode),
    .ch_prio_weight(ch_priority),
    .req_desc_fetch(req_desc_fetch),
    .req_data_read (req_data_read),
    .req_data_write(req_data_write),
    .req_desc_wb   (req_desc_wb),
    .xfer_busy     (arb_xfer_busy),
    .xfer_done     (arb_xfer_done),
    .grant         (arb_grant),
    .grant_id      (arb_grant_id),
    .grant_valid   (arb_grant_valid),
    .grant_type    (arb_grant_type)
  );

  // --------------------------------------------------------------------------
  // DMA Channels 0..3 Instantiation
  // --------------------------------------------------------------------------
  generate
    for (genvar ch = 0; ch < NUM_CH; ch++) begin : gen_dma_channels
      dma_channel #(
        .CHANNEL_ID    (ch),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .FIFO_DEPTH    (FIFO_DEPTH),
        .MAX_BURST     (MAX_BURST_LEN)
      ) u_channel (
        .clk                 (clk),
        .rst_n               (sys_rst_n),
        .ch_en               (ch_en[ch]),
        .ch_start            (ch_start[ch]),
        .ch_abort            (ch_abort[ch]),
        .ch_ring_mode        (ch_ring_mode[ch]),
        .ch_ie_done          (ch_ie_done[ch]),
        .ch_ie_err           (ch_ie_err[ch]),
        .ch_auto_wb          (ch_auto_wb[ch]),
        .ch_head_desc_ptr    (ch_head_desc_ptr[ch]),
        .irq_clear_done      (ch_irq_clear_done[ch]),
        .irq_clear_err       (ch_irq_clear_err[ch]),
        .ch_busy             (ch_busy[ch]),
        .ch_done             (ch_done[ch]),
        .ch_error            (ch_error[ch]),
        .ch_fsm_state        (ch_fsm_state[ch]),
        .ch_curr_desc_ptr    (ch_curr_desc_ptr[ch]),
        .ch_bytes_transferred(ch_bytes_transferred[ch]),
        .irq_line            (ch_irq_line[ch]),
        .req_desc_fetch      (req_desc_fetch[ch]),
        .req_data_read       (req_data_read[ch]),
        .req_data_write      (req_data_write[ch]),
        .req_desc_wb         (req_desc_wb[ch]),
        .arb_granted         (arb_grant[ch]),
        .arb_grant_type      (arb_grant_type),
        .burst_complete      (ch_burst_complete[ch]),
        .read_beat_ack       (ch_read_beat_ack[ch]),
        .write_beat_ack      (ch_write_beat_ack[ch]),
        .bus_err             (arb_xfer_err && arb_grant[ch]),
        .ch_araddr           (ch_araddr[ch]),
        .ch_arlen            (ch_arlen[ch]),
        .ch_arsize           (ch_arsize[ch]),
        .ch_awaddr           (ch_awaddr[ch]),
        .ch_awlen            (ch_awlen[ch]),
        .ch_awsize           (ch_awsize[ch]),
        .fifo_wr_en          (ch_fifo_wr_en[ch]),
        .fifo_wr_data        (ch_fifo_wr_data),
        .fifo_rd_en          (ch_fifo_rd_en[ch]),
        .fifo_rd_data        (ch_fifo_rd_data[ch]),
        .desc_rvalid         (ch_desc_rvalid[ch]),
        .desc_rdata          (ch_desc_rdata),
        .desc_rlast          (ch_desc_rlast),
        .desc_rerr           (ch_desc_rerr[ch]),
        .desc_wdata          (ch_desc_wdata[ch]),
        .desc_wb_addr        (ch_desc_wb_addr[ch]),
        .desc_wb_ack         (ch_desc_wb_ack[ch])
      );
    end
  endgenerate

  // --------------------------------------------------------------------------
  // Central AXI4 Master Engine
  // --------------------------------------------------------------------------
  dma_axi_master #(
    .NUM_CH        (NUM_CH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_STRB_WIDTH(AXI_STRB_WIDTH),
    .AXI_ID_WIDTH  (AXI_ID_WIDTH)
  ) u_axi_master (
    .clk              (clk),
    .rst_n            (sys_rst_n),
    .grant_valid      (arb_grant_valid),
    .grant_id         (arb_grant_id),
    .grant_type       (arb_grant_type),
    .xfer_busy        (arb_xfer_busy),
    .xfer_done        (arb_xfer_done),
    .xfer_err         (arb_xfer_err),
    .ch_araddr        (ch_araddr),
    .ch_arlen         (ch_arlen),
    .ch_arsize        (ch_arsize),
    .ch_awaddr        (ch_awaddr),
    .ch_awlen         (ch_awlen),
    .ch_awsize        (ch_awsize),
    .ch_fifo_wr_en    (ch_fifo_wr_en),
    .ch_fifo_wr_data  (ch_fifo_wr_data),
    .ch_fifo_rd_en    (ch_fifo_rd_en),
    .ch_fifo_rd_data  (ch_fifo_rd_data),
    .ch_desc_rvalid   (ch_desc_rvalid),
    .ch_desc_rdata    (ch_desc_rdata),
    .ch_desc_rlast    (ch_desc_rlast),
    .ch_desc_rerr     (ch_desc_rerr),
    .ch_desc_wdata    (ch_desc_wdata),
    .ch_desc_wb_addr  (ch_desc_wb_addr),
    .ch_desc_wb_ack   (ch_desc_wb_ack),
    .ch_read_beat_ack (ch_read_beat_ack),
    .ch_write_beat_ack(ch_write_beat_ack),
    .ch_burst_complete(ch_burst_complete),
    .m_axi_arid       (m_axi_arid),
    .m_axi_araddr     (m_axi_araddr),
    .m_axi_arlen      (m_axi_arlen),
    .m_axi_arsize     (m_axi_arsize),
    .m_axi_arburst    (m_axi_arburst),
    .m_axi_arlock     (m_axi_arlock),
    .m_axi_arcache    (m_axi_arcache),
    .m_axi_arprot     (m_axi_arprot),
    .m_axi_arvalid    (m_axi_arvalid),
    .m_axi_arready    (m_axi_arready),
    .m_axi_rid        (m_axi_rid),
    .m_axi_rdata      (m_axi_rdata),
    .m_axi_rresp      (m_axi_rresp),
    .m_axi_rlast      (m_axi_rlast),
    .m_axi_rvalid     (m_axi_rvalid),
    .m_axi_rready     (m_axi_rready),
    .m_axi_awid       (m_axi_awid),
    .m_axi_awaddr     (m_axi_awaddr),
    .m_axi_awlen      (m_axi_awlen),
    .m_axi_awsize     (m_axi_awsize),
    .m_axi_awburst    (m_axi_awburst),
    .m_axi_awlock     (m_axi_awlock),
    .m_axi_awcache    (m_axi_awcache),
    .m_axi_awprot     (m_axi_awprot),
    .m_axi_awvalid    (m_axi_awvalid),
    .m_axi_awready    (m_axi_awready),
    .m_axi_wdata      (m_axi_wdata),
    .m_axi_wstrb      (m_axi_wstrb),
    .m_axi_wlast      (m_axi_wlast),
    .m_axi_wvalid     (m_axi_wvalid),
    .m_axi_wready     (m_axi_wready),
    .m_axi_bid        (m_axi_bid),
    .m_axi_bresp      (m_axi_bresp),
    .m_axi_bvalid     (m_axi_bvalid),
    .m_axi_bready     (m_axi_bready)
  );

endmodule
