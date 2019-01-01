// ignore the file being called _leds.v :P
// this central interface consumes the memory mapped protocol and controls the
// rest of the design, including rendering.
module mmap_interface (
    input clk,
    input rst,

    output [2:0] leds,
    output flush_busy,

    // Master interface
    input m_new_cmd,
    input m_write,
    input [5:0] m_cmd,
    input [31:0] m_address,
    input [31:0] m_data,

    // Slave interface
    output [31:0] s_data,
    output s_drdy,

    // share output angle to other modules
    output [79:0] angle,

    // ray caster wires
    output reg [8:0] cast_x,
    output [15:0] map_pos_x,
    output [15:0] map_pos_y,
    output reg cast_start,
    input cast_busy,
    input cast_done,

    // line writer
    input [39:0] line_height, // observed line height
    input line_write_ready,
    input line_write_done,
    output reg line_write_start,
    output [8:0] line_ram_raddr,
    input [15:0] line_ram_read_data,
    // line writer texture memory.
    output reg [13:0] tram_waddr,
    output reg [3:0] tram_write_data,
    output reg tram_write_en,
    output reg [7:0] tpram_waddr,
    output reg [15:0] tpram_write_data,
    output reg tpram_write_en,

    // sprite metadata memory
    output reg [6:0] smeta_waddr,
    output reg [39:0] smeta_write_data,
    output reg smeta_write_en,
    output reg sprite_start,
    input sprite_done,

    // LCD driver
    output reg [7:0] lcd_data_in,
    output reg lcd_data_dcx, // low: data, hi: cmd
    output reg lcd_start,
    output lcd_rst,
    input lcd_done
);

// FIXME: reorg states and commands
localparam CMD_LEDS = 0,
    CMD_TEXP_LOAD = 1,
    CMD_TEX_LOAD = 3,
    CMD_CAST_FB = 4,
    CMD_LCD = 5,
    CMD_SPRITE_META = 6;

reg [2:0] led_d, led_q;
reg [31:0] data_d, data_q;
reg drdy_d, drdy_q;

assign leds = led_q;
assign s_data = data_q;
assign s_drdy = drdy_q;
assign lcd_rst = lcd_rst_q;
assign flush_busy = lcdstate_q != LCDIDLE;

// FSM for SDRAM read/writes.
localparam IDLE = 0,
    WAIT_DUMP = 4,
    WAIT_LCD = 5,
    WAIT_FOR_CAST = 6,
    WAIT_FOR_LINE = 7,
    CAST_FB = 8,
    CAST_FB_START = 9;

localparam LCDIDLE= 0,
    LCD_FB_DUMP = 2,
    LCD_FB_READRAM_RES = 3,
    LCD_FB_SPLIT = 4,
    LCD_FB_SPLIT_WAIT = 5,
    LCD_FB_DUMP_START = 6;

reg [4:0] state_d, state_q;
reg [4:0] lcdstate_d, lcdstate_q;

// turn angle ROM. data shared between ray caster and sprite scaler (at least)
reg [6:0] angle_addr;
angle_rom angle_rom (
    .clk(clk),
    .addr(angle_addr),
    .angle(angle) // 4x Q8.8: dirX, dirY, planeX, planeY
);

// ray caster positional data
reg [15:0] map_pos_x_d, map_pos_x_q;
reg [15:0] map_pos_y_d, map_pos_y_q;
reg [6:0] turn_addr_d, turn_addr_q; // angle lookup table index

// caster
assign map_pos_x = map_pos_x_q;
assign map_pos_y = map_pos_y_q;
reg [8:0] lw_raddr_d, lw_raddr_q; // line writer
reg [8:0] lw_base_raddr_d, lw_base_raddr_q; // line RAM bank
assign line_ram_raddr = lw_raddr_q + lw_base_raddr_q;

// screen casting.
localparam WIDTH = 320,
    HEIGHT = 240;
reg [8:0] camera_x_d, camera_x_q;
reg dump_ready_d, dump_ready_q;
reg line_go_d, line_go_q;
reg lcd_go_d, lcd_go_q;
reg lcd_ready_d, lcd_ready_q;
reg lcd_done_d, lcd_done_q; // FIXME: weird.
// FIXME: come up with more clear logic for determining when rendering is
// complete.
// this workaround waits for the "done" condition to be held for a while.
reg [8:0] pipe_done_d, pipe_done_q; 

// lcd
reg lcd_rst_d, lcd_rst_q;
reg lcd_bcnt_d, lcd_bcnt_q;

// frame render time tracker
reg [31:0] frame_cycle_d, frame_cycle_q;
reg [31:0] lframe_cycle_d, lframe_cycle_q;

initial begin
    lcd_rst_q = 1'b0;
    camera_x_q = 9'd0;
    turn_addr_q = 7'd0;
    lframe_cycle_q = 0;
end

// writing to SDRAM requires more states, but m_new_cmd/etc aren't held.
// - what happens if m_new_cmd comes high while we're in an FSM waiting for
// SDRAM?
// the read request shit queues but... do we lose serial transactions if we
// block too long? I think so.
// serial is slow enough that we might be fine for now.
// worst case we connect a couple RAM FIFO's, which I think we're intending on
// doing anyway.

