// sprite transformation pre-pass module.
// at the start of a frame, walks each sprite meta and writes out data
// transformed to the camera view.
// not exactly optimized; walks *all* sprites vs ones just available in frame.
// a much better algo would be to organize sprites into linked list buckets
// per map square. Then take a log of visited tiles during the ray cast and
// use that to index into squares.
//
// however, linked lists in raw verilog are time consuming for me to write, so
// I will do that as an optimization pass later (perhaps for a different
// engine).

// This module operates in Q16.16, though most lookup tables are some form of
// 16bit (Q8.8, Q4.12, etc). Otherwise a lot of the math doesn't work out.
module sprite (
    input clk,
    input rst,

    input start,
    output reg done,
    // turn data
    input [79:0] angle,
    input [15:0] map_pos_x,
    input [15:0] map_pos_y,
    
    // mmap_interface writes sprite metadata
    input [6:0] smeta_waddr,
    input [39:0] smeta_write_data,
    input smeta_write_en,
    // sprite scanline culler reads transformed data.
    input [6:0] stmeta_raddr,
    output [119:0] stmeta_read_data
);

localparam HEIGHT = 240,
    WIDTH = 320,
    HALF_HEIGHT = 120,
    HALF_WIDTH = 160,
    SPRITE_COUNT = 128;

// RAM module for x/y/tex meta
reg [6:0] smeta_raddr;
wire [39:0] smeta_read_data;

// 8bit sprite texture, x, y 16bit
simple_dual_ram #(.SIZE(40), .DEPTH(SPRITE_COUNT)) smeta_ram (
    .wclk(clk),
    .waddr(smeta_waddr),
    .write_data(smeta_write_data),
    .write_en(smeta_write_en),
    // read
    .rclk(clk),
    .raddr(smeta_raddr),
    .read_data(smeta_read_data)
);

// RAM module for transformed meta
reg [6:0] stmeta_waddr;
reg [119:0] stmeta_write_data;
reg stmeta_write_en;
// read wires?

simple_dual_ram #(.SIZE(120), .DEPTH(SPRITE_COUNT)) stmeta_ram (
    .wclk(clk),
    .waddr(stmeta_waddr),
    .write_data(stmeta_write_data),
    .write_en(stmeta_write_en),
    // read
    .rclk(clk),
    .raddr(stmeta_raddr),
    .read_data(stmeta_read_data)
);

// inverse distance rom (for transformY)
reg [9:0] idist_addr;
wire [15:0] idist;
idist_rom idist_rom (
    .clk(clk),
    .addr(idist_addr),
    .idist(idist)
);

reg [4:0] state_d, state_q;
reg [4:0] next_state_d, next_state_q;
localparam IDLE = 0,
    MULTIPLY = 1,
    TRANSFORM_START = 2,
    TRANSFORMX_1 = 3,
    TRANSFORMX_2 = 4,
    TRANSFORMX_3 = 5,
    TRANSFORMX_4 = 6,
    TRANSFORMY_1 = 7,
    TRANSFORMY_2 = 8,
    TRANSFORMY_3 = 9,
    SPRITE_SCREENX = 10,
    SPRITE_SCREENX_2 = 11,
    SPRITE_SCREENX_3 = 12,
    SPRITE_HEIGHT = 13,
    SPRITE_DRAWBOUNDS = 14,
    SAVE_TRANSFORMS = 15;

// shared multiplier
reg signed [31:0] mul_res_d, mul_res_q;
reg signed [31:0] mul_arg1_d, mul_arg1_q;
reg signed [31:0] mul_arg2_d, mul_arg2_q;
reg signed [31:0] math_hold_d, math_hold_q;

// turn angle data
reg signed [31:0] dirx_d, dirx_q;
reg signed [31:0] diry_d, diry_q;
reg signed [31:0] planex_d, planex_q;
reg signed [31:0] planey_d, planey_q;
reg signed [31:0] invdet_d, invdet_q;

reg signed [31:0] map_posx_d, map_posx_q;
reg signed [31:0] map_posy_d, map_posy_q;

// registers for temp sprite transform meta
reg signed [31:0] spritex_d, spritex_q;
reg signed [31:0] spritey_d, spritey_q;
reg signed [31:0] transformx_d, transformx_q;
reg signed [31:0] transformy_d, transformy_q;
reg signed [15:0] sprite_screenx_d, sprite_screenx_q;
reg signed [15:0] sprite_height_d, sprite_height_q;
reg signed [15:0] draw_starty_d, draw_starty_q;
reg signed [15:0] draw_endy_d, draw_endy_q;
reg signed [15:0] draw_startx_d, draw_startx_q;
reg signed [15:0] draw_endx_d, draw_endx_q;

reg [6:0] count_d, count_q;

