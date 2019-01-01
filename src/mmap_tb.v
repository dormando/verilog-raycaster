`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    00:29:36 10/21/2018 
// Design Name: 
// Module Name:    mmap_interface_tb 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module mmap_interface_tb(
    );

    reg clk;
    reg rst;

  wire [7:0] tx_data;
  wire new_tx_data;
  reg tx_busy;
  reg [7:0] rx_data;
  reg new_rx_data;

wire m_new_cmd;
wire m_write;
wire [5:0] m_cmd;
wire [31:0] m_address;
reg [31:0] s_data;
reg s_drdy;

    mmap_protocol DUT (
        .clk(clk),
        .rst(rst),
        .tx_data(tx_data),
        .new_tx_data(new_tx_data),
        .tx_busy(tx_busy),
        .rx_data(rx_data),
        .new_rx_data(new_rx_data),
         .m_new_cmd(m_new_cmd),
			.m_cmd(m_cmd),
         .m_write(m_write),
         .m_address(m_address),
         .s_data(s_data),
         .s_drdy(s_drdy)
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
		// command byte
        new_rx_data = 1'b1;
        rx_data = 8'b11000000;
        @(posedge clk);
		// "packet count" 16bit.
		rx_data = 8'd0;
		repeat(2) @(posedge clk);
		// "address" bytes. hold open for four clocks.
        rx_data = 8'b00000001;
		repeat(4) @(posedge clk);
		// "data" bytes. hold for another four clocks to load
		rx_data = 8'b01111111;
		repeat(4) @(posedge clk);
		// command should be parsed by now.
		new_rx_data = 1'b0;
		rx_data = 8'd0;
        repeat(8) @(posedge clk);
        // NEXT: issue a read command
        new_rx_data = 1'b1;
        rx_data = 8'b00000001;
        @(posedge clk);
        // packet count 16bit
        rx_data = 8'b00000000;
        repeat(2) @(posedge clk);
        // "address" bytes. four clocks to fill
        rx_data = 8'b00010000;
        repeat(4) @(posedge clk);
        // m_new_cmd should be high
        // m_write should be low.
        // m_address should be full
        new_rx_data = 1'b0;
        @(posedge clk);
        @(posedge clk);
        //new_rx_data = 1'b1;
        // reads request s_drdy and s_data to be set.
        s_data = {16{2'b10}};
        s_drdy = 1'b1;
        tx_busy = 1'b0;
        @(posedge clk);
        s_drdy = 1'b0;
        // during next repetitions, tx_data, new_tx_data, etc should be flipped
        repeat(25) @(posedge clk)
        #5000
        $finish;
    end

    initial begin
        #500000000
        $finish;
    end
endmodule
