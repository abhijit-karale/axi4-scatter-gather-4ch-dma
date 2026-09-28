// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: dma_multichannel_test.sv
// Description: Test case validating concurrent execution across 4 DMA channels.
// ============================================================================

`timescale 1ns / 1ps

class dma_multichannel_test extends dma_base_test;
  `uvm_component_utils(dma_multichannel_test)

  function new(string name = "dma_multichannel_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    dma_multichannel_seq seq;
    phase.raise_objection(this);

    `uvm_info("TEST", "==========================================================", UVM_NONE)
    `uvm_info("TEST", "  STARTING: Multi-Channel Concurrent DMA Test (4 Channels)", UVM_NONE)
    `uvm_info("TEST", "==========================================================", UVM_NONE)

    seq = dma_multichannel_seq::type_id::create("seq");
    seq.scb = env.m_scoreboard;
    seq.ram = env.m_ram_model;
    seq.start(env.m_axil_agent.sequencer);

    #100ns;
    `uvm_info("TEST", "Multi-Channel Concurrent DMA Test Finished", UVM_NONE)
    phase.drop_objection(this);
  endtask

endclass
