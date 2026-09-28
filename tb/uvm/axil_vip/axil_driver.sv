// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: axil_driver.sv
// Description: Master driver for AXI4-Lite CSR transactions.
// ============================================================================

`timescale 1ns / 1ps

class axil_driver extends uvm_driver #(axil_seq_item);
  `uvm_component_utils(axil_driver)

  virtual axil_if vif;

  function new(string name = "axil_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axil_if)::get(this, "", "axil_vif", vif)) begin
      `uvm_fatal("NOVIF", "Could not get virtual axil_if in driver")
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    reset_signals();
    @(posedge vif.rst_n);

    forever begin
      seq_item_port.get_next_item(req);
      if (req.is_write) begin
        drive_write(req);
      end else begin
        drive_read(req);
      end
      seq_item_port.item_done();
    end
  endtask

  virtual task reset_signals();
    vif.awaddr  <= '0;
    vif.awprot  <= '0;
    vif.awvalid <= 1'b0;
    vif.wdata   <= '0;
    vif.wstrb   <= '0;
    vif.wvalid  <= 1'b0;
    vif.bready  <= 1'b0;
    vif.araddr  <= '0;
    vif.arprot  <= '0;
    vif.arvalid <= 1'b0;
    vif.rready  <= 1'b0;
  endtask

  virtual task drive_write(axil_seq_item item);
    @(posedge vif.clk);
    vif.awaddr  <= item.addr;
    vif.awprot  <= 3'b000;
    vif.awvalid <= 1'b1;
    vif.wdata   <= item.data;
    vif.wstrb   <= item.strb;
    vif.wvalid  <= 1'b1;
    vif.bready  <= 1'b1;

    // Wait for AWREADY and WREADY
    fork
      begin
        do begin
          @(posedge vif.clk);
        end while (!vif.awready);
        vif.awvalid <= 1'b0;
      end
      begin
        do begin
          @(posedge vif.clk);
        end while (!vif.wready);
        vif.wvalid <= 1'b0;
      end
    join

    // Wait for BVALID
    do begin
      @(posedge vif.clk);
    end while (!vif.bvalid);

    item.resp  = vif.bresp;
    vif.bready <= 1'b0;
  endtask

  virtual task drive_read(axil_seq_item item);
    @(posedge vif.clk);
    vif.araddr  <= item.addr;
    vif.arprot  <= 3'b000;
    vif.arvalid <= 1'b1;
    vif.rready  <= 1'b1;

    // Wait for ARREADY
    do begin
      @(posedge vif.clk);
    end while (!vif.arready);
    vif.arvalid <= 1'b0;

    // Wait for RVALID
    do begin
      @(posedge vif.clk);
    end while (!vif.rvalid);

    item.data  = vif.rdata;
    item.resp  = vif.rresp;
    vif.rready <= 1'b0;
  endtask

endclass
