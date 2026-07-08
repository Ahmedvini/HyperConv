// ----------------------------------------------------------------------------
// HyperConv - window_gen.v
// Line-buffer + sliding-window generator.
//
// Accepts a row-major pixel stream (1 pixel/cycle when px_valid) and produces
// an N x N pixel window every valid cycle. "Valid" convolution: win_valid is
// asserted only for the (IMG_H-N+1) x (IMG_W-N+1) fully-interior positions,
// so no padding logic is needed and frames may stream back-to-back.
//
// Window index convention (matches the golden model, cross-correlation):
//   window[(i*N+j)*PIX_W +: PIX_W] = pixel(row - (N-1) + i, col - (N-1) + j)
//   i.e. i = 0 is the oldest row, j = 0 the oldest column.
// ----------------------------------------------------------------------------
`timescale 1ns / 1ps

module window_gen #(
    parameter N     = 3,
    parameter IMG_W = 32,
    parameter IMG_H = 32,
    parameter PIX_W = 8
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 px_valid,
    input  wire [PIX_W-1:0]     px_data,
    output wire [N*N*PIX_W-1:0] window,
    output reg                  win_valid
);

    localparam CW = (IMG_W > 1) ? $clog2(IMG_W) : 1;
    localparam RW = (IMG_H > 1) ? $clog2(IMG_H) : 1;

    // ------------------------------------------------------------ position
    reg [CW-1:0] col;   // column of the pixel currently on px_data
    reg [RW-1:0] row;

    always @(posedge clk) begin
        if (!rst_n) begin
            col <= {CW{1'b0}};
            row <= {RW{1'b0}};
        end else if (px_valid) begin
            if (col == IMG_W-1) begin
                col <= {CW{1'b0}};
                row <= (row == IMG_H-1) ? {RW{1'b0}} : row + 1'b1;
            end else begin
                col <= col + 1'b1;
            end
        end
    end

    // ---------------------------------------------------------- line buffers
    // lb chain: buffer g holds image row (row-1-g) at columns already passed.
    // Column taps, oldest row first: tap[i] = pixel(row-(N-1)+i, col).
    wire [PIX_W-1:0] tap [0:N-1];
    assign tap[N-1] = px_data;

    genvar g;
    generate
        for (g = 0; g < N-1; g = g + 1) begin : g_lb
            wire [PIX_W-1:0] lb_dout;
            if (g == 0) begin : g_head
                line_buffer #(.DEPTH(IMG_W), .DW(PIX_W)) u_lb (
                    .clk (clk), .we (px_valid), .addr (col),
                    .din (px_data), .dout (lb_dout)
                );
            end else begin : g_tail
                line_buffer #(.DEPTH(IMG_W), .DW(PIX_W)) u_lb (
                    .clk (clk), .we (px_valid), .addr (col),
                    .din (g_lb[g-1].lb_dout), .dout (lb_dout)
                );
            end
            assign tap[N-2-g] = lb_dout;
        end
    endgenerate

    // -------------------------------------------------------- window shifter
    reg [PIX_W-1:0] win [0:N-1][0:N-1];
    integer i, j;

    always @(posedge clk) begin
        if (px_valid) begin
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N-1; j = j + 1)
                    win[i][j] <= win[i][j+1];
                win[i][N-1] <= tap[i];
            end
        end
    end

    genvar gi, gj;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_row
            for (gj = 0; gj < N; gj = gj + 1) begin : g_col
                assign window[(gi*N+gj)*PIX_W +: PIX_W] = win[gi][gj];
            end
        end
    endgenerate

    // window is a valid interior position once N-1 full rows and N-1 pixels
    // of the current row have been consumed
    always @(posedge clk) begin
        if (!rst_n)
            win_valid <= 1'b0;
        else
            win_valid <= px_valid && (row >= N-1) && (col >= N-1);
    end

endmodule
