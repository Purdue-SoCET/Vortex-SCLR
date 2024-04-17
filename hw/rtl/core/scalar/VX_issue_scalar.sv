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
`include "VX_trace.vh"

module VX_issue_scalar #(
    parameter CORE_ID = 0,
    parameter THREAD_CNT = `NUM_THREADS,
    parameter ISSUE_CNT = `ISSUE_WIDTH,
    parameter WARP_CNT = `NUM_WARPS,
    parameter WARP_CNT_WIDTH = `LOG2UP(WARP_CNT)
) (
    `SCOPE_IO_DECL

    input wire              clk,
    input wire              reset,

    input [`ISSUE_WIDTH-1:0]commit_if_valid,
    input [`ISSUE_WIDTH-1:0]commit_if_ready,
    input [`ISSUE_WIDTH-1:0]branch_mispredict_flush,

`ifdef PERF_ENABLE
    VX_pipeline_perf_if.issue perf_issue_if,
`endif

    VX_decode_scalar_if.slave      decode_if,
    VX_writeback_if.slave   writeback_if [ISSUE_CNT],

    VX_dispatch_if.master   alu_dispatch_if [ISSUE_CNT],
    VX_dispatch_if.master   lsu_dispatch_if [ISSUE_CNT],
`ifdef EXT_F_ENABLE
    VX_dispatch_if.master   fpu_dispatch_if [ISSUE_CNT],
`endif
    VX_dispatch_if.master   sfu_dispatch_if [ISSUE_CNT]
);
    VX_ibuffer_scalar_if#(.WARP_CNT(WARP_CNT), .ISSUE_CNT(ISSUE_CNT), .THREAD_CNT (THREAD_CNT))  ibuffer_if [ISSUE_CNT]();
    VX_ibuffer_scalar_if#(.WARP_CNT(WARP_CNT), .ISSUE_CNT(ISSUE_CNT), .THREAD_CNT (THREAD_CNT))  scoreboard_if [ISSUE_CNT]();
    VX_operands_scalar_if#(.WARP_CNT(WARP_CNT), .ISSUE_CNT(ISSUE_CNT), .THREAD_CNT (THREAD_CNT)) operands_if [ISSUE_CNT]();

    `RESET_RELAY (ibuf_reset, reset);
    `RESET_RELAY (scoreboard_reset, reset);
    `RESET_RELAY (operands_reset, reset);
    `RESET_RELAY (dispatch_reset, reset);

    VX_ibuffer_scalar #(
        .CORE_ID (CORE_ID),
        .THREAD_CNT(THREAD_CNT),
        .ISSUE_CNT(ISSUE_CNT),
        .WARP_CNT(WARP_CNT)
    ) ibuffer (
        .clk            (clk),
        .reset          (ibuf_reset), 
        .decode_if      (decode_if),
        .ibuffer_if     (ibuffer_if),
        .branch_mispredict_flush (branch_mispredict_flush)
    );

    VX_scoreboard_scalar #(
        .CORE_ID (CORE_ID),
        .THREAD_CNT(THREAD_CNT),
        .ISSUE_CNT(ISSUE_CNT),
        .WARP_CNT(WARP_CNT)
    ) scoreboard (
        .clk            (clk),
        .reset          (scoreboard_reset),
        .writeback_if   (writeback_if),
        .ibuffer_if     (ibuffer_if),
        .scoreboard_if  (scoreboard_if),
        .branch_mispredict_flush (branch_mispredict_flush)
    );

    VX_operands_scalar #(
        .CORE_ID (CORE_ID),
        .THREAD_CNT(THREAD_CNT),
        .ISSUE_CNT(ISSUE_CNT),
        .WARP_CNT(WARP_CNT)
    ) operands (
        .clk            (clk), 
        .reset          (operands_reset), 
        .branch_mispredict_flush (branch_mispredict_flush)
        .writeback_if   (writeback_if),
        .scoreboard_if  (scoreboard_if),
        .operands_if    (operands_if)
    );

    VX_dispatch_scalar #(
        .CORE_ID (CORE_ID),
        .THREAD_CNT(THREAD_CNT),
        .ISSUE_CNT(ISSUE_CNT),
        .WARP_CNT(WARP_CNT)
    ) dispatch (
        .clk            (clk), 
        .reset          (dispatch_reset),
        .branch_mispredict_flush (branch_mispredict_flush)
    `ifdef PERF_ENABLE
        .perf_stalls    (perf_issue_if.dsp_stalls),
    `endif
        .operands_if    (operands_if),
        .commit_if_valid(commit_if_valid),
        .commit_if_ready(commit_if_ready),
        .alu_dispatch_if(alu_dispatch_if),
        .lsu_dispatch_if(lsu_dispatch_if),
    `ifdef EXT_F_ENABLE
        .fpu_dispatch_if(fpu_dispatch_if),
    `endif
        .sfu_dispatch_if(sfu_dispatch_if)
    ); 

`ifdef DBG_SCOPE_ISSUE
    if (CORE_ID == 0) begin
    `ifdef SCOPE
        wire operands_if_fire = operands_if[0].valid && operands_if[0].ready;
        wire operands_if_not_ready = ~operands_if[0].ready;
        wire writeback_if_valid = writeback_if[0].valid;
        VX_scope_tap #(
            .SCOPE_ID (2),
            .TRIGGERW (4),
            .PROBEW   (`UUID_WIDTH + THREAD_CNT + `EX_BITS + `INST_OP_BITS + `INST_MOD_BITS +
                1 + `NR_BITS + `XLEN + 1 + 1 + (THREAD_CNT * 3 * `XLEN) +
                `UUID_WIDTH + THREAD_CNT + `NR_BITS + (THREAD_CNT*`XLEN) + 1)
        ) scope_tap (
            .clk(clk),
            .reset(scope_reset),
            .start(1'b0),
            .stop(1'b0),
            .triggers({
                reset, 
                operands_if_fire,
                operands_if_not_ready, 
                writeback_if_valid
            }),
            .probes({
                operands_if[0].data.uuid,
                operands_if[0].data.tmask,
                operands_if[0].data.ex_type,
                operands_if[0].data.op_type,
                operands_if[0].data.op_mod,
                operands_if[0].data.wb,
                operands_if[0].data.rd,
                operands_if[0].data.imm,
                operands_if[0].data.use_PC,
                operands_if[0].data.use_imm,
                operands_if[0].data.rs1_data,
                operands_if[0].data.rs2_data,
                operands_if[0].data.rs3_data,
                writeback_if[0].data.uuid,
                writeback_if[0].data.tmask,
                writeback_if[0].data.rd,
                writeback_if[0].data.data,
                writeback_if[0].data.eop
            }),
            .bus_in(scope_bus_in),
            .bus_out(scope_bus_out)
        );
    `endif        
    `ifdef CHIPSCOPE
        ila_issue ila_issue_inst (
            .clk    (clk),
            .probe0 ({operands_if.uuid, ibuffer.rs3, ibuffer.rs2, ibuffer.rs1, operands_if.PC, operands_if.tmask, operands_if.wid, operands_if.ex_type, operands_if.op_type, operands_if.ready, operands_if.valid}),
            .probe1 ({writeback_if.uuid, writeback_if.data[0], writeback_if.PC, writeback_if.tmask, writeback_if.wid, writeback_if.eop, writeback_if.valid})
        );
    `endif
    end
`else
    `SCOPE_IO_UNUSED()
`endif

`ifdef PERF_ENABLE
    reg [`PERF_CTR_BITS-1:0] perf_ibf_stalls;
    reg [`PERF_CTR_BITS-1:0] perf_scb_stalls;

    wire [`LOG2UP(ISSUE_CNT+1)-1:0] scoreboard_stalls_per_cycle;
    reg [ISSUE_CNT-1:0] scoreboard_stalls;
    for (genvar i=0; i < ISSUE_CNT; ++i) begin
        assign scoreboard_stalls[i] = ibuffer_if[i].valid && ~ibuffer_if[i].ready;
    end
    `POP_COUNT(scoreboard_stalls_per_cycle, scoreboard_stalls);

    always @(posedge clk) begin
        if (reset) begin
            perf_ibf_stalls <= '0;
            perf_scb_stalls <= '0;
        end else begin
            if (decode_if.valid && ~decode_if.ready) begin
                perf_ibf_stalls <= perf_ibf_stalls + `PERF_CTR_BITS'(1);
            end
            perf_scb_stalls <= perf_scb_stalls + `PERF_CTR_BITS'(scoreboard_stalls_per_cycle);
        end
    end

    assign perf_issue_if.ibf_stalls = perf_ibf_stalls;
    assign perf_issue_if.scb_stalls = perf_scb_stalls;
`endif

endmodule
