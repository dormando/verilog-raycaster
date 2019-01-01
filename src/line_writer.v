// This module writes lines into a memory buffer, later to be blit to the
// screen.
// It was originally very simple; floors, ceilings, and sprites complicate it
// significantly.
// A few speedups and simplifications are possible:
// 1) mirror floor and ceiling writes (split the RAM into two modules for top
// and bottom half)
// 2) skip floor/ceiling calculations when drawing the wall :P
// 3) move some of the sprite logic (ie; x calculation) out into
// sprite_scanline.
module line_writer (
    input clk,
    input rst,

    input start,
    input [8:0] x,
    input [7:0] pixel, // color, now texture ID.
    input [39:0] height, // 39:32 height. 31:16 Q8.8 tex scale. 15:0 inverse dist
    input [6:0] tex_x, // texture X offset.
    input [15:0] floor_x,
    input [15:0] floor_y,
    input [15:0] pos_x,
    input [15:0] pos_y,

    // signal to ray module whether we're ready to run another line.
    output reg rdy,
    output reg done,

    // external LCD write reads from memory.
    input [RAM_ASIZE:0] ram_raddr,
    output [15:0] ram_read_data,

    // external mmap interface loads texture memory.
    input [13:0] tram_waddr,
    input [3:0] tram_write_data,
    input tram_write_en,
    // external mmap interface also loads texture palettes.
    input [7:0] tpram_waddr,
    input [15:0] tpram_write_data,
    input tpram_write_en,
    // sprites
    output reg sprscan_start,
    input sprscan_done,
    output reg [2:0] sprite_addr,
    input [119:0] sprite_meta,
    input [2:0] sprite_count
);

// TODO: Should be a configuration wire.
localparam HALF_HEIGHT = 8'd120;
localparam HEIGHT_MAX = 8'd239;
localparam RAM_ASIZE = 8;
localparam TEX_WIDTH = 32;
localparam TEX_SIZE = 11'd1024; // 32 * 32
localparam PAL_SIZE = 15; // should be 16 if I skip alpha channel for textures.
localparam FLOOR_OFFSET = 6144;
localparam CEILING_OFFSET = 7168;
localparam FLOOR_PAL = 90;
localparam CEILING_PAL = 105;

reg [3:0] state_d, state_q;
reg [7:0] count_d, count_q; // number of pixels filled
reg [7:0] color_d, color_q; // hold onto color value
reg [15:0] floor_x_d, floor_x_q;
reg [15:0] floor_y_d, floor_y_q;
reg [15:0] pos_x_d, pos_x_q;
reg [15:0] pos_y_d, pos_y_q;
reg [8:0] camera_x_d, camera_x_q;

// TODO: these lines are at most 8 bits (240 height)
// there's no reason to not also pre-calc the start/end values into the line
// height table, since the line height is never used.
reg [7:0] draw_start_d, draw_start_q;
reg [7:0] draw_end_d, draw_end_q;
reg [15:0] scale_d, scale_q;
reg [15:0] distwall_d, distwall_q;
reg [21:0] tex_offset_d, tex_offset_q; // Q13.8 -> 20:8 used for TRAM index.
reg [7:0] texp_offset_d, texp_offset_q;
reg [15:0] weight_d, weight_q;
reg [15:0] cfloor_x_d, cfloor_x_q;
reg [15:0] cfloor_y_d, cfloor_y_q;

// sprites
reg spr_rdy_d, spr_rdy_q;
reg [7:0] spr_texid_d, spr_texid_q;
reg signed [15:0] spr_screenx_d, spr_screenx_q;
reg signed [15:0] spr_height_d, spr_height_q;
reg signed [15:0] spr_starty_d, spr_starty_q;
reg signed [15:0] spr_endy_d, spr_endy_q;
reg signed [15:0] spr_idx_d, spr_idx_q;
reg signed [31:0] spr_iheight_d, spr_iheight_q;
// Q16.16 because I'm an idiot and it always should've been.
reg signed [31:0] spr_tex_x_d, spr_tex_x_q;
// whether an alpha pixel was found.
reg alpha_d, alpha_q;

// line RAM
reg [RAM_ASIZE:0] waddr_base_d, waddr_base_q;
reg [RAM_ASIZE:0] ram_waddr;
reg [15:0] ram_write_data;
reg ram_write_en;

// texture RAM
reg [13:0] tram_holdr_d, tram_holdr_q; // extra indirection for sprite writer.
wire [3:0] tram_read_data;
reg [13:0] tram_raddr;
wire [15:0] tpram_read_data;
reg [7:0] tpram_raddr;

simple_dual_ram #(.SIZE(16), .DEPTH((HEIGHT_MAX+1)*2)) line_ram (
    .wclk(clk),
    .waddr(ram_waddr),
    .write_data(ram_write_data),
    .write_en(ram_write_en),
    // read
    .rclk(clk),
    .raddr(ram_raddr),
    .read_data(ram_read_data)
);

