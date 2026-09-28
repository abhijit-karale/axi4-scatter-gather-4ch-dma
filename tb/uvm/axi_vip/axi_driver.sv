// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: axi_driver.sv
// Description: Reactive AXI4 Slave memory responder driving bus cycles and
//              maintaining backing memory state.
// ============================================================================

`timescale 1ns / 1ps

class axi_driver extends uvm_driver #(axi_seq_item);
  `uvm_component_utils(axi_driver)

  virtual axi_if vif;
  axi_ram_model  ram;

  function new(string name = "axi_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi_if)::get(this, "", "axi_vif", vif)) begin
      `uvm_fatal("NOVIF", "Could not get virtual axi_if")
    end
    if (!uvm_config_db#(axi_ram_model)::get(this, "", "axi_ram", ram)) begin
      `uvm_fatal("NORAM", "Could not get axi_ram_model handle")
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    reset_signals();
    @(posedge vif.rst_n);

    fork
      handle_read_transactions();
      handle_write_transactions();
    join
  endtask

  // Initialize output signals
  virtual task reset_signals();
    vif.arready <= 1'b0;
    vif.rvalid  <= 1'b0;
    vif.rdata   <= '0;
    vif.rresp   <= 2'b00;
    vif.rlast   <= 1'b0;
    vif.rid     <= '0;

    vif.awready <= 1'b0;
    vif.wready  <= 1'b0;
    vif.bvalid  <= 1'b0;
    vif.bresp   <= 2'b00;
    vif.bid     <= '0;
  endtask

  // Reactive Read Slave Task
  virtual task handle_read_transactions();
    bit [31:0] read_addr;
    bit [7:0]  read_len;
    bit [3:0]  read_id;
    bit [2:0]  read_size;

    forever begin
      @(posedge vif.clk);
      if (!vif.rst_n) begin
        vif.arready <= 1'b0;
        vif.rvalid  <= 1'b0;
        continue;
      end

      // Ready for AR
      vif.arready <= 1'b1;

      if (vif.arvalid && vif.arready) begin
        read_addr = vif.araddr;
        read_len  = vif.arlen;
        read_id   = vif.arid;
        read_size = vif.arsize;
        vif.arready <= 1'b0; // Deassert after handshake

        // Send Read Data beats
        for (int beat = 0; beat <= read_len; beat++) begin
          bit [31:0] word_data;
          word_data = ram.read_word(read_addr + (beat * 4));
          if (read_addr >= 32'h0000_2100 && read_addr < 32'h0000_2200) begin
            $display("[AXI_RD] addr=0x%08x data=0x%08x", read_addr + (beat * 4), word_data);
          end

          vif.rvalid <= 1'b1;
          vif.rdata  <= word_data;
          vif.rresp  <= 2'b00; // OKAY
          vif.rid    <= read_id;
          vif.rlast  <= (beat == read_len);

          // Wait for master RREADY
          do begin
            @(posedge vif.clk);
          end while (!(vif.rvalid && vif.rready));
        end

        vif.rvalid <= 1'b0;
        vif.rlast  <= 1'b0;
      end
    end
  endtask

  // Reactive Write Slave Task
  virtual task handle_write_transactions();
    bit [31:0] write_addr;
    bit [7:0]  write_len;
    bit [3:0]  write_id;
    bit [2:0]  write_size;

    forever begin
      @(posedge vif.clk);
      if (!vif.rst_n) begin
        vif.awready <= 1'b0;
        vif.wready  <= 1'b0;
        vif.bvalid  <= 1'b0;
        continue;
      end

      vif.awready <= 1'b1;

      if (vif.awvalid && vif.awready) begin
        write_addr = vif.awaddr;
        write_len  = vif.awlen;
        write_id   = vif.awid;
        write_size = vif.awsize;
        vif.awready <= 1'b0;

        // Receive W beats
        for (int beat = 0; beat <= write_len; beat++) begin
          vif.wready <= 1'b1;
          do begin
            @(posedge vif.clk);
          end while (!(vif.wvalid && vif.wready));

          // Store into RAM model
          ram.write_word(write_addr + (beat * 4), vif.wdata);
          if (write_addr >= 32'h0000_3100 && write_addr < 32'h0000_3200) begin
            $display("[AXI_WR] addr=0x%08x data=0x%08x", write_addr + (beat * 4), vif.wdata);
          end
        end
        vif.wready <= 1'b0;

        // Drive B Channel response
        vif.bvalid <= 1'b1;
        vif.bresp  <= 2'b00; // OKAY
        vif.bid    <= write_id;

        do begin
          @(posedge vif.clk);
        end while (!(vif.bvalid && vif.bready));

        vif.bvalid <= 1'b0;
      end
    end
  endtask

endclass
