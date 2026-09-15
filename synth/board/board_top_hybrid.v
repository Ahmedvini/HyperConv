// ----------------------------------------------------------------------------
// HyperConv hybrid - board_top_hybrid.v
// Thin board top for the 2-px/cycle hybrid self-test bitstream. Identical
// pin usage to board_top.v (same board.xdc): clock, reset button, 4 LEDs.
//
//   led[0] = pass       (steady on  = all outputs matched the golden result)
//   led[1] = fail       (steady on  = a mismatch was detected)
//   led[2] = done       (steady on  = frame finished)
//   led[3] = heartbeat  (blinks     = clock + logic alive)
// ----------------------------------------------------------------------------
`timescale 1ns / 1ps

module board_top_hybrid #(
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
    wire clk;
    BUFG u_bufg (.I(clk_pin), .O(clk));

    // ---- reset: PYNQ-Z2 buttons are active-high --------------------------
    wire rst_n = ~rst_pin;

    // ---- hybrid self-test core -------------------------------------------
    wire pass, fail, done, hb;

    selftest_top_hybrid #(
        .HB_BIT(HB_BIT),
        .IMG_FILE(IMG_FILE), .KER_FILE(KER_FILE), .EXP_FILE(EXP_FILE)
    ) u_selftest (
        .clk(clk), .rst_n(rst_n),
        .led_pass(pass), .led_fail(fail),
        .led_done(done), .led_heartbeat(hb)
    );

    assign led = {hb, done, fail, pass};

endmodule
