// ----------------------------------------------------------------------------
// HyperConv hybrid - selftest_top_hybrid.v
// Board-independent self-test wrapper for the 2-px/cycle hybrid core,
// mirroring rtl/selftest/selftest_top.v.
//
// On reset it: (1) programs the kernel into set 0, (2) streams the stored
// image through conv_top_hybrid as 2 pixels/cycle (px0 = even column,
// px1 = odd column), (3) compares both outputs of every beat against the
// stored golden result on-chip, and (4) reports on LEDs:
//     led_pass       high (steady) if all NOUT outputs matched
//     led_fail       high (steady) if any output mismatched
//     led_done       high once the frame has completed
//     led_heartbeat  free-running blink
//
// The comparison interleaves out0/out1 with the golden stream exactly like
// tb_conv_top_hybrid, so the SAME expected.hex as the baseline is used.
// ----------------------------------------------------------------------------
`timescale 1ns / 1ps

module selftest_top_hybrid #(
    parameter N           = 3,
    parameter IMG_W       = 32,
    parameter IMG_H       = 32,
    parameter KERNEL_SETS = 4,
    parameter PIX_W       = 8,
    parameter COEF_W      = 8,
    parameter OUT_W       = 16,
    parameter HB_BIT      = 25,
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
    localparam NOUT   = (IMG_H - N + 1) * (IMG_W - N + 1);   // even (W even, N odd)
    localparam NPAIR  = NPIX / 2;
    localparam NN     = N * N;
    localparam SET_AW = (KERNEL_SETS > 1) ? $clog2(KERNEL_SETS) : 1;
    localparam IDX_AW = (NN > 1) ? $clog2(NN) : 1;
    localparam PCW    = $clog2(NPAIR + 1);
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

    // conv_top_hybrid interface
    reg                      k_we;
    reg  [SET_AW-1:0]        k_wset;
    reg  [IDX_AW-1:0]        k_widx;
    reg  signed [COEF_W-1:0] k_din;
    reg  [SET_AW-1:0]        k_sel;
    reg                      px_valid;
    reg  [PIX_W-1:0]         px0, px1;
    wire                     out_valid;
    wire signed [OUT_W-1:0]  out0, out1;
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
            px0      <= {PIX_W{1'b0}};
            px1      <= {PIX_W{1'b0}};
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

                // ------------------------------------- stream 2 pixels / cycle
                S_STREAM: begin
                    px_valid <= 1'b1;
                    px0      <= img_rom[{pidx, 1'b0}];        // even column
                    px1      <= img_rom[{pidx, 1'b1}];        // odd column
                    if (pidx == NPAIR-1) state <= S_WAIT;
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
            // out0 = golden index oidx, out1 = golden index oidx+1
            if (out_valid) begin
                if (oidx < NOUT) begin
                    if (out0 != $signed(exp_rom[oidx]))
                        fail_r <= 1'b1;
                    if (oidx + 1 < NOUT) begin
                        if (out1 != $signed(exp_rom[oidx + 1]))
                            fail_r <= 1'b1;
                    end else if (out1 != {OUT_W{1'b0}}) begin
                        fail_r <= 1'b1;                       // spurious 2nd output
                    end
                    oidx <= oidx + 2'b10;
                end else begin
                    fail_r <= 1'b1;                           // spurious output
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
    conv_top_hybrid #(
        .N(N), .IMG_W(IMG_W), .IMG_H(IMG_H), .KERNEL_SETS(KERNEL_SETS),
        .PIX_W(PIX_W), .COEF_W(COEF_W), .OUT_W(OUT_W)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .k_we(k_we), .k_wset(k_wset), .k_widx(k_widx), .k_din(k_din),
        .k_sel(k_sel),
        .px_valid(px_valid), .px0(px0), .px1(px1),
        .out_valid(out_valid), .out0(out0), .out1(out1),
        .frame_done(frame_done)
    );

endmodule
