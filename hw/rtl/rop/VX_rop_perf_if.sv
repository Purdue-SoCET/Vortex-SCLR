//!/bin/bash

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

`include "VX_rop_define.vh"

interface VX_rop_perf_if ();

    wire [`PERF_CTR_BITS-1:0] mem_reads;
    wire [`PERF_CTR_BITS-1:0] mem_writes;
    wire [`PERF_CTR_BITS-1:0] mem_latency;
    wire [`PERF_CTR_BITS-1:0] stall_cycles;

    modport master (
        output mem_reads,
        output mem_writes,
        output mem_latency,
        output stall_cycles
    );

    modport slave (
        input mem_reads,
        input mem_writes,
        input mem_latency,
        input stall_cycles
    );

endinterface
