// Copyright © 2019-2023
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

`include "VX_define.vh"

`ifdef EXT_TEX_ENABLE
`include "VX_tex_define.vh"
`endif

`ifdef EXT_RASTER_ENABLE
`include "VX_raster_define.vh"
`endif

`ifdef EXT_ROP_ENABLE
`include "VX_rop_define.vh"
`endif

module VX_cluster import VX_gpu_pkg::*; #(
    parameter CLUSTER_ID = 0
) ( 
    `SCOPE_IO_DECL

    // Clock
    input  wire                 clk,
    input  wire                 reset,

`ifdef PERF_ENABLE
    VX_mem_perf_if.master       mem_perf_if,
    VX_mem_perf_if.slave        perf_memsys_total_if,
`endif

    VX_dcr_bus_if.slave         dcr_bus_if,

`ifdef EXT_TEX_ENABLE
`ifdef PERF_ENABLE
    VX_tex_perf_if.master       perf_tex_if,
    VX_cache_perf_if.master     perf_tcache_if,
    VX_tex_perf_if.slave        perf_tex_total_if,
    VX_cache_perf_if.slave      perf_tcache_total_if,
`endif
`endif

`ifdef EXT_RASTER_ENABLE
`ifdef PERF_ENABLE
    VX_raster_perf_if.master    perf_raster_if,
    VX_cache_perf_if.master     perf_rcache_if,
    VX_raster_perf_if.slave     perf_raster_total_if,
    VX_cache_perf_if.slave      perf_rcache_total_if,
`endif
`endif

`ifdef EXT_ROP_ENABLE
`ifdef PERF_ENABLE
    VX_rop_perf_if.master       perf_rop_if,
    VX_cache_perf_if.master     perf_ocache_if,
    VX_rop_perf_if.slave        perf_rop_total_if,
    VX_cache_perf_if.slave      perf_ocache_total_if,
`endif
`endif

    // Memory
    VX_mem_bus_if.master        mem_bus_if,

    // simulation helper signals
    output wire                 sim_ebreak,
    output wire [`NUM_REGS-1:0][`XLEN-1:0] sim_wb_value,

    // Status
    output wire                 busy
);

`ifdef SCOPE
    localparam scope_raster_units = `EXT_RASTER_ENABLED ? `NUM_RASTER_UNITS : 0;
    `SCOPE_IO_SWITCH (scope_raster_units + `NUM_SOCKETS);
`endif

`ifdef GBAR_ENABLE

    VX_gbar_bus_if per_socket_gbar_bus_if[`NUM_SOCKETS]();
    VX_gbar_bus_if gbar_bus_if();

    `RESET_RELAY (gbar_reset, reset);

    VX_gbar_arb #(
        .NUM_REQS (`NUM_SOCKETS),
        .OUT_REG  ((`NUM_SOCKETS > 2) ? 1 : 0) // bgar_unit has no backpressure
    ) gbar_arb (
        .clk        (clk),
        .reset      (gbar_reset),
        .bus_in_if  (per_socket_gbar_bus_if),
        .bus_out_if (gbar_bus_if)
    );

    VX_gbar_unit #(
        .INSTANCE_ID ($sformatf("gbar%0d", CLUSTER_ID))
    ) gbar_unit (
        .clk         (clk),
        .reset       (gbar_reset),
        .gbar_bus_if (gbar_bus_if)
    );
`endif

`ifdef EXT_RASTER_ENABLE

`ifdef PERF_ENABLE
    VX_raster_perf_if perf_raster_unit_if[`NUM_RASTER_UNITS]();
    `PERF_RASTER_ADD (perf_raster_if, perf_raster_unit_if, `NUM_RASTER_UNITS);
