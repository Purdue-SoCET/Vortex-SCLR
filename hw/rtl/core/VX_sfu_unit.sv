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

module VX_sfu_unit import VX_gpu_pkg::*; #(
    parameter CORE_ID = 0,
    parameter THREAD_CNT = `NUM_THREADS
) (    
    input wire              clk,
    input wire              reset,

`ifdef PERF_ENABLE
    VX_mem_perf_if.slave    mem_perf_if,
    VX_pipeline_perf_if.slave pipeline_perf_if,
`endif

    input base_dcrs_t       base_dcrs,

    // Inputs
    VX_dispatch_if.slave    dispatch_if [`ISSUE_WIDTH],
    
`ifdef EXT_F_ENABLE
    VX_fpu_to_csr_if.slave  fpu_to_csr_if [`NUM_FPU_BLOCKS],
`endif

`ifdef EXT_TEX_ENABLE
    VX_tex_bus_if.master    tex_bus_if,
`ifdef PERF_ENABLE
    VX_tex_perf_if.slave    perf_tex_if,
    VX_cache_perf_if.slave  perf_tcache_if,
`endif
`endif

`ifdef EXT_RASTER_ENABLE
    VX_raster_bus_if.slave  raster_bus_if,
`ifdef PERF_ENABLE
    VX_raster_perf_if.slave perf_raster_if,
    VX_cache_perf_if.slave  perf_rcache_if,
`endif
`endif

`ifdef EXT_ROP_ENABLE
    VX_rop_bus_if.master    rop_bus_if,
`ifdef PERF_ENABLE
    VX_rop_perf_if.slave    perf_rop_if,
    VX_cache_perf_if.slave  perf_ocache_if,
`endif
`endif

    // Outputs
    VX_commit_if.master     commit_if [`ISSUE_WIDTH],
    VX_commit_csr_if.slave  commit_csr_if,
    VX_sched_csr_if.slave   sched_csr_if,
    VX_warp_ctl_if.master   warp_ctl_if    
);
    `UNUSED_PARAM (CORE_ID)
    localparam BLOCK_SIZE   = 1;
    localparam NUM_LANES    = `MIN(`NUM_SFU_LANES,THREAD_CNT);
    localparam PID_BITS     = `CLOG2(THREAD_CNT / NUM_LANES);
    localparam PID_WIDTH    = `UP(PID_BITS);

    localparam RSP_ARB_DATAW = `UUID_WIDTH + `NW_WIDTH + NUM_LANES + (NUM_LANES * `XLEN) + `NR_BITS + 1 + `XLEN + PID_WIDTH + 1 + 1;
    localparam RSP_ARB_SIZE = 1 + 1 + `EXT_TEX_ENABLED + `EXT_RASTER_ENABLED + `EXT_ROP_ENABLED;
    localparam RSP_ARB_IDX_WCTL = 0;
    localparam RSP_ARB_IDX_CSR = 1;
    localparam RSP_ARB_IDX_RASTER = RSP_ARB_IDX_CSR + 1;
    localparam RSP_ARB_IDX_ROP = RSP_ARB_IDX_RASTER + `EXT_RASTER_ENABLED;    
    localparam RSP_ARB_IDX_TEX = RSP_ARB_IDX_ROP + `EXT_ROP_ENABLED;
    `UNUSED_PARAM (RSP_ARB_IDX_RASTER)
    `UNUSED_PARAM (RSP_ARB_IDX_ROP)
    `UNUSED_PARAM (RSP_ARB_IDX_TEX)

    VX_execute_if #(
        .THREAD_CNT(THREAD_CNT),
        .NUM_LANES (NUM_LANES)
    ) execute_if[BLOCK_SIZE]();

    `RESET_RELAY (dispatch_reset, reset);

    VX_dispatch_unit #(
        .BLOCK_SIZE (BLOCK_SIZE),
        .NUM_LANES  (NUM_LANES),
        .OUT_REG    (1),
        .THREAD_CNT(THREAD_CNT)
    ) dispatch_unit (
        .clk        (clk),
        .reset      (dispatch_reset),
        .dispatch_if(dispatch_if),
        .execute_if (execute_if)
    );

    wire [RSP_ARB_SIZE-1:0] rsp_arb_valid_in;
    wire [RSP_ARB_SIZE-1:0] rsp_arb_ready_in;
    wire [RSP_ARB_SIZE-1:0][RSP_ARB_DATAW-1:0] rsp_arb_data_in;
    
`ifdef PERF_ENABLE
    VX_sfu_perf_if sfu_perf_if();
