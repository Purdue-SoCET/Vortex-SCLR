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

module VX_dispatch import VX_gpu_pkg::*; #(
    parameter CORE_ID = 0,
    parameter THREAD_CNT = `NUM_THREADS
) (
    input wire              clk,
    input wire              reset,

`ifdef PERF_ENABLE
    output wire [`PERF_CTR_BITS-1:0] perf_stalls [`NUM_EX_UNITS],
`endif
    // inputs
    VX_operands_if.slave    operands_if [`ISSUE_WIDTH],

    // outputs
    VX_dispatch_if.master   alu_dispatch_if [`ISSUE_WIDTH],
    VX_dispatch_if.master   lsu_dispatch_if [`ISSUE_WIDTH],
`ifdef EXT_F_ENABLE
    VX_dispatch_if.master   fpu_dispatch_if [`ISSUE_WIDTH],
`endif
    VX_dispatch_if.master   sfu_dispatch_if [`ISSUE_WIDTH] 
);
    `UNUSED_PARAM (CORE_ID)

    localparam DATAW = `UUID_WIDTH + ISSUE_WIS_W + THREAD_CNT + `INST_OP_BITS + `INST_MOD_BITS + 1 + 1 + 1 + `XLEN + `XLEN + `NR_BITS + (3 * THREAD_CNT * `XLEN) + `NT_WIDTH;

    wire [`ISSUE_WIDTH-1:0][`NT_WIDTH-1:0] last_active_tid;

    wire [THREAD_CNT-1:0][`NT_WIDTH-1:0] tids;
    for (genvar i = 0; i < THREAD_CNT; ++i) begin                 
        assign tids[i] = `NT_WIDTH'(i);
    end

    for (genvar i = 0; i < `ISSUE_WIDTH; ++i) begin
        VX_find_first #(
            .N (THREAD_CNT),
            .DATAW (`NT_WIDTH),
            .REVERSE (1)
        ) last_tid_select (
            .valid_in (operands_if[i].data.tmask),
            .data_in  (tids),
            .data_out (last_active_tid[i]),
            `UNUSED_PIN (valid_out)
        );
    end
 
    // ALU dispatch    

    VX_operands_if#(.THREAD_CNT (THREAD_CNT)) alu_operands_if[`ISSUE_WIDTH]();
    
    for (genvar i = 0; i < `ISSUE_WIDTH; ++i) begin
        assign alu_operands_if[i].valid = operands_if[i].valid && (operands_if[i].data.ex_type == `EX_ALU);
        assign alu_operands_if[i].data = operands_if[i].data;

        `RESET_RELAY (alu_reset, reset);

        VX_elastic_buffer #(
            .DATAW   (DATAW),
            .SIZE    (2),
            .OUT_REG (2)
        ) alu_buffer (
            .clk        (clk),
            .reset      (alu_reset),
            .valid_in   (alu_operands_if[i].valid),
            .ready_in   (alu_operands_if[i].ready),
            .data_in    (`TO_DISPATCH_DATA(alu_operands_if[i].data, last_active_tid[i])),
            .data_out   (alu_dispatch_if[i].data),
            .valid_out  (alu_dispatch_if[i].valid),
            .ready_out  (alu_dispatch_if[i].ready)
        );
    end

    // LSU dispatch

    VX_operands_if#(.THREAD_CNT (THREAD_CNT)) lsu_operands_if[`ISSUE_WIDTH]();

    for (genvar i = 0; i < `ISSUE_WIDTH; ++i) begin
        assign lsu_operands_if[i].valid = operands_if[i].valid && (operands_if[i].data.ex_type == `EX_LSU);
        assign lsu_operands_if[i].data = operands_if[i].data;

        `RESET_RELAY (lsu_reset, reset);

        VX_elastic_buffer #(
            .DATAW   (DATAW),
            .SIZE    (2),
            .OUT_REG (2)
        ) lsu_buffer (
            .clk        (clk),
            .reset      (lsu_reset),
            .valid_in   (lsu_operands_if[i].valid),
            .ready_in   (lsu_operands_if[i].ready),
            .data_in    (`TO_DISPATCH_DATA(lsu_operands_if[i].data, last_active_tid[i])),           
            .data_out   (lsu_dispatch_if[i].data),
            .valid_out  (lsu_dispatch_if[i].valid),
            .ready_out  (lsu_dispatch_if[i].ready)
        );
    end

    // FPU dispatch

