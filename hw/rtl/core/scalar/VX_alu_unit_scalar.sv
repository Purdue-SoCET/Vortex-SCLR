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

module VX_alu_unit_scalar #(
    parameter CORE_ID = 0,
    parameter THREAD_CNT = `NUM_THREADS,
    parameter WARP_CNT = `NUM_WARPS,
    parameter ISSUE_CNT = `MIN(WARP_CNT, 4),
    parameter WARP_CNT_WIDTH = `LOG2UP(WARP_CNT),
    parameter NUM_ALU_BLOCKS = `UP(ISSUE_CNT/1)
) (
    input wire              clk,
    input wire              reset,
    
    // Inputs
    VX_dispatch_if.slave    dispatch_if [ISSUE_CNT],

    // Outputs
    VX_commit_scalar_if.master     commit_if [ISSUE_CNT],
    VX_branch_ctl_if.master branch_ctl_if [NUM_ALU_BLOCKS]
);   

    `UNUSED_PARAM (CORE_ID)
    localparam BLOCK_SIZE = `UP(ISSUE_CNT / 1);
    localparam NUM_LANES    = `UP(THREAD_CNT); //`MIN(`UP(THREAD_CNT/2),`NUM_ALU_LANES); // need to figure out what this does. 
    localparam PID_BITS     = `LOG2UP(THREAD_CNT / NUM_LANES);
    localparam PID_WIDTH    = `UP(PID_BITS);
    localparam RSP_ARB_DATAW= `UUID_WIDTH + WARP_CNT_WIDTH + NUM_LANES + `XLEN + `NR_BITS + 1 + NUM_LANES * `XLEN + PID_WIDTH + 1 + 1 + 1;
    localparam RSP_ARB_SIZE = 1 + `EXT_M_ENABLED;
    localparam PARTIAL_BW   = (BLOCK_SIZE != ISSUE_CNT) || (NUM_LANES != THREAD_CNT);

    VX_execute_if #(
        .NUM_LANES (NUM_LANES),
        .THREAD_CNT (THREAD_CNT),
        .WARP_CNT(WARP_CNT)
    ) execute_if[BLOCK_SIZE]();

    `RESET_RELAY (dispatch_reset, reset);

    VX_dispatch_unit #(
        .BLOCK_SIZE (BLOCK_SIZE),
        .NUM_LANES  (NUM_LANES),
        .OUT_REG    (PARTIAL_BW ? 1 : 0),
        .THREAD_CNT(THREAD_CNT),
        .WARP_CNT(WARP_CNT)
    ) dispatch_unit (
        .clk        (clk),
        .reset      (dispatch_reset),
        .dispatch_if(dispatch_if),
        .execute_if (execute_if)
    );

    VX_commit_scalar_if #(
        .NUM_LANES (NUM_LANES),
        .THREAD_CNT (THREAD_CNT),
        .WARP_CNT(WARP_CNT)
    ) commit_block_if[BLOCK_SIZE]();

    for (genvar block_idx = 0; block_idx < BLOCK_SIZE; ++block_idx) begin

        wire is_muldiv_op;

        VX_execute_if #(
            .NUM_LANES (NUM_LANES),
            .THREAD_CNT (THREAD_CNT),
            .WARP_CNT(WARP_CNT)
        ) int_execute_if();

        assign int_execute_if.valid = execute_if[block_idx].valid && ~is_muldiv_op;
        assign int_execute_if.data = execute_if[block_idx].data;

        VX_commit_scalar_if #(
            .NUM_LANES (NUM_LANES),
            .THREAD_CNT (THREAD_CNT),
            .WARP_CNT(WARP_CNT)
        ) int_commit_if();

        `RESET_RELAY (int_reset, reset);

        VX_int_unit_scalar #(
            .CORE_ID   (CORE_ID),
            .BLOCK_IDX (block_idx),
            .NUM_LANES (NUM_LANES),
            .THREAD_CNT(THREAD_CNT),
            .WARP_CNT(WARP_CNT)
        ) int_unit (
            .clk        (clk),
            .reset      (int_reset),
            .execute_if (int_execute_if),
            .branch_ctl_if (branch_ctl_if[block_idx]),
            .commit_if  (int_commit_if)
        );

    `ifdef EXT_M_ENABLE

        assign is_muldiv_op = `INST_ALU_IS_M(execute_if[block_idx].data.op_mod);

        `RESET_RELAY (mdv_reset, reset);

        VX_execute_if #(
            .NUM_LANES (NUM_LANES),
            .THREAD_CNT (THREAD_CNT),
            .WARP_CNT(WARP_CNT)
        ) mdv_execute_if();
        
        assign mdv_execute_if.valid = execute_if[block_idx].valid && is_muldiv_op;
        assign mdv_execute_if.data = execute_if[block_idx].data;

        VX_commit_scalar_if #(
            .NUM_LANES (NUM_LANES),
            .THREAD_CNT (THREAD_CNT),
            .WARP_CNT(WARP_CNT)
        ) mdv_commit_if();

        VX_muldiv_unit_scalar #(
            .CORE_ID   (CORE_ID),
            .NUM_LANES (NUM_LANES),
            .THREAD_CNT(THREAD_CNT),
            .WARP_CNT(WARP_CNT)
        ) mdv_unit (
            .clk        (clk),
            .reset      (mdv_reset),
            .execute_if (mdv_execute_if),
            .commit_if  (mdv_commit_if)
        );       
       
        assign execute_if[block_idx].ready = is_muldiv_op ? mdv_execute_if.ready : int_execute_if.ready;

    `else

        assign is_muldiv_op = 0;
        assign execute_if[block_idx].ready = int_execute_if.ready;

    `endif

        // send response

        VX_stream_arb #(
            .NUM_INPUTS (RSP_ARB_SIZE),
            .DATAW      (RSP_ARB_DATAW),
            .OUT_REG    (PARTIAL_BW ? 1 : 3)
        ) rsp_arb (
            .clk       (clk),
            .reset     (reset),
            .valid_in  ({                
            `ifdef EXT_M_ENABLE
                mdv_commit_if.valid,
            `endif
                int_commit_if.valid
            }),
            .ready_in  ({
            `ifdef EXT_M_ENABLE
                mdv_commit_if.ready,
            `endif
                int_commit_if.ready
            }),
            .data_in   ({
            `ifdef EXT_M_ENABLE
                mdv_commit_if.data,
            `endif
                int_commit_if.data
            }),
            .data_out  (commit_block_if[block_idx].data),
            .valid_out (commit_block_if[block_idx].valid), 
            .ready_out (commit_block_if[block_idx].ready),            
            `UNUSED_PIN (sel_out)
        );
    end

    `RESET_RELAY (commit_reset, reset);

    VX_gather_unit_scalar #(
        .BLOCK_SIZE (BLOCK_SIZE),
        .NUM_LANES  (NUM_LANES),
        .OUT_REG    (PARTIAL_BW ? 3 : 0),
        .THREAD_CNT(THREAD_CNT),
        .WARP_CNT(WARP_CNT)
    ) gather_unit (
        .clk           (clk),
        .reset         (commit_reset),
        .commit_in_if  (commit_block_if),
        .commit_out_if (commit_if)
    );

endmodule