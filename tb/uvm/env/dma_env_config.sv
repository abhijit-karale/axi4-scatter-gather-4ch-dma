// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: dma_env_config.sv
// Description: Configuration object for DMA UVM Environment.
// ============================================================================

`timescale 1ns / 1ps

class dma_env_config extends uvm_object;
  `uvm_object_utils(dma_env_config)

  bit has_axi_agent  = 1'b1;
  bit has_axil_agent = 1'b1;
  bit has_scoreboard = 1'b1;
  int num_channels   = 4;

  virtual axi_if  axi_vif;
  virtual axil_if axil_vif;

  function new(string name = "dma_env_config");
    super.new(name);
  endfunction

endclass
