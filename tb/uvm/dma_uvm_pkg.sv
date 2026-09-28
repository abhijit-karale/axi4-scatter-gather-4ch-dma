// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: dma_uvm_pkg.sv
// Description: UVM package aggregating all VIPs, environment components,
//              sequences, and verification testcases.
// ============================================================================

`timescale 1ns / 1ps

package dma_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import dma_pkg::*;
  import axi_vip_pkg::*;

  // AXI VIP Components
  `include "axi_ram_model.sv"
  `include "axi_seq_item.sv"
  `include "axi_driver.sv"
  `include "axi_monitor.sv"
  `include "axi_sequencer.sv"
  `include "axi_agent.sv"

  // AXI-Lite VIP Components
  `include "axil_seq_item.sv"
  `include "axil_driver.sv"
  `include "axil_monitor.sv"
  `include "axil_sequencer.sv"
  `include "axil_agent.sv"

  // Environment & Scoreboard
  `include "dma_env_config.sv"
  `include "dma_scoreboard.sv"
  `include "dma_env.sv"

  // Sequences
  `include "dma_base_seq.sv"
  `include "dma_sg_seq.sv"
  `include "dma_multichannel_seq.sv"

  // Tests
  `include "dma_base_test.sv"
  `include "dma_sg_test.sv"
  `include "dma_multichannel_test.sv"
  `include "dma_priority_test.sv"

endpackage: dma_uvm_pkg