`endif

    VX_mem_bus_if #(
        .DATA_SIZE (RCACHE_WORD_SIZE),
        .TAG_WIDTH (RCACHE_TAG_WIDTH)
    ) rcache_bus_if[`NUM_RASTER_UNITS * RCACHE_NUM_REQS]();

    VX_raster_bus_if #(
        .NUM_LANES (`NUM_SFU_LANES)
    ) raster_bus_if[`NUM_RASTER_UNITS]();

    VX_dcr_bus_if raster_dcr_bus_tmp_if();
    assign raster_dcr_bus_tmp_if.write_valid = dcr_bus_if.write_valid && (dcr_bus_if.write_addr >= `VX_DCR_RASTER_STATE_BEGIN && dcr_bus_if.write_addr < `VX_DCR_RASTER_STATE_END);
    assign raster_dcr_bus_tmp_if.write_addr  = dcr_bus_if.write_addr;
    assign raster_dcr_bus_tmp_if.write_data  = dcr_bus_if.write_data;

    `BUFFER_DCR_BUS_IF (raster_dcr_bus_if, raster_dcr_bus_tmp_if, 1);

    // Generate all raster units
    for (genvar i = 0; i < `NUM_RASTER_UNITS; ++i) begin

        `RESET_RELAY (raster_reset, reset);

        VX_raster_unit #( 
            .INSTANCE_ID     ($sformatf("cluster%0d-raster%0d", CLUSTER_ID, i)),
            .INSTANCE_IDX    (CLUSTER_ID * `NUM_RASTER_UNITS + i),
            .NUM_INSTANCES   (`NUM_CLUSTERS * `NUM_RASTER_UNITS),
            .NUM_SLICES      (`RASTER_NUM_SLICES),
            .TILE_LOGSIZE    (`RASTER_TILE_LOGSIZE),
            .BLOCK_LOGSIZE   (`RASTER_BLOCK_LOGSIZE),
            .MEM_FIFO_DEPTH  (`RASTER_MEM_FIFO_DEPTH),
            .QUAD_FIFO_DEPTH (`RASTER_QUAD_FIFO_DEPTH),
            .OUTPUT_QUADS    (`NUM_SFU_LANES)
        ) raster_unit (
            `SCOPE_IO_BIND (i)
            .clk           (clk),
            .reset         (raster_reset),
        `ifdef PERF_ENABLE
            .perf_raster_if(perf_raster_unit_if[i]),
        `endif
            .dcr_bus_if    (raster_dcr_bus_if),
            .raster_bus_if (raster_bus_if[i]),
            .cache_bus_if  (rcache_bus_if[i * RCACHE_NUM_REQS +: RCACHE_NUM_REQS])
        );
    end

    VX_raster_bus_if #(
        .NUM_LANES (`NUM_SFU_LANES)
    ) per_socket_raster_bus_if[`NUM_SOCKETS]();

    `RESET_RELAY (raster_arb_reset, reset);

    VX_raster_arb #(
        .NUM_INPUTS  (`NUM_RASTER_UNITS),
        .NUM_LANES   (`NUM_SFU_LANES),
        .NUM_OUTPUTS (`NUM_SOCKETS),
        .ARBITER     ("R"),
        .OUT_REG     ((`NUM_SOCKETS != `NUM_RASTER_UNITS) ? 2 : 0)
    ) raster_arb (
        .clk        (clk),
        .reset      (raster_arb_reset),
        .bus_in_if  (raster_bus_if),
        .bus_out_if (per_socket_raster_bus_if)
    );   
`endif

`ifdef EXT_ROP_ENABLE

`ifdef PERF_ENABLE
    VX_rop_perf_if perf_rop_unit_if[`NUM_ROP_UNITS]();
    `PERF_ROP_ADD (perf_rop_if, perf_rop_unit_if, `NUM_ROP_UNITS);
`endif

    VX_mem_bus_if #(
        .DATA_SIZE (OCACHE_WORD_SIZE),
        .TAG_WIDTH (OCACHE_TAG_WIDTH)
    ) ocache_bus_if[`NUM_ROP_UNITS * OCACHE_NUM_REQS]();

    VX_rop_bus_if #(
        .NUM_LANES (`NUM_SFU_LANES)
    ) per_socket_rop_bus_if[`NUM_SOCKETS]();

    VX_rop_bus_if #(
        .NUM_LANES (`NUM_SFU_LANES)
    ) rop_bus_if[`NUM_ROP_UNITS]();

    `RESET_RELAY (rop_arb_reset, reset);

    VX_rop_arb #(
        .NUM_INPUTS  (`NUM_SOCKETS),
        .NUM_LANES   (`NUM_SFU_LANES),
        .NUM_OUTPUTS (`NUM_ROP_UNITS),
        .ARBITER     ("R"),
        .OUT_REG    ((`NUM_SOCKETS != `NUM_ROP_UNITS) ? 2 : 0)
    ) rop_arb (
        .clk        (clk),
        .reset      (rop_arb_reset),
        .bus_in_if  (per_socket_rop_bus_if),
        .bus_out_if (rop_bus_if)
    );

    VX_dcr_bus_if rop_dcr_bus_tmp_if();
    assign rop_dcr_bus_tmp_if.write_valid = dcr_bus_if.write_valid && (dcr_bus_if.write_addr >= `VX_DCR_ROP_STATE_BEGIN && dcr_bus_if.write_addr < `VX_DCR_ROP_STATE_END);
    assign rop_dcr_bus_tmp_if.write_addr  = dcr_bus_if.write_addr;
    assign rop_dcr_bus_tmp_if.write_data  = dcr_bus_if.write_data;

    `BUFFER_DCR_BUS_IF (rop_dcr_bus_if, rop_dcr_bus_tmp_if, 1);

    // Generate all rop units
    for (genvar i = 0; i < `NUM_ROP_UNITS; ++i) begin

        `RESET_RELAY (rop_reset, reset);

        VX_rop_unit #(
            .INSTANCE_ID ($sformatf("cluster%0d-rop%0d", CLUSTER_ID, i)),
            .NUM_LANES   (`NUM_SFU_LANES)
        ) rop_unit (
            .clk           (clk),
            .reset         (rop_reset),
        `ifdef PERF_ENABLE
            .perf_rop_if   (perf_rop_unit_if[i]),
        `endif
            .dcr_bus_if    (rop_dcr_bus_if),
            .rop_bus_if    (rop_bus_if[i]),            
            .cache_bus_if  (ocache_bus_if[i * OCACHE_NUM_REQS +: OCACHE_NUM_REQS])
        );
    end

`endif

`ifdef EXT_TEX_ENABLE

`ifdef PERF_ENABLE
    VX_tex_perf_if perf_tex_unit_if[`NUM_TEX_UNITS]();
    `PERF_TEX_ADD (perf_tex_if, perf_tex_unit_if, `NUM_TEX_UNITS);
`endif

    VX_mem_bus_if #(
        .DATA_SIZE (TCACHE_WORD_SIZE),
        .TAG_WIDTH (TCACHE_TAG_WIDTH)
    ) tcache_bus_if[`NUM_TEX_UNITS * TCACHE_NUM_REQS]();

    VX_tex_bus_if #(
        .NUM_LANES (`NUM_SFU_LANES),
        .TAG_WIDTH (`TEX_REQ_ARB1_TAG_WIDTH)
    ) per_socket_tex_bus_if[`NUM_SOCKETS]();

    VX_tex_bus_if #(
        .NUM_LANES (`NUM_SFU_LANES),
        .TAG_WIDTH (`TEX_REQ_ARB2_TAG_WIDTH)
    ) tex_bus_if[`NUM_TEX_UNITS]();

    `RESET_RELAY (tex_arb_reset, reset);

    VX_tex_arb #(
        .NUM_INPUTS   (`NUM_SOCKETS),
        .NUM_LANES    (`NUM_SFU_LANES),
        .NUM_OUTPUTS  (`NUM_TEX_UNITS),
        .TAG_WIDTH    (`TEX_REQ_ARB1_TAG_WIDTH),
        .ARBITER      ("R"),
        .OUT_REG_REQ  ((`NUM_SOCKETS != `NUM_TEX_UNITS) ? 2 : 0)
    ) tex_arb (
        .clk        (clk),
        .reset      (tex_arb_reset),
        .bus_in_if  (per_socket_tex_bus_if),
        .bus_out_if (tex_bus_if)
    );

    VX_dcr_bus_if tex_dcr_bus_tmp_if();
    assign tex_dcr_bus_tmp_if.write_valid = dcr_bus_if.write_valid && (dcr_bus_if.write_addr >= `VX_DCR_TEX_STATE_BEGIN && dcr_bus_if.write_addr < `VX_DCR_TEX_STATE_END);
    assign tex_dcr_bus_tmp_if.write_addr  = dcr_bus_if.write_addr;
    assign tex_dcr_bus_tmp_if.write_data  = dcr_bus_if.write_data;

    `BUFFER_DCR_BUS_IF (tex_dcr_bus_if, tex_dcr_bus_tmp_if, 1);

    // Generate all texture units
    for (genvar i = 0; i < `NUM_TEX_UNITS; ++i) begin

        `RESET_RELAY (tex_reset, reset);

        VX_tex_unit #(
            .INSTANCE_ID ($sformatf("cluster%0d-tex%0d", CLUSTER_ID, i)),
            .NUM_LANES   (`NUM_SFU_LANES),
            .TAG_WIDTH   (`TEX_REQ_ARB2_TAG_WIDTH)
        ) tex_unit (
            .clk          (clk),
            .reset        (tex_reset),
        `ifdef PERF_ENABLE
            .perf_tex_if  (perf_tex_unit_if[i]),
        `endif 
            .dcr_bus_if   (tex_dcr_bus_if),
            .tex_bus_if   (tex_bus_if[i]),
            .cache_bus_if (tcache_bus_if[i * TCACHE_NUM_REQS +: TCACHE_NUM_REQS])
        );
    end
            
`endif
    VX_sfu_csr_if #(
        .NUM_LANES (`NUM_SFU_LANES)
    ) per_socket_csr_bus_if[2]();

    VX_mem_bus_if #(
        .DATA_SIZE (DCACHE_WORD_SIZE), 
        .TAG_WIDTH (DCACHE_ARB_TAG_WIDTH)
    ) per_socket_dcache_bus_if[`NUM_SOCKETS * DCACHE_NUM_REQS]();
    
    VX_mem_bus_if #(
        .DATA_SIZE (ICACHE_WORD_SIZE),
        .TAG_WIDTH (ICACHE_ARB_TAG_WIDTH)
    ) per_socket_icache_bus_if[`NUM_SOCKETS](); 
    // can we change NUM_SOCKETS() formula to include scalar core count? 

    `RESET_RELAY (mem_unit_reset, reset);

    VX_mem_unit #(
        .CLUSTER_ID (CLUSTER_ID)
    ) mem_unit (
        .clk                (clk),
        .reset              (mem_unit_reset),

    `ifdef PERF_ENABLE
        .mem_perf_if        (mem_perf_if),
    `endif

        .dcache_bus_if      (per_socket_dcache_bus_if),
        
        .icache_bus_if      (per_socket_icache_bus_if),

    `ifdef EXT_TEX_ENABLE
    `ifdef PERF_ENABLE
        .perf_tcache_if     (perf_tcache_if),
    `endif
        .tcache_bus_if      (tcache_bus_if),
    `endif

    `ifdef EXT_RASTER_ENABLE
    `ifdef PERF_ENABLE
        .perf_rcache_if     (perf_rcache_if),
    `endif
        .rcache_bus_if      (rcache_bus_if),
    `endif 

    `ifdef EXT_ROP_ENABLE
    `ifdef PERF_ENABLE
        .perf_ocache_if     (perf_ocache_if),
    `endif
        .ocache_bus_if      (ocache_bus_if),
    `endif

        .mem_bus_if         (mem_bus_if)
    );
    // This mem unit creates the cache, so One set of cache within a cluster? 
    ///////////////////////////////////////////////////////////////////////////

    wire [`NUM_SOCKETS-1:0] per_socket_sim_ebreak;
    wire [`NUM_SOCKETS-1:0][`NUM_REGS-1:0][`XLEN-1:0] per_socket_sim_wb_value;
    assign sim_ebreak = per_socket_sim_ebreak[0];
    assign sim_wb_value = per_socket_sim_wb_value[0];
    `UNUSED_VAR (per_socket_sim_ebreak)
    `UNUSED_VAR (per_socket_sim_wb_value)

    VX_dcr_bus_if socket_dcr_bus_tmp_if();
    assign socket_dcr_bus_tmp_if.write_valid = dcr_bus_if.write_valid && (dcr_bus_if.write_addr >= `VX_DCR_BASE_STATE_BEGIN && dcr_bus_if.write_addr < `VX_DCR_BASE_STATE_END);
    assign socket_dcr_bus_tmp_if.write_addr  = dcr_bus_if.write_addr;
    assign socket_dcr_bus_tmp_if.write_data  = dcr_bus_if.write_data;

    wire [`NUM_SOCKETS-1:0] per_socket_busy;

    `BUFFER_DCR_BUS_IF (socket_dcr_bus_if, socket_dcr_bus_tmp_if, (`NUM_SOCKETS > 1));

    // Generate all sockets
    for (genvar i = 0; i < `NUM_SOCKETS; ++i) begin

        `RESET_RELAY (socket_reset, reset);

        VX_socket #(
            .SOCKET_ID ((CLUSTER_ID * `NUM_SOCKETS) + i)
        ) socket (
            `SCOPE_IO_BIND  (scope_raster_units+i)

            .clk            (clk),
            .reset          (socket_reset),

        `ifdef PERF_ENABLE
            .mem_perf_if    (perf_memsys_total_if),
        `endif
            
            .dcr_bus_if     (socket_dcr_bus_if),

            .dcache_bus_if  (per_socket_dcache_bus_if[i * DCACHE_NUM_REQS +: DCACHE_NUM_REQS]),

            .icache_bus_if  (per_socket_icache_bus_if[i]),

            .hw_itr_ctrl_if (per_socket_csr_bus_if[i]),
            
            .interrupt_ctl_ttu_if (interrupt_ctl_ttu_if),
            .execute_hw_itr_if    (per_socket_execute_hw_itr_if[i]),

        `ifdef EXT_TEX_ENABLE
        `ifdef PERF_ENABLE
            .perf_tex_if    (perf_tex_total_if),
            .perf_tcache_if (perf_tcache_total_if),
        `endif
            .tex_bus_if     (per_socket_tex_bus_if[i]),
        `endif

        `ifdef EXT_RASTER_ENABLE
        `ifdef PERF_ENABLE
            .perf_raster_if (perf_raster_total_if),
            .perf_rcache_if (perf_rcache_total_if),
        `endif
            .raster_bus_if  (per_socket_raster_bus_if[i]),
        `endif
        
        `ifdef EXT_ROP_ENABLE
        `ifdef PERF_ENABLE
            .perf_rop_if    (perf_rop_total_if),
            .perf_ocache_if (perf_ocache_total_if),
        `endif
            .rop_bus_if     (per_socket_rop_bus_if[i]),
        `endif
        
        `ifdef GBAR_ENABLE
            .gbar_bus_if    (per_socket_gbar_bus_if[i]),
        `endif

            .sim_ebreak     (per_socket_sim_ebreak[i]),
            .sim_wb_value   (per_socket_sim_wb_value[i]),
            .busy           (per_socket_busy[i])
        );
    end

    `BUFFER_BUSY (busy, (| per_socket_busy), (`NUM_SOCKETS > 1));

    //***************************************
    // Hardware Interrupt Controller Module *
    //***************************************
    `RESET_RELAY (interrupt_ctl_reset, reset);
    VX_interrupt_ctl_ttu_if interrupt_ctl_ttu_if ();
    VX_execute_hw_itr_if    per_socket_execute_hw_itr_if[2]();

    VX_interrupt_ctl interrupt_controller
    (
        .clk                  (clk), 
        .reset                (interrupt_ctl_reset),
        .interrupt_ctl_ttu_if (interrupt_ctl_ttu_if),
        .simt_bus_if          (per_socket_csr_bus_if[0]),
        .scalar_bus_if        (per_socket_csr_bus_if[1]),
        .execute_hw_itr_if    (per_socket_execute_hw_itr_if)
    );


endmodule
