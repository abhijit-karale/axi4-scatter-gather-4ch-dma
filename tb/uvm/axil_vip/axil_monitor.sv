// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: axil_monitor.sv
// Description: Passive monitor observing AXI4-Lite CSR transactions.
// ============================================================================

`timescale 1ns / 1ps

class axil_monitor extends uvm_monitor;
  `uvm_component_utils(axil_monitor)

  virtual axil_if                   vif;
  uvm_analysis_port #(axil_seq_item) item_collected_port;

  function new(string name = "axil_monitor", uvm_component parent = null);
    super.new(name, parent);
    item_collected_port = new("item_collected_port", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axil_if)::get(this, "", "axil_vif", vif)) begin
      `uvm_fatal("NOVIF", "Could not get virtual axil_if in monitor")
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    fork
      monitor_writes();
      monitor_reads();
    join
  endtask

  virtual task monitor_writes();
    axil_seq_item item;
    forever begin
      @(posedge vif.clk);
      if (vif.awvalid && vif.awready) begin
        item = axil_seq_item::type_id::create("csr_wr_item");
        item.is_write = 1'b1;
        item.addr     = vif.awaddr;
        do begin
          @(posedge vif.clk);
        end while (!(vif.wvalid && vif.wready));
        item.data = vif.wdata;
        item.strb = vif.wstrb;

        do begin
          @(posedge vif.clk);
        end while (!(vif.bvalid && vif.bready));
        item.resp = vif.bresp;

        item_collected_port.write(item);
      end
    end
  endtask

  virtual task monitor_reads();
    axil_seq_item item;
    forever begin
      @(posedge vif.clk);
      if (vif.arvalid && vif.arready) begin
        item = axil_seq_item::type_id::create("csr_rd_item");
        item.is_write = 1'b0;
        item.addr     = vif.araddr;

        do begin
          @(posedge vif.clk);
        end while (!(vif.rvalid && vif.rready));
        item.data = vif.rdata;
        item.resp = vif.rresp;

        item_collected_port.write(item);
      end
    end
  endtask

endclass
