`include "VX_define.vh"

module VX_writeback #(
    parameter CORE_ID = 0
) (
    input wire          clk,
    input wire          reset,

    // inputs
    VX_exu_to_cmt_if    alu_commit_if,
    VX_exu_to_cmt_if    lsu_commit_if,  
    VX_exu_to_cmt_if    csr_commit_if,
    VX_exu_to_cmt_if    mul_commit_if,
    VX_fpu_to_cmt_if    fpu_commit_if,        
    VX_exu_to_cmt_if    gpu_commit_if,

    // outputs
    VX_writeback_if     writeback_if
);
    wire alu_valid = alu_commit_if.valid && alu_commit_if.wb;
    wire lsu_valid = lsu_commit_if.valid && lsu_commit_if.wb;
    wire csr_valid = csr_commit_if.valid && csr_commit_if.wb;
    wire mul_valid = mul_commit_if.valid && mul_commit_if.wb;
    wire fpu_valid = fpu_commit_if.valid && fpu_commit_if.wb;

    VX_writeback_if writeback_tmp_if();    

    assign writeback_tmp_if.valid = alu_valid ? alu_commit_if.valid :
                                    lsu_valid ? lsu_commit_if.valid :
                                    csr_valid ? csr_commit_if.valid :             
                                    mul_valid ? mul_commit_if.valid :                            
                                    fpu_valid ? fpu_commit_if.valid :                                                 
                                                0;     

    assign writeback_tmp_if.wid = alu_valid ? alu_commit_if.wid :
                                    lsu_valid ? lsu_commit_if.wid :   
                                    csr_valid ? csr_commit_if.wid :   
                                    mul_valid ? mul_commit_if.wid :                            
                                    fpu_valid ? fpu_commit_if.wid :  
                                                0;
    
    assign writeback_tmp_if.thread_mask = alu_valid ? alu_commit_if.thread_mask :
                                    lsu_valid ? lsu_commit_if.thread_mask :   
                                    csr_valid ? csr_commit_if.thread_mask :   
                                    mul_valid ? mul_commit_if.thread_mask :                            
                                    fpu_valid ? fpu_commit_if.thread_mask :  
                                                0;

    assign writeback_tmp_if.rd =    alu_valid ? alu_commit_if.rd :
                                    lsu_valid ? lsu_commit_if.rd :                           
                                    csr_valid ? csr_commit_if.rd :                           
                                    mul_valid ? mul_commit_if.rd :                            
                                    fpu_valid ? fpu_commit_if.rd :                                                               
                                                0;

    assign writeback_tmp_if.data =  alu_valid ? alu_commit_if.data :
                                    lsu_valid ? lsu_commit_if.data :                           
                                    csr_valid ? csr_commit_if.data :                           
                                    mul_valid ? mul_commit_if.data :                            
                                    fpu_valid ? fpu_commit_if.data :                                                               
                                                0;

    wire stall = ~writeback_if.ready && writeback_if.valid;

    VX_generic_register #(
        .N(1 + `NW_BITS + `NUM_THREADS + `NR_BITS + (`NUM_THREADS * 32))
    ) wb_reg (
        .clk   (clk),
        .reset (reset),
        .stall (stall),
        .flush (1'b0),
        .in    ({writeback_tmp_if.valid, writeback_tmp_if.wid, writeback_tmp_if.thread_mask, writeback_tmp_if.rd, writeback_tmp_if.data}),
        .out   ({writeback_if.valid,     writeback_if.wid,     writeback_if.thread_mask,     writeback_if.rd,     writeback_if.data})
    );

    assign alu_commit_if.ready = !stall;    
    assign lsu_commit_if.ready = !stall && !alu_valid;   
    assign csr_commit_if.ready = !stall && !alu_valid && !lsu_valid;
    assign mul_commit_if.ready = !stall && !alu_valid && !lsu_valid && !csr_valid;    
    assign fpu_commit_if.ready = !stall && !alu_valid && !lsu_valid && !csr_valid && !mul_valid;    
    assign gpu_commit_if.ready = 1'b1;
    
    // special workaround to get RISC-V tests Pass/Fail status
    reg [31:0] last_wb_value [`NUM_REGS-1:0] /* verilator public */;
    always @(posedge clk) begin
        if (writeback_if.valid && writeback_if.ready) begin
            last_wb_value[writeback_if.rd] <= writeback_if.data[0];
        end
    end

endmodule