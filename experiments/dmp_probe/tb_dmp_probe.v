// ----------------------------------------------------------------------------
// tb_dmp_probe.v - exhaustive-corner + random verification of the packed
// dual-multiply. Checks p0 == a0*c and p1 == a1*c over:
//   * all 256 x 256 x 256 is too big (16M) - instead:
//   * all (a0, a1) corners x all c in {-128, -127, -1, 0, 1, 126, 127}
//     plus a sweep of c with fixed pixel corners
//   * 100k random triples
// Reference computed independently in 32-bit integers.
// ----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_dmp_probe;

    reg              clk = 0, rst_n = 0, in_valid = 0;
    reg  [7:0]       a0 = 0, a1 = 0;
    reg  signed [7:0] c = 0;
    wire             out_valid;
    wire signed [16:0] p0, p1;

    integer errors = 0;
    integer checked = 0;
    integer i, j, m;      // initial-block loop vars only (kp is owned by the pipe always block)
    integer kp;
    integer ref0, ref1;
    reg [7:0] pipe_a0 [0:2];
    reg [7:0] pipe_a1 [0:2];
    reg signed [7:0] pipe_c [0:2];

    dmp_probe dut (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .a0(a0), .a1(a1), .c(c),
        .out_valid(out_valid), .p0(p0), .p1(p1)
    );

    always #2 clk = ~clk;   // 250 MHz

    task drive(input [7:0] xa0, input [7:0] xa1, input signed [7:0] xc);
        begin
            @(negedge clk);
            a0 = xa0; a1 = xa1; c = xc; in_valid = 1;
            @(negedge clk);
            in_valid = 0;
        end
    endtask

    // scoreboard reference model (DUT latency 3: input C0 -> checked at P4,
    // so a 3-deep pipe read at [2] holds C0's inputs)
    always @(posedge clk) begin
        pipe_a0[0] <= a0; pipe_a1[0] <= a1; pipe_c[0] <= c;
        for (kp = 2; kp > 0; kp = kp - 1) begin
            pipe_a0[kp] <= pipe_a0[kp-1];
            pipe_a1[kp] <= pipe_a1[kp-1];
            pipe_c[kp]  <= pipe_c[kp-1];
        end
    end

    always @(posedge clk) begin
        if (out_valid) begin
            // both operands explicitly signed: mixed-sign * in Verilog is unsigned!
            ref0 = $signed({1'b0, pipe_a0[2]}) * pipe_c[2];
            ref1 = $signed({1'b0, pipe_a1[2]}) * pipe_c[2];
            checked = checked + 1;
            if (p0 !== ref0[16:0] || p1 !== ref1[16:0]) begin
                errors = errors + 1;
                if (errors < 20)
                    $display("MISMATCH a0=%0d a1=%0d c=%0d : p0=%0d (exp %0d) p1=%0d (exp %0d)",
                             pipe_a0[2], pipe_a1[2], pipe_c[2], p0, ref0, p1, ref1);
            end
        end
    end

    // corner values for pixels
    reg [7:0] corners [0:5];
    reg signed [7:0] cvals [0:6];
    integer nc = 0;

    initial begin
        corners[0]=8'd0;   corners[1]=8'd1;   corners[2]=8'd127;
        corners[3]=8'd128; corners[4]=8'd254; corners[5]=8'd255;
        cvals[0]=-128; cvals[1]=-127; cvals[2]=-1;
        cvals[3]=0;    cvals[4]=1;    cvals[5]=126; cvals[6]=127;

        repeat (5) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        // 1) pixel corners x coefficient corners: 6*6*7 = 252 vectors
        for (i = 0; i < 6; i = i + 1)
            for (j = 0; j < 6; j = j + 1)
                for (m = 0; m < 7; m = m + 1)
                    drive(corners[i], corners[j], cvals[m]);

        // 2) full coefficient sweep with fixed extreme pixels
        for (i = -128; i <= 127; i = i + 1) begin
            drive(8'd255, 8'd0,   i[7:0]);
            drive(8'd0,   8'd255, i[7:0]);
            drive(8'd255, 8'd255, i[7:0]);
            drive(8'd128, 8'd128, i[7:0]);
        end

        // 3) 100k random vectors
        for (nc = 0; nc < 100000; nc = nc + 1) begin
            @(negedge clk);
            a0 = $random; a1 = $random; c = $random; in_valid = 1;
            if (nc % 25000 == 0) $display("TB: progress %0d/100000", nc);
        end
        @(negedge clk); in_valid = 0;
        repeat (6) @(negedge clk);

        if (errors == 0)
            $display("TB: PASS (%0d vectors checked, 0 errors)", checked);
        else
            $display("TB: FAIL (%0d errors out of %0d)", errors, checked);
        $finish;
    end

endmodule
