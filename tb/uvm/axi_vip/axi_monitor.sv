// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: axi_monitor.sv
// Description: Passive AXI4 bus monitor reconstructing read and write bursts.
// ============================================================================

`timescale 1ns / 1ps

class axi_monitor extends uvm_monitor;
  `uvm_component_utils(axi_monitor)

  virtual axi_if                               vif;
  uvm_analysis_port #(axi_seq_item)            item_collected_port;

  function new(string name = "axi_monitor", uvm_component parent = null);
    super.new(name, parent);
    item_collected_port = new("item_collected_port", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi_if)::get(this, "", "axi_vif", vif)) begin
      `uvm_fatal("NOVIF", "Could not get virtual axi_if in monitor")
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    fork
      monitor_reads();
      monitor_writes();
    join
  endtask

  virtual task monitor_reads();
    axi_seq_item item;
    forever begin
      @(posedge vif.clk);
      if (vif.arvalid && vif.arready) begin
        item = axi_seq_item::type_id::create("rd_item");
        item.trans_type = axi_vip_pkg::AXI_TRANS_READ;
        item.addr       = vif.araddr;
        item.len        = vif.arlen;
        item.size       = vif.arsize;
        item.burst      = axi_vip_pkg::axi_burst_enum_t'(vif.arburst);
        item.id         = vif.arid;
        item.data       = new[item.len + 1];
        item.resp       = new[item.len + 1];

        for (int i = 0; i <= item.len; i++) begin
          do begin
            @(posedge vif.clk);
          end while (!(vif.rvalid && vif.rready));
          item.data[i] = vif.rdata;
          item.resp[i] = axi_vip_pkg::axi_resp_enum_t'(vif.rresp);
        end
        item_collected_port.write(item);
      end
    end
  endtask

  virtual task monitor_writes();
    axi_seq_item item;
    forever begin
      @(posedge vif.clk);
      if (vif.awvalid && vif.awready) begin
        item = axi_seq_item::type_id::create("wr_item");
        item.trans_type = axi_vip_pkg::AXI_TRANS_WRITE;
        item.addr       = vif.awaddr;
        item.len        = vif.awlen;
        item.size       = vif.awsize;
        item.burst      = axi_vip_pkg::axi_burst_enum_t'(vif.awburst);
        item.id         = vif.awid;
        item.data       = new[item.len + 1];

        for (int i = 0; i <= item.len; i++) begin
          do begin
            @(posedge vif.clk);
          end while (!(vif.wvalid && vif.wready));
          item.data[i] = vif.wdata;
        end

        // Wait for B handshake
        do begin
          @(posedge vif.clk);
        end while (!(vif.bvalid && vif.bready));

        item_collected_port.write(item);
      end
    end
  endtask

endclass
