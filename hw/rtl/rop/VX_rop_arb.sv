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

module VX_rop_arb import VX_rop_pkg::*; #(
    parameter NUM_INPUTS     = 1,
    parameter NUM_OUTPUTS    = 1,
    parameter NUM_LANES      = 1,
    parameter OUT_REG       = 0,
    parameter `STRING ARBITER = "R"
) (
    input wire              clk,
    input wire              reset,

    // input requests    
    VX_rop_bus_if.slave     bus_in_if [NUM_INPUTS],

    // output request
    VX_rop_bus_if.master    bus_out_if [NUM_OUTPUTS]
);

    localparam REQ_DATAW  = `UUID_WIDTH + NUM_LANES * (1 + 2 * `VX_ROP_DIM_BITS + $bits(rgba_t) + `VX_ROP_DEPTH_BITS + 1);

    wire [NUM_INPUTS-1:0]                 req_valid_in;
    wire [NUM_INPUTS-1:0][REQ_DATAW-1:0]  req_data_in;
    wire [NUM_INPUTS-1:0]                 req_ready_in;    
    
    wire [NUM_OUTPUTS-1:0]                req_valid_out;
    wire [NUM_OUTPUTS-1:0][REQ_DATAW-1:0] req_data_out;
    wire [NUM_OUTPUTS-1:0]                req_ready_out;

    for (genvar i = 0; i < NUM_INPUTS; ++i) begin
        assign req_valid_in[i] = bus_in_if[i].req_valid;
        assign req_data_in[i] = bus_in_if[i].req_data;
        assign bus_in_if[i].req_ready = req_ready_in[i];
    end

    VX_stream_arb #(            
        .NUM_INPUTS (NUM_INPUTS),
        .NUM_OUTPUTS(NUM_OUTPUTS),
        .DATAW      (REQ_DATAW),
        .ARBITER    (ARBITER),
        .OUT_REG   (OUT_REG)
    ) req_arb (
        .clk        (clk),
        .reset      (reset),
        .valid_in   (req_valid_in),
        .ready_in   (req_ready_in),
        .data_in    (req_data_in),
        .data_out   (req_data_out),
        .valid_out  (req_valid_out),
        .ready_out  (req_ready_out),
        `UNUSED_PIN (sel_out)
    );
    
    for (genvar i = 0; i < NUM_OUTPUTS; ++i) begin
        assign bus_out_if[i].req_valid = req_valid_out[i];
        assign bus_out_if[i].req_data = req_data_out[i];
        assign req_ready_out[i] = bus_out_if[i].req_ready;
    end

endmodule
