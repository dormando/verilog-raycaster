module iheight_rom (
    input clk,
    input [8:0] addr,
    output [15:0] iheight // Q8.8 texture / height
    );

reg [15:0] iheights [1023:0];

reg [15:0] iheight_d, iheight_q;

assign iheight = iheight_q;

initial begin
`include "iheight.rom"
end

always @(*) begin
    iheight_d = iheights[addr];
end

always @(posedge clk) begin
    iheight_q <= iheight_d;
end

endmodule
