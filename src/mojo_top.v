module mojo_top(
    // 50MHz clock input
    input clk,
    // Input from reset button (active low)
    input rst_n,
    // cclk input from AVR, high when AVR is ready
    input cclk,
    // Outputs to the 8 onboard LEDs
    output[7:0]led,
    // AVR SPI connections
    output spi_miso,
    input spi_ss,
    input spi_mosi,
    input spi_sck,
    // AVR ADC channel select
    output [3:0] spi_channel,
    // Serial connections
    input avr_tx, // AVR Tx => FPGA Rx
    output avr_rx, // AVR Rx => FPGA Tx
    input avr_rx_busy, // AVR Rx buffer full
    // LCD SPI and control wires
    output lcd_sck,
    output lcd_mosi,
    output lcd_ss,
    output lcd_dcx, // hi: data, lo: cmd
    output lcd_bl,  // PWM'ed backlight
    output lcd_rst  // RST. LCD seems to hang sometimes.
    );

wire rst = ~rst_n; // make reset active high
wire fclk, nclk;

//assign led = 8'b0;

// these signals should be high-z when not used
//assign spi_miso = 1'bz;
//assign avr_rx = 1'bz;
//assign spi_channel = 4'bzzzz;
wire [7:0] tx_data;
wire new_tx_data;
wire tx_busy;
wire [7:0] rx_data;
wire new_rx_data;

// LCD wires
// TODO "LCD busy" wire for LED.
// LCD module wires
wire [7:0] lcd_data_in;
wire lcd_data_dcx;
wire lcd_start;
wire lcd_busy;
wire lcd_done;
// leave LCD backlight disconnected
assign lcd_bl = 1'bz;

// mmap interface specifics
wire m_new_cmd;
wire m_write;
wire [5:0] m_cmd;
wire [31:0] m_address;
wire [31:0] m_data;
wire [31:0] s_data;
wire s_drdy;
wire flush_busy;

wire [79:0] angle;

// line writer wires
wire [39:0] line_height;
wire [6:0] line_tex_x;
wire [7:0] color;
wire [15:0] line_floor_x;
wire [15:0] line_floor_y;
wire [15:0] line_pos_x;
wire [15:0] line_pos_y;
wire line_write_ready, line_write_start, line_write_done;
wire [8:0] line_ram_raddr;
wire [15:0] line_ram_read_data;
wire [13:0] line_tram_waddr;
wire [3:0] line_tram_write_data;
wire line_tram_write_en;
wire [7:0] line_tpram_waddr;
wire [15:0] line_tpram_write_data;
wire line_tpram_write_en;

// ray caster wires
wire cast_start;
wire cast_busy;
wire cast_done;
wire [8:0] cast_x;
wire [15:0] map_pos_x;
wire [15:0] map_pos_y;

// sprite transform wires
wire sprite_start;
wire sprite_done;
wire [6:0] smeta_waddr;
wire [39:0] smeta_write_data;
wire smeta_write_en;
wire [6:0] stmeta_raddr;
wire [119:0] stmeta_read_data;

// sprite scanline sorter
wire [15:0] wall_z;
wire [2:0] sprite_addr;
wire [119:0] sprite_meta;
wire sprscan_start;
wire sprscan_done;
wire [2:0] sprite_count;

// LED indicators.
assign led[3] = sprite_count != 0;
assign led[4] = flush_busy;
assign led[5] = lcd_busy;
assign led[6] = ~line_write_ready;
assign led[7] = cast_busy;

lcd_spi_clk lcd_spi_clk (
        .clk_in(clk),
        .clk_fout(fclk),
        .clk_nout(nclk)
);

lcd_driver lcd_driver (
    .clk(nclk),
    .fclk(fclk),
    .rst(rst),
    .lcd_sck(lcd_sck),
    .lcd_mosi(lcd_mosi),
    .lcd_ss(lcd_ss),
    .lcd_dcx(lcd_dcx),
    .data_in(lcd_data_in),
    .data_dcx(lcd_data_dcx),
    .start(lcd_start),
    .busy(lcd_busy),
    .done(lcd_done)
);

  avr_interface #(.CLK_RATE(50000000), .SERIAL_BAUD_RATE(500000)) avr_interface (
    .clk(nclk),
    .rst(rst),
    .cclk(cclk),
    .spi_miso(spi_miso),
    .spi_mosi(spi_mosi),
    .spi_sck(spi_sck),
    .spi_ss(spi_ss),
    .spi_channel(spi_channel),
    .tx(avr_rx), // FPGA tx goes to AVR rx
    .rx(avr_tx),
    .channel(4'd15), // invalid channel disables the ADC
    .new_sample(),
    .sample(),
    .sample_channel(),
    .tx_data(tx_data),
    .new_tx_data(new_tx_data),
    .tx_busy(tx_busy),
    .tx_block(avr_rx_busy),
    .rx_data(rx_data),
    .new_rx_data(new_rx_data)
  );

