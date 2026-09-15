// ----------------------------------------------------------------------------
// HyperConv hybrid - Step 1 experiment: isolated DMP (dual-multiply packing)
// probe. NOT part of the submission RTL.
//
// Question: can one DSP48E1 compute TWO independent u8 x s8 products?
//
// Answer encoded here: YES, but only when the two multiplications share the
// same coefficient. Two arbitrary 8x8 products cannot be packed (the 18-bit
// B port forces a stride <= 10, which lets cross-terms contaminate the low
// product). However, packing two unsigned pixels into the 25-bit A port with
// stride 16 and using a single shared signed coefficient in B works exactly:
//
//   A = a0 + 2^16 * a1            (25 bits, MSB hardwired 0 -> never negative
//                                  as a signed operand, a1 may use full u8)
//   B = c                         (s8, sign-extended to s18)
//   P = A*B = a0*c + 2^16*(a1*c)  (43-bit signed product)
//
// Extraction (a0*c and a1*c both fit in s16 exactly):
//   p0 = signed(P[15:0])                  -- exact, no correction
//   p1 = signed(P[32:16]) + P[15]         -- +1 borrow correction when a0*c < 0
//
//   Why the correction: write P = 2^16*Q + R, R in [0,2^16).
//     a0*c >= 0  ->  R = a0*c,        Q = a1*c
//     a0*c <  0  ->  R = 2^16 + a0*c, Q = a1*c - 1
//   and P[15] = 1 exactly when a0*c < 0 (since a0*c <= 32385 < 2^15).
//
// In the convolution datapath the shared-coefficient constraint is satisfied
// for free: two horizontally adjacent windows are convolved with the SAME
// kernel, so window0 pixel k and window1 pixel k both multiply coeff k.
//
// TB: tb_dmp_probe.v. Expected synthesis result: 1 DSP48E1 per instance.
// ----------------------------------------------------------------------------
`timescale 1ns / 1ps

module dmp_probe (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             in_valid,
    input  wire [7:0]       a0,       // unsigned pixel, window 0
    input  wire [7:0]       a1,       // unsigned pixel, window 1
    input  wire signed [7:0] c,       // shared coefficient
    output reg              out_valid,
    output reg  signed [16:0] p0,    // = a0 * c
    output reg  signed [16:0] p1     // = a1 * c
);

    wire        [24:0]   A = {1'b0, a1, 8'h00, a0};
    wire signed [17:0]   B = {{10{c[7]}}, c};

    // stage 1: the packed multiply (maps to DSP MREG)
    (* use_dsp = "yes" *) reg signed [42:0] prod;
    reg v1;
    always @(posedge clk) begin
        if (in_valid)
            prod <= $signed(A) * B;
    end

    // stage 2: second product register (maps to DSP PREG, like baseline)
    reg signed [42:0] prod_d;
    reg v2;
    always @(posedge clk) begin
        if (v1)
            prod_d <= prod;
    end

    // stage 3: extraction + correction
    reg signed [16:0] p0_c, p1_c;
    always @(*) begin
        p0_c = $signed(prod_d[15:0]);
        p1_c = $signed(prod_d[32:16]) + prod_d[15];
    end
    always @(posedge clk) begin
        if (v2) begin
            p0 <= p0_c;
            p1 <= p1_c;
        end
    end

    // valid chain: exactly 3 stages, matching the 3 data registers
    always @(posedge clk) begin
        if (!rst_n) begin
            v1        <= 1'b0;
            v2        <= 1'b0;
            out_valid <= 1'b0;
        end else begin
            v1        <= in_valid;
            v2        <= v1;
            out_valid <= v2;
        end
    end

endmodule
