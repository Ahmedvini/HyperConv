// ----------------------------------------------------------------------------
// HyperConv - tb_selftest.v
// Simulation check for the board self-test wrapper: clocks selftest_top with
// the sobel_x vectors and confirms led_pass asserts (and led_fail does not).
// Proves the on-chip compare / LED logic before it ever reaches a board.
//
//   +IMG/+KER/+EXP override the ROM files (defaults set via -generic_top).
// ----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_selftest;

    parameter N        = 3;
    parameter IMG_W    = 32;
    parameter IMG_H    = 32;
    parameter IMG_FILE = "img.hex";
    parameter KER_FILE = "kernel.hex";
    parameter EXP_FILE = "expected.hex";

    reg  clk = 1'b0;
    reg  rst_n = 1'b0;
    wire led_pass, led_fail, led_done, led_heartbeat;

    always #5 clk = ~clk;   // 100 MHz

    // small heartbeat bit so the blink is observable within the sim window
    selftest_top #(
        .N(N), .IMG_W(IMG_W), .IMG_H(IMG_H), .HB_BIT(4),
        .IMG_FILE(IMG_FILE), .KER_FILE(KER_FILE), .EXP_FILE(EXP_FILE)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .led_pass(led_pass), .led_fail(led_fail),
        .led_done(led_done), .led_heartbeat(led_heartbeat)
    );

    integer cycles = 0;
    always @(posedge clk) cycles = cycles + 1;

    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1'b1;

        // wait for the self-test to finish (led_done) or time out
        wait (led_done === 1'b1);
        repeat (5) @(negedge clk);

        $display("SELFTEST: done=%b pass=%b fail=%b  (finished in %0d cycles)",
                 led_done, led_pass, led_fail, cycles);
        if (led_pass === 1'b1 && led_fail === 1'b0)
            $display("SELFTEST: PASS");
        else
            $display("SELFTEST: FAIL");
        $finish;
    end

    // hard timeout guard
    initial begin
        #200000;
        $display("SELFTEST: TIMEOUT (led_done never asserted)");
        $display("SELFTEST: FAIL");
        $finish;
    end

endmodule
