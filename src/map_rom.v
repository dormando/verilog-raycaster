module map_rom (
    input [7:0] x,
    input [7:0] y,
    output reg [3:0] point
    );

reg [3:0] map [23:0][23:0];

initial begin
`include "map.rom"
end

always @(*) begin
    if (x < 24 && y < 24)
        point = map[x][y];
    else
        point = 4'd1;
end

endmodule
