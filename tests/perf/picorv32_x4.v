// Quad picorv32 wrapper for heavier benchmarks. Reuses tests/functional/picorv32.v.
module picorv32_x4 (
    input clk, resetn,
    input [3:0] mem_ready,
    input [127:0] mem_rdata,
    output [3:0] mem_valid, mem_instr,
    output [127:0] mem_addr, mem_wdata,
    output [15:0] mem_wstrb,
    output [3:0] trap
);
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : core
            picorv32 #(
                .ENABLE_COUNTERS(1),
                .ENABLE_REGS_16_31(1),
                .ENABLE_REGS_DUALPORT(1)
            ) cpu (
                .clk(clk),
                .resetn(resetn),
                .trap(trap[i]),
                .mem_valid(mem_valid[i]),
                .mem_instr(mem_instr[i]),
                .mem_ready(mem_ready[i]),
                .mem_addr(mem_addr[i*32 +: 32]),
                .mem_wdata(mem_wdata[i*32 +: 32]),
                .mem_wstrb(mem_wstrb[i*4 +: 4]),
                .mem_rdata(mem_rdata[i*32 +: 32])
            );
        end
    endgenerate
endmodule
