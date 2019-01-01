`timescale 1ns / 1ps

module line_writer_tb(
    );

reg clk;
reg rst;

reg start;
reg [7:0] pixel;
reg [23:0] height;
reg [6:0] tex_x;
reg [$clog2(240)-1:0] ram_raddr;
wire [7:0] ram_read_data;

reg [12:0] tram_waddr;
reg [7:0] tram_write_data;
reg tram_write_en;

line_writer DUT (
    .clk(clk),
    .rst(rst),
    .start(start),
    .pixel(pixel),
    .height(height),
    .tex_x(tex_x),
    .rdy(rdy),
    .ram_raddr(ram_raddr),
    .ram_read_data(ram_read_data)
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
        start = 1'b1;
        pixel = 8'd1;
        height = 24'hee_00_22;
        tex_x = 7'd15;
        @(posedge clk);
        start = 1'b0;
        ram_raddr = 8'd100;
        repeat(400) @(posedge clk);
        #5000
        $finish;
    end

    initial begin
        #500000000
        $finish;
    end
endmodule
