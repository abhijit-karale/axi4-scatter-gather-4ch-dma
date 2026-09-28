// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: dma_sg_seq.sv
// Description: Scatter-gather linked-list descriptor randomization sequence.
// ============================================================================

`timescale 1ns / 1ps

class dma_sg_seq extends dma_base_seq;
  `uvm_object_utils(dma_sg_seq)

  axi_ram_model  ram;
  dma_scoreboard scb;

  function new(string name = "dma_sg_seq");
    super.new(name);
  endfunction

  virtual task body();
    bit [31:0] desc0_addr = 32'h0000_1000;
    bit [31:0] desc1_addr = 32'h0000_1020;
    bit [31:0] desc2_addr = 32'h0000_1040;

    bit [31:0] src0_addr  = 32'h0000_2000;
    bit [31:0] dst0_addr  = 32'h0000_3000;
    int        len0       = 64;

    bit [31:0] src1_addr  = 32'h0000_2100;
    bit [31:0] dst1_addr  = 32'h0000_3100;
    int        len1       = 128;

    bit [31:0] src2_addr  = 32'h0000_2200;
    bit [31:0] dst2_addr  = 32'h0000_3200;
    int        len2       = 64;

    bit [31:0] rdata;

    `uvm_info("SG_SEQ", "Starting Scatter-Gather Linked-List Descriptor Sequence", UVM_LOW)

    // Retrieve RAM model & Scoreboard handles if not already assigned
    if (ram == null) begin
      if (!uvm_config_db#(axi_ram_model)::get(null, "*", "axi_ram", ram)) begin
        `uvm_fatal("NORAM", "Could not get axi_ram_model handle in sequence")
      end
    end

    // Populate Source Buffers in RAM
    for (int i = 0; i < len0; i++) ram.write_byte(src0_addr + i, 8'(8'hA0 + i));
    for (int i = 0; i < len1; i++) ram.write_byte(src1_addr + i, 8'(8'hB0 + i));
    for (int i = 0; i < len2; i++) ram.write_byte(src2_addr + i, 8'(8'hC0 + i));

    // Clear Destination Buffers in RAM
    for (int i = 0; i < len0; i++) ram.write_byte(dst0_addr + i, 8'h00);
    for (int i = 0; i < len1; i++) ram.write_byte(dst1_addr + i, 8'h00);
    for (int i = 0; i < len2; i++) ram.write_byte(dst2_addr + i, 8'h00);

    // Descriptor 0: valid=1, ioc=0, stop=0, src_inc=1, dst_inc=1, burst_len=15 (0xF), burst_size=2 -> 0x0F59
    // Flags: valid(1) | (0<<1) | (0<<2) | (1<<3) | (1<<4) | (2<<5) | (15<<8) = 1 | 0 | 0 | 8 | 16 | 64 | 3840 = 3929 = 0x0F59
    ram.write_desc(desc0_addr, src0_addr, dst0_addr, desc1_addr, len0, 32'h0000_0F59);

    // Descriptor 1: valid=1, ioc=0, stop=0, src_inc=1, dst_inc=1, burst_len=15, burst_size=2 -> 0x0F59
    ram.write_desc(desc1_addr, src1_addr, dst1_addr, desc2_addr, len1, 32'h0000_0F59);

    // Descriptor 2: valid=1, ioc=1, stop=1, src_inc=1, dst_inc=1, burst_len=15, burst_size=2 -> 0x0F5F
    // Flags: 1 | 2 | 4 | 8 | 16 | 64 | 3840 = 3935 = 0x0F5F
    ram.write_desc(desc2_addr, src2_addr, dst2_addr, 32'h0000_0000, len2, 32'h0000_0F5F);

    // Register expected transfers with Scoreboard
    if (scb != null) begin
      scb.add_expected_transfer(src0_addr, dst0_addr, len0, 0, 0);
      scb.add_expected_transfer(src1_addr, dst1_addr, len1, 0, 0);
      scb.add_expected_transfer(src2_addr, dst2_addr, len2, 0, 1);
    end

    // Enable Subsystem Globally
    write_reg(dma_pkg::ADDR_GLOBAL_CTRL, 32'h0000_0001);

    // Configure Channel 0 Head Descriptor Pointer (0x048)
    write_reg(dma_pkg::CH_BASE_OFFSET + dma_pkg::CH_OFFSET_DESC_PTR, desc0_addr);

    // Enable and Start Channel 0 with Interrupt on Completion enabled
    // CTRL: bit 0: EN, bit 1: START, bit 4: IE_DONE -> 0x0013
    write_reg(dma_pkg::CH_BASE_OFFSET + dma_pkg::CH_OFFSET_CTRL, 32'h0000_0013);

    // Poll Channel 0 Status (0x044) until bit 1 (DONE) is set
    `uvm_info("SG_SEQ", "Polling Channel 0 Status for completion...", UVM_LOW)
    poll_reg(dma_pkg::CH_BASE_OFFSET + dma_pkg::CH_OFFSET_STATUS, 32'h0000_0002, 32'h0000_0002, 2000);

    `uvm_info("SG_SEQ", "Channel 0 completed linked-list scatter-gather transfer successfully!", UVM_LOW)

    // Trigger end-to-end scoreboard check
    if (scb != null) begin
      scb.check_transfers();
    end
  endtask

endclass
