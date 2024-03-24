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

`include "VX_tex_define.vh"

module VX_tex_mem import VX_gpu_pkg::*; import VX_tex_pkg::*; #(
    parameter `STRING INSTANCE_ID = "",
    parameter REQ_INFOW   = 1,
    parameter NUM_LANES   = 1,
    parameter W_ADDR_BITS = `TEX_ADDR_BITS + 6
) (    
    input wire clk,
    input wire reset,

   // memory interface
    VX_mem_bus_if.master cache_bus_if [TCACHE_NUM_REQS],

    // inputs
    input wire                          req_valid,
    input wire [NUM_LANES-1:0]          req_mask,
    input wire [`TEX_FILTER_BITS-1:0]   req_filter,
    input wire [`TEX_LGSTRIDE_BITS-1:0] req_lgstride,
    input wire [NUM_LANES-1:0][W_ADDR_BITS-1:0] req_baseaddr,
    input wire [NUM_LANES-1:0][3:0][31:0] req_addr,
    input wire [REQ_INFOW-1:0]          req_info,
    output wire                         req_ready,

    // outputs
    output wire                         rsp_valid,
    output wire [NUM_LANES-1:0][3:0][31:0] rsp_data,
    output wire [REQ_INFOW-1:0]         rsp_info,
    input wire                          rsp_ready    
);

    localparam TAG_WIDTH  = REQ_INFOW + `TEX_LGSTRIDE_BITS + (NUM_LANES * 4 * 2) + 4;

    wire                           mem_req_valid;
    wire [3:0][NUM_LANES-1:0]      mem_req_mask;
    wire [3:0][NUM_LANES-1:0][TCACHE_ADDR_WIDTH-1:0] mem_req_addr;
    wire [3:0][NUM_LANES-1:0][3:0] mem_req_byteen;
    wire [TAG_WIDTH-1:0]           mem_req_tag;
    wire                           mem_req_ready;

    wire                           mem_rsp_valid;
    wire [3:0][NUM_LANES-1:0][31:0] mem_rsp_data;
    wire [TAG_WIDTH-1:0]           mem_rsp_tag;
    wire                           mem_rsp_ready;
    
    // full address calculation

    wire [NUM_LANES-1:0][3:0][W_ADDR_BITS-1:0] full_addr;    
    
    for (genvar i = 0; i < NUM_LANES; ++i) begin
        for (genvar j = 0; j < 4; ++j) begin
            assign full_addr[i][j] = req_baseaddr[i] + W_ADDR_BITS'(req_addr[i][j]);
        end
    end
    
    // reorder addresses into per-quad requests

    wire [3:0][NUM_LANES-1:0][1:0] mem_req_align;

    for (genvar i = 0; i < NUM_LANES; ++i) begin
        for (genvar j = 0; j < 4; ++j) begin
            assign mem_req_addr[j][i]   = TCACHE_ADDR_WIDTH'(full_addr[i][j][W_ADDR_BITS-1:2]);
            assign mem_req_align[j][i]  = full_addr[i][j][1:0];
            assign mem_req_byteen[j][i] = 4'b1111;
        end
    end

    // detect duplicate addresses

    wire [3:0] mem_req_dups;

    for (genvar i = 0; i < 4; ++i) begin
        wire texel_valid = req_filter || (i == 0);
        if (NUM_LANES > 1) begin
            wire [NUM_LANES-2:0] addr_matches;
            for (genvar j = 0; j < (NUM_LANES-1); ++j) begin                
                assign addr_matches[j] = (req_addr[j+1][i] == req_addr[0][i]) || ~req_mask[j+1];
            end
            assign mem_req_dups[i] = req_mask[0] && (& addr_matches);            
        end else begin
            assign mem_req_dups[i] = 0;
        end
        for (genvar j = 0; j < NUM_LANES; ++j) begin
            assign mem_req_mask[i][j] = req_mask[j] && texel_valid && (~mem_req_dups[i] || (j == 0));
        end
    end

    // submit request to memory   

    assign mem_req_valid = req_valid;
    assign mem_req_tag   = {req_info, req_lgstride, mem_req_align, mem_req_dups};
    assign req_ready     = mem_req_ready;

    // schedule memory request

    wire [TCACHE_NUM_REQS-1:0]              cache_req_valid;
    wire [TCACHE_NUM_REQS-1:0]              cache_req_rw;
    wire [TCACHE_NUM_REQS-1:0][3:0]         cache_req_byteen;
    wire [TCACHE_NUM_REQS-1:0][TCACHE_ADDR_WIDTH-1:0] cache_req_addr;
    wire [TCACHE_NUM_REQS-1:0][31:0]        cache_req_data;
    wire [TCACHE_NUM_REQS-1:0][TCACHE_TAG_WIDTH-1:0] cache_req_tag;
    wire [TCACHE_NUM_REQS-1:0]              cache_req_ready;
    wire [TCACHE_NUM_REQS-1:0]              cache_rsp_valid;
    wire [TCACHE_NUM_REQS-1:0][31:0]        cache_rsp_data;
    wire [TCACHE_NUM_REQS-1:0][TCACHE_TAG_WIDTH-1:0] cache_rsp_tag;
    wire [TCACHE_NUM_REQS-1:0]              cache_rsp_ready;

    VX_mem_scheduler #(
        .INSTANCE_ID ($sformatf("%s-memsched", INSTANCE_ID)),
        .NUM_REQS    (TEX_MEM_REQS), 
        .NUM_BANKS   (TCACHE_NUM_REQS),
        .ADDR_WIDTH  (TCACHE_ADDR_WIDTH),
        .DATA_WIDTH  (32),
        .QUEUE_SIZE  (`TEX_MEM_QUEUE_SIZE),
        .TAG_WIDTH   (TAG_WIDTH),
        .MEM_TAG_ID  (`UUID_WIDTH),
        .UUID_WIDTH  (`UUID_WIDTH),
        .MEM_OUT_REG (2)
    ) mem_scheduler (
        .clk            (clk),
        .reset          (reset),

        // Input request
        .req_valid      (mem_req_valid),
        .req_rw         (1'b0),
        .req_mask       (mem_req_mask),
        .req_byteen     (mem_req_byteen),
        .req_addr       (mem_req_addr),
        `UNUSED_PIN     (req_data),
        .req_tag        (mem_req_tag),
        `UNUSED_PIN     (req_empty),
        .req_ready      (mem_req_ready),
        `UNUSED_PIN     (write_notify),
        
        // Output response
        .rsp_valid      (mem_rsp_valid),
        `UNUSED_PIN     (rsp_mask),
        .rsp_data       (mem_rsp_data),
        .rsp_tag        (mem_rsp_tag),
        `UNUSED_PIN     (rsp_sop),
        `UNUSED_PIN     (rsp_eop),
        .rsp_ready      (mem_rsp_ready),

        // Memory request
        .mem_req_valid  (cache_req_valid),
        .mem_req_rw     (cache_req_rw),
        .mem_req_byteen (cache_req_byteen),
        .mem_req_addr   (cache_req_addr),
        .mem_req_data   (cache_req_data),
        .mem_req_tag    (cache_req_tag),
        .mem_req_ready  (cache_req_ready),

        // Memory response
        .mem_rsp_valid  (cache_rsp_valid),
        .mem_rsp_data   (cache_rsp_data),
        .mem_rsp_tag    (cache_rsp_tag),
        .mem_rsp_ready  (cache_rsp_ready)
    );

    for (genvar i = 0; i < TCACHE_NUM_REQS; ++i) begin
        assign cache_bus_if[i].req_valid = cache_req_valid[i];
        assign cache_bus_if[i].req_data.rw = cache_req_rw[i];
        assign cache_bus_if[i].req_data.byteen = cache_req_byteen[i];
        assign cache_bus_if[i].req_data.addr = cache_req_addr[i];
        assign cache_bus_if[i].req_data.data = cache_req_data[i]; 
        assign cache_bus_if[i].req_data.tag = cache_req_tag[i];
        assign cache_req_ready[i] = cache_bus_if[i].req_ready;

        assign cache_rsp_valid[i] = cache_bus_if[i].rsp_valid;
        assign cache_rsp_data[i] = cache_bus_if[i].rsp_data.data;
        assign cache_rsp_tag[i] = cache_bus_if[i].rsp_data.tag;
        assign cache_bus_if[i].rsp_ready = cache_rsp_ready[i]; 
    end

    // handle memory response

    wire [REQ_INFOW-1:0]          mem_rsp_info;
    wire [`TEX_LGSTRIDE_BITS-1:0] mem_rsp_lgstride;    
    wire [3:0][NUM_LANES-1:0][1:0] mem_rsp_align;
    wire [3:0]                    mem_rsp_dups;
    
    assign {mem_rsp_info, mem_rsp_lgstride, mem_rsp_align, mem_rsp_dups} = mem_rsp_tag;

    reg [NUM_LANES-1:0][3:0][31:0] mem_rsp_data_qual;

    for (genvar i = 0; i < NUM_LANES; ++i) begin   
        for (genvar j = 0; j < 4; ++j) begin
            wire [31:0] src_data = ((i == 0 || mem_rsp_dups[j]) ? mem_rsp_data[j][0] : mem_rsp_data[j][i]);

            reg [31:0] rsp_data_shifted;
            always @(*) begin
                rsp_data_shifted[31:16] = src_data[31:16];
                rsp_data_shifted[15:0]  = mem_rsp_align[j][i][1] ? src_data[31:16]        : src_data[15:0];
                rsp_data_shifted[7:0]   = mem_rsp_align[j][i][0] ? rsp_data_shifted[15:8] : rsp_data_shifted[7:0];
            end

            always @(*) begin
                case (mem_rsp_lgstride)
                0:       mem_rsp_data_qual[i][j] = 32'(rsp_data_shifted[7:0]);
                1:       mem_rsp_data_qual[i][j] = 32'(rsp_data_shifted[15:0]);
                2:       mem_rsp_data_qual[i][j] = rsp_data_shifted;
                default: mem_rsp_data_qual[i][j] = 'x;
                endcase
            end
        end        
    end

    VX_elastic_buffer #(
        .DATAW   (REQ_INFOW + (4 * NUM_LANES * 32)),
        .OUT_REG (1)
    ) rsp_pipe_reg (
        .clk       (clk),
        .reset     (reset),
        .valid_in  (mem_rsp_valid),
        .ready_in  (mem_rsp_ready),
        .data_in   ({mem_rsp_info, mem_rsp_data_qual}),
        .data_out  ({rsp_info,     rsp_data}),
        .valid_out (rsp_valid),
        .ready_out (rsp_ready)
    );

`ifdef DBG_TRACE_TEX

    always @(posedge clk) begin 
        if (req_valid && req_ready) begin
            `TRACE(2, ("%d: %s-mem-req: valid=%b, filter=%0d, lgstride=%0d, baseaddr=", $time, INSTANCE_ID, req_mask, req_filter, req_lgstride));
            `TRACE_ARRAY1D(2, req_baseaddr, NUM_LANES);
            `TRACE(2, (", addr=0x")); 
            `TRACE_ARRAY2D(2, req_addr, 4, NUM_LANES);
            `TRACE(2, (" (#%0d)\n", req_info[REQ_INFOW-1 -: `UUID_WIDTH]));
        end
        if (rsp_valid && rsp_ready) begin
            `TRACE(2, ("%d: %s-mem-rsp: data=", $time, INSTANCE_ID));
            `TRACE_ARRAY2D(2, rsp_data, 4, NUM_LANES);
            `TRACE(2, (" (#%0d)\n", rsp_info[REQ_INFOW-1 -: `UUID_WIDTH]));
        end        
    end
`endif

endmodule
