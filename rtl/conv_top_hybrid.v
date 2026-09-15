// ----------------------------------------------------------------------------
// HyperConv hybrid - conv_top_hybrid.v
// 2-pixel-per-cycle convolution accelerator top level.
//
// Same feature set as the baseline conv_top (programmable N x N kernel sets,
// stride 1, u8 in / s8 coeff / s16 saturated out, optional ReLU, valid
// convolution, back-to-back frames) with:
//   * 2 pixels input per cycle (px0 = even column, px1 = odd column)
//   * 2 result pixels per cycle (out0 = left window, out1 = right window)
//   * N*N DSP48E1 blocks total via dual-multiply packing (baseline needs
//     N*N DSPs per pixel stream; two streams share the packed DSPs)
//
// Constraints: IMG_W even, N odd (see window_gen_2px).
// Latency from an input pair to its result pair: 7 cycles
// (1 window register + 6 MAC stages).
// ----------------------------------------------------------------------------
`timescale 1ns / 1ps

module conv_top_hybrid #(
    parameter N           = 3,
    parameter IMG_W       = 32,
    parameter IMG_H       = 32,
    parameter KERNEL_SETS = 4,
    parameter PIX_W       = 8,
    parameter COEF_W      = 8,
    parameter OUT_W       = 16,
    parameter RELU        = 0,
    // derived - do not override
    parameter SET_AW = (KERNEL_SETS > 1) ? $clog2(KERNEL_SETS) : 1,
    parameter IDX_AW = (N > 1) ? $clog2(N*N) : 1
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // kernel coefficient write port (row-major index i*N+j)
    input  wire                    k_we,
    input  wire [SET_AW-1:0]       k_wset,
    input  wire [IDX_AW-1:0]       k_widx,
    input  wire signed [COEF_W-1:0] k_din,
    input  wire [SET_AW-1:0]       k_sel,     // active set (stable per frame)

    // pixel stream in: 2 pixels/cycle, row-major (px0 = even col)
    input  wire                    px_valid,
    input  wire [PIX_W-1:0]        px0,
    input  wire [PIX_W-1:0]        px1,

    // result stream out: 2 pixels/cycle, row-major (out0 = left)
    output wire                    out_valid,
    output wire signed [OUT_W-1:0] out0,
    output wire signed [OUT_W-1:0] out1,
    output reg                     frame_done // 1-cycle pulse on last output
);

    localparam OUT_PIX = (IMG_H - N + 1) * (IMG_W - N + 1);
    localparam OCW     = $clog2(OUT_PIX + 1);

    wire [N*N*PIX_W-1:0]  window0, window1;
    wire                  win_valid;
    wire [N*N*COEF_W-1:0] coeffs;

    kernel_mem #(
        .N(N), .COEF_W(COEF_W), .SETS(KERNEL_SETS)
    ) u_kmem (
        .clk    (clk),
        .k_we   (k_we),
        .k_wset (k_wset),
        .k_widx (k_widx),
        .k_din  (k_din),
        .k_sel  (k_sel),
        .coeffs (coeffs)
    );

    window_gen_2px #(
        .N(N), .IMG_W(IMG_W), .IMG_H(IMG_H), .PIX_W(PIX_W)
    ) u_win (
        .clk       (clk),
        .rst_n     (rst_n),
        .px_valid  (px_valid),
        .px0       (px0),
        .px1       (px1),
        .window0   (window0),
        .window1   (window1),
        .win_valid (win_valid)
    );

    dmp_mac_array #(
        .N(N), .PIX_W(PIX_W), .COEF_W(COEF_W), .OUT_W(OUT_W), .RELU(RELU)
    ) u_mac (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (win_valid),
        .window0   (window0),
        .window1   (window1),
        .coeffs    (coeffs),
        .out_valid (out_valid),
        .out0_data (out0),
        .out1_data (out1)
    );

    // ------------------------------------------------------- frame bookkeeping
    reg [OCW-1:0] out_cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            out_cnt    <= {OCW{1'b0}};
            frame_done <= 1'b0;
        end else begin
            frame_done <= 1'b0;
            if (out_valid) begin
                // two outputs per beat (OUT_PIX is even under the
                // IMG_W-even / N-odd constraints)
                if (out_cnt == OUT_PIX-2) begin
                    out_cnt    <= {OCW{1'b0}};
                    frame_done <= 1'b1;
                end else begin
                    out_cnt <= out_cnt + 2'b10;
                end
            end
        end
    end

endmodule
