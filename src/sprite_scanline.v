// module for culling and sorting sprites to be displayed on a particular
// scanline.

// This uses the pre-transformed sprite data to determine if a sprite scanline
// exists on the current line or not.
// It caches data for up to N sprites, which is then read by the line writer
// during the display routine.
// This module gets kicked off while the walls are being drawn.

// Note how this isn't generally optimized: this has to scan every possible
// sprite once per scanline, then sort, which is only consistently faster than
// the wall draw if there're < 128 sprites in a level.
//
// However, this is fine for this implementation since each sprite cull test
// can be done within a single cycle!
// A better one, and more closely matching the wolf3D engine, would have the
// sprite pre-transform sort sprites into map squares. The raycaster then logs
// which tiles it sees for each ray, which is used to more quickly cull
// sprites. It can also be used to improve ordering since map tiles can be
// examined from near-to-far, so you only have to sort sprites within
// a particular tile.

module sprite_scanline (
    input clk,
    input rst,

    input start,
    output reg done,

    input [8:0] x, // camera X position
    input [15:0] wall_z, // z buffer of casted wall
    
    // transformed sprite metadata
    output reg [6:0] stmeta_raddr,
    input [119:0] stmeta_read_data,

    // hook sorted registers into line writer
    input [2:0] sprite_addr,
    output reg [119:0] sprite_meta,
    output reg [2:0] sprite_count
);

localparam WIDTH = 320;

localparam IDLE = 0,
    CULL_FETCH = 1,
    CULL = 2;
reg [3:0] state_d, state_q;

reg [6:0] count_d, count_q;
reg [2:0] scount_d, scount_q;
// add an extra bit so we can do signed comparisons.
reg signed [15:0] camera_x_d, camera_x_q;

// FIXME:  use pointers instead and serve from stmeta_raddr.
reg [119:0] sprites [2:0];

reg save_meta;

always @(*) begin
    state_d = state_q;
    count_d = count_q;
    stmeta_raddr = count_q;
    camera_x_d = camera_x_q;
    save_meta = 1'b0;
    sprite_count = scount_q;
    scount_d = scount_q;
    done = 1'b0;

    case (state_q)
        IDLE: begin
            count_d = 0;
            if (start) begin
                state_d = CULL_FETCH;
                camera_x_d = x - 1'b1;
                scount_d = 3'd0;
            end
        end
        CULL_FETCH: begin
            // load the metadata from RAM
            // can remove this step once tested/understood better.
            state_d = CULL;
        end
        CULL: begin
            // First test is the wall Z depth cull.
            // Then, if camera X is within sprite X draw boundaries
            if ($signed(stmeta_read_data[111:96]) < wall_z
             && $signed(stmeta_read_data[111:96]) > 0
             && $signed(stmeta_read_data[31:16]) <= camera_x_q
             && $signed(stmeta_read_data[15:0]) >= camera_x_q
             ) begin
                // save the sprite info if it's visible
                save_meta = 1'b1;
                scount_d = scount_q + 1'b1;
             end
             count_d = count_q + 1'b1;
             if (count_q == 127 || scount_d == 8) begin
                 done = 1'b1;
                 state_d = IDLE;
             end else begin
                 state_d = CULL_FETCH;
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
    camera_x_q <= camera_x_d;
    scount_q <= scount_d;
    if (save_meta) begin
        sprites[count_q] <= stmeta_read_data;
    end
    sprite_meta <= sprites[sprite_addr];
end

endmodule
