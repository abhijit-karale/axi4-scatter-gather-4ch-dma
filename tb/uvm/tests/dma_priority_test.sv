// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: dma_priority_test.sv
// Description: Test case validating Fixed Priority arbitration (CH0 > CH3).
// ============================================================================

`timescale 1ns / 1ps

class dma_priority_seq extends dma_base_seq;
  `uvm_object_utils(dma_priority_seq)

  axi_ram_model  ram;
  dma_scoreboard scb;

  function new(string name = "dma_priority_seq");
    super.new(name);
  endfunction

  virtual task body();
    bit [31:0] desc_ch0 = 32'h0000_1000;
    bit [31:0] desc_ch3 = 32'h0000_1040;
    bit [31:0] src_ch0  = 32'h0000_2000;
    bit [31:0] dst_ch0  = 32'h0000_3000;
    bit [31:0] src_ch3  = 32'h0000_2400;
    bit [31:0] dst_ch3  = 32'h0000_3400;
    int        len      = 64;

    `uvm_info("PRIO_SEQ", "Starting Fixed Priority Arbitration Test (CH0 vs CH3)", UVM_LOW)

    if (!uvm_config_db#(axi_ram_model)::get(null, "*", "axi_ram", ram)) begin
      `uvm_fatal("NORAM", "Could not get axi_ram_model in priority sequence")
    end

    // Populate buffers
    for (int i = 0; i < len; i++) begin
      ram.write_byte(src_ch0 + i, 8'(8'h10 + i));
      ram.write_byte(dst_ch0 + i, 8'h00);
      ram.write_byte(src_ch3 + i, 8'(8'h30 + i));
      ram.write_byte(dst_ch3 + i, 8'h00);
    end

    ram.write_desc(desc_ch0, src_ch0, dst_ch0, 32'h0000_0000, len, 32'h0000_0F5F);
    ram.write_desc(desc_ch3, src_ch3, dst_ch3, 32'h0000_0000, len, 32'h0000_0F5F);

    if (scb != null) begin
      scb.add_expected_transfer(src_ch0, dst_ch0, len, 0, 1);
      scb.add_expected_transfer(src_ch3, dst_ch3, len, 3, 1);
    end

    // Configure Fixed Priority: bit [3:2] = 2'b00 -> 0x0001
    write_reg(dma_pkg::ADDR_GLOBAL_CTRL, 32'h0000_0001);

    // Setup Head Pointers
    write_reg(dma_pkg::CH_BASE_OFFSET + (0 * dma_pkg::CH_STRIDE) + dma_pkg::CH_OFFSET_DESC_PTR, desc_ch0);
    write_reg(dma_pkg::CH_BASE_OFFSET + (3 * dma_pkg::CH_STRIDE) + dma_pkg::CH_OFFSET_DESC_PTR, desc_ch3);

    // Start Channel 3 first, then immediately Channel 0
    write_reg(dma_pkg::CH_BASE_OFFSET + (3 * dma_pkg::CH_STRIDE) + dma_pkg::CH_OFFSET_CTRL, 32'h0000_0013);
    write_reg(dma_pkg::CH_BASE_OFFSET + (0 * dma_pkg::CH_STRIDE) + dma_pkg::CH_OFFSET_CTRL, 32'h0000_0013);

    // Poll completion of CH0
    poll_reg(dma_pkg::CH_BASE_OFFSET + (0 * dma_pkg::CH_STRIDE) + dma_pkg::CH_OFFSET_STATUS, 32'h0000_0002, 32'h0000_0002, 2000);
    // Poll completion of CH3
    poll_reg(dma_pkg::CH_BASE_OFFSET + (3 * dma_pkg::CH_STRIDE) + dma_pkg::CH_OFFSET_STATUS, 32'h0000_0002, 32'h0000_0002, 2000);

    if (scb != null) begin
      scb.check_transfers();
    end
  endtask
endclass

class dma_priority_test extends dma_base_test;
  `uvm_component_utils(dma_priority_test)

  function new(string name = "dma_priority_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    dma_priority_seq seq;
    phase.raise_objection(this);

    `uvm_info("TEST", "==========================================================", UVM_NONE)
    `uvm_info("TEST", "  STARTING: DMA Priority Arbitration Verification Test", UVM_NONE)
    `uvm_info("TEST", "==========================================================", UVM_NONE)

    seq = dma_priority_seq::type_id::create("seq");
    seq.scb = env.m_scoreboard;
    seq.start(env.m_axil_agent.sequencer);

    #100ns;
    `uvm_info("TEST", "DMA Priority Arbitration Test Finished", UVM_NONE)
    phase.drop_objection(this);
  endtask
endclass
