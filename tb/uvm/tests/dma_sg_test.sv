// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: dma_sg_test.sv
// Description: Test case validating multi-descriptor linked-list scatter-gather.
// ============================================================================

`timescale 1ns / 1ps

class dma_sg_test extends dma_base_test;
  `uvm_component_utils(dma_sg_test)

  function new(string name = "dma_sg_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    dma_sg_seq seq;
    phase.raise_objection(this);

    `uvm_info("TEST", "==========================================================", UVM_NONE)
    `uvm_info("TEST", "  STARTING: Scatter-Gather Linked-List DMA Test", UVM_NONE)
    `uvm_info("TEST", "==========================================================", UVM_NONE)

    seq = dma_sg_seq::type_id::create("seq");
    seq.scb = env.m_scoreboard;
    seq.start(env.m_axil_agent.sequencer);

    #100ns;
    `uvm_info("TEST", "Scatter-Gather Linked-List DMA Test Finished", UVM_NONE)
    phase.drop_objection(this);
  endtask

endclass
