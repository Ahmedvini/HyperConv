// ----------------------------------------------------------------------------
// HyperConv - kernel_mem.v
// Programmable coefficient storage with multiple kernel sets (bonus feature).
//
// Write port loads one signed 8-bit coefficient per cycle into any set at
// row-major index i*N+j. The set selected by k_sel drives the MAC array
// through a registered mux, so k_sel must be stable one cycle before the
// first pixel of a frame (and held during the frame).
// ----------------------------------------------------------------------------
`timescale 1ns / 1ps

module kernel_mem #(
    parameter N      = 3,
    parameter COEF_W = 8,
    parameter SETS   = 4,
    parameter SET_AW = (SETS > 1) ? $clog2(SETS) : 1,  // derived - do not set
    parameter IDX_AW = (N > 1) ? $clog2(N*N) : 1       // derived - do not set
) (
    input  wire                     clk,
    input  wire                     k_we,
    input  wire [SET_AW-1:0]        k_wset,   // set being written
    input  wire [IDX_AW-1:0]        k_widx,   // row-major coefficient index
    input  wire signed [COEF_W-1:0] k_din,
    input  wire [SET_AW-1:0]        k_sel,    // active set for convolution
    output reg  [N*N*COEF_W-1:0]    coeffs    // active set, flattened
);

    localparam NN = N * N;

    reg [COEF_W-1:0] mem [0:SETS*NN-1];

    integer i;
    always @(posedge clk) begin
        if (k_we)
            mem[k_wset*NN + k_widx] <= k_din;
        for (i = 0; i < NN; i = i + 1)
            coeffs[i*COEF_W +: COEF_W] <= mem[k_sel*NN + i];
    end

endmodule
