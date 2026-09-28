// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem
// File: dma_arbiter.sv
// Description: Central multi-channel arbiter supporting configurable Fixed
//              Priority and Round-Robin arbitration policies with transaction locking.
// Target Node & Clock: SkyWater 130nm @ 200 MHz
// Engineer: Abhijit Karale
// ============================================================================

`timescale 1ns / 1ps

module dma_arbiter
  import dma_pkg::*;
#(
  parameter int NUM_CH = NUM_CHANNELS
)(
  input  logic                    clk,
  input  logic                    rst_n,

  // Configuration
  input  arb_mode_t               arb_mode,
  input  logic [NUM_CH-1:0][1:0]  ch_prio_weight, // Per-channel priority weight if configured

  // Channel Request Inputs (Channel 0..3)
  input  logic [NUM_CH-1:0]       req_desc_fetch,
  input  logic [NUM_CH-1:0]       req_data_read,
  input  logic [NUM_CH-1:0]       req_data_write,
  input  logic [NUM_CH-1:0]       req_desc_wb,

  // Lock / Busy feedback from AXI Master Engine
  input  logic                    xfer_busy,      // AXI Master is actively handling a transaction
  input  logic                    xfer_done,      // Active transaction completed

  // Arbiter Grants to Channels
  output logic [NUM_CH-1:0]       grant,
  output logic [$clog2(NUM_CH)-1:0] grant_id,
  output logic                    grant_valid,

  // Granted Transaction Type (encoded for AXI Master engine)
  // 2'b00: DESC_FETCH, 2'b01: DATA_READ, 2'b10: DATA_WRITE, 2'b11: DESC_WB
  output logic [1:0]              grant_type
);

  localparam int CH_ID_WIDTH = $clog2(NUM_CH);

  // Aggregated request per channel
  logic [NUM_CH-1:0] ch_active_req;
  logic [1:0]        ch_req_type [NUM_CH-1:0];

  // For each channel, determine its highest internal priority request:
  // Internal channel priority:
  // 1. Descriptor Fetch (must get descriptor before anything else)
  // 2. Data Write (flush internal FIFO to free up buffer space)
  // 3. Data Read (fill FIFO)
  // 4. Descriptor Writeback (post-transfer status update)
  always_comb begin
    for (int i = 0; i < NUM_CH; i++) begin
      ch_active_req[i] = req_desc_fetch[i] | req_data_write[i] | req_data_read[i] | req_desc_wb[i];
      if (req_desc_fetch[i]) begin
        ch_req_type[i] = 2'b00; // DESC_FETCH
      end else if (req_data_write[i]) begin
        ch_req_type[i] = 2'b10; // DATA_WRITE
      end else if (req_data_read[i]) begin
        ch_req_type[i] = 2'b01; // DATA_READ
      end else begin
        ch_req_type[i] = 2'b11; // DESC_WB
      end
    end
  end

  // Internal arbiter state
  logic                   locked;
  logic [CH_ID_WIDTH-1:0] locked_ch;
  logic [1:0]             locked_type;
  logic [CH_ID_WIDTH-1:0] rr_ptr;

  // Selected candidate from arbitration schemes
  logic [CH_ID_WIDTH-1:0] fixed_candidate;
  logic                   fixed_valid;
  logic [CH_ID_WIDTH-1:0] rr_candidate;
  logic                   rr_valid;

  // Fixed Priority Scheme: CH0 > CH1 > CH2 > CH3
  always_comb begin
    fixed_candidate = '0;
    fixed_valid     = 1'b0;
    for (int i = NUM_CH - 1; i >= 0; i--) begin
      if (ch_active_req[i]) begin
        fixed_candidate = CH_ID_WIDTH'(i);
        fixed_valid     = 1'b1;
      end
    end
  end

  // Round-Robin Scheme: Searches starting from rr_ptr upwards
  always_comb begin
    rr_candidate = rr_ptr;
    rr_valid     = 1'b0;
    for (int offset = 0; offset < NUM_CH; offset++) begin
      logic [CH_ID_WIDTH-1:0] idx;
      idx = CH_ID_WIDTH'((int'(rr_ptr) + offset) % NUM_CH);
      if (ch_active_req[idx] && !rr_valid) begin
        rr_candidate = idx;
        rr_valid     = 1'b1;
      end
    end
  end

  // Arbitration Decision Multiplexer
  logic [CH_ID_WIDTH-1:0] win_ch;
  logic                   win_valid;

  always_comb begin
    if (arb_mode == ARB_MODE_FIXED) begin
      win_ch    = fixed_candidate;
      win_valid = fixed_valid;
    end else begin
      win_ch    = rr_candidate;
      win_valid = rr_valid;
    end
  end

  // Grant and Lock FSM
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      locked      <= 1'b0;
      locked_ch   <= '0;
      locked_type <= '0;
      rr_ptr      <= '0;
    end else begin
      if (locked) begin
        // Release lock once the transaction finishes
        if (xfer_done) begin
          locked <= 1'b0;
          // Advance Round-Robin pointer to next channel
          rr_ptr <= CH_ID_WIDTH'((int'(locked_ch) + 1) % NUM_CH);
        end
      end else begin
        // Arbiter is free: evaluate incoming requests
        if (win_valid) begin
          locked      <= 1'b1;
          locked_ch   <= win_ch;
          locked_type <= ch_req_type[win_ch];
        end
      end
    end
  end

  // Output Grant Generation
  always_comb begin
    if (locked) begin
      grant_valid = 1'b1;
      grant_id    = locked_ch;
      grant_type  = locked_type;
    end else if (win_valid) begin
      grant_valid = 1'b1;
      grant_id    = win_ch;
      grant_type  = ch_req_type[win_ch];
    end else begin
      grant_valid = 1'b0;
      grant_id    = '0;
      grant_type  = '0;
    end

    // One-hot grant vector
    grant = '0;
    if (grant_valid) begin
      grant[grant_id] = 1'b1;
    end
  end

endmodule
