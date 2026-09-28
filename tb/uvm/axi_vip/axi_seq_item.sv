// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: axi_seq_item.sv
// Description: UVM Sequence Item representing AXI4 transactions.
// ============================================================================

`timescale 1ns / 1ps

class axi_seq_item extends uvm_sequence_item;
  `uvm_object_utils(axi_seq_item)

  rand axi_vip_pkg::axi_trans_type_e trans_type;
  rand bit [31:0]                    addr;
  rand bit [7:0]                     len;
  rand bit [2:0]                     size;
  rand axi_vip_pkg::axi_burst_enum_t burst;
  rand bit [3:0]                     id;
  rand bit [31:0]                    data[];
  rand axi_vip_pkg::axi_resp_enum_t  resp[];

  function new(string name = "axi_seq_item");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("AXI_%s ID=%0d Addr=0x%08x Len=%0d Size=%0d Beats=%0d",
                     trans_type.name(), id, addr, len, size, data.size());
  endfunction

  virtual function void do_copy(uvm_object rhs);
    axi_seq_item rhs_;
    if (!$cast(rhs_, rhs)) begin
      `uvm_fatal("CAST_FAIL", "Failed to cast rhs in do_copy")
    end
    super.do_copy(rhs);
    this.trans_type = rhs_.trans_type;
    this.addr       = rhs_.addr;
    this.len        = rhs_.len;
    this.size       = rhs_.size;
    this.burst      = rhs_.burst;
    this.id         = rhs_.id;
    this.data       = rhs_.data;
    this.resp       = rhs_.resp;
  endfunction

endclass
