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

module VX_socket import VX_gpu_pkg::*; #( 
    parameter SOCKET_ID = 0
) (        
    `SCOPE_IO_DECL
    
    // Clock
    input wire              clk,
    input wire              reset,

`ifdef PERF_ENABLE
    VX_mem_perf_if.slave    mem_perf_if,
`endif

    VX_dcr_bus_if.slave     dcr_bus_if,

    VX_mem_bus_if.master    dcache_bus_if [DCACHE_NUM_REQS],

    VX_mem_bus_if.master    icache_bus_if,

`ifdef EXT_TEX_ENABLE
`ifdef PERF_ENABLE
    VX_tex_perf_if.slave    perf_tex_if,
    VX_cache_perf_if.slave  perf_tcache_if,
`endif
    VX_tex_bus_if.master    tex_bus_if,
`endif

`ifdef EXT_RASTER_ENABLE
`ifdef PERF_ENABLE
    VX_raster_perf_if.slave perf_raster_if,
    VX_cache_perf_if.slave  perf_rcache_if,
`endif
    VX_raster_bus_if.slave  raster_bus_if,
`endif

`ifdef EXT_ROP_ENABLE
`ifdef PERF_ENABLE
    VX_rop_perf_if.slave    perf_rop_if,
    VX_cache_perf_if.slave  perf_ocache_if,
`endif
    VX_rop_bus_if.master    rop_bus_if,
`endif

`ifdef GBAR_ENABLE
    VX_gbar_bus_if.master   gbar_bus_if,
`endif

    // simulation helper signals
    output wire             sim_ebreak,
    output wire [`NUM_REGS-1:0][`XLEN-1:0] sim_wb_value,

    // Status
    output wire             busy
);

`ifdef GBAR_ENABLE
    VX_gbar_bus_if per_core_gbar_bus_if[`SOCKET_SIZE]();

    `RESET_RELAY (gbar_arb_reset, reset);

    VX_gbar_arb #(
        .NUM_REQS (`SOCKET_SIZE),
        .OUT_REG  ((`SOCKET_SIZE > 1) ? 2 : 0)
    ) gbar_arb (
        .clk        (clk),
        .reset      (gbar_arb_reset),
        .bus_in_if  (per_core_gbar_bus_if),
        .bus_out_if (gbar_bus_if)
    );
`endif

`ifdef EXT_RASTER_ENABLE

    VX_raster_bus_if #(
        .NUM_LANES (`NUM_SFU_LANES)
    ) per_core_raster_bus_if[`SOCKET_SIZE](), raster_bus_tmp_if[1]();

    `RESET_RELAY (raster_arb_reset, reset);

    VX_raster_arb #(
        .NUM_INPUTS  (1),
        .NUM_LANES   (`NUM_SFU_LANES),
        .NUM_OUTPUTS (`SOCKET_SIZE),
        .ARBITER     ("R"),
        .OUT_REG     ((`SOCKET_SIZE > 1) ? 2 : 0)
    ) raster_arb (
        .clk        (clk),
        .reset      (raster_arb_reset),
        .bus_in_if  (raster_bus_tmp_if),
        .bus_out_if (per_core_raster_bus_if)
    );

    `ASSIGN_VX_RASTER_BUS_IF (raster_bus_tmp_if[0], raster_bus_if);

`endif

