// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem
// File: dma_desc_engine.sv
// Description: Scatter-gather descriptor fetch, parse, and writeback engine.
//              Handles 32-byte hardware descriptors formatted for linked-list
//              and circular ring-buffer transactions.
// Target Node & Clock: SkyWater 130nm @ 200 MHz
// Engineer: Abhijit Karale
// ============================================================================

`timescale 1ns / 1ps

module dma_desc_engine
  import dma_pkg::*;
#(
  parameter int AXI_ADDR_WIDTH = 32,
  parameter int AXI_DATA_WIDTH = 32
)(
  input  logic                      clk,
  input  logic                      rst_n,

  // Control from Channel FSM
  input  logic                      fetch_start,     // Pulse to start descriptor fetch
  input  logic                      wb_start,        // Pulse to start status writeback
  input  logic                      ring_mode,       // 1: Loop back to head descriptor when next is 0
  input  logic [AXI_ADDR_WIDTH-1:0] head_desc_addr,  // Programmed head descriptor address
  input  logic [AXI_ADDR_WIDTH-1:0] curr_desc_addr,  // Active descriptor address
  input  logic [23:0]               bytes_transferred,
  input  logic                      transfer_err,    // Transfer encountered error

  // Descriptor Fetch Bus Interface (Read stream from AXI Master)
  input  logic                      desc_rdata_valid,
  input  logic [AXI_DATA_WIDTH-1:0] desc_rdata,
  input  logic                      desc_rdata_last,
  input  logic                      desc_bus_err,    // Bus error during descriptor fetch

  // Descriptor Writeback Interface (Write stream to AXI Master)
  output logic                      desc_wdata_valid,
  output logic [AXI_DATA_WIDTH-1:0] desc_wdata,
  output logic [AXI_ADDR_WIDTH-1:0] desc_wb_addr,
  input  logic                      desc_wb_ready,

  // Parsed Descriptor Outputs to Channel
  output logic                      desc_valid,      // Descriptor successfully parsed & valid
  output logic                      desc_error,      // Descriptor error (invalid format or bus error)
  output logic                      desc_ioc,        // Interrupt on completion flag
  output logic                      desc_stop,       // Stop flag (end of chain)
  output logic                      desc_src_inc,    // Increment source address
  output logic                      desc_dst_inc,    // Increment destination address
  output logic [2:0]                desc_burst_size, // AXI AWSIZE/ARSIZE
  output logic [7:0]                desc_burst_len,  // Max burst length
  output logic [AXI_ADDR_WIDTH-1:0] desc_src_addr,
  output logic [AXI_ADDR_WIDTH-1:0] desc_dst_addr,
  output logic [AXI_ADDR_WIDTH-1:0] desc_next_addr,
  output logic [31:0]               desc_transfer_len,

  // Engine Status
  output logic                      engine_busy,
  output logic                      engine_done
);

  // FSM States
  typedef enum logic [2:0] {
    ST_IDLE      = 3'b000,
    ST_FETCHING  = 3'b001,
    ST_VALIDATE  = 3'b010,
    ST_READY     = 3'b011,
    ST_WRITEBACK = 3'b100,
    ST_WB_WAIT   = 3'b101,
    ST_ERROR     = 3'b110
  } state_t;

  state_t state, state_next;

  // Word reception counter (0 to 7 for 8 words = 32 bytes)
  logic [2:0] word_idx;

  // Stored descriptor fields
  logic [AXI_ADDR_WIDTH-1:0] r_src_addr;
  logic [AXI_ADDR_WIDTH-1:0] r_dst_addr;
  logic [AXI_ADDR_WIDTH-1:0] r_next_addr;
  logic [31:0]               r_transfer_len;
  logic [31:0]               r_ctrl_word;
  logic [31:0]               r_status_word;

  // Output assignments from stored registers
  assign desc_src_addr     = r_src_addr;
  assign desc_dst_addr     = r_dst_addr;
  assign desc_next_addr    = (ring_mode && (r_next_addr == '0)) ? head_desc_addr : r_next_addr;
  assign desc_transfer_len = r_transfer_len;

  // Control word bit extractions (matching dma_pkg::dma_desc_t)
  // ctrl word format:
  // [0]    : valid
  // [1]    : ioc
  // [2]    : stop
  // [3]    : src_inc
  // [4]    : dst_inc
  // [7:5]  : burst_size
  // [15:8] : burst_len
  assign desc_ioc          = r_ctrl_word[1];
  assign desc_stop         = r_ctrl_word[2] || (desc_next_addr == '0);
  assign desc_src_inc      = r_ctrl_word[3];
  assign desc_dst_inc      = r_ctrl_word[4];
  assign desc_burst_size   = r_ctrl_word[7:5];
  assign desc_burst_len    = r_ctrl_word[15:8];

  assign engine_busy = (state != ST_IDLE) && (state != ST_READY) && (state != ST_ERROR);
  assign engine_done = (state == ST_READY);
  assign desc_valid  = (state == ST_READY);
  assign desc_error  = (state == ST_ERROR);

  // Writeback signals
  assign desc_wb_addr     = curr_desc_addr + 32'd20; // Word 5 offset = 5 * 4 = 20 bytes
  assign desc_wdata       = {bytes_transferred, 5'b00000, transfer_err, 1'b1, 1'b1};
  assign desc_wdata_valid = (state == ST_WRITEBACK);

  // FSM Next-State Logic
  always_comb begin
    state_next = state;
    case (state)
      ST_IDLE: begin
        if (fetch_start) begin
          state_next = ST_FETCHING;
        end else if (wb_start) begin
          state_next = ST_WRITEBACK;
        end
      end

      ST_FETCHING: begin
        if (desc_bus_err) begin
          $display("[DEBUG DESC_ENG] Bus error during fetch!");
          state_next = ST_ERROR;
        end else if (desc_rdata_valid && (word_idx == 3'd7 || desc_rdata_last)) begin
          $display("[DEBUG DESC_ENG] Fetch finished: word_idx=%0d rdata_last=%0b ctrl=0x%08x len=%0d", word_idx, desc_rdata_last, r_ctrl_word, r_transfer_len);
          state_next = ST_VALIDATE;
        end
      end

      ST_VALIDATE: begin
        // Validate descriptor control word: valid bit must be 1, length > 0
        if (r_ctrl_word[0] && (r_transfer_len > 0)) begin
          state_next = ST_READY;
        end else begin
          $display("[DEBUG DESC_ENG] Validation failed: ctrl[0]=%0b len=%0d", r_ctrl_word[0], r_transfer_len);
          state_next = ST_ERROR;
        end
      end

      ST_READY: begin
        if (fetch_start) begin
          state_next = ST_FETCHING;
        end else if (wb_start) begin
          state_next = ST_WRITEBACK;
        end
      end

      ST_WRITEBACK: begin
        if (desc_wb_ready) begin
          state_next = ST_WB_WAIT;
        end
      end

      ST_WB_WAIT: begin
        state_next = ST_IDLE;
      end

      ST_ERROR: begin
        if (fetch_start) begin
          state_next = ST_FETCHING;
        end
      end

      default: state_next = ST_IDLE;
    endcase
  end

  // Sequential State & Descriptor Register Updates
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state          <= ST_IDLE;
      word_idx       <= '0;
      r_src_addr     <= '0;
      r_dst_addr     <= '0;
      r_next_addr    <= '0;
      r_transfer_len <= '0;
      r_ctrl_word    <= '0;
      r_status_word  <= '0;
    end else begin
      state <= state_next;

      if (fetch_start) begin
        word_idx <= '0;
      end else if (state == ST_FETCHING && desc_rdata_valid) begin
        $display("[DESC_WORD] time=%0t word_idx=%0d data=0x%08x last=%0b", $time, word_idx, desc_rdata, desc_rdata_last);
        word_idx <= word_idx + 1'b1;
        case (word_idx)
          3'd0: r_src_addr     <= desc_rdata;
          3'd1: r_dst_addr     <= desc_rdata;
          3'd2: r_next_addr    <= desc_rdata;
          3'd3: r_transfer_len <= desc_rdata;
          3'd4: r_ctrl_word    <= desc_rdata;
          3'd5: r_status_word  <= desc_rdata;
          default: ; // Words 6 and 7 reserved
        endcase
      end
    end
  end

endmodule
