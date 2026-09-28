// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: dma_base_seq.sv
// Description: Base sequence with register programming and polling helper tasks.
// ============================================================================

`timescale 1ns / 1ps

class dma_base_seq extends uvm_sequence #(axil_seq_item);
  `uvm_object_utils(dma_base_seq)

  function new(string name = "dma_base_seq");
    super.new(name);
  endfunction

  // Write CSR Register via AXI-Lite
  virtual task write_reg(bit [11:0] addr, bit [31:0] data);
    axil_seq_item item;
    item = axil_seq_item::type_id::create("csr_wr");
    start_item(item);
    item.is_write = 1'b1;
    item.addr     = addr;
    item.data     = data;
    finish_item(item);
  endtask

  // Read CSR Register via AXI-Lite
  virtual task read_reg(bit [11:0] addr, output bit [31:0] data);
    axil_seq_item item;
    item = axil_seq_item::type_id::create("csr_rd");
    start_item(item);
    item.is_write = 1'b0;
    item.addr     = addr;
    finish_item(item);
    data = item.data;
  endtask

  // Poll CSR Register bit until expected value or timeout
  virtual task poll_reg(bit [11:0] addr, bit [31:0] mask, bit [31:0] expected_val, int max_polls = 1000);
    bit [31:0] rdata;
    int count = 0;
    forever begin
      read_reg(addr, rdata);
      if ((rdata & mask) == (expected_val & mask)) begin
        break;
      end
      count++;
      if (count >= max_polls) begin
        `uvm_fatal("POLL_TIMEOUT", $sformatf("Timeout polling register 0x%03x! Mask=0x%08x, Exp=0x%08x, Read=0x%08x",
                                             addr, mask, expected_val, rdata))
      end
      #20ns;
    end
  endtask

endclass
