// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: axi_ram_model.sv
// Description: Sparse memory model modeling backing DRAM/SRAM for AXI memory slave.
// ============================================================================

`timescale 1ns / 1ps

class axi_ram_model extends uvm_object;
  `uvm_object_utils(axi_ram_model)

  // Sparse associative memory storage: byte-indexed
  protected bit [7:0] memory[bit [31:0]];

  function new(string name = "axi_ram_model");
    super.new(name);
  endfunction

  // Write a single byte
  function void write_byte(bit [31:0] addr, bit [7:0] data);
    memory[addr] = data;
  endfunction

  // Read a single byte (defaults to 0x00 if unwritten)
  function bit [7:0] read_byte(bit [31:0] addr);
    if (memory.exists(addr)) begin
      return memory[addr];
    end else begin
      return 8'h00;
    end
  endfunction

  // Write a 32-bit little-endian word
  function void write_word(bit [31:0] addr, bit [31:0] data);
    memory[addr + 0] = data[7:0];
    memory[addr + 1] = data[15:8];
    memory[addr + 2] = data[23:16];
    memory[addr + 3] = data[31:24];
  endfunction

  // Read a 32-bit little-endian word
  function bit [31:0] read_word(bit [31:0] addr);
    bit [31:0] val;
    val[7:0]   = read_byte(addr + 0);
    val[15:8]  = read_byte(addr + 1);
    val[23:16] = read_byte(addr + 2);
    val[31:24] = read_byte(addr + 3);
    return val;
  endfunction

  // Helper to write a 32-byte scatter-gather descriptor to memory
  function void write_desc(
    bit [31:0] desc_addr,
    bit [31:0] src_addr,
    bit [31:0] dst_addr,
    bit [31:0] next_desc_addr,
    bit [31:0] transfer_len,
    bit [31:0] ctrl_word
  );
    write_word(desc_addr + 32'd0,  src_addr);
    write_word(desc_addr + 32'd4,  dst_addr);
    write_word(desc_addr + 32'd8,  next_desc_addr);
    write_word(desc_addr + 32'd12, transfer_len);
    write_word(desc_addr + 32'd16, ctrl_word);
    write_word(desc_addr + 32'd20, 32'h0000_0000); // Initial status
    write_word(desc_addr + 32'd24, 32'h0000_0000); // Reserved
    write_word(desc_addr + 32'd28, 32'h0000_0000); // Reserved
  endfunction

  // End-to-end buffer comparison
  function bit compare_buffers(bit [31:0] src_addr, bit [31:0] dst_addr, int len_bytes);
    bit match = 1'b1;
    for (int i = 0; i < len_bytes; i++) begin
      bit [7:0] s_byte, d_byte;
      s_byte = read_byte(src_addr + i);
      d_byte = read_byte(dst_addr + i);
      if (s_byte !== d_byte) begin
        `uvm_error("MEM_MISMATCH", $sformatf("Mismatch at offset %0d: SRC[0x%08x]=0x%02x != DST[0x%08x]=0x%02x",
                                             i, src_addr + i, s_byte, dst_addr + i, d_byte))
        match = 1'b0;
      end
    end
    return match;
  endfunction

  // Clear memory
  function void clear();
    memory.delete();
  endfunction

endclass
