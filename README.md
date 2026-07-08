# HyperConv — N×N Convolution Accelerator

Entry for the **2026 IEEE SSCS Egypt Student Design Competition** (see
[plan.md](plan.md)): a fully pipelined, FPGA-based N×N convolution
accelerator for grayscale images / single-channel feature maps.

## Specifications

| Parameter | Value |
|---|---|
| Kernel | N×N (synthesis parameter, default 3×3), stride 1 |
| Coefficients | 8-bit signed, runtime-programmable, **4 selectable kernel sets** |
| Input | ≥32×32 (parameter), 8-bit unsigned pixels, streamed row-major |
| Output | 16-bit signed, saturated, "valid" convolution ((H−N+1)×(W−N+1)) |
| Throughput | **1 output pixel/cycle** in steady state (fully pipelined) |
| Latency | (N−1)·IMG_W + N pixels to first window + 5 pipeline cycles (71 total for 32×32, N=3) |
| BRAM | 0 — line buffers use distributed (LUT) RAM at these sizes |

Convolution is implemented as cross-correlation (no kernel flip), the CNN
framework convention; the golden model is bit-exact identical.

## Repository layout

```
rtl/        conv_top.v (top) · window_gen.v · line_buffer.v · kernel_mem.v · mac_array.v
tb/         tb_conv_top.v — self-checking, file-driven testbench
golden/     conv_golden.py — bit-exact reference · gen_tests.py — vector generator
sim/        run_all.sh — batch xsim runner · tests/<case>/ — generated vectors
synth/      build.tcl — OOC synth+impl for ZCU106 (XCZU7EV) · ooc.xdc · reports/
docs/       report material
```

## How to run

Requires Vivado (tested with 2025.2 at `/tools/2025.2/Vivado`; override with
`XILINX_VIVADO`) and Python 3 + numpy.

```bash
python3 golden/gen_tests.py     # generate stimulus + golden outputs
sim/run_all.sh                  # compile + simulate all 9 testcases (xsim)
sim/run_all.sh random_n5        # or a single testcase

# synthesis + implementation reports (utilization / timing / power):
vivado -mode batch -source synth/build.tcl
```

Every test prints `TB: PASS/FAIL` plus measured latency; the runner
summarizes. Add `-testplusarg VCD` in `run_all.sh` (or run xsim manually) to
dump waveforms.

## FPGA results (post-route, Vivado 2025.2, out-of-context, N=3, 32×32)

Two multiplier mappings measured on two parts; **DSP variant is the chosen
configuration** (better on every axis — the hard DSP registers absorb the
pipeline FFs and shorten the multiply path):

| | ZCU106 LUT-mult | **ZCU106 DSP** | Z7020 LUT-mult | **Z7020 DSP** |
|---|---|---|---|---|
| LUTs / FFs / DSPs / BRAMs | 842 / 404 / 0 / 0 | 263 / 140 / 9 / 0 | 851 / 463 / 0 / 0 | 290 / 140 / 9 / 0 |
| Fmax (constraint) | 479 MHz (300 ✓) | **598 MHz** (300 ✓)¹ | 173 MHz (200 ✗) | **259 MHz** (200 ✓) |
| Power: static + dynamic | 0.592 + 0.041 W | 0.592 + 0.029 W | 0.103 + 0.043 W | 0.103 + 0.034 W |
| FoM = Thr/(P·(LUT+50·DSP+100·BRAM)) | 1.88×10⁻³ | 2.26×10⁻³ | 8.05×10⁻³ | **9.79×10⁻³** |

ZCU106 = XCZU7EV-2 (user board); Z7020 = XC7Z020-1 (PYNQ-Z2/Zybo class).
The FoM gap between parts is almost entirely static power — the design
itself burns ≤43 mW.
¹ Internal fabric paths; with the 25%-period I/O delay budget now in the
constraints the reported WNS is +1.094 ns @ 300 MHz (Fmax ≈ 446 MHz).
The methodology report is clean: 0 SYNTH-9, 0 TIMING-18.

Reproduce with `vivado -mode batch -source synth/build.tcl -tclargs
<part> <clk_ns> <tag> [lutmult]` (no tclargs = ZCU106 @ 300 MHz; DSP
multipliers are the default, `lutmult` forces the LUT variant). Reports
land in `synth/reports*/`. See `docs/report_skeleton.md` for the report
draft.

## Verification status

All 9 testcases pass bit-exact against the golden model (Vivado 2025.2 xsim):
identity, hand-checked 4×4, full random 32×32 (contiguous and with random
input stalls), Sobel X/Y edge-detection demo, ±saturation extremes, and a
5×5-kernel run proving N parameterization. Kernel-set isolation is exercised
in every test by loading a decoy kernel into a neighboring set.
