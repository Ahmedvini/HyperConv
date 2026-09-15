// ----------------------------------------------------------------------------
// HyperConv hybrid - dmp_mac_array.v
// Dual-multiply-packed MAC array: computes TWO convolutions (two horizontally
// adjacent windows sharing the same coefficient set) with N*N DSP48E1 blocks
// instead of 2*N*N.
//
// Packing (verified by experiments/dmp_probe, 101k vectors, 0 errors):
//   A = {1'b0, w1_k, 8'h00, w0_k}   (25-bit, never negative as signed)
//   B = sign-extend(c_k)            (18-bit signed)
//   P = A*B = w0_k*c_k + 2^16*(w1_k*c_k)
// Extraction:
//   p0_k = $signed(P[15:0])                 -- exact s16 (u8*s8 fits s16)
//   p1_k = $signed(P[32:16]) + P[15]        -- +1 borrow correction
//
// Pipeline (6 stages; +1 window register in window_gen_2px = 7-cycle total):
//   stage 1: packed products            (DSP MREG)
//   stage 2: product register           (DSP PREG)
//   stage 3: extraction + correction    (fabric)
//   stage 4: first-level partial sums   (per window, GROUP=3 products)
//   stage 5: final sums
//   stage 6: saturation + optional ReLU (per window)
//
// Fixed-point (N = 3 defaults):
//   product  : u8 x s8 -> s16 (stored s17)
//   partial  : 3 products -> 19 bits
//   final    : 3 partials -> ACC_W = 21 bits, no overflow possible
//   output   : saturated to s16, optional ReLU
//
// Requires PIX_W = 8 and COEF_W = 8 (stride-16 packing is hardwired).
// ----------------------------------------------------------------------------
`timescale 1ns / 1ps

module dmp_mac_array #(
    parameter N      = 3,
    parameter PIX_W  = 8,
    parameter COEF_W = 8,
    parameter OUT_W  = 16,
    parameter RELU   = 0
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    in_valid,
    input  wire [N*N*PIX_W-1:0]    window0,   // unsigned pixels, row-major
    input  wire [N*N*PIX_W-1:0]    window1,   // adjacent window (col s+1)
    input  wire [N*N*COEF_W-1:0]   coeffs,    // signed, row-major (shared!)
    output reg                     out_valid,
    output reg  signed [OUT_W-1:0] out0_data,
    output reg  signed [OUT_W-1:0] out1_data
);

    localparam NN     = N * N;
    localparam PROD_W = 43;                       // 25 x 18 packed product
    localparam EXT_W  = 17;                       // extracted product width
    localparam GROUP  = 3;
    localparam NGRP   = (NN + GROUP - 1) / GROUP;
    localparam PART_W = EXT_W + $clog2(GROUP + 1);
    localparam ACC_W  = PART_W + ((NGRP > 1) ? $clog2(NGRP) : 1);

    localparam signed [ACC_W-1:0] SAT_MAX =  (1 << (OUT_W-1)) - 1;
    localparam signed [ACC_W-1:0] SAT_MIN = -(1 << (OUT_W-1));

    // ------------------------------------------- stage 1: packed products
    (* use_dsp = "yes" *) reg signed [PROD_W-1:0] prod [0:NN-1];
    reg v1;
    integer k, g;
    reg signed [COEF_W-1:0] c_k;

    always @(posedge clk) begin
        if (in_valid)
            for (k = 0; k < NN; k = k + 1) begin
                c_k = coeffs[k*COEF_W +: COEF_W];
                // B's sign extension is implicit: the numeric product of
                // $signed(A) * $signed(c_k) equals $signed(A) * sext(c_k)
                prod[k] <= $signed({1'b0, window1[k*PIX_W +: PIX_W],
                                    8'h00, window0[k*PIX_W +: PIX_W]}) * c_k;
            end
    end

    // ------------------------------------------- stage 2: product register
    reg signed [PROD_W-1:0] prod_d [0:NN-1];
    reg v2;

    always @(posedge clk) begin
        if (v1)
            for (k = 0; k < NN; k = k + 1)
                prod_d[k] <= prod[k];
    end

    // --------------------------------- stage 3: extraction + correction
    reg signed [EXT_W-1:0] p0 [0:NN-1];
    reg signed [EXT_W-1:0] p1 [0:NN-1];
    reg v3;

    always @(posedge clk) begin
        if (v2)
            for (k = 0; k < NN; k = k + 1) begin
                p0[k] <= $signed(prod_d[k][15:0]);
                p1[k] <= $signed(prod_d[k][32:16]) + prod_d[k][15];
            end
    end

    // --------------------------------- stage 4: first-level partial sums
    reg signed [PART_W-1:0] part0 [0:NGRP-1];
    reg signed [PART_W-1:0] part1 [0:NGRP-1];
    reg v4;

    reg signed [PART_W-1:0] pc0, pc1;
    always @(posedge clk) begin
        if (v3)
            for (g = 0; g < NGRP; g = g + 1) begin
                pc0 = {PART_W{1'b0}};
                pc1 = {PART_W{1'b0}};
                for (k = g*GROUP; k < g*GROUP + GROUP; k = k + 1)
                    if (k < NN) begin
                        pc0 = pc0 + p0[k];
                        pc1 = pc1 + p1[k];
                    end
                part0[g] <= pc0;
                part1[g] <= pc1;
            end
    end

    // ------------------------------------------- stage 5: final sums
    reg signed [ACC_W-1:0] sum_c0, sum_c1;
    always @* begin
        sum_c0 = {ACC_W{1'b0}};
        sum_c1 = {ACC_W{1'b0}};
        for (k = 0; k < NGRP; k = k + 1) begin
            sum_c0 = sum_c0 + part0[k];
            sum_c1 = sum_c1 + part1[k];
        end
    end

    reg signed [ACC_W-1:0] acc0, acc1;
    reg v5;

    always @(posedge clk) begin
        if (v4) begin
            acc0 <= sum_c0;
            acc1 <= sum_c1;
        end
    end

    // ----------------------------- stage 6: saturation + optional ReLU
    always @(posedge clk) begin
        if (v5) begin
            out0_data <= (acc0 > SAT_MAX) ? SAT_MAX[OUT_W-1:0] :
                         (RELU && (acc0 < 0)) ? {OUT_W{1'b0}} :
                         (acc0 < SAT_MIN) ? SAT_MIN[OUT_W-1:0] :
                                            acc0[OUT_W-1:0];
            out1_data <= (acc1 > SAT_MAX) ? SAT_MAX[OUT_W-1:0] :
                         (RELU && (acc1 < 0)) ? {OUT_W{1'b0}} :
                         (acc1 < SAT_MIN) ? SAT_MIN[OUT_W-1:0] :
                                            acc1[OUT_W-1:0];
        end
    end

    // ------------------------------------------------------- valid chain
    always @(posedge clk) begin
        if (!rst_n) begin
            v1        <= 1'b0;
            v2        <= 1'b0;
            v3        <= 1'b0;
            v4        <= 1'b0;
            v5        <= 1'b0;
            out_valid <= 1'b0;
        end else begin
            v1        <= in_valid;
            v2        <= v1;
            v3        <= v2;
            v4        <= v3;
            v5        <= v4;
            out_valid <= v5;
        end
    end

endmodule
