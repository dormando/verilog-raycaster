`timescale 1ns / 1ps

module cast_ray_tb(
    );

reg clk;
reg rst;

reg [8:0] x;
reg [6:0] turn;

reg [15:0] map_pos_x;
reg [15:0] map_pos_y;

reg start;
wire busy;
wire [23:0] line_height;
wire [7:0] line_color;
wire [6:0] line_tex_x;

cast_ray DUT (
    .clk(clk),
    .rst(rst),
    .x(x),
    .turn(turn),
    .map_pos_x(map_pos_x),
    .map_pos_y(map_pos_y),
    .start(start),
    .busy(busy),
    .line_height(line_height),
    .line_color(line_color),
    .line_tex_x(line_tex_x)
);

    // wait by delay for clocks rather than manually run them.
	 initial begin
	     clk = 0;
		  forever #10 clk = ~clk;
	 end

    initial begin
        rst = 1'b1;
        repeat(6) @(posedge clk);
        rst = 1'b0;
   	    repeat(2) @(posedge clk);
        /*delta_dist_n_x = 16'hFF_00;
        delta_dist_n_y = 16'hFE_7D;
        map_pos_x = 16'h16_00;
        map_pos_y = 16'h16_00;*/
        // 37 fe d0 fe
        //delta_dist_n_y = 16'hFE_37;
        //delta_dist_n_x = 16'hFE_D0;
        // 0c 13 90 14
        x = 9'd30;
        turn = 7'd16;
        map_pos_x = 16'h13_0c;
        map_pos_y = 16'h14_90;
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        repeat(100) @(posedge clk);
        // done and line_height should be set.
        #5000
        $finish;
    end

    initial begin
        #500000000
        $finish;
    end
endmodule
