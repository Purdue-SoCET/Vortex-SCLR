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

interface VX_commit_scalar_if #(
    parameter THREAD_CNT = `NUM_THREADS,
    parameter NUM_LANES = THREAD_CNT,
    parameter PID_WIDTH = `LOG2UP(THREAD_CNT / NUM_LANES),
    parameter WARP_CNT = `NUM_WARPS,
    parameter WARP_CNT_WIDTH = `LOG2UP(WARP_CNT)
) ();
    
    typedef struct packed {
        logic [`UUID_WIDTH-1:0]     uuid;
        logic [WARP_CNT_WIDTH-1:0]       wid;
        logic [NUM_LANES-1:0]       tmask;
        logic [`XLEN-1:0]           PC;
        logic                       wb;
        logic [`NR_BITS-1:0]        rd;
        logic [NUM_LANES-1:0][`XLEN-1:0] data;
        logic [PID_WIDTH-1:0]       pid;
        logic                       sop;
        logic                       eop;
        logic                       halt;
    } data_t;

    logic  valid;
    data_t data;
    logic  ready;    

    modport master (
        output valid,
        output data,
        input  ready
    );

    modport slave (
        input  valid,
        input  data,
        output ready
    );

endinterface