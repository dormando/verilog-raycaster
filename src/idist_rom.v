module idist_rom (
    input clk,
    input [9:0] addr,
    output [15:0] idist // Q8.8 inverse distance
    );

reg [15:0] idists [1023:0];

reg [15:0] idist_d, idist_q;

assign idist = idist_q;

initial begin
`include "idist.rom"
end

always @(*) begin
    if (addr < 10'd1023)
        idist_d = idists[addr];
    else
        idist_d = 16'd0;
end

always @(posedge clk) begin
    idist_q <= idist_d;
end

endmodule
