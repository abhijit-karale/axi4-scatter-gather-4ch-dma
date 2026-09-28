// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem
// File: dma_fifo.sv
// Description: Fully synchronous, parameterized FIFO buffer with watermarks,
//              occupancy counter, and zero-latency/single-cycle read latency.
// Target Node & Clock: SkyWater 130nm @ 200 MHz
// Engineer: Abhijit Karale
// ============================================================================

`timescale 1ns / 1ps

module dma_fifo #(
  parameter int DATA_WIDTH = 32,
  parameter int DEPTH      = 64,
  parameter int ALMOST_FULL_THRESH  = DEPTH - 4,
  parameter int ALMOST_EMPTY_THRESH = 4
)(
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    flush,

  // Write Interface
  input  logic                    wr_en,
  input  logic [DATA_WIDTH-1:0]   wr_data,
  output logic                    full,
  output logic                    almost_full,

  // Read Interface
  input  logic                    rd_en,
  output logic [DATA_WIDTH-1:0]   rd_data,
  output logic                    empty,
  output logic                    almost_empty,

  // Status & Watermarks
  output logic [$clog2(DEPTH+1)-1:0] level,
  output logic [$clog2(DEPTH+1)-1:0] avail_space
);

  localparam int ADDR_WIDTH = $clog2(DEPTH);

  // Storage array
  logic [DATA_WIDTH-1:0] mem [DEPTH-1:0];

  logic [ADDR_WIDTH-1:0] wr_ptr;
  logic [ADDR_WIDTH-1:0] rd_ptr;
  logic [$clog2(DEPTH+1)-1:0] count;

  // Combinational status
  assign empty        = (count == 0);
  assign full         = (count == DEPTH);
  assign almost_empty = (count <= ALMOST_EMPTY_THRESH);
  assign almost_full  = (count >= ALMOST_FULL_THRESH);
  assign level        = count;
  assign avail_space  = DEPTH - count;

  // Direct read out
  assign rd_data = mem[rd_ptr];

  // FIFO Pointer and Count Updates
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
      count  <= '0;
    end else if (flush) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
      count  <= '0;
    end else begin
      case ({wr_en && !full, rd_en && !empty})
        2'b10: begin // Write only
          mem[wr_ptr] <= wr_data;
          wr_ptr      <= (wr_ptr == DEPTH - 1) ? '0 : wr_ptr + 1'b1;
          count       <= count + 1'b1;
        end
        2'b01: begin // Read only
          rd_ptr      <= (rd_ptr == DEPTH - 1) ? '0 : rd_ptr + 1'b1;
          count       <= count - 1'b1;
        end
        2'b11: begin // Simultaneous read & write
          mem[wr_ptr] <= wr_data;
          wr_ptr      <= (wr_ptr == DEPTH - 1) ? '0 : wr_ptr + 1'b1;
          rd_ptr      <= (rd_ptr == DEPTH - 1) ? '0 : rd_ptr + 1'b1;
          // count remains unchanged
        end
        default: ; // Idle
      endcase
    end
  end

endmodule
