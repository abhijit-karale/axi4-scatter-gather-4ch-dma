// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: axi_sequencer.sv
// Description: Sequencer for AXI VIP.
// ============================================================================

`timescale 1ns / 1ps

class axi_sequencer extends uvm_sequencer #(axi_seq_item);
  `uvm_component_utils(axi_sequencer)

  function new(string name = "axi_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

endclass
