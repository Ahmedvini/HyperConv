// ----------------------------------------------------------------------------
// HyperConv - line_buffer.v
// Single image-row buffer. Asynchronous read so Vivado infers distributed
// (LUT) RAM: for small row widths this costs zero BRAM, which is heavily
// weighted in the competition FoM.
// ----------------------------------------------------------------------------
`timescale 1ns / 1ps

module line_buffer #(
    parameter DEPTH = 32,                              // image width in pixels
    parameter DW    = 8,                               // pixel width
    parameter AW    = (DEPTH > 1) ? $clog2(DEPTH) : 1  // derived - do not set
) (
    input  wire          clk,
    input  wire          we,
    input  wire [AW-1:0] addr,   // shared read/write address (current column)
    input  wire [DW-1:0] din,
    output wire [DW-1:0] dout    // value held before this cycle's write
);

    reg [DW-1:0] mem [0:DEPTH-1];

    assign dout = mem[addr];

    always @(posedge clk)
        if (we)
            mem[addr] <= din;

endmodule
