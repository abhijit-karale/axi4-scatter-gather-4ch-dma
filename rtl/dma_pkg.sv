// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem
// File: dma_pkg.sv
// Description: Global system definitions, data structures, register address map,
//              and hardware descriptor layout for the DMA Subsystem.
// Target Node & Clock: SkyWater 130nm @ 200 MHz
// Engineer: Abhijit Karale
// ============================================================================

`timescale 1ns / 1ps

package dma_pkg;

  // --------------------------------------------------------------------------
  // Subsystem Configuration Parameters
  // --------------------------------------------------------------------------
  localparam int NUM_CHANNELS        = 4;
  localparam int AXI_ADDR_WIDTH      = 32;
  localparam int AXI_DATA_WIDTH      = 32;
  localparam int AXI_STRB_WIDTH      = AXI_DATA_WIDTH / 8;
  localparam int AXI_ID_WIDTH        = 4;
  localparam int AXIL_ADDR_WIDTH     = 12;
  localparam int AXIL_DATA_WIDTH     = 32;
  localparam int FIFO_DEPTH          = 64;   // Per-channel data buffer depth (32-bit words)
  localparam int MAX_BURST_LEN       = 16;   // Max AXI beats per burst (1 to 256)
  localparam int DESC_SIZE_BYTES     = 32;   // 8 x 32-bit words per descriptor

  // Type aliases for arrays to avoid vlog port kind warnings
  typedef logic [1:0]                prio_weight_t;
  typedef logic [AXI_ADDR_WIDTH-1:0] axi_addr_t;
  typedef logic [AXI_DATA_WIDTH-1:0] axi_data_t;
  typedef logic [7:0]                axi_len_t;
  typedef logic [2:0]                axi_size_t;
  typedef logic [3:0]                ch_fsm_state_t;
  typedef logic [31:0]               ch_stat_word_t;

  // --------------------------------------------------------------------------
  // AXI4 Burst Type Definitions
  // --------------------------------------------------------------------------
  typedef enum logic [1:0] {
    AXI_BURST_FIXED    = 2'b00,
    AXI_BURST_INCR     = 2'b01,
    AXI_BURST_WRAP     = 2'b10,
    AXI_BURST_RESERVED = 2'b11
  } axi_burst_t;

  // AXI Response Types
  typedef enum logic [1:0] {
    AXI_RESP_OKAY   = 2'b00,
    AXI_RESP_EXOKAY = 2'b01,
    AXI_RESP_SLVERR = 2'b10,
    AXI_RESP_DECERR = 2'b11
  } axi_resp_t;

  // --------------------------------------------------------------------------
  // Channel Arbitration Modes
  // --------------------------------------------------------------------------
  typedef enum logic [1:0] {
    ARB_MODE_FIXED       = 2'b00, // Channel 0 > Channel 1 > Channel 2 > Channel 3
    ARB_MODE_ROUND_ROBIN = 2'b01, // Fair Round-Robin among active requests
    ARB_MODE_WEIGHTED    = 2'b10  // Weighted round-robin based on channel priority
  } arb_mode_t;

  // --------------------------------------------------------------------------
  // Channel State Machine States
  // --------------------------------------------------------------------------
  typedef enum logic [3:0] {
    CH_STATE_IDLE        = 4'h0,
    CH_STATE_FETCH_REQ   = 4'h1,
    CH_STATE_FETCH_WAIT  = 4'h2,
    CH_STATE_PARSE_DESC  = 4'h3,
    CH_STATE_READ_REQ    = 4'h4,
    CH_STATE_READ_BURST  = 4'h5,
    CH_STATE_WRITE_REQ   = 4'h6,
    CH_STATE_WRITE_BURST = 4'h7,
    CH_STATE_WB_REQ      = 4'h8,
    CH_STATE_WB_WAIT     = 4'h9,
    CH_STATE_NEXT_DESC   = 4'hA,
    CH_STATE_DONE        = 4'hB,
    CH_STATE_ERROR       = 4'hE
  } ch_state_t;

  // --------------------------------------------------------------------------
  // Scatter-Gather Hardware Descriptor Structure (32-byte layout)
  // Aligned to 8 words (256 bits) in system memory.
  // --------------------------------------------------------------------------
  typedef struct packed {
    // Word 7: Reserved / Custom User Tag
    logic [31:0] reserved1;
    // Word 6: Reserved / Custom Timestamp
    logic [31:0] reserved0;
    // Word 5: Descriptor Status (Written back upon completion)
    struct packed {
      logic [23:0] actual_bytes;  // Bytes successfully transferred
      logic [4:0]  reserved;
      logic        desc_err;      // 1: Bus error during transfer
      logic        desc_done;     // 1: Hardware completed this descriptor
      logic        valid;         // 1: Hardware status valid
    } status;
    // Word 4: Descriptor Control Flags
    struct packed {
      logic [15:0] reserved;
      logic [7:0]  burst_len;     // Max beats per burst (0 = 1 beat, 15 = 16 beats)
      logic [2:0]  burst_size;    // 000=1B, 001=2B, 010=4B
      logic        dst_inc;       // 1: Increment DST_ADDR, 0: Fixed
      logic        src_inc;       // 1: Increment SRC_ADDR, 0: Fixed
      logic        stop;          // 1: End of chain (no next fetch)
      logic        ioc;           // 1: Interrupt on Completion
      logic        valid;         // 1: Descriptor is ready for processing
    } ctrl;
    // Word 3: Total transfer length in bytes
    logic [31:0] transfer_len;
    // Word 2: Pointer to next linked-list descriptor (Physical Address)
    logic [31:0] next_desc_addr;
    // Word 1: Destination Physical Address
    logic [31:0] dst_addr;
    // Word 0: Source Physical Address
    logic [31:0] src_addr;
  } dma_desc_t;

  // --------------------------------------------------------------------------
  // AXI4-Lite CSR Register Map
  // --------------------------------------------------------------------------
  // Global Subsystem Registers
  localparam logic [11:0] ADDR_GLOBAL_CTRL       = 12'h000;
  localparam logic [11:0] ADDR_GLOBAL_STATUS     = 12'h004;
  localparam logic [11:0] ADDR_GLOBAL_IRQ_EN     = 12'h008;
  localparam logic [11:0] ADDR_GLOBAL_IRQ_STATUS = 12'h00C;

  // Channel Register Offsets: CH_BASE = 0x040 + (ch_id * 0x040)
  localparam logic [11:0] CH_BASE_OFFSET         = 12'h040;
  localparam logic [11:0] CH_STRIDE              = 12'h040;

  localparam logic [11:0] CH_OFFSET_CTRL         = 12'h000;
  localparam logic [11:0] CH_OFFSET_STATUS       = 12'h004;
  localparam logic [11:0] CH_OFFSET_DESC_PTR     = 12'h008;
  localparam logic [11:0] CH_OFFSET_CURR_DESC    = 12'h00C;
  localparam logic [11:0] CH_OFFSET_BYTES_XFER   = 12'h010;
  localparam logic [11:0] CH_OFFSET_IRQ_STATUS   = 12'h014;
  localparam logic [11:0] CH_OFFSET_PRIORITY     = 12'h018;

  // Global Control Register Bits
  localparam int GCTRL_DMA_EN_BIT    = 0;
  localparam int GCTRL_SOFT_RST_BIT  = 1;
  localparam int GCTRL_ARB_MODE_LSB  = 2;
  localparam int GCTRL_ARB_MODE_MSB  = 3;

  // Channel Control Register Bits
  localparam int CCTRL_EN_BIT        = 0;
  localparam int CCTRL_START_BIT     = 1;
  localparam int CCTRL_ABORT_BIT     = 2;
  localparam int CCTRL_RING_MODE_BIT = 3;
  localparam int CCTRL_IE_DONE_BIT   = 4;
  localparam int CCTRL_IE_ERR_BIT    = 5;
  localparam int CCTRL_AUTO_WB_BIT   = 6; // 1: Auto write back status word to memory

  // Channel Status Register Bits
  localparam int CSTAT_BUSY_BIT      = 0;
  localparam int CSTAT_DONE_BIT      = 1;
  localparam int CSTAT_ERR_BIT       = 2;
  localparam int CSTAT_SUSPENDED_BIT = 3;
  localparam int CSTAT_STATE_LSB     = 4;
  localparam int CSTAT_STATE_MSB     = 7;

  // Channel IRQ Status Register Bits (Write-1-to-Clear)
  localparam int CIRQ_DONE_BIT       = 0;
  localparam int CIRQ_ERR_BIT        = 1;
  localparam int CIRQ_DESC_ERR_BIT   = 2;

endpackage: dma_pkg
