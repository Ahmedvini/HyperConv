// ----------------------------------------------------------------------------
// HyperConv - board_top.v
// Thin, board-independent top for a standalone self-test bitstream.
// Wraps selftest_top with a clock buffer and exposes only a clock, a reset
// button, and 4 status LEDs -- the minimum a board needs.
//
// To target a specific board you only touch:
//   1. the clock: single-ended (default, BUFG) vs differential (IBUFDS) below
//   2. reset polarity: active-low button (default) vs active-high
//   3. synth/board/board.xdc: package pins + I/O standards + create_clock
//
// LED bus mapping (led[3:0]):
//   led[0] = pass       (steady on  = all outputs matched the golden result)
//   led[1] = fail       (steady on  = a mismatch was detected)
//   led[2] = done       (steady on  = frame finished)
//   led[3] = heartbeat  (blinks     = clock + logic alive)
// ----------------------------------------------------------------------------
`timescale 1ns / 1ps

module board_top #(
    parameter HB_BIT   = 25,                // heartbeat: ~1.5 Hz at 100 MHz
    parameter IMG_FILE = "img.hex",
    parameter KER_FILE = "kernel.hex",
    parameter EXP_FILE = "expected.hex"
) (
    input  wire       clk_pin,   // board clock (single-ended); see board.xdc
    input  wire       rst_pin,   // reset button, active-low (see below)
    output wire [3:0] led
);

    // ---- clock buffer ----------------------------------------------------
    // Single-ended board clock. Vivado inserts the input IBUF automatically;
    // BUFG puts it on a global clock net.
    wire clk;
    BUFG u_bufg (.I(clk_pin), .O(clk));

    // For a DIFFERENTIAL board clock, delete the two lines above, change the
    // port to clk_pin_p / clk_pin_n, and use:
    //   wire clk_ibuf;
    //   IBUFDS u_ibufds (.I(clk_pin_p), .IB(clk_pin_n), .O(clk_ibuf));
    //   BUFG   u_bufg   (.I(clk_ibuf), .O(clk));

    // ---- reset -----------------------------------------------------------
    // Active-low push button drives active-low reset directly.
    // If your board's button is active-high, use:  wire rst_n = ~rst_pin;
    wire rst_n = rst_pin;

    // ---- self-test core --------------------------------------------------
    wire pass, fail, done, hb;

    selftest_top #(
        .HB_BIT(HB_BIT),
        .IMG_FILE(IMG_FILE), .KER_FILE(KER_FILE), .EXP_FILE(EXP_FILE)
    ) u_selftest (
        .clk(clk), .rst_n(rst_n),
        .led_pass(pass), .led_fail(fail),
        .led_done(done), .led_heartbeat(hb)
    );

    assign led = {hb, done, fail, pass};

endmodule