`endif

`ifdef EXT_TEX_ENABLE
    VX_sfu_csr_if  #(.THREAD_CNT(THREAD_CNT)) tex_csr_if();
`endif

`ifdef EXT_RASTER_ENABLE
    VX_sfu_csr_if  #(.THREAD_CNT(THREAD_CNT)) raster_csr_if();
`endif

`ifdef EXT_ROP_ENABLE
    VX_sfu_csr_if #(.THREAD_CNT(THREAD_CNT)) rop_csr_if();
`endif

    // Warp control block    
    VX_execute_if #(
        .THREAD_CNT(THREAD_CNT),
        .NUM_LANES (NUM_LANES)
    ) wctl_execute_if();
    VX_commit_if#(
        .THREAD_CNT(THREAD_CNT),
        .NUM_LANES (NUM_LANES)
    ) wctl_commit_if();
    
    assign wctl_execute_if.valid = execute_if[0].valid && `INST_SFU_IS_WCTL(execute_if[0].data.op_type);
    assign wctl_execute_if.data = execute_if[0].data;

    `RESET_RELAY (wctl_reset, reset);
    
    VX_wctl_unit #(
        .CORE_ID   (CORE_ID),
        .THREAD_CNT(THREAD_CNT),
        .NUM_LANES (NUM_LANES)
    ) wctl_unit (
        .clk        (clk),
        .reset      (wctl_reset),
        .execute_if (wctl_execute_if), 
        .warp_ctl_if(warp_ctl_if), 
        .commit_if  (wctl_commit_if)
    );

    assign rsp_arb_valid_in[RSP_ARB_IDX_WCTL] = wctl_commit_if.valid;
    assign rsp_arb_data_in[RSP_ARB_IDX_WCTL] = wctl_commit_if.data;
    assign wctl_commit_if.ready = rsp_arb_ready_in[RSP_ARB_IDX_WCTL];

    // CSR unit
    VX_execute_if #(
        .THREAD_CNT(THREAD_CNT),
        .NUM_LANES (NUM_LANES)
    ) csr_execute_if();
    VX_commit_if #(
        .THREAD_CNT(THREAD_CNT),
        .NUM_LANES (NUM_LANES)
    ) csr_commit_if();

    assign csr_execute_if.valid = execute_if[0].valid && `INST_SFU_IS_CSR(execute_if[0].data.op_type);
    assign csr_execute_if.data = execute_if[0].data;

    `RESET_RELAY (csr_reset, reset);

    VX_csr_unit #(
        .CORE_ID   (CORE_ID),
        .NUM_LANES (NUM_LANES),
        .THREAD_CNT(THREAD_CNT)
    ) csr_unit (
        .clk            (clk),
        .reset          (csr_reset),

        .base_dcrs      (base_dcrs),
        .execute_if     (csr_execute_if),
    
    `ifdef PERF_ENABLE
        .mem_perf_if    (mem_perf_if),
        .pipeline_perf_if(pipeline_perf_if),
        .sfu_perf_if    (sfu_perf_if),
    `endif
   
    `ifdef EXT_F_ENABLE  
        .fpu_to_csr_if  (fpu_to_csr_if),
    `endif        
    
    `ifdef EXT_TEX_ENABLE        
        .tex_csr_if     (tex_csr_if),
    `ifdef PERF_ENABLE
        .perf_tex_if    (perf_tex_if),
        .perf_tcache_if (perf_tcache_if),
    `endif
    `endif
    
    `ifdef EXT_RASTER_ENABLE        
        .raster_csr_if  (raster_csr_if),
    `ifdef PERF_ENABLE
        .perf_raster_if (perf_raster_if),
        .perf_rcache_if (perf_rcache_if),
    `endif
    `endif

    `ifdef EXT_ROP_ENABLE        
        .rop_csr_if     (rop_csr_if),
    `ifdef PERF_ENABLE
        .perf_rop_if    (perf_rop_if),
        .perf_ocache_if (perf_ocache_if),
    `endif
    `endif

        .sched_csr_if   (sched_csr_if),
        .commit_csr_if  (commit_csr_if),
        .commit_if      (csr_commit_if)
    );    

    assign rsp_arb_valid_in[RSP_ARB_IDX_CSR] = csr_commit_if.valid;
    assign rsp_arb_data_in[RSP_ARB_IDX_CSR] = csr_commit_if.data;
    assign csr_commit_if.ready = rsp_arb_ready_in[RSP_ARB_IDX_CSR];
    
`ifdef EXT_TEX_ENABLE

    VX_execute_if #(
        .THREAD_CNT(THREAD_CNT),
        .NUM_LANES (NUM_LANES)
    ) tex_execute_if();
    VX_commit_if #(
        .THREAD_CNT(THREAD_CNT),
        .NUM_LANES (NUM_LANES)
    ) tex_commit_if();

    assign tex_execute_if.valid = execute_if[0].valid && (execute_if[0].data.op_type == `INST_SFU_TEX);
    assign tex_execute_if.data = execute_if[0].data;

    `RESET_RELAY (tex_reset, reset);

    VX_tex_agent #(
        .CORE_ID   (CORE_ID),
        .NUM_LANES (NUM_LANES)
    ) tex_agent (
        .clk        (clk),
        .reset      (tex_reset),
        .execute_if (tex_execute_if),
        .tex_csr_if (tex_csr_if),
        .tex_bus_if (tex_bus_if),
        .commit_if  (tex_commit_if)        
    );     

    assign rsp_arb_valid_in[RSP_ARB_IDX_TEX] = tex_commit_if.valid;
    assign rsp_arb_data_in[RSP_ARB_IDX_TEX] = tex_commit_if.data;
    assign tex_commit_if.ready = rsp_arb_ready_in[RSP_ARB_IDX_TEX];

