module floordist_rom (
    input clk,
    input [8:0] addr,
    output [15:0] floordist // Q8.8
    );

reg [15:0] floor_dist [119:0];

reg [15:0] fd_d, fd_q;

assign floordist = fd_q;

initial begin
`include "floordist.rom"
end

always @(*) begin
    if (addr < 8'd120)
        fd_d = floor_dist[8'd119 - addr];
    else
        fd_d = floor_dist[addr - 8'd119];
end

always @(posedge clk) begin
    fd_q <= fd_d;
end

endmodule
