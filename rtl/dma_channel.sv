// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem
// File: dma_channel.sv
// Description: Parameterized DMA channel core containing descriptor engine,
//              internal data FIFO, transfer control FSM, and address trackers.
// Target Node & Clock: SkyWater 130nm @ 200 MHz
// Engineer: Abhijit Karale
// ============================================================================

`timescale 1ns / 1ps

module dma_channel
  import dma_pkg::*;
#(
  parameter int CHANNEL_ID     = 0,
  parameter int AXI_ADDR_WIDTH = 32,
  parameter int AXI_DATA_WIDTH = 32,
  parameter int FIFO_DEPTH     = 64,
  parameter int MAX_BURST      = MAX_BURST_LEN
)(
  input  logic                      clk,
  input  logic                      rst_n,

  // Control from CSR
  input  logic                      ch_en,
  input  logic                      ch_start,
  input  logic                      ch_abort,
  input  logic                      ch_ring_mode,
  input  logic                      ch_ie_done,
  input  logic                      ch_ie_err,
  input  logic                      ch_auto_wb,
  input  logic [AXI_ADDR_WIDTH-1:0] ch_head_desc_ptr,
  input  logic                      irq_clear_done,
  input  logic                      irq_clear_err,

  // Status to CSR
  output logic                      ch_busy,
  output logic                      ch_done,
  output logic                      ch_error,
  output logic [3:0]                ch_fsm_state,
  output logic [AXI_ADDR_WIDTH-1:0] ch_curr_desc_ptr,
  output logic [31:0]               ch_bytes_transferred,
  output logic                      irq_line,

  // Requests to Central Arbiter
  output logic                      req_desc_fetch,
  output logic                      req_data_read,
  output logic                      req_data_write,
  output logic                      req_desc_wb,

  // Feedback from Arbiter / Master Engine
  input  logic                      arb_granted,
  input  logic [1:0]                arb_grant_type,
  input  logic                      burst_complete,
  input  logic                      read_beat_ack,
  input  logic                      write_beat_ack,
  input  logic                      bus_err,

  // Address and Burst Info to Master Engine
  output logic [AXI_ADDR_WIDTH-1:0] ch_araddr,
  output logic [7:0]                ch_arlen,
  output logic [2:0]                ch_arsize,
  output logic [AXI_ADDR_WIDTH-1:0] ch_awaddr,
  output logic [7:0]                ch_awlen,
  output logic [2:0]                ch_awsize,

  // Master Engine Data FIFO Interconnect
  input  logic                      fifo_wr_en,
  input  logic [AXI_DATA_WIDTH-1:0] fifo_wr_data,
  input  logic                      fifo_rd_en,
  output logic [AXI_DATA_WIDTH-1:0] fifo_rd_data,

  // Master Engine Descriptor Stream Interconnect
  input  logic                      desc_rvalid,
  input  logic [AXI_DATA_WIDTH-1:0] desc_rdata,
  input  logic                      desc_rlast,
  input  logic                      desc_rerr,
  output logic [AXI_DATA_WIDTH-1:0] desc_wdata,
  output logic [AXI_ADDR_WIDTH-1:0] desc_wb_addr,
  input  logic                      desc_wb_ack
);

  localparam int BYTES_PER_BEAT = AXI_DATA_WIDTH / 8;
  localparam int SIZE_SHIFT      = $clog2(BYTES_PER_BEAT);

  // Channel State Machine
  ch_state_t state, state_next;

  // Active descriptor tracking registers
  logic [AXI_ADDR_WIDTH-1:0] curr_desc_addr;
  logic [AXI_ADDR_WIDTH-1:0] curr_src_addr;
  logic [AXI_ADDR_WIDTH-1:0] curr_dst_addr;
  logic [31:0]               rem_read_bytes;
  logic [31:0]               rem_write_bytes;
  logic [31:0]               cumul_bytes;

  // Descriptor engine interface signals
  logic                      desc_fetch_start;
  logic                      desc_wb_start;
  logic                      desc_valid;
  logic                      desc_error;
  logic                      desc_ioc;
  logic                      desc_stop;
  logic                      desc_src_inc;
  logic                      desc_dst_inc;
  logic [2:0]                desc_burst_size;
  logic [7:0]                desc_burst_len;
  logic [AXI_ADDR_WIDTH-1:0] desc_src_addr;
  logic [AXI_ADDR_WIDTH-1:0] desc_dst_addr;
  logic [AXI_ADDR_WIDTH-1:0] desc_next_addr;
  logic [31:0]               desc_transfer_len;
  logic                      desc_engine_busy;
  logic                      desc_engine_done;

  // FIFO signals
  logic                      fifo_full;
  logic                      fifo_empty;
  logic                      fifo_flush;
  logic [$clog2(FIFO_DEPTH+1)-1:0] fifo_level;
  logic [$clog2(FIFO_DEPTH+1)-1:0] fifo_avail;

  // Burst Calculation Variables
  logic [7:0]                calc_read_len;
  logic [7:0]                calc_write_len;
  logic [7:0]                active_rd_len;
  logic [7:0]                active_wr_len;

  // IRQ Pending Flip-Flops
  logic                      irq_done_pending;
  logic                      irq_err_pending;

  assign ch_fsm_state         = state;
  assign ch_curr_desc_ptr     = curr_desc_addr;
  assign ch_bytes_transferred = cumul_bytes;
  assign ch_busy              = (state != CH_STATE_IDLE) && (state != CH_STATE_DONE) && (state != CH_STATE_ERROR);
  assign ch_done              = (state == CH_STATE_DONE);
  assign ch_error             = (state == CH_STATE_ERROR);
  assign irq_line             = (irq_done_pending && ch_ie_done) || (irq_err_pending && ch_ie_err);

  // Instantiate FIFO Buffer
  dma_fifo #(
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .DEPTH(FIFO_DEPTH)
  ) u_data_fifo (
    .clk         (clk),
    .rst_n       (rst_n),
    .flush       (fifo_flush),
    .wr_en       (fifo_wr_en),
    .wr_data     (fifo_wr_data),
    .full        (fifo_full),
    .almost_full (),
    .rd_en       (fifo_rd_en),
    .rd_data     (fifo_rd_data),
    .empty       (fifo_empty),
    .almost_empty(),
    .level       (fifo_level),
    .avail_space (fifo_avail)
  );

  // Instantiate Descriptor Engine
  dma_desc_engine #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
  ) u_desc_engine (
    .clk              (clk),
    .rst_n            (rst_n),
    .fetch_start      (desc_fetch_start),
    .wb_start         (desc_wb_start),
    .ring_mode        (ch_ring_mode),
    .head_desc_addr   (ch_head_desc_ptr),
    .curr_desc_addr   (curr_desc_addr),
    .bytes_transferred(cumul_bytes[23:0]),
    .transfer_err     (ch_error),
    .desc_rdata_valid (desc_rvalid),
    .desc_rdata       (desc_rdata),
    .desc_rdata_last  (desc_rlast),
    .desc_bus_err     (desc_rerr),
    .desc_wdata_valid (),
    .desc_wdata       (desc_wdata),
    .desc_wb_addr     (desc_wb_addr),
    .desc_wb_ready    (desc_wb_ack),
    .desc_valid       (desc_valid),
    .desc_error       (desc_error),
    .desc_ioc         (desc_ioc),
    .desc_stop        (desc_stop),
    .desc_src_inc     (desc_src_inc),
    .desc_dst_inc     (desc_dst_inc),
    .desc_burst_size  (desc_burst_size),
    .desc_burst_len   (desc_burst_len),
    .desc_src_addr    (desc_src_addr),
    .desc_dst_addr    (desc_dst_addr),
    .desc_next_addr   (desc_next_addr),
    .desc_transfer_len(desc_transfer_len),
    .engine_busy      (desc_engine_busy),
    .engine_done      (desc_engine_done)
  );

  // Calculate burst length for upcoming operations
  always_comb begin
    // Words remaining to read
    logic [31:0] rem_read_words;
    logic [31:0] rem_write_words;
    rem_read_words  = (rem_read_bytes + BYTES_PER_BEAT - 1) >> SIZE_SHIFT;
    rem_write_words = (rem_write_bytes + BYTES_PER_BEAT - 1) >> SIZE_SHIFT;

    // Read burst length calculation
    if (rem_read_words > MAX_BURST) begin
      calc_read_len = 8'(MAX_BURST - 1);
    end else if (rem_read_words > 0) begin
      calc_read_len = 8'(rem_read_words - 1);
    end else begin
      calc_read_len = '0;
    end

    // Write burst length calculation
    if (rem_write_words > MAX_BURST) begin
      calc_write_len = 8'(MAX_BURST - 1);
    end else if (rem_write_words > 0) begin
      calc_write_len = 8'(rem_write_words - 1);
    end else begin
      calc_write_len = '0;
    end
  end

  // AXI Master Request Parameters
  assign ch_araddr = (state == CH_STATE_FETCH_REQ || state == CH_STATE_FETCH_WAIT) ? curr_desc_addr : curr_src_addr;
  assign ch_arlen  = (state == CH_STATE_FETCH_REQ || state == CH_STATE_FETCH_WAIT) ? 8'd7 : active_rd_len;
  assign ch_arsize = 3'b010; // 4 bytes

  assign ch_awaddr = curr_dst_addr;
  assign ch_awlen  = active_wr_len;
  assign ch_awsize = 3'b010; // 4 bytes

  // Arbiter Request Generation
  assign req_desc_fetch = (state == CH_STATE_FETCH_REQ);
  assign req_desc_wb    = (state == CH_STATE_WB_REQ);
  assign req_data_read  = (state == CH_STATE_READ_REQ);
  assign req_data_write = (state == CH_STATE_WRITE_REQ);

  // FSM Next-State Logic
  always_comb begin
    state_next       = state;
    desc_fetch_start = 1'b0;
    desc_wb_start    = 1'b0;
    fifo_flush       = 1'b0;

    if (ch_abort) begin
      state_next = CH_STATE_IDLE;
      fifo_flush = 1'b1;
    end else begin
      case (state)
        CH_STATE_IDLE: begin
          if (ch_en && ch_start) begin
            desc_fetch_start = 1'b1;
            state_next       = CH_STATE_FETCH_REQ;
            fifo_flush       = 1'b1;
          end
        end

        CH_STATE_FETCH_REQ: begin
          if (arb_granted && (arb_grant_type == 2'b00)) begin
            state_next = CH_STATE_FETCH_WAIT;
          end
        end

        CH_STATE_FETCH_WAIT: begin
          if (desc_error || bus_err) begin
            state_next = CH_STATE_ERROR;
          end else if (desc_engine_done && desc_valid) begin
            state_next = CH_STATE_PARSE_DESC;
          end
        end

        CH_STATE_PARSE_DESC: begin
          // Ready to begin data transfer
          if (rem_read_bytes > 0 && fifo_avail >= (calc_read_len + 1)) begin
            state_next = CH_STATE_READ_REQ;
          end else if (fifo_level > 0) begin
            state_next = CH_STATE_WRITE_REQ;
          end else if (rem_write_bytes == 0) begin
            state_next = CH_STATE_NEXT_DESC;
          end
        end

        CH_STATE_READ_REQ: begin
          if (arb_granted && (arb_grant_type == 2'b01)) begin
            state_next = CH_STATE_READ_BURST;
          end
        end

        CH_STATE_READ_BURST: begin
          if (bus_err) begin
            state_next = CH_STATE_ERROR;
          end else if (burst_complete) begin
            // Decide next action: write if FIFO has enough data or read complete
            if (fifo_level >= (calc_write_len + 1) || (rem_read_bytes == 0 && fifo_level > 0)) begin
              state_next = CH_STATE_WRITE_REQ;
            end else if (rem_read_bytes > 0 && fifo_avail >= (calc_read_len + 1)) begin
              state_next = CH_STATE_READ_REQ;
            end else begin
              state_next = CH_STATE_WRITE_REQ;
            end
          end
        end

        CH_STATE_WRITE_REQ: begin
          if (arb_granted && (arb_grant_type == 2'b10)) begin
            state_next = CH_STATE_WRITE_BURST;
          end
        end

        CH_STATE_WRITE_BURST: begin
          if (bus_err) begin
            state_next = CH_STATE_ERROR;
          end else if (burst_complete) begin
            if (rem_write_bytes == 0) begin
              // Descriptor payload complete!
              if (ch_auto_wb) begin
                desc_wb_start = 1'b1;
                state_next    = CH_STATE_WB_REQ;
              end else begin
                state_next    = CH_STATE_NEXT_DESC;
              end
            end else if (rem_read_bytes > 0 && fifo_avail >= (calc_read_len + 1)) begin
              state_next = CH_STATE_READ_REQ;
            end else if (fifo_level > 0) begin
              state_next = CH_STATE_WRITE_REQ;
            end else begin
              state_next = CH_STATE_READ_REQ;
            end
          end
        end

        CH_STATE_WB_REQ: begin
          if (arb_granted && (arb_grant_type == 2'b11)) begin
            state_next = CH_STATE_WB_WAIT;
          end
        end

        CH_STATE_WB_WAIT: begin
          if (desc_wb_ack) begin
            state_next = CH_STATE_NEXT_DESC;
          end
        end

        CH_STATE_NEXT_DESC: begin
          if (desc_stop || (desc_next_addr == '0)) begin
            state_next = CH_STATE_DONE;
          end else begin
            // Fetch next linked descriptor
            desc_fetch_start = 1'b1;
            state_next       = CH_STATE_FETCH_REQ;
          end
        end

        CH_STATE_DONE: begin
          if (!ch_en || ch_start) begin
            state_next = CH_STATE_IDLE;
          end
        end

        CH_STATE_ERROR: begin
          if (!ch_en) begin
            state_next = CH_STATE_IDLE;
          end
        end

        default: state_next = CH_STATE_IDLE;
      endcase
    end
  end

  // Sequential Datapath Updates
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state            <= CH_STATE_IDLE;
      curr_desc_addr   <= '0;
      curr_src_addr    <= '0;
      curr_dst_addr    <= '0;
      rem_read_bytes   <= '0;
      rem_write_bytes  <= '0;
      cumul_bytes      <= '0;
      active_rd_len    <= '0;
      active_wr_len    <= '0;
      irq_done_pending <= 1'b0;
      irq_err_pending  <= 1'b0;
    end else begin
      state <= state_next;

      // Handle IRQ Clear from CSR
      if (irq_clear_done) irq_done_pending <= 1'b0;
      if (irq_clear_err)  irq_err_pending  <= 1'b0;

      case (state)
        CH_STATE_IDLE: begin
          if (ch_en && ch_start) begin
            curr_desc_addr <= ch_head_desc_ptr;
            cumul_bytes    <= '0;
          end
        end

        CH_STATE_PARSE_DESC: begin
          curr_src_addr   <= desc_src_addr;
          curr_dst_addr   <= desc_dst_addr;
          rem_read_bytes  <= desc_transfer_len;
          rem_write_bytes <= desc_transfer_len;
        end

        CH_STATE_READ_REQ: begin
          active_rd_len <= calc_read_len;
        end

        CH_STATE_READ_BURST: begin
          if (read_beat_ack) begin
            if (desc_src_inc) begin
              curr_src_addr <= curr_src_addr + BYTES_PER_BEAT;
            end
            if (rem_read_bytes >= BYTES_PER_BEAT) begin
              rem_read_bytes <= rem_read_bytes - BYTES_PER_BEAT;
            end else begin
              rem_read_bytes <= '0;
            end
          end
        end

        CH_STATE_WRITE_REQ: begin
          active_wr_len <= calc_write_len;
        end

        CH_STATE_WRITE_BURST: begin
          if (write_beat_ack) begin
            if (desc_dst_inc) begin
              curr_dst_addr <= curr_dst_addr + BYTES_PER_BEAT;
            end
            if (rem_write_bytes >= BYTES_PER_BEAT) begin
              rem_write_bytes <= rem_write_bytes - BYTES_PER_BEAT;
              cumul_bytes     <= cumul_bytes + BYTES_PER_BEAT;
            end else begin
              cumul_bytes     <= cumul_bytes + rem_write_bytes;
              rem_write_bytes <= '0;
            end
          end
        end

        CH_STATE_NEXT_DESC: begin
          // Trigger IRQ if Interrupt on Completion was requested
          if (desc_ioc) begin
            irq_done_pending <= 1'b1;
          end

          if (!desc_stop && (desc_next_addr != '0)) begin
            curr_desc_addr <= desc_next_addr;
          end
        end

        CH_STATE_DONE: begin
          // Final IRQ assertion if not already asserted
          if (desc_ioc) begin
            irq_done_pending <= 1'b1;
          end
        end

        CH_STATE_ERROR: begin
          irq_err_pending <= 1'b1;
        end

        default: ;
      endcase
    end
  end

endmodule