`endif

`ifdef EXT_RASTER_ENABLE
    
    VX_execute_if #(
        .THREAD_CNT(THREAD_CNT),
        .NUM_LANES (NUM_LANES)
    ) raster_execute_if();
    VX_commit_if #(
        .THREAD_CNT(THREAD_CNT),
        .NUM_LANES (NUM_LANES)
    ) raster_commit_if();

    assign raster_execute_if.valid = execute_if[0].valid && (execute_if[0].data.op_type == `INST_SFU_RASTER);
    assign raster_execute_if.data = execute_if[0].data;

    `RESET_RELAY (raster_reset, reset);

    VX_raster_agent #(
        .CORE_ID   (CORE_ID),
        .NUM_LANES (NUM_LANES),
        .THREAD_CNT(THREAD_CNT)
    ) raster_agent (
        .clk        (clk),
        .reset      (raster_reset),
        .execute_if (raster_execute_if),
        .raster_csr_if(raster_csr_if),
        .raster_bus_if(raster_bus_if), 
        .commit_if  (raster_commit_if)       
    );

    assign rsp_arb_valid_in[RSP_ARB_IDX_RASTER] = raster_commit_if.valid;
    assign rsp_arb_data_in[RSP_ARB_IDX_RASTER] = raster_commit_if.data;
    assign raster_commit_if.ready = rsp_arb_ready_in[RSP_ARB_IDX_RASTER];

`endif

`ifdef EXT_ROP_ENABLE
    
    VX_execute_if #(
        .THREAD_CNT(THREAD_CNT),
        .NUM_LANES (NUM_LANES)
    ) rop_execute_if();
    VX_commit_if #(
        .THREAD_CNT(THREAD_CNT),
        .NUM_LANES (NUM_LANES)
    ) rop_commit_if();

    assign rop_execute_if.valid = execute_if[0].valid && (execute_if[0].data.op_type == `INST_SFU_ROP);
    assign rop_execute_if.data = execute_if[0].data;

    `RESET_RELAY (rop_reset, reset);
            
    VX_rop_agent #(
        .CORE_ID   (CORE_ID),
        .NUM_LANES (NUM_LANES),
        .THREAD_CNT(THREAD_CNT)
    ) rop_agent (
        .clk        (clk),
        .reset      (rop_reset),
        .execute_if (rop_execute_if),
        .rop_csr_if (rop_csr_if),
        .rop_bus_if (rop_bus_if),
        .commit_if  (rop_commit_if)
    );

    assign rsp_arb_valid_in[RSP_ARB_IDX_ROP] = rop_commit_if.valid;
    assign rsp_arb_data_in[RSP_ARB_IDX_ROP] = rop_commit_if.data;
    assign rop_commit_if.ready = rsp_arb_ready_in[RSP_ARB_IDX_ROP];

