// not using signed values here since I had some bugs.
// users of this data need to treat it as signed.
module camerax_rom (
    input clk,
    input [8:0] addr,
    output [15:0] camerax // Q8.8
    );

reg [15:0] camerax_pos [319:0];

reg [15:0] cx_d, cx_q;

assign camerax = cx_q;

initial begin
`include "camerax.rom"
end

always @(*) begin
    if (addr < 9'd320)
        cx_d = camerax_pos[addr];
    else
        cx_d = 16'd0;
end

always @(posedge clk) begin
    cx_q <= cx_d;
end

endmodule
