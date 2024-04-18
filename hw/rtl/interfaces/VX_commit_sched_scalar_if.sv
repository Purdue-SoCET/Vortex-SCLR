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

interface VX_commit_sched_scalar_if
#(
    parameter WARP_CNT = `NUM_WARPS,
    parameter ISSUE_CNT = `MIN(WARP_CNT, 4),
    parameter WARP_CNT_WIDTH = `LOG2UP(WARP_CNT)
 ) ();

    wire [ISSUE_CNT-1:0] committed;
    wire [ISSUE_CNT-1:0][WARP_CNT_WIDTH-1:0] committed_wid;
    wire [ISSUE_CNT-1:0] halt;

    modport master (
        output committed,
        output committed_wid,
        output halt
    );

    modport slave (
        input committed,
        input committed_wid,
        input halt
    );

endinterface