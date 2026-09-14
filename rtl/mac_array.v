// ----------------------------------------------------------------------------
// HyperConv - mac_array.v
// N*N parallel multiply-accumulate with 5-stage pipeline:
//   stage 1: N*N products  (u8 pixel x s8 coefficient -> s16)
//   stage 2: second product register (maps to the DSP PREG; stage 1's
//            register maps to MREG, so the multiplier itself is pipelined)
//   stage 3: first-level partial sums (GROUP products each)
//   stage 4: final sum -> ACC_W-bit accumulator
//   stage 5: saturate to signed OUT_W and register the output
// The adder tree is split across stages 3/4 to keep logic depth low on
// slow fabrics (a single-stage 9-input tree misses 166 MHz on 7-series -1).
//
// Fixed-point analysis (defaults, N = 3):
//   product  : u8 x s8             -> range [-32640, +32385], fits s16
//   partial  : sum of 3 products   -> 18 bits
//   final    : sum of 3 partials   -> ACC_W = 20 bits, no overflow possible
//   output   : saturated to s16    -> [-32768, +32767]
//
// Data registers are gated by the valid chain to cut switching power;
// the valid bits themselves free-run so bubbles flush correctly.
// ----------------------------------------------------------------------------
`timescale 1ns / 1ps

module mac_array #(
    parameter N      = 3,
    parameter PIX_W  = 8,
    parameter COEF_W = 8,
    parameter OUT_W  = 16,
    parameter RELU   = 0               // 1 = ReLU activation: clamp negatives to 0
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    in_valid,
    input  wire [N*N*PIX_W-1:0]    window,   // unsigned pixels, row-major
    input  wire [N*N*COEF_W-1:0]   coeffs,   // signed coefficients, row-major
    output reg                     out_valid,
    output reg  signed [OUT_W-1:0] out_data
);

    localparam NN     = N * N;
    localparam PROD_W = PIX_W + COEF_W;
    localparam GROUP  = 3;                       // products per partial sum
    localparam NGRP   = (NN + GROUP - 1) / GROUP;
    localparam PART_W = PROD_W + $clog2(GROUP + 1);
    localparam ACC_W  = PART_W + ((NGRP > 1) ? $clog2(NGRP) : 1);

    localparam signed [ACC_W-1:0] SAT_MAX =  (1 << (OUT_W-1)) - 1;
    localparam signed [ACC_W-1:0] SAT_MIN = -(1 << (OUT_W-1));

    // ------------------------------------------------------ stage 1: products
    // Multipliers map onto DSP blocks by default: measured better than LUT
    // multipliers on LUTs, FFs, Fmax, power and FoM (the 50/DSP FoM cost is
    // outweighed by ~560 LUTs saved), and required to meet timing on slower
    // fabrics (7-series -1). Define NO_DSP_MULT to force LUT multipliers.
`ifdef NO_DSP_MULT
    reg signed [PROD_W-1:0] prod [0:NN-1];
`else
    (* use_dsp = "yes" *) reg signed [PROD_W-1:0] prod [0:NN-1];
`endif
    reg v1;
    integer k, g;

    always @(posedge clk) begin
        if (in_valid)
            for (k = 0; k < NN; k = k + 1)
                prod[k] <= $signed({1'b0, window[k*PIX_W +: PIX_W]})
                         * $signed(coeffs[k*COEF_W +: COEF_W]);
    end

    // ------------------------------- stage 2: second product register (PREG)
    // Gives the DSP a register on both sides of the multiplier (MREG + PREG):
    // silences the DPOP-2 DRC, shortens the multiply path and saves power.
    reg signed [PROD_W-1:0] prod_d [0:NN-1];
    reg v2;

    always @(posedge clk) begin
        if (v1)
            for (k = 0; k < NN; k = k + 1)
                prod_d[k] <= prod[k];
    end

    // -------------------------------------------- stage 3: partial sums of 3
    reg signed [PART_W-1:0] part_c;
    reg signed [PART_W-1:0] part [0:NGRP-1];
    reg v3;

    always @(posedge clk) begin
        if (v2)
            for (g = 0; g < NGRP; g = g + 1) begin
                part_c = {PART_W{1'b0}};
                for (k = g*GROUP; k < g*GROUP + GROUP; k = k + 1)
                    if (k < NN)
                        part_c = part_c + prod_d[k];
                part[g] <= part_c;
            end
    end

    // -------------------------------------------------- stage 4: final sum
    reg signed [ACC_W-1:0] sum_c;
    always @* begin
        sum_c = {ACC_W{1'b0}};
        for (k = 0; k < NGRP; k = k + 1)
            sum_c = sum_c + part[k];
    end

    reg signed [ACC_W-1:0] acc;
    reg v4;

    always @(posedge clk) begin
        if (v3)
            acc <= sum_c;
    end

    // ---------------------------------------------------- stage 5: saturation
    // With RELU=1 the output is max(0, saturated result): positive overflow
    // still saturates to +SAT_MAX, everything negative (incl. SAT_MIN)
    // clamps to 0. Same register stage, so latency is unchanged.
    always @(posedge clk) begin
        if (v4)
            out_data <= (acc > SAT_MAX) ? SAT_MAX[OUT_W-1:0] :
                        (RELU && (acc < 0)) ? {OUT_W{1'b0}} :
                        (acc < SAT_MIN) ? SAT_MIN[OUT_W-1:0] :
                                          acc[OUT_W-1:0];
    end

    // ------------------------------------------------------------ valid chain
    always @(posedge clk) begin
        if (!rst_n) begin
            v1        <= 1'b0;
            v2        <= 1'b0;
            v3        <= 1'b0;
            v4        <= 1'b0;
            out_valid <= 1'b0;
        end else begin
            v1        <= in_valid;
            v2        <= v1;
            v3        <= v2;
            v4        <= v3;
            out_valid <= v4;
        end
    end

endmodule
