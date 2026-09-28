// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: axil_agent.sv
// Description: UVM Agent containing AXI4-Lite Driver, Monitor, and Sequencer.
// ============================================================================

`timescale 1ns / 1ps

class axil_agent extends uvm_agent;
  `uvm_component_utils(axil_agent)

  axil_driver    driver;
  axil_monitor   monitor;
  axil_sequencer sequencer;

  function new(string name = "axil_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    monitor = axil_monitor::type_id::create("monitor", this);
    if (get_is_active() == UVM_ACTIVE) begin
      driver    = axil_driver::type_id::create("driver", this);
      sequencer = axil_sequencer::type_id::create("sequencer", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction

endclass
