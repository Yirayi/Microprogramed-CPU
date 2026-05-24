`timescale 1ns / 1ps
// PS2_host_tx.v
// Sends a single byte from FPGA (PS/2 host) to PIC24 (PS/2 device).
// Intended use: send 0xF4 (Enable Scanning) each time the PIC24
// sends 0xAA (BAT Complete), completing the standard PS/2 handshake.
//
// PS/2 open-drain bus:
//   clk_oe=1  → FPGA pulls ps2_clk  LOW  (wired-AND with pullup)
//   data_oe=1 → FPGA pulls ps2_data LOW
//   oe=0      → FPGA releases line  → pullup restores HIGH
//
// Host-to-device 11-bit frame (device generates clock after inhibit):
//   Falling edge 0 : start bit (DATA=0, pre-asserted during inhibit)
//   Falling edges 1-8 : D0..D7 (LSB first)
//   Falling edge 9 : parity (odd)
//   Falling edge 10: stop  (host releases DATA → 1 via pullup)
//   After edge 10  : device pulls DATA low for one CLK = ACK
module PS2_host_tx (
    input  wire       clk,
    input  wire       rst,
    input  wire       send,        // 1-cycle pulse: start transmission
    input  wire [7:0] tx_byte,     // byte to send

    // Open-drain control outputs (connect to tristate logic in ALL_top)
    output reg        clk_oe,      // 1 = drive ps2_clk  LOW
    output reg        data_oe,     // 1 = drive ps2_data LOW

    // Raw PS/2 bus inputs (2-stage sync done internally)
    input  wire       ps2_clk_raw,
    input  wire       ps2_data_raw,

    output reg        busy,
    output reg        tx_done      // 1-cycle pulse on completion/timeout
);

// ── 2-stage synchroniser ──────────────────────────────────────────────────────
reg [1:0] clk_r, data_r;
always @(posedge clk or posedge rst) begin
    if (rst) begin clk_r <= 2'b11; data_r <= 2'b11; end
    else     begin
        clk_r  <= {clk_r[0],  ps2_clk_raw};
        data_r <= {data_r[0], ps2_data_raw};
    end
end
wire clk_s  = clk_r[1];
wire data_s = data_r[1];

// ── falling-edge detector ─────────────────────────────────────────────────────
reg clk_prev;
always @(posedge clk or posedge rst)
    if (rst) clk_prev <= 1'b1;
    else     clk_prev <= clk_s;

wire clk_fall = clk_prev & ~clk_s;

// ── states ────────────────────────────────────────────────────────────────────
localparam S_IDLE    = 3'd0;
localparam S_INHIBIT = 3'd1; // CLK + DATA pulled low >= 100 us
localparam S_START   = 3'd2; // release CLK, DATA stays low (start bit)
localparam S_BITS    = 3'd3; // device clocks in 11 bits via falling edges
localparam S_ACK     = 3'd4; // wait for device to pull DATA low (ACK)
localparam S_DONE    = 3'd5; // wait for bus idle, then signal tx_done

// 100 us at 100 MHz
localparam INHIBIT_CYCLES = 16'd10_000;
// 5 ms watchdog for S_BITS and S_ACK
localparam WATCHDOG_MAX   = 20'd500_000;

reg [2:0]  state;
reg [15:0] inh_cnt;
reg [19:0] wdog_cnt;
reg [3:0]  bit_cnt;  // counts falling edges in S_BITS (0..10)
// shift[8]=parity, shift[7:0]=tx_byte; shift[0]=D0 sent first (LSB)
reg [8:0]  shift;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state    <= S_IDLE;
        clk_oe   <= 1'b0; data_oe  <= 1'b0;
        busy     <= 1'b0; tx_done  <= 1'b0;
        inh_cnt  <= 16'd0; wdog_cnt <= 20'd0; bit_cnt <= 4'd0;
        shift    <= 9'd0;
    end else begin
        tx_done <= 1'b0;

        case (state)

        S_IDLE: begin
            clk_oe <= 1'b0; data_oe <= 1'b0; busy <= 1'b0;
            if (send) begin
                // odd parity: parity bit = ~(XOR of all data bits)
                shift   <= {~(^tx_byte), tx_byte};
                inh_cnt <= 16'd0;
                bit_cnt <= 4'd0;
                busy    <= 1'b1;
                state   <= S_INHIBIT;
            end
        end

        S_INHIBIT: begin
            clk_oe  <= 1'b1;   // hold CLK low (inhibit)
            data_oe <= 1'b1;   // hold DATA low (pre-assert start bit)
            if (inh_cnt < INHIBIT_CYCLES - 1)
                inh_cnt <= inh_cnt + 16'd1;
            else begin
                clk_oe   <= 1'b0;   // release CLK → pullup → device takes over
                wdog_cnt <= 20'd0;
                state    <= S_START;
            end
        end

        // One-cycle buffer: CLK is released, DATA still low (start bit).
        // Transition immediately to S_BITS; first clk_fall detected there.
        S_START: begin
            clk_oe  <= 1'b0;
            data_oe <= 1'b1;   // start bit
            state   <= S_BITS;
        end

        S_BITS: begin
            // Watchdog: if device never clocks us, abort
            if (clk_fall) begin
                wdog_cnt <= 20'd0;
                case (bit_cnt)
                    // Edges 0-8: start/D0-D7 just sampled; output next bit
                    4'd9: begin
                        // parity just sampled → release DATA for stop bit
                        data_oe <= 1'b0;
                        bit_cnt <= 4'd10;
                    end
                    4'd10: begin
                        // stop bit just sampled → wait for ACK
                        wdog_cnt <= 20'd0;
                        state    <= S_ACK;
                    end
                    default: begin  // bit_cnt 0..8
                        // data_oe=1 drives low (bit=0), data_oe=0 releases high (bit=1)
                        data_oe <= ~shift[bit_cnt];
                        bit_cnt <= bit_cnt + 4'd1;
                    end
                endcase
            end else begin
                if (wdog_cnt < WATCHDOG_MAX)
                    wdog_cnt <= wdog_cnt + 20'd1;
                else
                    state <= S_IDLE;  // device did not respond; abort
            end
        end

        S_ACK: begin
            // Device pulls DATA low as ACK for one CLK period
            if (~data_s) begin
                state <= S_DONE;
            end else if (wdog_cnt < WATCHDOG_MAX) begin
                wdog_cnt <= wdog_cnt + 20'd1;
            end else begin
                state <= S_DONE;  // timeout; still proceed to release bus
            end
        end

        S_DONE: begin
            // Wait for both lines to return HIGH (bus idle) then signal done
            if (clk_s && data_s) begin
                tx_done <= 1'b1;
                busy    <= 1'b0;
                state   <= S_IDLE;
            end
        end

        default: state <= S_IDLE;
        endcase
    end
end

endmodule
