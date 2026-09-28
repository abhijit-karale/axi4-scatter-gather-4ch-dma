// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem
// File: dma_axi_master.sv
// Description: AXI4 Master engine supporting high-throughput read/write bursts,
//              4KB address boundary crossing protection, and multi-channel routing.
// Target Node & Clock: SkyWater 130nm @ 200 MHz
// Engineer: Abhijit Karale
// ============================================================================

`timescale 1ns / 1ps

module dma_axi_master
  import dma_pkg::*;
#(
  parameter int NUM_CH         = NUM_CHANNELS,
  parameter int AXI_ADDR_WIDTH = 32,
  parameter int AXI_DATA_WIDTH = 32,
  parameter int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8,
  parameter int AXI_ID_WIDTH   = 4
)(
  input  logic                      clk,
  input  logic                      rst_n,

  // Central Arbiter Interface
  input  logic                      grant_valid,
  input  logic [$clog2(NUM_CH)-1:0] grant_id,
  input  logic [1:0]                grant_type,      // 00:DESC_FETCH, 01:DATA_READ, 10:DATA_WRITE, 11:DESC_WB
  output logic                      xfer_busy,
  output logic                      xfer_done,
  output logic                      xfer_err,

  // Channel Transaction Requests (from granted channel)
  input  wire axi_addr_t            ch_araddr       [NUM_CH-1:0],
  input  wire axi_len_t             ch_arlen        [NUM_CH-1:0],
  input  wire axi_size_t            ch_arsize       [NUM_CH-1:0],
  input  wire axi_addr_t            ch_awaddr       [NUM_CH-1:0],
  input  wire axi_len_t             ch_awlen        [NUM_CH-1:0],
  input  wire axi_size_t            ch_awsize       [NUM_CH-1:0],

  // Channel Data FIFO Interfaces
  // Read path: Master writes incoming RDATA into granted channel's FIFO
  output logic [NUM_CH-1:0]         ch_fifo_wr_en,
  output logic [AXI_DATA_WIDTH-1:0] ch_fifo_wr_data,
  // Write path: Master reads outgoing WDATA from granted channel's FIFO
  output logic [NUM_CH-1:0]         ch_fifo_rd_en,
  input  wire axi_data_t            ch_fifo_rd_data [NUM_CH-1:0],

  // Descriptor Engine Interfaces
  output logic [NUM_CH-1:0]         ch_desc_rvalid,
  output logic [AXI_DATA_WIDTH-1:0] ch_desc_rdata,
  output logic                      ch_desc_rlast,
  output logic [NUM_CH-1:0]         ch_desc_rerr,
  input  wire axi_data_t            ch_desc_wdata   [NUM_CH-1:0],
  input  wire axi_addr_t            ch_desc_wb_addr [NUM_CH-1:0],
  output logic [NUM_CH-1:0]         ch_desc_wb_ack,

  // Channel Burst Progress Tracking
  output logic [NUM_CH-1:0]                    ch_read_beat_ack,
  output logic [NUM_CH-1:0]                    ch_write_beat_ack,
  output logic [NUM_CH-1:0]                    ch_burst_complete,

  // AXI4 Master Interface
  // Read Address Channel
  output logic [AXI_ID_WIDTH-1:0]              m_axi_arid,
  output logic [AXI_ADDR_WIDTH-1:0]            m_axi_araddr,
  output logic [7:0]                           m_axi_arlen,
  output logic [2:0]                           m_axi_arsize,
  output logic [1:0]                           m_axi_arburst,
  output logic                                 m_axi_arlock,
  output logic [3:0]                           m_axi_arcache,
  output logic [2:0]                           m_axi_arprot,
  output logic                                 m_axi_arvalid,
  input  logic                                 m_axi_arready,

  // Read Data Channel
  input  logic [AXI_ID_WIDTH-1:0]              m_axi_rid,
  input  logic [AXI_DATA_WIDTH-1:0]            m_axi_rdata,
  input  logic [1:0]                           m_axi_rresp,
  input  logic                                 m_axi_rlast,
  input  logic                                 m_axi_rvalid,
  output logic                                 m_axi_rready,

  // Write Address Channel
  output logic [AXI_ID_WIDTH-1:0]              m_axi_awid,
  output logic [AXI_ADDR_WIDTH-1:0]            m_axi_awaddr,
  output logic [7:0]                           m_axi_awlen,
  output logic [2:0]                           m_axi_awsize,
  output logic [1:0]                           m_axi_awburst,
  output logic                                 m_axi_awlock,
  output logic [3:0]                           m_axi_awcache,
  output logic [2:0]                           m_axi_awprot,
  output logic                                 m_axi_awvalid,
  input  logic                                 m_axi_awready,

  // Write Data Channel
  output logic [AXI_DATA_WIDTH-1:0]            m_axi_wdata,
  output logic [AXI_STRB_WIDTH-1:0]            m_axi_wstrb,
  output logic                                 m_axi_wlast,
  output logic                                 m_axi_wvalid,
  input  logic                                 m_axi_wready,

  // Write Response Channel
  input  logic [AXI_ID_WIDTH-1:0]              m_axi_bid,
  input  logic [1:0]                           m_axi_bresp,
  input  logic                                 m_axi_bvalid,
  output logic                                 m_axi_bready
);

  localparam int CH_ID_WIDTH = $clog2(NUM_CH);

  // FSM States
  typedef enum logic [2:0] {
    MST_IDLE        = 3'b000,
    MST_AR_ADDR     = 3'b001,
    MST_R_DATA      = 3'b010,
    MST_AW_ADDR     = 3'b011,
    MST_W_DATA      = 3'b100,
    MST_B_RESP      = 3'b101,
    MST_COMPLETE    = 3'b110
  } mst_state_t;

  mst_state_t state, state_next;

  // Active Transaction Registers
  logic [CH_ID_WIDTH-1:0]   curr_ch;
  logic [1:0]               curr_type;
  logic [AXI_ADDR_WIDTH-1:0] target_addr;
  logic [7:0]               target_len;
  logic [2:0]               target_size;
  logic [7:0]               wbeat_count;

  // Constant AXI bus attributes
  assign m_axi_arid    = {{(AXI_ID_WIDTH-CH_ID_WIDTH){1'b0}}, curr_ch};
  assign m_axi_awid    = {{(AXI_ID_WIDTH-CH_ID_WIDTH){1'b0}}, curr_ch};
  assign m_axi_arburst = AXI_BURST_INCR;
  assign m_axi_awburst = AXI_BURST_INCR;
  assign m_axi_arlock  = 1'b0;
  assign m_axi_awlock  = 1'b0;
  assign m_axi_arcache = 4'b0011; // Modifiable bufferable
  assign m_axi_awcache = 4'b0011;
  assign m_axi_arprot  = 3'b000;
  assign m_axi_awprot  = 3'b000;
  assign m_axi_bready  = 1'b1;
  assign m_axi_rready  = 1'b1;

  assign xfer_busy = (state != MST_IDLE);

  // Address Boundary Check (4KB protection calculation)
  function automatic logic [7:0] clamp_to_4kb(
    input logic [AXI_ADDR_WIDTH-1:0] addr,
    input logic [7:0]                req_len,
    input logic [2:0]                size
  );
    logic [11:0] page_offset;
    logic [12:0] bytes_to_boundary;
    logic [7:0]  max_beats;
    begin
      page_offset       = addr[11:0];
      bytes_to_boundary = 13'h1000 - {1'b0, page_offset};
      max_beats         = (bytes_to_boundary >> size) - 1'b1;
      if (req_len > max_beats) begin
        clamp_to_4kb = max_beats;
      end else begin
        clamp_to_4kb = req_len;
      end
    end
  endfunction

  // Master FSM Transitions
  always_comb begin
    state_next = state;
    case (state)
      MST_IDLE: begin
        if (grant_valid) begin
          case (grant_type)
            2'b00: state_next = MST_AR_ADDR; // DESC_FETCH
            2'b01: state_next = MST_AR_ADDR; // DATA_READ
            2'b10: state_next = MST_AW_ADDR; // DATA_WRITE
            2'b11: state_next = MST_AW_ADDR; // DESC_WB
            default: state_next = MST_IDLE;
          endcase
        end
      end

      MST_AR_ADDR: begin
        if (m_axi_arvalid && m_axi_arready) begin
          state_next = MST_R_DATA;
        end
      end

      MST_R_DATA: begin
        if (m_axi_rvalid && m_axi_rready && m_axi_rlast) begin
          state_next = MST_COMPLETE;
        end
      end

      MST_AW_ADDR: begin
        if (m_axi_awvalid && m_axi_awready) begin
          state_next = MST_W_DATA;
        end
      end

      MST_W_DATA: begin
        if (m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
          state_next = MST_B_RESP;
        end
      end

      MST_B_RESP: begin
        if (m_axi_bvalid && m_axi_bready) begin
          state_next = MST_COMPLETE;
        end
      end

      MST_COMPLETE: begin
        state_next = MST_IDLE;
      end

      default: state_next = MST_IDLE;
    endcase
  end

  always_ff @(posedge clk) begin
    if (state != state_next) begin
      $display("[%0t] [MST_FSM] %s -> %s, ch=%0d, type=%b, len=%0d, addr=%08x",
               $time, state.name(), state_next.name(), curr_ch, curr_type, target_len, target_addr);
    end
  end

  // Sequential Logic & Counter Updates
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state         <= MST_IDLE;
      curr_ch       <= '0;
      curr_type     <= '0;
      target_addr   <= '0;
      target_len    <= '0;
      target_size   <= 3'b010; // 4 bytes
      wbeat_count   <= '0;
      xfer_done     <= 1'b0;
      xfer_err      <= 1'b0;
    end else begin
      state     <= state_next;
      xfer_done <= 1'b0;
      xfer_err  <= 1'b0;

      case (state)
        MST_IDLE: begin
          if (grant_valid) begin
            curr_ch   <= grant_id;
            curr_type <= grant_type;
            case (grant_type)
              2'b00: begin // DESC_FETCH: 8 beats of 32-bit words
                target_addr <= ch_araddr[grant_id];
                target_len  <= 8'd7; // 8 beats
                target_size <= 3'b010;
              end
              2'b01: begin // DATA_READ
                target_addr <= ch_araddr[grant_id];
                target_len  <= clamp_to_4kb(ch_araddr[grant_id], ch_arlen[grant_id], ch_arsize[grant_id]);
                target_size <= ch_arsize[grant_id];
              end
              2'b10: begin // DATA_WRITE
                target_addr <= ch_awaddr[grant_id];
                target_len  <= clamp_to_4kb(ch_awaddr[grant_id], ch_awlen[grant_id], ch_awsize[grant_id]);
                target_size <= ch_awsize[grant_id];
              end
              2'b11: begin // DESC_WB: Single beat write
                target_addr <= ch_desc_wb_addr[grant_id];
                target_len  <= 8'd0; // 1 beat
                target_size <= 3'b010;
              end
            endcase
            wbeat_count <= '0;
          end
        end

        MST_W_DATA: begin
          if (m_axi_wvalid && m_axi_wready) begin
            wbeat_count <= wbeat_count + 1'b1;
          end
        end

        MST_R_DATA: begin
          if (m_axi_rvalid && m_axi_rready && (m_axi_rresp != AXI_RESP_OKAY)) begin
            xfer_err <= 1'b1;
          end
        end

        MST_B_RESP: begin
          if (m_axi_bvalid && m_axi_bready && (m_axi_bresp != AXI_RESP_OKAY)) begin
            xfer_err <= 1'b1;
          end
        end

        MST_COMPLETE: begin
          xfer_done <= 1'b1;
        end

        default: ;
      endcase
    end
  end

  // AXI Address & Control Outputs
  assign m_axi_araddr  = target_addr;
  assign m_axi_arlen   = target_len;
  assign m_axi_arsize  = target_size;
  assign m_axi_arvalid = (state == MST_AR_ADDR);

  assign m_axi_awaddr  = target_addr;
  assign m_axi_awlen   = target_len;
  assign m_axi_awsize  = target_size;
  assign m_axi_awvalid = (state == MST_AW_ADDR);

  // AXI Write Data Routing
  always_comb begin
    if (curr_type == 2'b11) begin
      // Writeback status word
      m_axi_wdata = ch_desc_wdata[curr_ch];
      m_axi_wstrb = {AXI_STRB_WIDTH{1'b1}};
    end else begin
      // Data stream from channel FIFO
      m_axi_wdata = ch_fifo_rd_data[curr_ch];
      m_axi_wstrb = {AXI_STRB_WIDTH{1'b1}};
    end
  end

  assign m_axi_wvalid = (state == MST_W_DATA);
  assign m_axi_wlast  = (state == MST_W_DATA) && (wbeat_count == target_len);

  // FIFO & Channel Routing
  always_comb begin
    ch_fifo_wr_en     = '0;
    ch_fifo_wr_data   = m_axi_rdata;
    ch_fifo_rd_en     = '0;
    ch_desc_rvalid    = '0;
    ch_desc_rdata     = m_axi_rdata;
    ch_desc_rlast     = m_axi_rlast;
    ch_desc_rerr      = '0;
    ch_desc_wb_ack    = '0;
    ch_read_beat_ack  = '0;
    ch_write_beat_ack = '0;
    ch_burst_complete = '0;

    if (state == MST_R_DATA && m_axi_rvalid && m_axi_rready) begin
      if (curr_type == 2'b00) begin
        // Descriptor fetch stream
        ch_desc_rvalid[curr_ch] = 1'b1;
        if (m_axi_rresp != AXI_RESP_OKAY) begin
          ch_desc_rerr[curr_ch] = 1'b1;
        end
      end else if (curr_type == 2'b01) begin
        // Payload read into channel FIFO
        ch_fifo_wr_en[curr_ch]    = 1'b1;
        ch_read_beat_ack[curr_ch] = 1'b1;
      end
    end

    if (state == MST_W_DATA && m_axi_wvalid && m_axi_wready) begin
      if (curr_type == 2'b10) begin
        // Pop word from FIFO
        ch_fifo_rd_en[curr_ch]     = 1'b1;
        ch_write_beat_ack[curr_ch] = 1'b1;
      end
    end

    if (state == MST_COMPLETE) begin
      ch_burst_complete[curr_ch] = 1'b1;
      if (curr_type == 2'b11) begin
        ch_desc_wb_ack[curr_ch] = 1'b1;
      end
    end
  end

endmodule
