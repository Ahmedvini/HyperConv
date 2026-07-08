// ----------------------------------------------------------------------------
// HyperConv - conv_top.v
// Top level of the N x N convolution accelerator.
// 2026 IEEE SSCS Egypt Student Design Competition entry.
//
//   * N x N kernel (synthesis parameter, default 3), stride 1
//   * input : row-major stream of unsigned PIX_W-bit pixels, 1 pixel/cycle
//   * output: (IMG_H-N+1) x (IMG_W-N+1) signed OUT_W-bit results, saturated,
//             1 output pixel/cycle in steady state (fully pipelined)
//   * KERNEL_SETS runtime-programmable coefficient sets, selected by k_sel
//   * "valid" convolution (no padding); frames may stream back-to-back
//
// Latency from a pixel entering to its window's result on out_data:
//   1 (window regs) + 4 (MAC pipeline) = 5 cycles.
// ----------------------------------------------------------------------------
`timescale 1ns / 1ps

module conv_top #(
    parameter N           = 3,    // kernel size
    parameter IMG_W       = 32,   // image width  (>= N)
    parameter IMG_H       = 32,   // image height (>= N)
    parameter KERNEL_SETS = 4,    // programmable kernel sets
    parameter PIX_W       = 8,    // pixel width (unsigned)
    parameter COEF_W      = 8,    // coefficient width (signed)
    parameter OUT_W       = 16,   // output width (signed, saturated)
    // derived - do not override
    parameter SET_AW = (KERNEL_SETS > 1) ? $clog2(KERNEL_SETS) : 1,
    parameter IDX_AW = (N > 1) ? $clog2(N*N) : 1
) (
    input  wire                    clk,
    input  wire                    rst_n,     // synchronous, active low

    // kernel coefficient write port (row-major index i*N+j)
    input  wire                    k_we,
    input  wire [SET_AW-1:0]       k_wset,
    input  wire [IDX_AW-1:0]       k_widx,
    input  wire signed [COEF_W-1:0] k_din,
    input  wire [SET_AW-1:0]       k_sel,     // active set (stable per frame)

    // pixel stream in (row-major)
    input  wire                    px_valid,
    input  wire [PIX_W-1:0]        px_data,

    // result stream out (row-major)
    output wire                    out_valid,
    output wire signed [OUT_W-1:0] out_data,
    output reg                     frame_done // 1-cycle pulse on last output
);

    localparam OUT_PIX = (IMG_H - N + 1) * (IMG_W - N + 1);
    localparam OCW     = $clog2(OUT_PIX + 1);

    wire [N*N*PIX_W-1:0]  window;
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

    window_gen #(
        .N(N), .IMG_W(IMG_W), .IMG_H(IMG_H), .PIX_W(PIX_W)
    ) u_win (
        .clk       (clk),
        .rst_n     (rst_n),
        .px_valid  (px_valid),
        .px_data   (px_data),
        .window    (window),
        .win_valid (win_valid)
    );

    mac_array #(
        .N(N), .PIX_W(PIX_W), .COEF_W(COEF_W), .OUT_W(OUT_W)
    ) u_mac (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (win_valid),
        .window    (window),
        .coeffs    (coeffs),
        .out_valid (out_valid),
        .out_data  (out_data)
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
                if (out_cnt == OUT_PIX-1) begin
                    out_cnt    <= {OCW{1'b0}};
                    frame_done <= 1'b1;
                end else begin
                    out_cnt <= out_cnt + 1'b1;
                end
            end
        end
    end

endmodule
