`timescale 1ns / 1ps

module sprite_tb(
    );

reg clk;
reg rst;

reg start;
wire done;
//reg [79:0] angle;
reg [15:0] map_pos_x;
reg [15:0] map_pos_y;

reg [6:0] smeta_waddr;
reg [39:0] smeta_write_data;
reg smeta_write_en;
reg [6:0] stmeta_raddr;
wire [119:0] stmeta_read_data;

reg [6:0] angle_addr;
wire [79:0] angle;
angle_rom angle_rom (
    .clk(clk),
    .addr(angle_addr),
    .angle(angle) // 4x Q8.8: dirX, dirY, planeX, planeY
);

sprite DUT (
    .clk(clk),
    .rst(rst),
    .start(start),
    .done(done),
    .angle(angle),
    .map_pos_x(map_pos_x),
    .map_pos_y(map_pos_y),
    .smeta_waddr(smeta_waddr),
    .smeta_write_data(smeta_write_data),
    .smeta_write_en(smeta_write_en),
    .stmeta_raddr(stmeta_raddr),
    .stmeta_read_data(stmeta_read_data)
);

    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    initial begin
        rst = 1'b1;
        repeat(6) @(posedge clk);
        rst = 1'b0;
   	    repeat(2) @(posedge clk);
        smeta_waddr = 0;
        // texture 1, map pos h12, h12.
        smeta_write_data = 40'h01_1200_1200;
        smeta_write_en = 1'b1;
        angle_addr = 0;
        repeat(1) @(posedge clk);
        smeta_write_en = 1'b0;
        //angle = 80'hff_00_00_00_00_00_00_a8_02_f0;
        //angle = 80'hff_00_00_00_00_00_00_a8_01_83; 
        map_pos_x = 16'h13_00;
        map_pos_y = 16'h13_00;
        start = 1'b1;
        repeat(1) @(posedge clk);
        start = 1'b0;
        repeat(400) @(posedge clk);
        #5000
        $finish;
    end

    initial begin
        #500000000
        $finish;
    end
endmodule
