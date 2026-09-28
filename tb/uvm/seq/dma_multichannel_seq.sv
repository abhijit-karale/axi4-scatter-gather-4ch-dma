// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: dma_multichannel_seq.sv
// Description: Multi-channel concurrent transfer sequence launching all 4
//              channels under Round-Robin arbitration.
// ============================================================================

`timescale 1ns / 1ps

class dma_multichannel_seq extends dma_base_seq;
  `uvm_object_utils(dma_multichannel_seq)

  axi_ram_model  ram;
  dma_scoreboard scb;

  function new(string name = "dma_multichannel_seq");
    super.new(name);
  endfunction

  virtual task body();
    bit [31:0] desc_addr[4];
    bit [31:0] src_addr[4];
    bit [31:0] dst_addr[4];
    int        xfer_len = 64;

    `uvm_info("MC_SEQ", "Starting Multi-Channel Concurrent Transfer Sequence (4 Channels)", UVM_LOW)

    if (!uvm_config_db#(axi_ram_model)::get(null, "*", "axi_ram", ram)) begin
      `uvm_fatal("NORAM", "Could not get axi_ram_model in multichannel sequence")
    end

    // Configure addresses for each channel
    for (int ch = 0; ch < 4; ch++) begin
      desc_addr[ch] = 32'h0000_5000 + (ch * 32'h0040);
      src_addr[ch]  = 32'h0000_6000 + (ch * 32'h0200);
      dst_addr[ch]  = 32'h0000_7000 + (ch * 32'h0200);

      // Populate source buffer
      for (int i = 0; i < xfer_len; i++) begin
        ram.write_byte(src_addr[ch] + i, 8'((ch << 4) + i));
        ram.write_byte(dst_addr[ch] + i, 8'h00);
      end

      // Single descriptor per channel: STOP=1, IOC=1, SRC_INC=1, DST_INC=1
      ram.write_desc(desc_addr[ch], src_addr[ch], dst_addr[ch], 32'h0000_0000, xfer_len, 32'h0000_0F5F);

      if (scb != null) begin
        scb.add_expected_transfer(src_addr[ch], dst_addr[ch], xfer_len, ch, 1);
      end
    end

    // Enable Global Subsystem and set Arbiter to Round-Robin (bit [3:2] = 2'b01 -> 0x0005)
    write_reg(dma_pkg::ADDR_GLOBAL_CTRL, 32'h0000_0005);

    // Program Head Descriptors for all 4 channels
    for (int ch = 0; ch < 4; ch++) begin
      bit [11:0] ch_base = dma_pkg::CH_BASE_OFFSET + (ch * dma_pkg::CH_STRIDE);
      write_reg(ch_base + dma_pkg::CH_OFFSET_DESC_PTR, desc_addr[ch]);
    end

    // Launch all 4 channels
    for (int ch = 0; ch < 4; ch++) begin
      bit [11:0] ch_base = dma_pkg::CH_BASE_OFFSET + (ch * dma_pkg::CH_STRIDE);
      write_reg(ch_base + dma_pkg::CH_OFFSET_CTRL, 32'h0000_0013);
    end

    // Wait for all 4 channels to reach DONE
    for (int ch = 0; ch < 4; ch++) begin
      bit [11:0] ch_base = dma_pkg::CH_BASE_OFFSET + (ch * dma_pkg::CH_STRIDE);
      `uvm_info("MC_SEQ", $sformatf("Waiting for Channel %0d to complete...", ch), UVM_LOW)
      poll_reg(ch_base + dma_pkg::CH_OFFSET_STATUS, 32'h0000_0002, 32'h0000_0002, 3000);
      `uvm_info("MC_SEQ", $sformatf("Channel %0d completed successfully!", ch), UVM_LOW)
    end

    // Check all transfers in scoreboard
    if (scb != null) begin
      scb.check_transfers();
    end
  endtask

endclass
