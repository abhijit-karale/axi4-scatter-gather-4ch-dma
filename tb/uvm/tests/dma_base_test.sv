// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: dma_base_test.sv
// Description: Base test establishing environment, objections, and reporting.
// ============================================================================

`timescale 1ns / 1ps

class dma_base_test extends uvm_test;
  `uvm_component_utils(dma_base_test)

  dma_env env;

  function new(string name = "dma_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = dma_env::type_id::create("env", this);
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

endclass