// texture RAM module. holds 32x32 textures with up to 4 bit color.
// would be one fewer wire if mmap owned it, but harder to test bench.
// TODO: simple_dual_ram has equal sized read/write ports. mmap interface can
// write four bytes at once, but to avoid excess logic we're only loading
// one per command.

simple_dual_ram #(.SIZE(4), .DEPTH(16384)) texture_ram (
    .wclk(clk),
    .waddr(tram_waddr),
    .write_data(tram_write_data),
    .write_en(tram_write_en),
    // read
    .rclk(clk),
    .raddr(tram_raddr),
    .read_data(tram_read_data)
);

simple_dual_ram #(.SIZE(16), .DEPTH(256)) texture_pal_ram (
    .wclk(clk),
    .waddr(tpram_waddr),
    .write_data(tpram_write_data),
    .write_en(tpram_write_en),
    // read
    .rclk(clk),
    .raddr(tpram_raddr),
    .read_data(tpram_read_data)
);

// floor dist precalcs
reg [8:0] fd_addr;
wire [15:0] floordist;
floordist_rom floordist_rom (
    .clk(clk),
    .addr(fd_addr),
    .floordist(floordist)
);

// inverse sprite height
reg [8:0] iheight_addr;
wire[15:0] iheight;
iheight_rom iheight_rom (
    .clk(clk),
    .addr(iheight_addr),
    .iheight(iheight)
);

localparam IDLE = 0,
    FILLING = 1,
    FILL_PRECALC = 2,
    FILL_PRECALC2 = 3,
    FILL_PRECALC3 = 4,
    CHECK_PAL = 5,
    SPRITE_START = 6,
    SPRITE_DRAW = 7,
    SPRITE_CALCX = 8,
    SPRITE_CALCX2 = 9,
    SPRITE_FINDPIXEL = 10,
    SPRITE_LOOKUP = 11,
    SPRITE_PAL = 12,
    SPRITE_FILL = 13,
    FINISH = 14;

initial begin
    draw_end_q = 16'd0;
    draw_start_q = 16'd0;
    color_q = 8'd0;
    count_q = 8'd0;
end

