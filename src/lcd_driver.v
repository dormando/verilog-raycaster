// the actual SPI driver for the LCD runs in a separate clock domain, so we
// need to use the task_crossdomain module to safely signal to the SPI and
// back. This adds a few cycles of delay on either side.
// Further improvements could queue the next byte and ensure the SPI stays
// fed.
module lcd_driver (
    input clk,
    input fclk, // faster clock for SPI
    input rst,
    output lcd_sck,
    output lcd_mosi,
    output lcd_ss,
    output lcd_dcx, // lo: data, hi: cmd
    // TODO: backlight and reset.
    input [7:0] data_in, // data to write out
    input data_dcx, // lo: data, hi: cmd
    input start,
    output busy,
    output reg done // done executing transfer.
);

localparam STATE_SIZE = 2;
localparam IDLE = 0,
    START_TRANSFER = 1,
    WAIT_TRANSFER = 2;

reg [STATE_SIZE-1:0] state_d, state_q;

reg [7:0] data_d, data_q;

wire spi_busy;
reg spi_start;
wire spi_start_l, spi_done_l;
reg data_dcx_d, data_dcx_q;

assign lcd_dcx = data_dcx_q;
assign busy = state_q != IDLE;

task_crossdomain task_crossdomain(
    .clka(clk), // external (slow) clock domain
    .taskstart_clka(spi_start),
    .taskbusy_clka(spi_busy),
    .taskdone_clka(),
    .clkb(fclk), // internal (fast) clock domain
    .taskstart_clkb(spi_start_l),
    .taskbusy_clkb(),
    .taskdone_clkb(spi_done_l)
);

spi #(.CLK_DIV(2)) lcd_spi (
    .clk(fclk),
    .rst(rst),
    .mosi(lcd_mosi),
    .miso(),
    .sck(lcd_sck),
    .start(spi_start_l),
    .ss(lcd_ss),
    .data_in(data_q),
    .data_out(),
    .busy(),
    .new_data(spi_done_l)
);

always @(*) begin
    data_dcx_d = data_dcx_q;
    data_d = data_q;
    spi_start = 1'b0;
    done = 1'b0;
    state_d = state_q;

    case (state_q)
        IDLE: begin
            if (start) begin
                data_dcx_d = data_dcx;
                data_d = data_in;
                state_d = START_TRANSFER;
            end
        end
        START_TRANSFER: begin
            if (!spi_busy) begin
                spi_start = 1'b1;
                state_d = WAIT_TRANSFER;
            end
        end
        WAIT_TRANSFER: begin
            if (!spi_busy) begin
                done = 1'b1;
                state_d = IDLE;
            end
        end
        default: state_d = IDLE;
    endcase
end

always @(posedge clk) begin
    if (rst) begin
        state_q <= IDLE;
        data_dcx_q <= 0;
        data_q <= 0;
    end else begin
        state_q <= state_d;
        data_dcx_q <= data_dcx_d;
        data_q <= data_d;
    end
end

endmodule
