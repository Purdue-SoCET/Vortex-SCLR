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

module VX_pending_instr #(
    parameter CTR_WIDTH  = 12,
    parameter ALM_EMPTY  = 1,
    parameter DECR_COUNT = 1,
    parameter WARP_CNT = `NUM_WARPS,
    parameter WARP_CNT_WIDTH = `LOG2UP(WARP_CNT)
) (
    input wire                  clk,
    input wire                  reset,
    input wire                  incr,
    input wire [WARP_CNT_WIDTH-1:0]  incr_wid,
    input wire [DECR_COUNT-1:0] decr,
    input wire [DECR_COUNT-1:0][WARP_CNT_WIDTH-1:0] decr_wid,
    input wire [WARP_CNT_WIDTH-1:0]  alm_empty_wid,
    output wire                 empty,
    output wire                 alm_empty
);
    localparam COUNTW = `LOG2UP(DECR_COUNT+1);

    reg [WARP_CNT-1:0][CTR_WIDTH-1:0] pending_instrs;
    reg [WARP_CNT-1:0][COUNTW-1:0] decr_cnt;
    reg [WARP_CNT-1:0][DECR_COUNT-1:0] decr_mask;
    reg [WARP_CNT-1:0] incr_cnt, incr_cnt_n;
    reg [WARP_CNT-1:0] alm_empty_r, empty_r;

    always @(*) begin
        incr_cnt_n = 0;
        decr_mask = 0;
        if (incr) begin
            incr_cnt_n[incr_wid] = 1;
        end
        for (integer i = 0; i < DECR_COUNT; ++i) begin
            if (decr[i]) begin
                decr_mask[decr_wid[i]][i] = 1;
            end
        end
    end

    for (genvar i = 0; i < WARP_CNT; ++i) begin
        
        wire [COUNTW-1:0] decr_cnt_n;
        `POP_COUNT(decr_cnt_n, decr_mask[i]);
        
        wire [CTR_WIDTH-1:0] pending_instrs_n = pending_instrs[i] + CTR_WIDTH'(incr_cnt[i]) - CTR_WIDTH'(decr_cnt[i]);

        always @(posedge clk) begin
            if (reset) begin
                incr_cnt[i]       <= '0;
                decr_cnt[i]       <= '0;
                pending_instrs[i] <= '0;
                alm_empty_r[i]    <= 0;
                empty_r[i]        <= 1;
            end else begin            
                incr_cnt[i]       <= incr_cnt_n[i];
                decr_cnt[i]       <= decr_cnt_n;
                pending_instrs[i] <= pending_instrs_n;
                alm_empty_r[i]    <= (pending_instrs_n == ALM_EMPTY);
                empty_r[i]        <= (pending_instrs_n == 0);
            end
		end
	end

    assign alm_empty = alm_empty_r[alm_empty_wid];
    assign empty = (& empty_r);

endmodule
