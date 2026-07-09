// ----------------------------------------------------------------------------
// HyperConv - selftest_top.v
// Board-independent self-test wrapper for a standalone bitstream demo.
//
// On reset it: (1) programs the kernel into set 0, (2) streams a stored
// IMG_H x IMG_W image through conv_top at 1 pixel/cycle, (3) compares every
// output against the stored golden result on-chip, and (4) reports the
// verdict on LEDs:
//     led_pass       high (steady) if all NOUT outputs matched the golden ROM
//     led_fail       high (steady) if any output mismatched
//     led_done       high once the frame has completed
//     led_heartbeat  free-running blink, proves the clock/logic is alive
//
// The image / kernel / golden data are initialised from $readmemh files
// (defaults = the sobel_x edge-detection testcase). This module is fully
// board-agnostic: it has only clk, rst_n and LED outputs. A thin per-board
// top (clock buffer/PLL + pin XDC) instantiates it to build a bitstream.
// ----------------------------------------------------------------------------
`timescale 1ns / 1ps

module selftest_top #(
    parameter N           = 3,
    parameter IMG_W       = 32,
    parameter IMG_H       = 32,
    parameter KERNEL_SETS = 4,
    parameter PIX_W       = 8,
    parameter COEF_W      = 8,
    parameter OUT_W       = 16,
    parameter HB_BIT      = 25,             // heartbeat: clk bit driving the LED
    parameter IMG_FILE    = "img.hex",
    parameter KER_FILE    = "kernel.hex",
    parameter EXP_FILE    = "expected.hex"
) (
    input  wire clk,
    input  wire rst_n,
    output reg  led_pass,
    output reg  led_fail,
    output reg  led_done,
    output wire led_heartbeat
);

    localparam NPIX   = IMG_W * IMG_H;
    localparam NOUT   = (IMG_H - N + 1) * (IMG_W - N + 1);
    localparam NN     = N * N;
    localparam SET_AW = (KERNEL_SETS > 1) ? $clog2(KERNEL_SETS) : 1;
    localparam IDX_AW = (NN > 1) ? $clog2(NN) : 1;
    localparam PCW    = $clog2(NPIX + 1);
    localparam OCW    = $clog2(NOUT + 1);
    localparam KCW    = $clog2(NN + 1);

    // --------------------------------------------------------------- ROMs
    reg [PIX_W-1:0]  img_rom [0:NPIX-1];
    reg [COEF_W-1:0] ker_rom [0:NN-1];
    reg [OUT_W-1:0]  exp_rom [0:NOUT-1];

    initial begin
        $readmemh(IMG_FILE, img_rom);
        $readmemh(KER_FILE, ker_rom);
        $readmemh(EXP_FILE, exp_rom);
    end

    // ------------------------------------------------------------- control
    localparam [2:0] S_IDLE  = 3'd0,
                     S_LOADK = 3'd1,
                     S_SETK  = 3'd2,
                     S_STREAM= 3'd3,
                     S_WAIT  = 3'd4,
                     S_DONE  = 3'd5;

    reg [2:0]      state;
    reg [KCW-1:0]  kidx;
    reg [PCW-1:0]  pidx;
    reg [OCW-1:0]  oidx;
    reg            fail_r;

    // conv_top interface
    reg                      k_we;
    reg  [SET_AW-1:0]        k_wset;
    reg  [IDX_AW-1:0]        k_widx;
    reg  signed [COEF_W-1:0] k_din;
    reg  [SET_AW-1:0]        k_sel;
    reg                      px_valid;
    reg  [PIX_W-1:0]         px_data;
    wire                     out_valid;
    wire signed [OUT_W-1:0]  out_data;
    wire                     frame_done;

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            kidx     <= {KCW{1'b0}};
            pidx     <= {PCW{1'b0}};
            oidx     <= {OCW{1'b0}};
            fail_r   <= 1'b0;
            k_we     <= 1'b0;
            k_wset   <= {SET_AW{1'b0}};
            k_widx   <= {IDX_AW{1'b0}};
            k_din    <= {COEF_W{1'b0}};
            k_sel    <= {SET_AW{1'b0}};
            px_valid <= 1'b0;
            px_data  <= {PIX_W{1'b0}};
            led_pass <= 1'b0;
            led_fail <= 1'b0;
            led_done <= 1'b0;
        end else begin
            k_we     <= 1'b0;
            px_valid <= 1'b0;

            case (state)
                // ------------------------------------------------ program kernel
                S_IDLE: begin
                    kidx  <= {KCW{1'b0}};
                    state <= S_LOADK;
                end

                S_LOADK: begin
                    k_we   <= 1'b1;
                    k_wset <= {SET_AW{1'b0}};                 // set 0
                    k_widx <= kidx[IDX_AW-1:0];
                    k_din  <= ker_rom[kidx];
                    if (kidx == NN-1) state <= S_SETK;
                    kidx <= kidx + 1'b1;
                end

                // let the registered coefficient mux settle
                S_SETK: begin
                    k_sel <= {SET_AW{1'b0}};
                    pidx  <= {PCW{1'b0}};
                    state <= S_STREAM;
                end

                // ----------------------------------------------- stream the image
                S_STREAM: begin
                    px_valid <= 1'b1;
                    px_data  <= img_rom[pidx];
                    if (pidx == NPIX-1) state <= S_WAIT;
                    pidx <= pidx + 1'b1;
                end

                // ---------------------------------- drain pipeline / finish frame
                S_WAIT: begin
                    if (frame_done) state <= S_DONE;
                end

                S_DONE: begin
                    led_done <= 1'b1;
                    led_pass <= ~fail_r;
                    led_fail <=  fail_r;
                end

                default: state <= S_IDLE;
            endcase

            // -------------------------------------- on-chip golden comparison
            if (out_valid) begin
                if (oidx < NOUT) begin
                    if (out_data != $signed(exp_rom[oidx]))
                        fail_r <= 1'b1;
                    oidx <= oidx + 1'b1;
                end else begin
                    fail_r <= 1'b1;                            // spurious output
                end
            end
        end
    end

    // ------------------------------------------------------------- heartbeat
    reg [HB_BIT:0] hb;
    always @(posedge clk) begin
        if (!rst_n) hb <= {(HB_BIT+1){1'b0}};
        else        hb <= hb + 1'b1;
    end
    assign led_heartbeat = hb[HB_BIT];

    // ------------------------------------------------------------- DUT
    conv_top #(
        .N(N), .IMG_W(IMG_W), .IMG_H(IMG_H), .KERNEL_SETS(KERNEL_SETS),
        .PIX_W(PIX_W), .COEF_W(COEF_W), .OUT_W(OUT_W)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .k_we(k_we), .k_wset(k_wset), .k_widx(k_widx), .k_din(k_din),
        .k_sel(k_sel),
        .px_valid(px_valid), .px_data(px_data),
        .out_valid(out_valid), .out_data(out_data), .frame_done(frame_done)
    );

endmodule
