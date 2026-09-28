// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem
// File: dma_csr_axi_lite.sv
// Description: AXI4-Lite Control/Status Register (CSR) block. Provides full
//              programming interface for channels, global configuration, and IRQs.
// Target Node & Clock: SkyWater 130nm @ 200 MHz
// Engineer: Abhijit Karale
// ============================================================================

`timescale 1ns / 1ps

module dma_csr_axi_lite
  import dma_pkg::*;
#(
  parameter int NUM_CH         = NUM_CHANNELS,
  parameter int AXIL_ADDR_WIDTH = 12,
  parameter int AXIL_DATA_WIDTH = 32
)(
  input  logic                      clk,
  input  logic                      rst_n,

  // AXI4-Lite Slave Interface
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

  // Global Subsystem Controls
  output logic                      global_dma_en,
  output logic                      global_soft_rst,
  output arb_mode_t                 global_arb_mode,
  output logic                      global_irq,

  // Per-Channel Control Outputs
  output logic [NUM_CH-1:0]         ch_en,
  output logic [NUM_CH-1:0]         ch_start,
  output logic [NUM_CH-1:0]         ch_abort,
  output logic [NUM_CH-1:0]         ch_ring_mode,
  output logic [NUM_CH-1:0]         ch_ie_done,
  output logic [NUM_CH-1:0]         ch_ie_err,
  output logic [NUM_CH-1:0]         ch_auto_wb,
  output logic [AXI_ADDR_WIDTH-1:0] ch_head_desc_ptr [NUM_CH-1:0],
  output logic [NUM_CH-1:0][1:0]    ch_priority,
  output logic [NUM_CH-1:0]         ch_irq_clear_done,
  output logic [NUM_CH-1:0]         ch_irq_clear_err,

  // Per-Channel Status Inputs
  input  logic [NUM_CH-1:0]         ch_busy,
  input  logic [NUM_CH-1:0]         ch_done,
  input  logic [NUM_CH-1:0]         ch_error,
  input  logic [3:0]                ch_fsm_state         [NUM_CH-1:0],
  input  logic [AXI_ADDR_WIDTH-1:0] ch_curr_desc_ptr     [NUM_CH-1:0],
  input  logic [31:0]               ch_bytes_transferred [NUM_CH-1:0],
  input  logic [NUM_CH-1:0]         ch_irq_line
);

  // Registers Storage
  logic [31:0] r_global_ctrl;
  logic [31:0] r_global_irq_en;
  logic [31:0] r_global_irq_status;

  logic [31:0] r_ch_ctrl     [NUM_CH-1:0];
  logic [31:0] r_ch_desc_ptr [NUM_CH-1:0];
  logic [31:0] r_ch_priority [NUM_CH-1:0];

  // AXI-Lite Handshake Logic
  logic aw_en;
  logic [AXIL_ADDR_WIDTH-1:0] axi_awaddr;
  logic [AXIL_ADDR_WIDTH-1:0] axi_araddr;

  assign s_axil_bresp = AXI_RESP_OKAY;
  assign s_axil_rresp = AXI_RESP_OKAY;

  // Global assignments
  assign global_dma_en   = r_global_ctrl[GCTRL_DMA_EN_BIT];
  assign global_soft_rst = r_global_ctrl[GCTRL_SOFT_RST_BIT];
  assign global_arb_mode = arb_mode_t'(r_global_ctrl[GCTRL_ARB_MODE_MSB:GCTRL_ARB_MODE_LSB]);

  // Channel control unpack
  always_comb begin
    for (int i = 0; i < NUM_CH; i++) begin
      ch_en[i]            = r_ch_ctrl[i][CCTRL_EN_BIT] & global_dma_en;
      ch_start[i]         = r_ch_ctrl[i][CCTRL_START_BIT];
      ch_abort[i]         = r_ch_ctrl[i][CCTRL_ABORT_BIT];
      ch_ring_mode[i]     = r_ch_ctrl[i][CCTRL_RING_MODE_BIT];
      ch_ie_done[i]       = r_ch_ctrl[i][CCTRL_IE_DONE_BIT];
      ch_ie_err[i]        = r_ch_ctrl[i][CCTRL_IE_ERR_BIT];
      ch_auto_wb[i]       = r_ch_ctrl[i][CCTRL_AUTO_WB_BIT];
      ch_head_desc_ptr[i] = r_ch_desc_ptr[i];
      ch_priority[i]      = r_ch_priority[i][1:0];
    end
  end

  // Interrupt aggregation
  assign global_irq = |(r_global_irq_status[NUM_CH-1:0] & r_global_irq_en[NUM_CH-1:0]);

  // AXI-Lite Write Address Channel
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axil_awready <= 1'b0;
      aw_en          <= 1'b1;
      axi_awaddr     <= '0;
    end else begin
      if (!s_axil_awready && s_axil_awvalid && s_axil_wvalid && aw_en) begin
        s_axil_awready <= 1'b1;
        aw_en          <= 1'b0;
        axi_awaddr     <= s_axil_awaddr;
      end else if (s_axil_bvalid && s_axil_bready) begin
        aw_en          <= 1'b1;
        s_axil_awready <= 1'b0;
      end else begin
        s_axil_awready <= 1'b0;
      end
    end
  end

  // AXI-Lite Write Data Channel & Register Writes
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axil_wready       <= 1'b0;
      s_axil_bvalid       <= 1'b0;
      r_global_ctrl       <= 32'h0000_0001; // Enable by default, Fixed Arbiter
      r_global_irq_en     <= 32'h0000_000F; // Enable all channel IRQs
      r_global_irq_status <= '0;
      for (int i = 0; i < NUM_CH; i++) begin
        r_ch_ctrl[i]      <= '0;
        r_ch_desc_ptr[i]  <= '0;
        r_ch_priority[i]  <= 32'(i);
        ch_irq_clear_done[i] <= 1'b0;
        ch_irq_clear_err[i]  <= 1'b0;
      end
    end else begin
      // Pulse clears low by default
      for (int i = 0; i < NUM_CH; i++) begin
        ch_irq_clear_done[i] <= 1'b0;
        ch_irq_clear_err[i]  <= 1'b0;
      end

      // Update interrupt status from channel hardware
      for (int i = 0; i < NUM_CH; i++) begin
        if (ch_irq_line[i]) begin
          r_global_irq_status[i] <= 1'b1;
        end
      end

      // Write handshake
      if (!s_axil_wready && s_axil_wvalid && s_axil_awvalid && aw_en) begin
        s_axil_wready <= 1'b1;
      end else begin
        s_axil_wready <= 1'b0;
      end

      // Write response
      if (s_axil_awready && s_axil_wready && !s_axil_bvalid) begin
        s_axil_bvalid <= 1'b1;
      end else if (s_axil_bvalid && s_axil_bready) begin
        s_axil_bvalid <= 1'b0;
      end

      // Register write decode
      if (s_axil_wready && s_axil_wvalid) begin
        logic [11:0] addr;
        addr = axi_awaddr;

        if (addr == ADDR_GLOBAL_CTRL) begin
          r_global_ctrl <= s_axil_wdata;
        end else if (addr == ADDR_GLOBAL_IRQ_EN) begin
          r_global_irq_en <= s_axil_wdata;
        end else if (addr == ADDR_GLOBAL_IRQ_STATUS) begin
          // Write-1-to-Clear
          r_global_irq_status <= r_global_irq_status & ~s_axil_wdata;
        end else begin
          // Per-channel registers
          for (int i = 0; i < NUM_CH; i++) begin
            logic [11:0] base;
            base = CH_BASE_OFFSET + (12'(i) * CH_STRIDE);
            if (addr == (base + CH_OFFSET_CTRL)) begin
              r_ch_ctrl[i] <= s_axil_wdata;
            end else if (addr == (base + CH_OFFSET_DESC_PTR)) begin
              r_ch_desc_ptr[i] <= s_axil_wdata;
            end else if (addr == (base + CH_OFFSET_PRIORITY)) begin
              r_ch_priority[i] <= s_axil_wdata;
            end else if (addr == (base + CH_OFFSET_IRQ_STATUS)) begin
              if (s_axil_wdata[0]) ch_irq_clear_done[i] <= 1'b1;
              if (s_axil_wdata[1]) ch_irq_clear_err[i]  <= 1'b1;
            end
          end
        end
      end
    end
  end

  // AXI-Lite Read Address Channel
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axil_arready <= 1'b0;
      s_axil_rvalid  <= 1'b0;
      s_axil_rdata   <= '0;
      axi_araddr     <= '0;
    end else begin
      if (!s_axil_arready && s_axil_arvalid) begin
        s_axil_arready <= 1'b1;
        axi_araddr     <= s_axil_araddr;
      end else begin
        s_axil_arready <= 1'b0;
      end

      if (s_axil_arready && s_axil_arvalid && !s_axil_rvalid) begin
        s_axil_rvalid <= 1'b1;
        // Read Decode
        s_axil_rdata  <= 32'h0000_0000;
        if (axi_araddr == ADDR_GLOBAL_CTRL) begin
          s_axil_rdata <= r_global_ctrl;
        end else if (axi_araddr == ADDR_GLOBAL_STATUS) begin
          // [3:0]: Active channels, [7:4]: Error channels
          s_axil_rdata <= {24'h0, ch_error, ch_busy};
        end else if (axi_araddr == ADDR_GLOBAL_IRQ_EN) begin
          s_axil_rdata <= r_global_irq_en;
        end else if (axi_araddr == ADDR_GLOBAL_IRQ_STATUS) begin
          s_axil_rdata <= r_global_irq_status;
        end else begin
          for (int i = 0; i < NUM_CH; i++) begin
            logic [11:0] base;
            base = CH_BASE_OFFSET + (12'(i) * CH_STRIDE);
            if (axi_araddr == (base + CH_OFFSET_CTRL)) begin
              s_axil_rdata <= r_ch_ctrl[i];
            end else if (axi_araddr == (base + CH_OFFSET_STATUS)) begin
              s_axil_rdata <= {24'h0, ch_fsm_state[i], 1'b0, ch_error[i], ch_done[i], ch_busy[i]};
            end else if (axi_araddr == (base + CH_OFFSET_DESC_PTR)) begin
              s_axil_rdata <= r_ch_desc_ptr[i];
            end else if (axi_araddr == (base + CH_OFFSET_CURR_DESC)) begin
              s_axil_rdata <= ch_curr_desc_ptr[i];
            end else if (axi_araddr == (base + CH_OFFSET_BYTES_XFER)) begin
              s_axil_rdata <= ch_bytes_transferred[i];
            end else if (axi_araddr == (base + CH_OFFSET_IRQ_STATUS)) begin
              s_axil_rdata <= {30'h0, ch_error[i], ch_done[i]};
            end else if (axi_araddr == (base + CH_OFFSET_PRIORITY)) begin
              s_axil_rdata <= r_ch_priority[i];
            end
          end
        end
      end else if (s_axil_rvalid && s_axil_rready) begin
        s_axil_rvalid <= 1'b0;
      end
    end
  end

endmodule
