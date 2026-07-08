// ----------------------------------------------------------------------------
// HyperConv - tb_conv_top.v
// Self-checking testbench: loads image/kernel/expected hex files (produced by
// golden/gen_tests.py), programs the kernel through the coefficient write
// port, streams the image at 1 pixel/cycle (optionally with random bubbles),
// and compares every output against the golden model bit-for-bit.
//
// Plusargs:
//   +IMG=<file> +KER=<file> +EXP=<file>   stimulus / golden files
//   +GAPS                                 insert random px_valid bubbles
//   +VCD                                  dump dump.vcd
// Parameters N / IMG_W / IMG_H / KSEL are set per-test via xelab -generic_top.
// ----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_conv_top;

    parameter N           = 3;
    parameter IMG_W       = 32;
    parameter IMG_H       = 32;
    parameter KERNEL_SETS = 4;
    parameter KSEL        = 0;    // kernel set used by this test

    localparam PIX_W  = 8;
    localparam COEF_W = 8;
    localparam OUT_W  = 16;
    localparam SET_AW = (KERNEL_SETS > 1) ? $clog2(KERNEL_SETS) : 1;
    localparam IDX_AW = (N > 1) ? $clog2(N*N) : 1;
    localparam NPIX   = IMG_W * IMG_H;
    localparam NOUT   = (IMG_H - N + 1) * (IMG_W - N + 1);

    // --------------------------------------------------------------- signals
    reg                     clk = 1'b0;
    reg                     rst_n = 1'b0;
    reg                     k_we = 1'b0;
    reg  [SET_AW-1:0]       k_wset = {SET_AW{1'b0}};
    reg  [IDX_AW-1:0]       k_widx = {IDX_AW{1'b0}};
    reg  signed [COEF_W-1:0] k_din = {COEF_W{1'b0}};
    reg  [SET_AW-1:0]       k_sel = {SET_AW{1'b0}};
    reg                     px_valid = 1'b0;
    reg  [PIX_W-1:0]        px_data = {PIX_W{1'b0}};
    wire                    out_valid;
    wire signed [OUT_W-1:0] out_data;
    wire                    frame_done;

    always #5 clk = ~clk;   // 100 MHz behavioural clock

    conv_top #(
        .N(N), .IMG_W(IMG_W), .IMG_H(IMG_H), .KERNEL_SETS(KERNEL_SETS),
        .PIX_W(PIX_W), .COEF_W(COEF_W), .OUT_W(OUT_W)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .k_we(k_we), .k_wset(k_wset), .k_widx(k_widx), .k_din(k_din),
        .k_sel(k_sel),
        .px_valid(px_valid), .px_data(px_data),
        .out_valid(out_valid), .out_data(out_data), .frame_done(frame_done)
    );

    // ------------------------------------------------------------- stimulus
    reg [PIX_W-1:0]  img_mem [0:NPIX-1];
    reg [COEF_W-1:0] ker_mem [0:N*N-1];
    reg [OUT_W-1:0]  exp_mem [0:NOUT-1];

    reg [8*256-1:0] img_f, ker_f, exp_f;
    integer gaps = 0;

    // --------------------------------------------------------------- checker
    integer out_cnt = 0;
    integer err_cnt = 0;
    integer cycle = 0;
    integer first_px_cycle = -1;
    integer first_out_cycle = -1;
    integer done_seen = 0;

    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (px_valid && first_px_cycle < 0)
            first_px_cycle <= cycle;
        if (frame_done)
            done_seen <= done_seen + 1;
        if (out_valid) begin
            if (first_out_cycle < 0)
                first_out_cycle <= cycle;
            if (out_cnt < NOUT) begin
                if (out_data !== $signed(exp_mem[out_cnt])) begin
                    err_cnt <= err_cnt + 1;
                    if (err_cnt < 10)
                        $display("MISMATCH out[%0d] (row %0d col %0d): dut=%0d exp=%0d",
                                 out_cnt, out_cnt/(IMG_W-N+1), out_cnt%(IMG_W-N+1),
                                 out_data, $signed(exp_mem[out_cnt]));
                end
            end else begin
                err_cnt <= err_cnt + 1;
                if (err_cnt < 10)
                    $display("SPURIOUS extra output #%0d = %0d", out_cnt, out_data);
            end
            out_cnt <= out_cnt + 1;
        end
        if (cycle > NPIX*8 + 4000) begin
            $display("TIMEOUT: only %0d/%0d outputs after %0d cycles",
                     out_cnt, NOUT, cycle);
            $display("TB: FAIL");
            $finish;
        end
    end

    // ----------------------------------------------------------------- tasks
    task load_kernel(input integer set, input integer real_coeffs);
        integer i;
        begin
            for (i = 0; i < N*N; i = i + 1) begin
                @(negedge clk);
                k_we   = 1'b1;
                k_wset = set[SET_AW-1:0];
                k_widx = i[IDX_AW-1:0];
                // real kernel, or a decoy pattern to prove set isolation
                k_din  = real_coeffs ? $signed(ker_mem[i]) : 8'h55;
            end
            @(negedge clk);
            k_we = 1'b0;
        end
    endtask

    task stream_image;
        integer i;
        begin
            for (i = 0; i < NPIX; i = i + 1) begin
                if (gaps) begin
                    while (({$random} % 4) == 0) begin
                        @(negedge clk);
                        px_valid = 1'b0;
                    end
                end
                @(negedge clk);
                px_valid = 1'b1;
                px_data  = img_mem[i];
            end
            @(negedge clk);
            px_valid = 1'b0;
        end
    endtask

    // ------------------------------------------------------------------ main
    initial begin
        if (!$value$plusargs("IMG=%s", img_f)) img_f = "img.hex";
        if (!$value$plusargs("KER=%s", ker_f)) ker_f = "kernel.hex";
        if (!$value$plusargs("EXP=%s", exp_f)) exp_f = "expected.hex";
        if ($test$plusargs("GAPS")) gaps = 1;
        if ($test$plusargs("VCD")) begin
            $dumpfile("dump.vcd");
            $dumpvars(0, tb_conv_top);
        end

        $readmemh(img_f, img_mem);
        $readmemh(ker_f, ker_mem);
        $readmemh(exp_f, exp_mem);

        $display("TB: N=%0d image=%0dx%0d outputs=%0d kernel_set=%0d gaps=%0d",
                 N, IMG_W, IMG_H, NOUT, KSEL, gaps);

        repeat (5) @(negedge clk);
        rst_n = 1'b1;

        // decoy kernel into a neighbouring set, real kernel into set KSEL
        load_kernel((KSEL+1) % KERNEL_SETS, 0);
        load_kernel(KSEL, 1);

        @(negedge clk);
        k_sel = KSEL[SET_AW-1:0];
        repeat (2) @(negedge clk);   // registered coefficient mux settles

        stream_image;

        // drain the pipeline
        wait (out_cnt >= NOUT);
        repeat (20) @(negedge clk);

        $display("TB: outputs=%0d/%0d mismatches=%0d frame_done_pulses=%0d",
                 out_cnt, NOUT, err_cnt, done_seen);
        $display("TB: latency first-pixel -> first-output = %0d cycles",
                 first_out_cycle - first_px_cycle);
        if (err_cnt == 0 && out_cnt == NOUT && done_seen == 1)
            $display("TB: PASS");
        else
            $display("TB: FAIL");
        $finish;
    end

endmodule