mmap_protocol mmap_protocol (
    .clk(nclk),
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
    .m_data(m_data),
    .s_data(s_data),
    .s_drdy(s_drdy)
  );

mmap_interface mmaped_interface (
	.clk(nclk),
	.rst(rst),
	.leds(led[2:0]),
    .flush_busy(flush_busy),
    // Protocol handler wires
	.m_new_cmd(m_new_cmd),
    .m_cmd(m_cmd),
	.m_write(m_write),
	.m_address(m_address),
	.m_data(m_data),
	.s_data(s_data),
	.s_drdy(s_drdy),
    .angle(angle),
    // ray caster wires
    .cast_x(cast_x),
    .map_pos_x(map_pos_x),
    .map_pos_y(map_pos_y),
    .cast_start(cast_start),
    .cast_busy(cast_busy),
    .cast_done(cast_done),
    // line writer wires
    .line_height(line_height),
    .line_write_ready(line_write_ready),
    .line_write_start(line_write_start),
    .line_write_done(line_write_done),
    .line_ram_raddr(line_ram_raddr),
    .line_ram_read_data(line_ram_read_data),
    .tram_waddr(line_tram_waddr),
    .tram_write_data(line_tram_write_data),
    .tram_write_en(line_tram_write_en),
    .tpram_waddr(line_tpram_waddr),
    .tpram_write_data(line_tpram_write_data),
    .tpram_write_en(line_tpram_write_en),
    // sprite metadata wires
    .smeta_waddr(smeta_waddr),
    .smeta_write_data(smeta_write_data),
    .smeta_write_en(smeta_write_en),
    .sprite_start(sprite_start),
    .sprite_done(sprite_done),
    // LCD driver wires
    .lcd_rst(lcd_rst),
    .lcd_data_in(lcd_data_in),
    .lcd_data_dcx(lcd_data_dcx),
    .lcd_start(lcd_start),
    .lcd_done(lcd_done)
  );

line_writer line_writer (
    .clk(nclk),
    .rst(rst),
    .start(line_write_start),
    .x(cast_x),
    .pixel(color),
    .height(line_height),
    .tex_x(line_tex_x),
    .floor_x(line_floor_x),
    .floor_y(line_floor_y),
    .pos_x(line_pos_x),
    .pos_y(line_pos_y),
    .rdy(line_write_ready),
    .done(line_write_done),
    .ram_raddr(line_ram_raddr),
    .ram_read_data(line_ram_read_data),
    .tram_waddr(line_tram_waddr),
    .tram_write_data(line_tram_write_data),
    .tram_write_en(line_tram_write_en),
    .tpram_waddr(line_tpram_waddr),
    .tpram_write_data(line_tpram_write_data),
    .tpram_write_en(line_tpram_write_en),
    .sprscan_start(sprscan_start),
    .sprscan_done(sprscan_done),
    .sprite_addr(sprite_addr),
    .sprite_meta(sprite_meta),
    .sprite_count(sprite_count)
);

cast_ray cast_ray (
    .clk(nclk),
    .rst(rst),
    .x(cast_x),
    .angle(angle),
    .map_pos_x(map_pos_x),
    .map_pos_y(map_pos_y),
    .start(cast_start),
    .busy(cast_busy),
    .done(cast_done),
    .line_height(line_height),
    .line_tex_x(line_tex_x),
    .line_color(color),
    .line_floor_x(line_floor_x),
    .line_floor_y(line_floor_y),
    .line_pos_x(line_pos_x),
    .line_pos_y(line_pos_y),
    .wall_z(wall_z)
);

sprite sprite (
    .clk(nclk),
    .rst(rst),
    .start(sprite_start),
    .done(sprite_done),
    .angle(angle),
    .map_pos_x(map_pos_x),
    .map_pos_y(map_pos_y),
    .smeta_waddr(smeta_waddr),
    .smeta_write_data(smeta_write_data),
    .smeta_write_en(smeta_write_en),
    .stmeta_raddr(stmeta_raddr),
    .stmeta_read_data(stmeta_read_data)
);

sprite_scanline sprite_scanline (
    .clk(nclk),
    .rst(rst),
    .start(sprscan_start),
    .done(sprscan_done),
    .x(cast_x),
    .wall_z(wall_z),
    .stmeta_raddr(stmeta_raddr),
    .stmeta_read_data(stmeta_read_data),
    .sprite_addr(sprite_addr),
    .sprite_meta(sprite_meta),
    .sprite_count(sprite_count)
);

endmodule