always @(*) begin
        state_d = state_q;
        lcdstate_d = lcdstate_q;
        led_d = led_q;
        data_d = data_q;
        drdy_d = 0;
        line_write_start = 1'b0;
        lw_raddr_d = lw_raddr_q;
        lw_base_raddr_d = lw_base_raddr_q;
        dump_ready_d = dump_ready_q;
        line_go_d = line_go_q;
        lcd_go_d = lcd_go_q;
        lcd_ready_d = lcd_ready_q;
        lcd_done_d = lcd_done_q;
        pipe_done_d = pipe_done_q;
        frame_cycle_d = frame_cycle_q + 1'b1;
        lframe_cycle_d = lframe_cycle_q;
        // ray caster
        camera_x_d = camera_x_q;
        map_pos_x_d = map_pos_x_q;
        map_pos_y_d = map_pos_y_q;
        turn_addr_d = turn_addr_q;
        cast_x = camera_x_q;
        // ensure the angle is loaded
        angle_addr = turn_addr_q;
        cast_start = 1'b0;
        // LCD regs
        lcd_data_in = 8'd0;
        lcd_data_dcx = 1'b0;
        lcd_start = 1'b0;
        lcd_rst_d = lcd_rst_q;
        lcd_bcnt_d = lcd_bcnt_q;
        // line texture memory.
        tram_waddr = 13'd0;
        tram_write_data = 8'd0;
        tram_write_en = 1'b0;
        tpram_waddr = 13'd0;
        tpram_write_data = 8'd0;
        tpram_write_en = 1'b0;
        // sprite metadata memory.
        smeta_waddr = 7'd0;
        smeta_write_data = 39'd0;
        smeta_write_en = 1'b0;
        sprite_start = 1'b0;

        case (lcdstate_q)
          LCDIDLE: begin

          end
          LCD_FB_DUMP: begin
            if (lw_raddr_q != 8'd240) begin
                lcdstate_d = LCD_FB_READRAM_RES;
            end else begin
                lcd_done_d = 1'b1;
                lcdstate_d = LCDIDLE;
                // flip RAM line read bank.
                if (lw_base_raddr_q == 9'd0) begin
                    lw_base_raddr_d = 9'd240;
                end else begin
                    lw_base_raddr_d = 9'd0;
                end
            end
          end
          LCD_FB_READRAM_RES: begin
            data_d[15:0] = line_ram_read_data;
            lcd_bcnt_d = 1'b0;
            lcdstate_d = LCD_FB_SPLIT;
          end
          LCD_FB_SPLIT: begin
            // for each byte, send each half to SPI.
            lcd_bcnt_d = ~lcd_bcnt_q;
            if (!lcd_bcnt_q) begin
                lcd_data_in = data_q[15:8];
            end else begin
                lcd_data_in = data_q[7:0];
            end

            lcd_data_dcx = 1'b1;
            lcd_start = 1'b1;
            lcdstate_d = LCD_FB_SPLIT_WAIT;
          end
          LCD_FB_SPLIT_WAIT: begin
            if (lcd_done) begin
                if (!lcd_bcnt_q) begin // if we've flipped back to zero.
                    lw_raddr_d = lw_raddr_q + 1'b1;
                    lcdstate_d = LCD_FB_DUMP;
                end else begin
                    lcdstate_d = LCD_FB_SPLIT;
                end
            end
          end
          default: lcdstate_d = LCDIDLE;
        endcase

        case (state_q)
          IDLE: begin
            if (m_new_cmd) begin
                led_d[0] = 1'b0;
                case (m_cmd)
                    CMD_LEDS: begin
                        if (m_write) begin
                            led_d[2:0] = m_data[2:0];
                        end else begin
                            data_d[7:0] = led_q;
                            drdy_d = 1'b1;
                        end
                    end
                    CMD_LCD: begin
                        // No read mode (until SD card interface?)
                        // FIXME: making an assumption about readiness :P
                        if (m_write) begin
                            state_d = WAIT_LCD;
                            lcd_data_in = m_data[7:0];
                            lcd_data_dcx = m_data[8];
                            lcd_start = 1'b1;
                        end else begin
                            // hack to allow RST toggling.
                            lcd_rst_d = m_address[0];
                            drdy_d = 1'b1;
                        end
                    end
                    CMD_TEX_LOAD: begin
                        if (m_write) begin
                            tram_waddr = m_address[13:0];
                            tram_write_data = m_data[3:0];
                            tram_write_en = 1'b1;
                        end else begin
                            // no readback.
                            data_d = 32'd0;
                            drdy_d = 1'b1;
                        end
                    end
                    CMD_TEXP_LOAD: begin
                        if (m_write) begin
                            tpram_waddr = m_address[7:0];
                            tpram_write_data = m_data[15:0];
                            tpram_write_en = 1'b1;
                        end else begin
                            // no readback.
                            data_d = 32'd0;
                            drdy_d = 1'b1;
                        end
                    end
                    CMD_SPRITE_META: begin
                        if (m_write) begin
                            smeta_waddr = m_address[6:0];
                            // texture ID is cuddled in the address.
                            smeta_write_data[39:32] = m_address[15:8];
                            // x, y offsets in Q8.8
                            smeta_write_data[31:0] = m_data;
                            smeta_write_en = 1'b1;
                            led_d[1] = 1'b1;
                        end else begin
                            // no readback.
                            data_d = 32'd0;
                            drdy_d = 1'b1;
                        end
                    end
                    CMD_CAST_FB: begin
                        if (m_write) begin
                            case (m_address)
                            31'd0: begin
                                map_pos_x_d = m_data[31:16];
                                map_pos_y_d = m_data[15:0];
                                camera_x_d = 9'd0;
                            end
                            31'd1: begin
                                turn_addr_d = m_data[6:0];
                                state_d = CAST_FB_START;
                                lcd_data_dcx = 1'b0;
                                lcd_data_in = 8'h2C; // RAMWR
                                lcd_start = 1'b1;
                                // prep state
                                dump_ready_d = 1'b1;
                                lcd_ready_d = 1'b1;
                                line_go_d = 1'b0;
                                pipe_done_d = 10'd0;
                                // kick render chain
                                sprite_start = 1'b1;
                                frame_cycle_d = 32'd0;
                            end
                            endcase
                        end else begin
                            // return cycle count of previously rendered frame
                            data_d = lframe_cycle_q;
                            drdy_d = 1'b1;
                        end
                    end
                endcase
            end else begin
                led_d[0] = 1'b1;
            end
          end
          CAST_FB_START: begin
              // wait for sprite transforms to complete.
              if (sprite_done) begin
                cast_start = 1'b1;
                state_d = CAST_FB;
              end
          end
          CAST_FB: begin
              if (cast_done) begin
                line_go_d = 1'b1;
                camera_x_d = camera_x_q + 1'b1;
              end

              if (line_go_q && dump_ready_q) begin
                line_write_start = 1'b1;
                line_go_d = 1'b0;
                dump_ready_d = 1'b0;
                // re-kick pipelined ray cast.
                if (camera_x_q != WIDTH) begin
                    cast_start = 1'b1;
                end
              end

              if (line_write_done) begin
                lcd_go_d = 1'b1;
              end

              if (lcd_go_q && lcd_ready_q) begin
                dump_ready_d = 1'b1;
                lcd_go_d = 1'b0;
                lcd_ready_d = 1'b0;
                lw_raddr_d = 8'd0;
                lcdstate_d = LCD_FB_DUMP;
              end

              if (lcd_done_q) begin
                lcd_ready_d = 1'b1;
                lcd_done_d = 1'b0;
              end

              // FIXME: race condition in this logic still, but I don't see it
              // offhand. At lower frame rates it's easy to start another
              // frame while the lcd writer is still going, which causes the
              // frame to snap at an offset.
              // at higher framerates + some delay here this doesn't seem to
              // happen.
              if (camera_x_q == WIDTH && !cast_busy && dump_ready_q && lcd_ready_q) begin
                pipe_done_d = pipe_done_q + 1'b1;
                if (&pipe_done_q) begin
                  lcd_data_dcx = 1'b0;
                  lcd_data_in = 8'h00; // NOP
                  lcd_start = 1'b1;
                  state_d = WAIT_LCD;
                  // hold timing of previous frame
                  lframe_cycle_d = frame_cycle_q;
                end
              end else begin
                pipe_done_d = 10'd0;
              end
          end
          WAIT_LCD: begin
            if (lcd_done) begin
                state_d = IDLE;
            end
          end
          default: state_d = IDLE;
        endcase
end

always @(posedge clk) begin
    if (rst) begin
        led_q <= 0;
        data_q <= 0;
        drdy_q <= 0;
    	state_q = 0;
        lcdstate_q = 0;
        map_pos_x_q <= 0;
        map_pos_y_q <= 0;
        lw_raddr_q <= 0;
        lw_base_raddr_q <= 0;
        camera_x_q <= 0;
        turn_addr_q <= 0;
        lcd_bcnt_q <= 0;
      end else begin
        state_q = state_d;
        lcdstate_q = lcdstate_d;
        data_q <= data_d;
        drdy_q <= drdy_d;
        led_q <= led_d;
        map_pos_x_q <= map_pos_x_d;
        map_pos_y_q <= map_pos_y_d;
        lw_raddr_q <= lw_raddr_d;
        lw_base_raddr_q <= lw_base_raddr_d;
        camera_x_q <= camera_x_d;
        turn_addr_q <= turn_addr_d;
        lcd_bcnt_q <= lcd_bcnt_d;
      end

      lcd_rst_q <= lcd_rst_d;
      dump_ready_q <= dump_ready_d;
      line_go_q <= line_go_d;
      lcd_done_q <= lcd_done_d;
      lcd_go_q <= lcd_go_d;
      lcd_ready_q <= lcd_ready_d;
      pipe_done_q <= pipe_done_d;
      frame_cycle_q <= frame_cycle_d;
      lframe_cycle_q <= lframe_cycle_d;
end

endmodule