always @(*) begin
    state_d = state_q;
    next_state_d = next_state_q;
    count_d = count_q;
    smeta_raddr = count_q;
    stmeta_waddr = count_q;
    stmeta_write_data = 120'd0;
    stmeta_write_en = 1'b0;
    idist_addr = 0;
    done = 1'b0;
    // multiplier
    mul_res_d = mul_res_q;
    mul_arg1_d = mul_arg1_q;
    mul_arg2_d = mul_arg2_q;
    math_hold_d = math_hold_q;
    next_state_d = next_state_q;
    // angle data
    dirx_d = dirx_q;
    diry_d = diry_q;
    planex_d = planex_q;
    planey_d = planey_q;
    invdet_d = invdet_q;
    map_posx_d = map_posx_q;
    map_posy_d = map_posy_q;
    // temp sprite metadata.
    spritex_d = spritex_q;
    spritey_d = spritey_q;
    transformx_d = transformx_q;
    transformy_d = transformy_q;
    sprite_screenx_d = sprite_screenx_q;
    sprite_height_d = sprite_height_q;
    draw_starty_d = draw_starty_q;
    draw_endy_d = draw_endy_q;
    draw_startx_d = draw_startx_q;
    draw_endx_d = draw_endx_q;

    case (state_q)
        IDLE: begin
            if (start) begin
                // hold angle data. convert Q8.8 -> Q16.16
                // FIXME: fucking up the sign extension!
                // dirx_d is becoming a huge number instead of -1
                dirx_d[31:16] = angle[79:64];
                dirx_d[15:0] = 0;
                diry_d[31:16] = angle[63:48];
                diry_d[15:0] = 0;
                planex_d[31:16] = angle[47:32];
                planex_d[15:0] = 0;
                planey_d[31:16] = angle[31:16];
                planey_d[15:0] = 0;
                invdet_d[31:16] = angle[15:0];
                invdet_d[15:0] = 0;

                map_posx_d = map_pos_x <<< 8;
                map_posy_d = map_pos_y <<< 8;
                count_d = 0;

                state_d = TRANSFORM_START;
            end
            // ensure smeta_ram is ready with the first value on start
            smeta_raddr = 0;
        end
        MULTIPLY: begin
            mul_res_d = trunc_fixed_mul(mul_arg1_q * mul_arg2_q);
            state_d = next_state_q;
        end
        // for each sprite, find its X/Y positions, as well as
        // height/width.
        TRANSFORM_START: begin
            // Finish transforming signed Q8.8's to Q16.16
            dirx_d = dirx_q >>> 8;
            diry_d = diry_q >>> 8;
            planex_d = planex_q >>> 8;
            planey_d = planey_q >>> 8;
            invdet_d = invdet_q >>> 8;

            // sprite position relative to camera.
            spritex_d = (smeta_read_data[31:16] << 8) - map_posx_q;
            spritey_d = (smeta_read_data[15:0] << 8) - map_posy_q;
            // rest of smeta is the sprite texture id. we'll simply write
            // directly from smeta_read_data when done with the transform.
            // also, could seed the multiplier here, but lets keep the code
            // more clear.
            state_d = TRANSFORMX_1;
        end
        TRANSFORMX_1: begin
            // transformX = invDet * (dirY * spriteX - dirX * spriteY);
            // need to set up several multiplications, bouncing through shared
            // logic.
            mul_arg1_d = diry_q;
            mul_arg2_d = spritex_q;
            next_state_d = TRANSFORMX_2;
            state_d = MULTIPLY;
        end
        TRANSFORMX_2: begin
            // effectively registers :)
            math_hold_d = mul_res_q;
            mul_arg1_d = dirx_q;
            mul_arg2_d = spritey_q;
            next_state_d = TRANSFORMX_3;
            state_d = MULTIPLY;
        end
        TRANSFORMX_3: begin
            // this is pretty much "bizarro assembler".
            // final multiplication for tX is invdet * (stuff so far)
            mul_arg1_d = invdet_q;
            mul_arg2_d = math_hold_q - mul_res_q;
            next_state_d = TRANSFORMX_4;
            state_d = MULTIPLY;
        end
        TRANSFORMX_4: begin
            // I did create a tiny cpu core, assembler, etc which I'd intended
            // to use here to avoid exploding logic and reuse a multiplier.
            transformx_d = mul_res_q;
            // now again for tY!
            mul_arg1_d = ((~planey_q) + 1'b1); // negate
            mul_arg2_d = spritex_q;
            next_state_d = TRANSFORMY_1;
            state_d = MULTIPLY;
        end
        TRANSFORMY_1: begin
            // The core used a lot of LUT's, even after aggressive area
            // optimization. Compared to simply sharing the multiplier, the
            // logic here wasn't long enough to justify using it.
            math_hold_d = mul_res_q;
            mul_arg1_d = planex_q;
            mul_arg2_d = spritey_q;
            next_state_d = TRANSFORMY_2;
            state_d = MULTIPLY;
        end
        TRANSFORMY_2: begin
            // It's also (surprisingly) a lot more clear to read what this is
            // doing vs jumping around with an amateur assembly file.
            // If it gets too complex, there are enough resources to use a few
            // more multipliers an simplify it again.
            mul_arg1_d = invdet_q;
            mul_arg2_d = math_hold_q + mul_res_q;
            next_state_d = TRANSFORMY_3;
            state_d = MULTIPLY;
        end
        TRANSFORMY_3: begin
            // using two multipliers would cut these states in half, for
            // example. since this isn't too long and I'd like to port this
            // engine to smaller FPGA's, we'll try to stick with this.
            transformy_d = mul_res_q;
            // next up: spriteScreenX = int((w / 2) * (1 + transformX / transformY))
            // to avoid the division, we have a Q4.12 inversion of transformY.
            // taken from a Q5.5 out of transformY.
            idist_addr = mul_res_q[21:10];
            state_d = SPRITE_SCREENX;
        end
        SPRITE_SCREENX: begin
            mul_arg1_d = transformx_q;
            mul_arg2_d = idist << 8; // lookup table stored Q8.8
            next_state_d = SPRITE_SCREENX_2;
            state_d = MULTIPLY;
        end
        SPRITE_SCREENX_2: begin
            mul_arg1_d = HALF_WIDTH << 16;
            // Add a Q16.16 1.0 to the previous result.
            mul_arg2_d = 31'h0001_0000 + mul_res_q;
            next_state_d = SPRITE_SCREENX_3;
            state_d = MULTIPLY;
            // we need the inverse distance again to find sprite height.
            math_hold_d = mul_arg2_q;
        end
        SPRITE_SCREENX_3: begin
            sprite_screenx_d = mul_res_q >>> 16;
            // next up is sprite height:
            // spriteHeight = abs(int(h / (transformY)))
            mul_arg1_d = HEIGHT << 16;
            mul_arg2_d = math_hold_q;
            next_state_d = SPRITE_HEIGHT;
            state_d = MULTIPLY;
        end
        SPRITE_HEIGHT: begin
            // invert if negative.
            // convert back to normal 16bit signed integer.
            if (mul_res_q[31]) begin
                sprite_height_d = (~mul_res_q) + 1'b1 >> 16;
            end else begin
                sprite_height_d = mul_res_q >> 16;
            end
            // width and height are identical; stick to one register.
            state_d = SPRITE_DRAWBOUNDS;
        end
        SPRITE_DRAWBOUNDS: begin
            // find the bounds, but we don't actually want to use them
            // out of screen range (< 0 or > WIDTH)
            draw_starty_d = (~(sprite_height_q >> 1)) + 1'b1 + HALF_HEIGHT;
            draw_endy_d = (sprite_height_q >> 1) + HALF_HEIGHT;
            draw_startx_d = (~(sprite_height_q >> 1)) + 1'b1 + sprite_screenx_q;
            draw_endx_d = (sprite_height_q >> 1) + sprite_screenx_q;
            state_d = SAVE_TRANSFORMS;
        end
        SAVE_TRANSFORMS: begin
            // could have done this in the previous cycle, but less clear.
            stmeta_write_data = {smeta_read_data[39:32], transformy_q[23:8], sprite_screenx_q, sprite_height_q, draw_starty_q, draw_endy_q, draw_startx_q, draw_endx_q};
            stmeta_write_en = 1'b1;
            count_d = count_q + 1'b1;
            if (count_q == SPRITE_COUNT-1) begin
                done = 1'b1;
                state_d = IDLE;
            end else begin
                // FIXME: REVERT AFTER TESTING!
                state_d = TRANSFORM_START;
                //state_d = IDLE;
            end
        end
    endcase
end

always @(posedge clk) begin
    if (rst) begin
        state_q <= IDLE;
    end else begin
        state_q <= state_d;
    end

    count_q <= count_d;
    // multiplier
    mul_res_q <= mul_res_d;
    mul_arg1_q <= mul_arg1_d;
    mul_arg2_q <= mul_arg2_d;
    math_hold_q <= math_hold_d;
    next_state_q <= next_state_d;
    // angle data
    dirx_q <= dirx_d;
    diry_q <= diry_d;
    planex_q <= planex_d;
    planey_q <= planey_d;
    invdet_q <= invdet_d;
    map_posx_q <= map_posx_d;
    map_posy_q <= map_posy_d;
    // temp sprite metadata.
    spritex_q <= spritex_d;
    spritey_q <= spritey_d;
    transformx_q <= transformx_d;
    transformy_q <= transformy_d;
    sprite_screenx_q <= sprite_screenx_d;
    sprite_height_q <= sprite_height_d;
    draw_starty_q <= draw_starty_d;
    draw_endy_q <= draw_endy_d;
    draw_startx_q <= draw_startx_d;
    draw_endx_q <= draw_endx_d;
end

// see cast_ray.v
// multiplies out to 64bit, then returns Q16.16 middle.
function signed [31:0] trunc_fixed_mul(input signed [63:0] mulres);
  trunc_fixed_mul = mulres[47:16];
endfunction

endmodule
