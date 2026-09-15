// ----------------------------------------------------------------------------
// HyperConv hybrid - window_gen_2px.v
// Line-buffer + sliding-window generator for TWO horizontally adjacent
// windows per cycle (2-pixel streaming).
//
// Consumes 2 pixels/cycle (px0 = even column 2k, px1 = odd column 2k+1) and
// produces two N x N windows per valid cycle: window0 starting at column s
// and window1 at column s+1, where s advances by 2 per beat.
//
// Constraints (checked by construction, asserted in simulation):
//   * IMG_W must be even (pixel pairing)
//   * N must be odd (so the first beat aligns window0 with column 0;
//     all competition kernels are 3x3 / 5x5)
// Under these constraints every output beat has BOTH windows valid and
// (IMG_W-N+1) is even, so no half-empty beats occur.
//
// Line buffers keep the zero-BRAM property: each of the N-1 row delays is
// two distributed-RAM line_buffer instances (even/odd column interleave,
// DEPTH = IMG_W/2, shared pair-index address), reusing rtl/line_buffer.v
// unchanged.
//
// Window index convention (matches the golden model, cross-correlation):
//   window0[(i*N+j)*PIX_W +: PIX_W] = pixel(row-(N-1)+i, s+j)
//   window1[(i*N+j)*PIX_W +: PIX_W] = pixel(row-(N-1)+i, s+j+1)
// ----------------------------------------------------------------------------
`timescale 1ns / 1ps

module window_gen_2px #(
    parameter N     = 3,
    parameter IMG_W = 32,
    parameter IMG_H = 32,
    parameter PIX_W = 8
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     px_valid,
    input  wire [PIX_W-1:0]         px0,      // even column pixel
    input  wire [PIX_W-1:0]         px1,      // odd column pixel
    output wire [N*N*PIX_W-1:0]     window0,
    output wire [N*N*PIX_W-1:0]     window1,
    output reg                      win_valid
);

    localparam PW   = IMG_W / 2;                      // pairs per row
    localparam CW   = (PW  > 1) ? $clog2(PW)   : 1;   // pair-index width
    localparam RW   = (IMG_H > 1) ? $clog2(IMG_H) : 1;
    localparam KMIN = (N - 1) / 2;                    // first valid pair index
                                                      // (N odd -> exact)

    // ------------------------------------------------------------ position
    reg [CW-1:0] kpair;   // index of the pair currently on px0/px1
    reg [RW-1:0] row;

    always @(posedge clk) begin
        if (!rst_n) begin
            kpair <= {CW{1'b0}};
            row   <= {RW{1'b0}};
        end else if (px_valid) begin
            if (kpair == PW-1) begin
                kpair <= {CW{1'b0}};
                row   <= (row == IMG_H-1) ? {RW{1'b0}} : row + 1'b1;
            end else begin
                kpair <= kpair + 1'b1;
            end
        end
    end

    // ---------------------------------------------------------- line buffers
    // Each stage holds one image row of pairs, oldest row first.
    // tap_e[i]/tap_o[i] = pixel(row-(N-1)+i, 2k) / (..., 2k+1).
    wire [PIX_W-1:0] tap_e [0:N-1];
    wire [PIX_W-1:0] tap_o [0:N-1];
    assign tap_e[N-1] = px0;
    assign tap_o[N-1] = px1;

    genvar g;
    generate
        for (g = 0; g < N-1; g = g + 1) begin : g_lb
            wire [PIX_W-1:0] din_e, din_o, dout_e, dout_o;
            if (g == 0) begin : g_head
                assign din_e = px0;
                assign din_o = px1;
            end else begin : g_tail
                assign din_e = g_lb[g-1].dout_e;
                assign din_o = g_lb[g-1].dout_o;
            end
            line_buffer #(.DEPTH(PW), .DW(PIX_W)) u_lb_e (
                .clk (clk), .we (px_valid), .addr (kpair),
                .din (din_e), .dout (dout_e)
            );
            line_buffer #(.DEPTH(PW), .DW(PIX_W)) u_lb_o (
                .clk (clk), .we (px_valid), .addr (kpair),
                .din (din_o), .dout (dout_o)
            );
            assign tap_e[N-2-g] = dout_e;
            assign tap_o[N-2-g] = dout_o;
        end
    endgenerate

    // ------------------------------------------------- (N+1)-wide row shifter
    // After consuming pair k, row register i holds columns
    // 2k+1-N .. 2k+1 in positions 0..N. Window0 = positions 0..N-1,
    // window1 = positions 1..N.
    reg [PIX_W-1:0] wrow [0:N-1][0:N];
    integer i, j;

    always @(posedge clk) begin
        if (px_valid) begin
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j <= N-2; j = j + 1)
                    wrow[i][j] <= wrow[i][j+2];
                wrow[i][N-1] <= tap_e[i];
                wrow[i][N]   <= tap_o[i];
            end
        end
    end

    genvar gi, gj;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_row
            for (gj = 0; gj < N; gj = gj + 1) begin : g_col
                assign window0[(gi*N+gj)*PIX_W +: PIX_W]     = wrow[gi][gj];
                assign window1[(gi*N+gj)*PIX_W +: PIX_W]     = wrow[gi][gj+1];
            end
        end
    endgenerate

    // both windows of a beat are valid once N-1 full rows and the columns
    // 0..N of the current row have been consumed (pair index >= (N-1)/2)
    always @(posedge clk) begin
        if (!rst_n)
            win_valid <= 1'b0;
        else
            win_valid <= px_valid && (row >= N-1) && (kpair >= KMIN[CW-1:0]);
    end

endmodule