always @(*) begin
    state_d = state_q;
    count_d = count_q;
    camera_x_d = camera_x_q;
    draw_start_d = draw_start_q;
    draw_end_d = draw_end_q;
    scale_d = scale_q;
    tex_offset_d = tex_offset_q;
    waddr_base_d = waddr_base_q;
    ram_waddr = count_q + waddr_base_q;
    ram_write_en = 1'b0;
    ram_write_data = 8'd0;
    rdy = 0;
    done = 0;
    color_d = color_q;
    tram_raddr = tex_offset_q[21:8];
    tpram_raddr = 0;
    fd_addr = count_q;
    floor_x_d = floor_x_q;
    floor_y_d = floor_y_q;
    pos_x_d = pos_x_q;
    pos_y_d = pos_y_q;
    distwall_d = distwall_q;
    weight_d = weight_q;
    cfloor_x_d = cfloor_x_q;
    cfloor_y_d = cfloor_y_q;
    texp_offset_d = texp_offset_q;
    // sprites
    sprscan_start = 1'b0;
    spr_rdy_d = spr_rdy_q;
    sprite_addr = 3'b0;
    iheight_addr = 9'd0;
    spr_texid_d = spr_texid_q;
    spr_screenx_d = spr_screenx_q;
    spr_height_d = spr_height_q;
    spr_starty_d = spr_starty_q;
    spr_endy_d = spr_endy_q;
    spr_iheight_d = spr_iheight_q;
    spr_tex_x_d = spr_tex_x_q;
    spr_idx_d = spr_idx_q;
    alpha_d = alpha_q;
    tram_holdr_d = tram_holdr_q;

    // can happen anytime, so log it outside of the state machine.
    if (sprscan_done) begin
        spr_rdy_d = 1'b1;
    end

    case (state_q)
        IDLE: begin
            if (start) begin
                state_d = FILL_PRECALC;
                count_d = 0;
                color_d = pixel;
                /*
                * drawStart = -height / 2 + HALF_HEIGHT;
                * drawEnd = height / 2 + HALF_HEIGHT
                * min(start, 0)
                * max(end, HEIGHT)
                */
                draw_start_d = ( (~(height[39:32] >> 1)) + 8'd1 ) + HALF_HEIGHT;
                draw_end_d = ( height[39:32] >> 1 ) + HALF_HEIGHT;
                scale_d = height[31:16];
                distwall_d = height[15:0];
                floor_x_d = floor_x;
                floor_y_d = floor_y;
                pos_x_d = pos_x;
                pos_y_d = pos_y;
                // always start with the bottom texture pixel.
                // replace the TEX_SIZE "mul" which is getting turned into
                // a shift anyway.
                tex_offset_d[21:8] = TEX_SIZE * (pixel[3:0] - 1'b1) + (tex_x << 5);
                tex_offset_d[7:0] = 8'd0;
                texp_offset_d = PAL_SIZE * (pixel[3:0] - 1'b1);
                // kick off sprite sorting while we do the wall.
                spr_rdy_d = 1'b0;
                sprscan_start = 1'b1;
                camera_x_d = x - 1'b1;
            end else begin
                rdy = 1'b1;
            end
        end
        FILL_PRECALC: begin
            weight_d = trunc_fixed_mul(floordist * distwall_q);
            state_d = FILL_PRECALC2;
        end
        FILL_PRECALC2: begin
            // bits 7:3 are the final texture coordinates
            cfloor_x_d = trunc_fixed_mul(weight_q * floor_x_q) + trunc_fixed_mul((16'h01_00 - weight_q) * pos_x_q);
            cfloor_y_d = trunc_fixed_mul(weight_q * floor_y_q) + trunc_fixed_mul((16'h01_00 - weight_q) * pos_y_q);
            state_d = FILL_PRECALC3;
        end
        FILL_PRECALC3: begin
		    // FIXME: Can remove this cycle if adding a bit more to previous
            // cycles and filling tram_raddr above.
            if (count_q < draw_start_q) begin
                tram_raddr = CEILING_OFFSET + (cfloor_x_q[7:3] << 5) + cfloor_y_q[7:3];
            end else if (count_q > draw_end_q) begin
                // override the texture RAM lookup if we're casting to the
                // floor.
                tram_raddr = FLOOR_OFFSET + (cfloor_x_q[7:3] << 5) + cfloor_y_q[7:3];
            end
            state_d = CHECK_PAL;
        end
        CHECK_PAL: begin
            tpram_raddr = texp_offset_q + tram_read_data;
            if (count_q < draw_start_q) begin
                tpram_raddr = CEILING_PAL + tram_read_data;
            end else if (count_q > draw_end_q) begin
                tpram_raddr = FLOOR_PAL + tram_read_data;
            end
            state_d = FILLING;
        end
        FILLING: begin
            count_d = count_q + 1'b1;
            if (count_q < draw_start_q) begin
                // ceiling gets normal color.
                ram_write_data = tpram_read_data;
            end else if (count_q >= draw_start_q && count_q <= draw_end_q) begin
                // if "side", darken the color
                // RGB 565
                // FIXME: function.
                if (color_q[7]) begin
                    ram_write_data[15:11] = tpram_read_data[15:11] >> 1;
                    ram_write_data[10:5] = tpram_read_data[10:5] >> 1;
                    ram_write_data[4:0] = tpram_read_data[4:0] >> 1;
                end else begin
                    ram_write_data = tpram_read_data;
                end
                tex_offset_d = tex_offset_q + scale_q;
            end else if (count_q > draw_end_q) begin
                // floor, darken color.
                ram_write_data[15:11] = tpram_read_data[15:11] >> 1;
                ram_write_data[10:5] = tpram_read_data[10:5] >> 1;
                ram_write_data[4:0] = tpram_read_data[4:0] >> 1;
            end
            ram_write_en = 1'b1;

            if (count_q == 239) begin
                state_d = SPRITE_START;
            end else begin
                count_d = count_q + 1'b1;
                state_d = FILL_PRECALC;
            end
        end
        SPRITE_START: begin
            if (spr_rdy_q) begin
                if (sprite_count != 3'd0) begin
                    state_d = SPRITE_DRAW;
                end else begin
                    state_d = FINISH;
                end
            end
        end
        SPRITE_DRAW: begin
            // 1) load in relevant sprite meta
            spr_texid_d = sprite_meta[119:112];
            spr_screenx_d = sprite_meta[95:80];
            spr_height_d = sprite_meta[79:64];
            spr_starty_d = sprite_meta[63:48];
            spr_endy_d = sprite_meta[47:32];
            iheight_addr = spr_height_d[8:0];
            // test data
            /*spr_texid_d = 8'd8;
            spr_screenx_d = 16'd120;
            spr_height_d = 16'd60;
            spr_starty_d = 16'd90;
            spr_endy_d = 16'd150;
            iheight_addr = 16'd60;*/

            state_d = SPRITE_CALCX;
        end
        SPRITE_CALCX: begin
            // 2) calculate tex_x
            spr_tex_x_d = ((spr_height_q >> 1) - (spr_screenx_q - camera_x_q)) << 16;
            // Q8.8 - need to convert to Q16.16
            spr_iheight_d = iheight << 8;
            state_d = SPRITE_CALCX2;
        end
        SPRITE_CALCX2: begin
            // we only need Q5.0 out of here
            spr_tex_x_d = trunc_fixed_mul32(spr_tex_x_q * spr_iheight_q);
            // 3) seed tex_offset_d and texp_offset_d
            tex_offset_d[21:8] = (spr_texid_q << 10) + (spr_tex_x_d[20:16] << 5);
            tex_offset_d[7:0] = 8'd0;
            // FIXME: lookup table. (or round  it to 16 and shift)
            texp_offset_d = PAL_SIZE * spr_texid_q;
            // 4) adjust draw boundaries
            // seed counter
            if (spr_starty_q < 0) begin
                spr_starty_d = 0;
                // how far we've indexed into the "scaled" sprite.
                spr_idx_d = (~spr_starty_q) + 1'b1;
                count_d = 0;
            end else begin
                spr_idx_d = 0;
                count_d = spr_starty_q;
            end
            if (spr_endy_q > HEIGHT_MAX-1) begin
                spr_endy_d = HEIGHT_MAX-1;
            end
            // switch to draw state
            state_d = SPRITE_FINDPIXEL;
        end
        SPRITE_FINDPIXEL: begin
            // draaaaaaaaaaaaaaaaawwww
            // sadly the Q16.16 multiplication is so large this violates
            // timing, so we add the extra cycle of indirection.
            // this could be removed if we pre-multiply to find the bottom of
            // the sprite and then add the scale offset the same way as
            // scaling a wall texture.
            tram_holdr_d = (trunc_fixed_mul32((spr_idx_q << 16) * spr_iheight_q) >> 16) + tex_offset_q[21:8];
            state_d = SPRITE_LOOKUP;
        end
        SPRITE_LOOKUP: begin
            tram_raddr = tram_holdr_q;
            state_d = SPRITE_PAL;
        end
        SPRITE_PAL: begin
            if (tram_read_data == 4'd15) begin
                alpha_d = 1'b1;
            end else begin
                alpha_d = 1'b0;
                tpram_raddr = texp_offset_q + tram_read_data;
            end
            state_d = SPRITE_FILL;
        end
        SPRITE_FILL: begin
            count_d = count_q + 1'b1;
            spr_idx_d = spr_idx_q + 1'b1;
            // alpha test. skip transparent sprite pixels.
            if (!alpha_q) begin
                ram_write_data = tpram_read_data;
                ram_write_en = 1'b1;
            end
            if (count_q == spr_endy_q) begin
                state_d = FINISH;
            end else begin
                state_d = SPRITE_FINDPIXEL;
            end
        end
        FINISH: begin
            done = 1'b1;
            if (waddr_base_q == 9'd0) begin
                waddr_base_d = 9'd240;
            end else begin
                waddr_base_d = 9'd0;
            end
            state_d = IDLE;
        end
    endcase
end

always @(posedge clk) begin
    if (rst) begin
        state_q = IDLE;
        count_q <= 0;
        draw_start_q <= 0;
        draw_end_q <= 0;
        color_q <= 0;
        tex_offset_q <= 0;
        waddr_base_q <= 0;
    end else begin
        state_q = state_d;
        count_q <= count_d;
        draw_start_q <= draw_start_d;
        draw_end_q <= draw_end_d;
        color_q <= color_d;
        tex_offset_q <= tex_offset_d;
        waddr_base_q <= waddr_base_d;
    end

    scale_q <= scale_d;
    floor_x_q <= floor_x_d;
    floor_y_q <= floor_y_d;
    pos_x_q <= pos_x_d;
    pos_y_q <= pos_y_d;
    distwall_q <= distwall_d;
    weight_q <= weight_d;
    cfloor_x_q <= cfloor_x_d;
    cfloor_y_q <= cfloor_y_d;
    texp_offset_q <= texp_offset_d;
    spr_rdy_q <= spr_rdy_d;
    camera_x_q <= camera_x_d;
    spr_texid_q <= spr_texid_d;
    spr_screenx_q <= spr_screenx_d;
    spr_height_q <= spr_height_d;
    spr_starty_q <= spr_starty_d;
    spr_endy_q <= spr_endy_d;
    spr_tex_x_q <= spr_tex_x_d;
    spr_iheight_q <= spr_iheight_d;
    spr_idx_q <= spr_idx_d;
    alpha_q <= alpha_d;
    tram_holdr_q <= tram_holdr_d;
end

function signed [15:0] trunc_fixed_mul(input signed [31:0] mulres);
  trunc_fixed_mul = mulres[23:8];
endfunction

function signed [31:0] trunc_fixed_mul32(input signed [63:0] mulres);
  trunc_fixed_mul32 = mulres[47:16];
endfunction

endmodule
