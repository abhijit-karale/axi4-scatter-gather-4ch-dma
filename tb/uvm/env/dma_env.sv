// ============================================================================
// Multi-Channel Scatter-Gather DMA Subsystem - UVM 1.2 Verification Suite
// File: dma_env.sv
// Description: Top-level verification environment assembling agents, RAM model,
//              and scoreboard.
// ============================================================================

`timescale 1ns / 1ps

class dma_env extends uvm_env;
  `uvm_component_utils(dma_env)

  dma_env_config env_cfg;
  axi_agent      m_axi_agent;
  axil_agent     m_axil_agent;
  axi_ram_model  m_ram_model;
  dma_scoreboard m_scoreboard;

  function new(string name = "dma_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(dma_env_config)::get(this, "", "env_cfg", env_cfg)) begin
      `uvm_info("CFG_DEFAULT", "Using default environment configuration", UVM_MEDIUM)
      env_cfg = dma_env_config::type_id::create("env_cfg");
    end

    // Instantiate RAM model
    m_ram_model = axi_ram_model::type_id::create("m_ram_model");
    uvm_config_db#(axi_ram_model)::set(this, "*", "axi_ram", m_ram_model);

    // Build Agents
    if (env_cfg.has_axi_agent) begin
      m_axi_agent = axi_agent::type_id::create("m_axi_agent", this);
      m_axi_agent.is_active = UVM_ACTIVE;
    end

    if (env_cfg.has_axil_agent) begin
      m_axil_agent = axil_agent::type_id::create("m_axil_agent", this);
      m_axil_agent.is_active = UVM_ACTIVE;
    end

    // Build Scoreboard
    if (env_cfg.has_scoreboard) begin
      m_scoreboard = dma_scoreboard::type_id::create("m_scoreboard", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    if (env_cfg.has_scoreboard) begin
      if (env_cfg.has_axi_agent) begin
        m_axi_agent.monitor.item_collected_port.connect(m_scoreboard.axi_export);
      end
      if (env_cfg.has_axil_agent) begin
        m_axil_agent.monitor.item_collected_port.connect(m_scoreboard.axil_export);
      end
    end
  endfunction

endclass
