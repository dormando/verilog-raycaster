/*
 This module adapted from reg_interface.luc from embedded micro.
 // 1 CMD byte:
 // 5:0 CMD - up to 64 different GPU commands
 // 6 inc it
 // 7 wr bit
 // 16bit data packet count (could possibly encode)
 // 32bit addr
 // 32bit data [up to repeat count]
 // is zero an acceptable count?
 // NOTE: Not exposing the run count
 // if inc -> addr += 4 per run
 */

module mmap_protocol #(
      parameter CLK_FREQ = 50000000
    )(
    input clk,
    input rst,

    // Serial RX
    input [7:0] rx_data,
    input new_rx_data,

    // Serial TX
    output reg [7:0] tx_data,
    output reg new_tx_data,
    input tx_busy,

    // Master interface
    output reg m_new_cmd,
    output reg m_write,
    output [5:0] m_cmd,
    output [31:0] m_address,
    output [31:0] m_data,

    // Slave interface
    input [31:0] s_data,
    input s_drdy
);

localparam STATE_SIZE = 4;
localparam IDLE = 0,
    GET_ADDR = 1,
    WRITE = 2,
    REQUEST_WRITE = 3,
    REQUEST_READ = 4,
    WAIT_READ = 5,
    READ_RESULT = 6,
    GET_PCOUNT = 7;

reg [STATE_SIZE-1:0] state_d, state_q;

reg [5:0] cmd_d, cmd_q;
reg [15:0] addr_ct_d, addr_ct_q;
reg [1:0] byte_ct_d, byte_ct_q;
reg inc_d, inc_q; // address increment bit
reg wr_d, wr_q;  // write request bit
reg [$clog2(CLK_FREQ/2):0] timeout_d, timeout_q; // timeout counter
//reg [31:0] timeout; // timeout counter
reg [31:0] addr_d, addr_q; // saved address
reg [31:0] data_d, data_q; // saved data
//reg [1:0] delay; // hmm

assign m_data = data_q;
assign m_cmd = cmd_q;
assign m_address = addr_q;

always @(*) begin
    // incremnt timeout, or reset if new data is avilable.
    timeout_d = timeout_q + 1'b1;
    if (new_rx_data)
        timeout_d = 0;

    // defaults.
    m_new_cmd = 0;
    m_write = 0;
    tx_data = 7'bx;
    wr_d = wr_q;
    inc_d = inc_q;
    state_d = state_q;
    byte_ct_d = byte_ct_q;
    data_d = data_q;
    addr_d = addr_q;
    addr_ct_d = addr_ct_q;
    cmd_d = cmd_q;
    new_tx_data = 0;

    case (state_q)
        IDLE: begin
            timeout_d = 0;
            byte_ct_d = 0;

            if (new_rx_data) begin
                wr_d = rx_data[7];
                inc_d = rx_data[6];
                cmd_d = rx_data[5:0];
                state_d = GET_PCOUNT;
            end
        end
        GET_PCOUNT: begin
            // number of four byte data packets to read
            if (new_rx_data) begin
                addr_ct_d = {rx_data, addr_ct_q[15-:8]};
                byte_ct_d = byte_ct_q + 1'b1;
                if (byte_ct_q == 2'd1) begin
                    byte_ct_d = 2'd0;
                    state_d = GET_ADDR;
                end
            end
        end
        GET_ADDR: begin
            if (new_rx_data) begin
                addr_d = {rx_data, addr_q[31-:24]}; // shift in a byte
                byte_ct_d = byte_ct_q + 1'b1;
                if (byte_ct_q == 2'd3) begin
                    if (wr_q) begin
                        state_d = WRITE;
                    end else begin
                        state_d = REQUEST_READ;
                    end
                end
            end
        end
        WRITE: begin
            if (new_rx_data) begin
                data_d = {rx_data, data_q[31-:24]};
                byte_ct_d = byte_ct_q + 1'b1;
                if (byte_ct_q == 2'd3) begin
                    state_d = REQUEST_WRITE;
                end
            end
        end
        REQUEST_WRITE: begin
            m_new_cmd = 1'b1;
            m_write = 1'b1;
            addr_ct_d = addr_ct_q - 1'b1;
            if (addr_ct_q == 1'b0) begin
                state_d = IDLE;
            end else begin
                state_d = WRITE;
                if (inc_q) begin
                    addr_d = addr_q + 1'd1;
                end
            end
        end
        REQUEST_READ: begin
            m_new_cmd = 1'b1;
            m_write = 0;
            //delay <= {2{1'b1}};
            if (s_drdy) begin
                byte_ct_d = 2'd0;
                data_d = s_data;
                state_d = READ_RESULT;
            end else begin
                state_d = WAIT_READ;
            end
        end
        WAIT_READ: begin
            if (s_drdy) begin
                byte_ct_d = 2'd0;
                data_d = s_data;
                state_d = READ_RESULT;
            end
        end
        READ_RESULT: begin
            timeout_d = 0;
            //delay <= delay - 1'b1;
            //if (!tx_busy && delay == {2{1'b0}}) begin
            if (!tx_busy) begin
                     //delay <= {2{1'b1}};
                tx_data = data_q[7:0];
                data_d = data_q >> 8;
                new_tx_data = 1'b1;
                byte_ct_d = byte_ct_q + 1'b1;
                if (byte_ct_q == 2'd3) begin
                  addr_ct_d = addr_ct_q - 1'b1;
                  if (addr_ct_q == 0) begin
                      state_d = IDLE;
                  end else begin
                      state_d = REQUEST_READ;
                      if (inc_q) begin
                          addr_d = addr_q + 1'd1;
                      end
                  end
                end
            end
        end
        default: state_d = IDLE;
    endcase

    if (&timeout_q) begin
        state_d = IDLE;
    end
end

always @(posedge clk) begin
    if (rst) begin
        state_q <= IDLE;
        addr_ct_q <= 0;
        byte_ct_q <= 0;
        inc_q <= 0;
        wr_q <= 0;
        data_q <= 0;
        addr_q <= 0;
        cmd_q <= 0;
        //delay_q <= 0;
    end else begin
        timeout_q <= timeout_d;
        //m_new_cmd_q <= m_new_cmd_d;
        //m_write_q <= m_write_d;
        cmd_q <= cmd_d;
        wr_q <= wr_d;
        inc_q <= inc_d;
        state_q <= state_d;
        data_q <= data_d;
        addr_q <= addr_d;
        byte_ct_q <= byte_ct_d;
        addr_ct_q <= addr_ct_d;
    end
end

endmodule