`endif

    // can accept new request?

    reg sfu_req_ready;
    always @(*) begin
        case (execute_if[0].data.op_type)
         `INST_SFU_CSRRW,
         `INST_SFU_CSRRS,
         `INST_SFU_CSRRC: sfu_req_ready = csr_execute_if.ready;
    `ifdef EXT_TEX_ENABLE
        `INST_SFU_TEX: sfu_req_ready = tex_execute_if.ready;
    `endif
    `ifdef EXT_RASTER_ENABLE
        `INST_SFU_RASTER: sfu_req_ready = raster_execute_if.ready;
    `endif
    `ifdef EXT_ROP_ENABLE
        `INST_SFU_ROP: sfu_req_ready = rop_execute_if.ready;
    `endif
        default: sfu_req_ready = wctl_execute_if.ready;
        endcase
    end   
    assign execute_if[0].ready = sfu_req_ready;

    // response arbitration
    
    `RESET_RELAY (commit_reset, reset);

    VX_commit_if #(
        .THREAD_CNT(THREAD_CNT),
        .NUM_LANES (NUM_LANES)
    ) arb_commit_if[BLOCK_SIZE]();

    VX_stream_arb #(
        .NUM_INPUTS (RSP_ARB_SIZE),
        .DATAW      (RSP_ARB_DATAW),
        .ARBITER    ("R"),
        .OUT_REG    (1)
    ) rsp_arb (
        .clk       (clk),
        .reset     (commit_reset), 
        .valid_in  (rsp_arb_valid_in),
        .ready_in  (rsp_arb_ready_in),
        .data_in   (rsp_arb_data_in),
        .data_out  (arb_commit_if[0].data),
        .valid_out (arb_commit_if[0].valid),
        .ready_out (arb_commit_if[0].ready),
        `UNUSED_PIN (sel_out)
    );

    VX_gather_unit #(
        .BLOCK_SIZE (BLOCK_SIZE),
        .NUM_LANES  (NUM_LANES),
        .OUT_REG    (3),
        .THREAD_CNT(THREAD_CNT)
    ) gather_unit (
        .clk           (clk),
        .reset         (commit_reset),
        .commit_in_if  (arb_commit_if),
        .commit_out_if (commit_if)
    );

`ifdef PERF_ENABLE
`ifdef EXT_TEX_ENABLE
    reg [`PERF_CTR_BITS-1:0] perf_tex_stalls;
    always @(posedge clk) begin
        if (reset) begin
            perf_tex_stalls <= '0;
        end else begin
            perf_tex_stalls <= perf_tex_stalls + `PERF_CTR_BITS'(tex_execute_if.valid && ~tex_execute_if.ready);
        end
    end
    assign sfu_perf_if.tex_stalls = perf_tex_stalls;
`endif
`ifdef EXT_RASTER_ENABLE
    reg [`PERF_CTR_BITS-1:0] perf_raster_stalls;
    always @(posedge clk) begin
        if (reset) begin
            perf_raster_stalls <= '0;
        end else begin
            perf_raster_stalls <= perf_raster_stalls + `PERF_CTR_BITS'(raster_execute_if.valid && ~raster_execute_if.ready);
        end
    end
    assign sfu_perf_if.raster_stalls = perf_raster_stalls;
`endif
`ifdef EXT_ROP_ENABLE
    reg [`PERF_CTR_BITS-1:0] perf_rop_stalls;
    always @(posedge clk) begin
        if (reset) begin
            perf_rop_stalls <= '0;
        end else begin
            perf_rop_stalls <= perf_rop_stalls + `PERF_CTR_BITS'(rop_execute_if.valid && ~rop_execute_if.ready);
        end
    end
    assign sfu_perf_if.rop_stalls = perf_rop_stalls;
`endif
    reg [`PERF_CTR_BITS-1:0] perf_wctl_stalls;
    always @(posedge clk) begin
        if (reset) begin
            perf_wctl_stalls <= '0;
        end else begin
            perf_wctl_stalls <= perf_wctl_stalls + `PERF_CTR_BITS'(wctl_execute_if.valid && ~wctl_execute_if.ready);
        end
    end
    assign sfu_perf_if.wctl_stalls = perf_wctl_stalls;
`endif

endmodule