`ifdef EXT_ROP_ENABLE

    VX_rop_bus_if #(
        .NUM_LANES (`NUM_SFU_LANES)
    ) per_core_rop_bus_if[`SOCKET_SIZE](), rop_bus_tmp_if[1]();

    `RESET_RELAY (rop_arb_reset, reset);

    VX_rop_arb #(
        .NUM_INPUTS  (`SOCKET_SIZE),
        .NUM_OUTPUTS (1),
        .NUM_LANES   (`NUM_SFU_LANES),        
        .ARBITER     ("R"),
        .OUT_REG     ((`SOCKET_SIZE > 1) ? 2 : 0)
    ) rop_arb (
        .clk        (clk),
        .reset      (rop_arb_reset),
        .bus_in_if  (per_core_rop_bus_if),
        .bus_out_if (rop_bus_tmp_if)
    );

    `ASSIGN_VX_ROP_BUS_IF (rop_bus_if, rop_bus_tmp_if[0]);

`endif

`ifdef EXT_TEX_ENABLE

    VX_tex_bus_if #(
        .NUM_LANES (`NUM_SFU_LANES),
        .TAG_WIDTH (`TEX_REQ_TAG_WIDTH)
    ) per_core_tex_bus_if[`SOCKET_SIZE]();

    VX_tex_bus_if #(
        .NUM_LANES (`NUM_SFU_LANES),
        .TAG_WIDTH (`TEX_REQ_ARB1_TAG_WIDTH)
    ) tex_bus_tmp_if[1]();

    `RESET_RELAY (tex_arb_reset, reset);

    VX_tex_arb #(
        .NUM_INPUTS   (`SOCKET_SIZE),        
        .NUM_OUTPUTS  (1),
        .NUM_LANES    (`NUM_SFU_LANES),
        .TAG_WIDTH    (`TEX_REQ_TAG_WIDTH),
        .ARBITER      ("R"),
        .OUT_REG_REQ ((`SOCKET_SIZE > 1) ? 2 : 0)
    ) tex_arb (
        .clk        (clk),
        .reset      (tex_arb_reset),
        .bus_in_if  (per_core_tex_bus_if),
        .bus_out_if (tex_bus_tmp_if)
    );

    `ASSIGN_VX_TEX_BUS_IF (tex_bus_if, tex_bus_tmp_if[0]);
            
`endif

    ///////////////////////////////////////////////////////////////////////////
    // They are wittling down 4 cores' requests to 1 outgoing request
    VX_mem_bus_if #(
        .DATA_SIZE (DCACHE_WORD_SIZE), 
        .TAG_WIDTH (DCACHE_NOSM_TAG_WIDTH)
    ) per_core_dcache_bus_if[`SOCKET_SIZE * DCACHE_NUM_REQS]();

    `RESET_RELAY (dcache_arb_reset, reset);

    for (genvar i = 0; i < DCACHE_NUM_REQS; ++i) begin
        VX_mem_bus_if #(
            .DATA_SIZE (DCACHE_WORD_SIZE),
            .TAG_WIDTH (DCACHE_ARB_TAG_WIDTH)
        ) dcache_bus_tmp_if[1]();

        VX_mem_bus_if #(
            .DATA_SIZE (DCACHE_WORD_SIZE),
            .TAG_WIDTH (DCACHE_NOSM_TAG_WIDTH)
        ) per_core_dcache_bus_tmp_if[`SOCKET_SIZE]();

        for (genvar j = 0; j < `SOCKET_SIZE; ++j) begin
            `ASSIGN_VX_MEM_BUS_IF (per_core_dcache_bus_tmp_if[j], per_core_dcache_bus_if[j * DCACHE_NUM_REQS + i]);
        end

        VX_mem_arb #(
            .NUM_INPUTS   (`SOCKET_SIZE),
            .DATA_SIZE    (DCACHE_WORD_SIZE),
            .TAG_WIDTH    (DCACHE_NOSM_TAG_WIDTH),
            .TAG_SEL_IDX  (`CACHE_ADDR_TYPE_BITS),
            .ARBITER      ("R"),
            .OUT_REG_REQ  ((`SOCKET_SIZE > 1) ? 2 : 0),
            .OUT_REG_RSP  ((`SOCKET_SIZE > 1) ? 2 : 0)
        ) dcache_arb (
            .clk        (clk),
            .reset      (dcache_arb_reset),
            .bus_in_if  (per_core_dcache_bus_tmp_if),
            .bus_out_if (dcache_bus_tmp_if)
        );
    
        `ASSIGN_VX_MEM_BUS_IF (dcache_bus_if[i], dcache_bus_tmp_if[0]);
    end

    ///////////////////////////////////////////////////////////////////////////
    
    VX_mem_bus_if #(
        .DATA_SIZE (ICACHE_WORD_SIZE), 
        .TAG_WIDTH (ICACHE_TAG_WIDTH)
    ) per_core_icache_bus_if[`SOCKET_SIZE]();

    VX_mem_bus_if #(
        .DATA_SIZE (ICACHE_WORD_SIZE),
        .TAG_WIDTH (ICACHE_ARB_TAG_WIDTH)
    ) icache_bus_tmp_if[1]();

    `RESET_RELAY (icache_arb_reset, reset);

    VX_mem_arb #(
        .NUM_INPUTS   (`SOCKET_SIZE),
        .NUM_OUTPUTS  (1),
        .DATA_SIZE    (ICACHE_WORD_SIZE),
        .TAG_WIDTH    (ICACHE_TAG_WIDTH),
        .TAG_SEL_IDX  (0),
        .ARBITER      ("R"),
        .OUT_REG_REQ  ((`SOCKET_SIZE > 1) ? 2 : 0),
        .OUT_REG_RSP  ((`SOCKET_SIZE > 1) ? 2 : 0)
    ) icache_arb (
        .clk        (clk),
        .reset      (icache_arb_reset),
        .bus_in_if  (per_core_icache_bus_if),
        .bus_out_if (icache_bus_tmp_if)
    );

    `ASSIGN_VX_MEM_BUS_IF (icache_bus_if, icache_bus_tmp_if[0]);

    ///////////////////////////////////////////////////////////////////////////

    wire [`SOCKET_SIZE-1:0] per_core_sim_ebreak;
    wire [`SOCKET_SIZE-1:0][`NUM_REGS-1:0][`XLEN-1:0] per_core_sim_wb_value;
    assign sim_ebreak = per_core_sim_ebreak[0];
    assign sim_wb_value = per_core_sim_wb_value[0];
    `UNUSED_VAR (per_core_sim_ebreak)
    `UNUSED_VAR (per_core_sim_wb_value)

    wire [`SOCKET_SIZE-1:0] per_core_busy;

    `BUFFER_DCR_BUS_IF (core_dcr_bus_if, dcr_bus_if, (`SOCKET_SIZE > 1));
    localparam NUM_VEC_CORES = `UP(`NUM_CORES/2);
    
    `SCOPE_IO_SWITCH (`SOCKET_SIZE)
    
    // Generate all cores
    for (genvar i = 0; i < `SOCKET_SIZE; ++i) begin

        `RESET_RELAY (core_reset, reset);
        if(((SOCKET_ID * `SOCKET_SIZE) + i)>=NUM_VEC_CORES) begin : scalar_core_gen
            VX_core #(
                .CORE_ID ((SOCKET_ID * `SOCKET_SIZE) + i),
                .THREAD_CNT(1),
                .WARP_CNT(1),
                .ISSUE_CNT(1)
            ) core (
                `SCOPE_IO_BIND  (i)

                .clk            (clk),
                .reset          (core_reset),

            `ifdef PERF_ENABLE
                .mem_perf_if    (mem_perf_if),
            `endif
                
                .dcr_bus_if     (core_dcr_bus_if),

                .dcache_bus_if  (per_core_dcache_bus_if[i * DCACHE_NUM_REQS +: DCACHE_NUM_REQS]),

                .icache_bus_if  (per_core_icache_bus_if[i]),

            `ifdef EXT_TEX_ENABLE
            `ifdef PERF_ENABLE
                .perf_tex_if    (perf_tex_if),
                .perf_tcache_if (perf_tcache_if),
            `endif
                .tex_bus_if     (per_core_tex_bus_if[i]),
            `endif

            `ifdef EXT_RASTER_ENABLE
            `ifdef PERF_ENABLE
                .perf_raster_if (perf_raster_if),
                .perf_rcache_if (perf_rcache_if),
            `endif
                .raster_bus_if  (per_core_raster_bus_if[i]),
            `endif
            
            `ifdef EXT_ROP_ENABLE
            `ifdef PERF_ENABLE
                .perf_rop_if    (perf_rop_if),
                .perf_ocache_if (perf_ocache_if),
            `endif
                .rop_bus_if     (per_core_rop_bus_if[i]),
            `endif

            `ifdef GBAR_ENABLE
                .gbar_bus_if    (per_core_gbar_bus_if[i]),
            `endif

                .sim_ebreak     (per_core_sim_ebreak[i]),
                .sim_wb_value   (per_core_sim_wb_value[i]),
                .busy           (per_core_busy[i])
            );
        end else begin : simt_core_gen
        VX_core #(
            .CORE_ID ((SOCKET_ID * `SOCKET_SIZE) + i),
            .THREAD_CNT(`NUM_THREADS)
        ) core (
            `SCOPE_IO_BIND  (i)

            .clk            (clk),
            .reset          (core_reset),

        `ifdef PERF_ENABLE
            .mem_perf_if    (mem_perf_if),
        `endif
            
            .dcr_bus_if     (core_dcr_bus_if),

            .dcache_bus_if  (per_core_dcache_bus_if[i * DCACHE_NUM_REQS +: DCACHE_NUM_REQS]),

            .icache_bus_if  (per_core_icache_bus_if[i]),

        `ifdef EXT_TEX_ENABLE
        `ifdef PERF_ENABLE
            .perf_tex_if    (perf_tex_if),
            .perf_tcache_if (perf_tcache_if),
        `endif
            .tex_bus_if     (per_core_tex_bus_if[i]),
        `endif

        `ifdef EXT_RASTER_ENABLE
        `ifdef PERF_ENABLE
            .perf_raster_if (perf_raster_if),
            .perf_rcache_if (perf_rcache_if),
        `endif
            .raster_bus_if  (per_core_raster_bus_if[i]),
        `endif
        
        `ifdef EXT_ROP_ENABLE
        `ifdef PERF_ENABLE
            .perf_rop_if    (perf_rop_if),
            .perf_ocache_if (perf_ocache_if),
        `endif
            .rop_bus_if     (per_core_rop_bus_if[i]),
        `endif

        `ifdef GBAR_ENABLE
            .gbar_bus_if    (per_core_gbar_bus_if[i]),
        `endif

            .sim_ebreak     (per_core_sim_ebreak[i]),
            .sim_wb_value   (per_core_sim_wb_value[i]),
            .busy           (per_core_busy[i])
        );
        end
    end

    // for (genvar i = 0; i < `SOCKET_SIZE; ++i) begin

    //     `RESET_RELAY (core_reset, reset);
        
    //     VX_core #(
    //         .CORE_ID ((SOCKET_ID * `SOCKET_SIZE) + i),
    //         .THREAD_CNT(`NUM_THREADS)
    //     ) core (
    //         `SCOPE_IO_BIND  (i)

    //         .clk            (clk),
    //         .reset          (core_reset),

    //     `ifdef PERF_ENABLE
    //         .mem_perf_if    (mem_perf_if),
    //     `endif
            
    //         .dcr_bus_if     (core_dcr_bus_if),

    //         .dcache_bus_if  (per_core_dcache_bus_if[i * DCACHE_NUM_REQS +: DCACHE_NUM_REQS]),

    //         .icache_bus_if  (per_core_icache_bus_if[i]),

    //     `ifdef EXT_TEX_ENABLE
    //     `ifdef PERF_ENABLE
    //         .perf_tex_if    (perf_tex_if),
    //         .perf_tcache_if (perf_tcache_if),
    //     `endif
    //         .tex_bus_if     (per_core_tex_bus_if[i]),
    //     `endif

    //     `ifdef EXT_RASTER_ENABLE
    //     `ifdef PERF_ENABLE
    //         .perf_raster_if (perf_raster_if),
    //         .perf_rcache_if (perf_rcache_if),
    //     `endif
    //         .raster_bus_if  (per_core_raster_bus_if[i]),
    //     `endif
        
    //     `ifdef EXT_ROP_ENABLE
    //     `ifdef PERF_ENABLE
    //         .perf_rop_if    (perf_rop_if),
    //         .perf_ocache_if (perf_ocache_if),
    //     `endif
    //         .rop_bus_if     (per_core_rop_bus_if[i]),
    //     `endif

    //     `ifdef GBAR_ENABLE
    //         .gbar_bus_if    (per_core_gbar_bus_if[i]),
    //     `endif

    //         .sim_ebreak     (per_core_sim_ebreak[i]),
    //         .sim_wb_value   (per_core_sim_wb_value[i]),
    //         .busy           (per_core_busy[i])
    //     );
    //     end

    `BUFFER_BUSY (busy, (| per_core_busy), (`SOCKET_SIZE > 1));
    
endmodule
