// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: axil_seq_item.sv
// Description: UVM Sequence Item for AXI4-Lite CSR transactions.
// ============================================================================

`timescale 1ns / 1ps

class axil_seq_item extends uvm_sequence_item;
  `uvm_object_utils(axil_seq_item)

  rand bit        is_write;
  rand bit [11:0] addr;
  rand bit [31:0] data;
  rand bit [3:0]  strb;
  bit [1:0]       resp;

  function new(string name = "axil_seq_item");
    super.new(name);
    strb = 4'hF;
  endfunction

  virtual function string convert2string();
    return $sformatf("AXIL_%s Addr=0x%03x Data=0x%08x Resp=0x%0x",
                     is_write ? "WRITE" : "READ", addr, data, resp);
  endfunction

  virtual function void do_copy(uvm_object rhs);
    axil_seq_item rhs_;
    if (!$cast(rhs_, rhs)) `uvm_fatal("CAST_FAIL", "Failed casting axil_seq_item")
    super.do_copy(rhs);
    this.is_write = rhs_.is_write;
    this.addr     = rhs_.addr;
    this.data     = rhs_.data;
    this.strb     = rhs_.strb;
    this.resp     = rhs_.resp;
  endfunction

endclass