`ifdef EXT_F_ENABLE

    VX_operands_if#(.THREAD_CNT (THREAD_CNT)) fpu_operands_if[`ISSUE_WIDTH]();

    for (genvar i = 0; i < `ISSUE_WIDTH; ++i) begin
        assign fpu_operands_if[i].valid = operands_if[i].valid && (operands_if[i].data.ex_type == `EX_FPU);
        assign fpu_operands_if[i].data = operands_if[i].data;

        `RESET_RELAY (fpu_reset, reset);

        VX_elastic_buffer #(
            .DATAW   (DATAW),
            .SIZE    (2),
            .OUT_REG (2)
        ) fpu_buffer (
            .clk        (clk),
            .reset      (fpu_reset),
            .valid_in   (fpu_operands_if[i].valid),
            .ready_in   (fpu_operands_if[i].ready),
            .data_in    (`TO_DISPATCH_DATA(fpu_operands_if[i].data, last_active_tid[i])),           
            .data_out   (fpu_dispatch_if[i].data),
            .valid_out  (fpu_dispatch_if[i].valid),
            .ready_out  (fpu_dispatch_if[i].ready)
        );
    end
`endif

    // SFU dispatch

    VX_operands_if#(.THREAD_CNT (THREAD_CNT)) sfu_operands_if[`ISSUE_WIDTH]();

    for (genvar i = 0; i < `ISSUE_WIDTH; ++i) begin
        assign sfu_operands_if[i].valid = operands_if[i].valid && (operands_if[i].data.ex_type == `EX_SFU);
        assign sfu_operands_if[i].data = operands_if[i].data;

        `RESET_RELAY (sfu_reset, reset);

        VX_elastic_buffer #(
            .DATAW   (DATAW),
            .SIZE    (2),
            .OUT_REG (2)
        ) sfu_buffer (
            .clk        (clk),
            .reset      (sfu_reset),
            .valid_in   (sfu_operands_if[i].valid),
            .ready_in   (sfu_operands_if[i].ready),
            .data_in    (`TO_DISPATCH_DATA(sfu_operands_if[i].data, last_active_tid[i])),           
            .data_out   (sfu_dispatch_if[i].data),
            .valid_out  (sfu_dispatch_if[i].valid),
            .ready_out  (sfu_dispatch_if[i].ready)
        );
    end

    // can take next request?
    for (genvar i = 0; i < `ISSUE_WIDTH; ++i) begin
        assign operands_if[i].ready = (alu_operands_if[i].ready && (operands_if[i].data.ex_type == `EX_ALU)) 
                                   || (lsu_operands_if[i].ready && (operands_if[i].data.ex_type == `EX_LSU))
                                `ifdef EXT_F_ENABLE
                                   || (fpu_operands_if[i].ready && (operands_if[i].data.ex_type == `EX_FPU))
                                `endif
                                   || (sfu_operands_if[i].ready && (operands_if[i].data.ex_type == `EX_SFU));
    end

`ifdef PERF_ENABLE
    reg [`NUM_EX_UNITS-1:0][`PERF_CTR_BITS-1:0] perf_stalls_n, perf_stalls_r;
    wire [`ISSUE_WIDTH-1:0] operands_stall;
    wire [`ISSUE_WIDTH-1:0][`EX_BITS-1:0] operands_ex_type;

    for (genvar i=0; i < `ISSUE_WIDTH; ++i) begin
        assign operands_stall[i] = operands_if[i].valid && ~operands_if[i].ready;
        assign operands_ex_type[i] = operands_if[i].data.ex_type;
    end

    always @(*) begin
        perf_stalls_n = perf_stalls_r;
        for (integer i=0; i < `ISSUE_WIDTH; ++i) begin
            if (operands_stall[i]) begin
                perf_stalls_n[operands_ex_type[i]] += `PERF_CTR_BITS'(1);
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            perf_stalls_r <= '0;
        end else begin
            perf_stalls_r <= perf_stalls_n;
        end
    end
    
    for (genvar i=0; i < `NUM_EX_UNITS; ++i) begin
        assign perf_stalls[i] = perf_stalls_r[i];
    end
`endif

`ifdef DBG_TRACE_CORE_PIPELINE
    for (genvar i=0; i < `ISSUE_WIDTH; ++i) begin
        always @(posedge clk) begin
            if (operands_if[i].valid && operands_if[i].ready) begin
                `TRACE(1, ("%d: core%0d-issue: wid=%0d, PC=0x%0h, ex=", $time, CORE_ID, wis_to_wid(operands_if[i].data.wis, i), operands_if[i].data.PC));
                trace_ex_type(1, operands_if[i].data.ex_type);
                `TRACE(1, (", mod=%0d, tmask=%b, wb=%b, rd=%0d, rs1_data=", operands_if[i].data.op_mod, operands_if[i].data.tmask, operands_if[i].data.wb, operands_if[i].data.rd));
                `TRACE_ARRAY1D(1, operands_if[i].data.rs1_data, THREAD_CNT);
                `TRACE(1, (", rs2_data="));
                `TRACE_ARRAY1D(1, operands_if[i].data.rs2_data, THREAD_CNT);
                `TRACE(1, (", rs3_data="));
                `TRACE_ARRAY1D(1, operands_if[i].data.rs3_data, THREAD_CNT);
                `TRACE(1, (" (#%0d)\n", operands_if[i].data.uuid));
            end
        end
    end
`endif

endmodule
