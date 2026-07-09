# HyperConv — Competition Report Skeleton

> Working draft for the 2026 IEEE SSCS Egypt Student Design Competition report.
> Sections map 1:1 to the deliverables checklist in plan.md. Items marked
> `TODO` need content or final numbers.

## 1. Architecture overview

Streaming line-buffer + sliding-window architecture, fully pipelined at
**1 output pixel per cycle** (bonus feature):

```
px stream ──► window_gen ──────────► mac_array ──► out stream (s16, saturated)
              │ N−1 line buffers      │ N² multipliers
              │ (distributed RAM)     │ two-stage adder tree
              │ N×N window regs       │ saturation stage
              └ position counters     └ 4-stage pipeline
kernel bus ─► kernel_mem (4 programmable sets, registered select mux)
```

- **No control FSM is needed for the datapath**: the design is a free-running
  pipeline gated by `px_valid`; position counters derive window validity.
  (Report should explain this as a deliberate simplification over the
  classic LOAD/COMPUTE/WRITE FSM — fewer states, no dead cycles.)
- **"Valid" convolution** (no padding): output is (H−N+1)×(W−N+1).
  Assumption stated explicitly; frames can stream back-to-back with no
  flush cycles because window validity is position-based.
- Input stalls (`px_valid` low) are tolerated arbitrarily; verified with
  randomized-gap testcase.

## 2. Fixed-point analysis

| Signal | Format | Range | Bits |
|---|---|---|---|
| Input pixel | UQ8.0 | 0 … 255 | 8 (unsigned) |
| Coefficient | SQ8.0 | −128 … +127 | 8 (signed) |
| Product | u8×s8 | −32 640 … +32 385 | 16 (signed) |
| Partial sum (3 products) | 16 + 2 | ±97 155 max | 18 (signed) |
| Accumulator (N=3) | 18 + ⌈log₂3⌉ | ±291 465 max | 20 (signed) |
| Output | SQ16.0 | −32 768 … +32 767 | 16 (signed, **saturated**) |

- Accumulator is full-precision → **no intermediate overflow possible**;
  the only precision decision is the final saturation to 16 bits
  (no rounding needed — integer arithmetic is exact).
- Numeric example (TODO: copy one window from hand_4x4 testcase).
- Justification of 8-bit unsigned input: native grayscale range.

## 3. RTL implementation

- `conv_top.v` — integration + frame_done bookkeeping
- `window_gen.v` — counters, N−1 chained line buffers, N×N window shifter
- `line_buffer.v` — async-read row RAM → distributed RAM, **0 BRAM**
- `kernel_mem.v` — 4 kernel sets × N² × s8, single write port, registered mux
- `mac_array.v` — N² multipliers, two-stage adder tree (partial sums of 3,
  then final sum — keeps logic depth low on slow fabrics), saturation;
  valid-gated data registers for power
- Pipeline latency: 5 cycles (window reg → product → partial → sum → saturate)

## 4. Verification

Golden models: `golden/conv_golden.py` (numpy) and `golden/conv_golden.m`
(MATLAB/Octave), both bit-exact including saturation. Vector generator:
`golden/gen_tests.py`. Verification is a three-way cross-check: the
self-checking TB compares every output pixel against the Python golden
files, dumps the raw RTL outputs (`dut_out.hex`), and
`golden/check_all_tests.m` independently recomputes each case in MATLAB
and compares against both. 9 testcases, all **PASS** (Vivado 2025.2 xsim):

| Testcase | Purpose | Result |
|---|---|---|
| identity_n3 | Sanity: output = cropped input | PASS |
| hand_4x4 | Hand-verifiable 4×4, all-ones kernel | PASS |
| random_n3 | Full random image + kernel | PASS |
| random_n3_gaps | Same, with random input stalls | PASS |
| sobel_x / sobel_y | Edge-detection demo (bonus) | PASS |
| saturate_max / min | ±saturation extremes | PASS |
| random_n5 | 5×5 kernel (N parameterization) | PASS |

TODO: waveform screenshots (xsim `+VCD` or Vivado GUI on the routed dcp).

## 5. FPGA results (ZCU106, xczu7ev-ffvc1156-2-e, Vivado 2025.2, OOC, 300 MHz target)

Post-route, chosen configuration (DSP multipliers — the RTL default;
N=3, 32×32, 4 kernel sets), from synth/reports_zu_dsp/:

| Metric | Value |
|---|---|
| CLB LUTs | 263 — 0.11 % |
| CLB Registers | 140 — 0.03 % |
| DSPs | **9** (DSP48E2, one per product; hard regs absorb pipeline FFs) |
| BRAMs | **0** (line buffers in distributed RAM, by design) |
| Timing | WNS **+1.094 ns** at 300 MHz → met (hold met, WHS +0.036 ns); **Fmax ≈ 446 MHz** (incl. I/O budget; internal fabric paths alone ≈ 598 MHz) |
| Power | 0.621 W total = 0.592 W static (die leakage) + **0.029 W dynamic** |
| Power confidence | Medium (vectorless, default toggle rates) |
| Methodology (`report_methodology`) | **0 violations** (clean) |

FoM = Throughput / (Power × (LUTs + 50·DSPs + 100·BRAMs))
    = 1 / (0.621 × (263 + 450)) = **2.26 × 10⁻³** (total power)
    = 1 / (0.029 × 713) = 48.4 × 10⁻³ (dynamic-only, for discussion)

Note: static leakage of the large ZU7EV die dominates the power term and
therefore the FoM. See section 8 — the same RTL on the small Zynq-7020
scores ≈4.3× better (9.79 × 10⁻³), and the LUT-multiplier variant is
measured there as the justification for choosing DSP mapping.

## 6. Table 1 (required)

| Parameter | Specification | Team Result | Units | Comments |
|-----------|---------------|-------------|-------|----------|
| Input image size | ≥ 32×32 | 32×32 (parameterizable) | pixels | IMG_W/IMG_H params |
| Input precision | Fixed-point unsigned | 8 | bits | native grayscale |
| Kernel precision | 8-bit signed | 8 | bits | 4 programmable sets |
| Architecture type | — | line-buffer + sliding window, fully pipelined | | |
| Multipliers / MACs | — | N² = 9 (N=3) | | mapped to DSP48E2 |
| Pipeline stages | — | 5 | | window→prod→partial→sum→sat |
| Latency | — | 71 (32×32, N=3) | cycles | first px → first out |
| Throughput | — | 1 steady-state (0.879 frame-avg) | pixels/cycle | 900 out / 1024 in |
| FPGA utilization | LUTs, FFs, DSPs, BRAMs | 263 / 140 / 9 / 0 | | ZCU106, post-route, DSP variant |
| Maximum frequency | — | 446 (WNS +1.094 @ 300 MHz) | MHz | timing met, incl. I/O delay budget |
| Power estimate | — | 621 (29 dynamic + 592 static) | mW | report_power, vectorless |
| Verification status | Pass/Fail + cases | PASS, 9/9 cases | | bit-exact vs golden |
| FoM | Thr / (P × (LUT+50·DSP+100·BRAM)) | 2.26×10⁻³ | | ZCU106; 9.79×10⁻³ on Z7020 (§8) |

## 7. Assumptions (state all)

- Part: xczu7ev-ffvc1156-2-e (ZCU106); tool: Vivado 2025.2; OOC flow
  (accelerator is a core; pin/board integration out of scope)
- Clock target 300 MHz; power is vectorless estimate at default toggle rates
- Core ports constrained with an input/output delay budget of 25% of the
  period (max/setup) and 10% (min/hold), so port paths are timed (TIMING-18)
  and the max/min corners are distinguished (XDCH-2). `report_methodology`
  is clean (0 violations); `report_timing_summary` meets setup and hold
- SSN (simultaneous switching noise) is reported as "No Analysis / 0 ports"
  — the OOC core has no package-pin assignments, so SSN is not applicable
  (it would only apply to a pin-constrained board wrapper)
- Pixels stream row-major from the testbench (no bus interface); kernel
  loaded via dedicated write port before the frame
- k_sel stable ≥1 cycle before first pixel of a frame (registered mux)
- Zero padding **not** used — valid convolution, documented above
- Cross-correlation convention (no kernel flip), matching golden model

## 8. Tradeoffs discussion (TODO: expand)

- Adder-tree pipelining: the original single-stage 9-input tree was the
  critical path on 7-series (6.5 ns, 9 logic levels). Splitting it into
  partial-sums-of-3 + final sum (+1 cycle latency) raised ZCU106 Fmax from
  405 to 479 MHz and *reduced* LUTs (899→842) — shallower carry chains
  pack better. Good report narrative: measured, not guessed.
- DSP vs LUT multipliers: with LUT multipliers the Z7020 critical path is
  the 9×8 multiply itself (5.8 ns), and synthesis raises 72 SYNTH-9
  warnings suggesting USE_DSP48. DSP mapping is now the RTL default;
  `-tclargs <part> <ns> <tag> lutmult` reproduces the LUT variant:

| Variant (post-route) | ZCU106 LUT-mult | ZCU106 DSP | Z7020 LUT-mult | Z7020 DSP |
|---|---|---|---|---|
| LUTs / FFs / DSPs | 842 / 404 / 0 | 263 / 140 / 9 | 851 / 463 / 0 | 290 / 140 / 9 |
| Fmax | ≈479 MHz | ≈598 MHz | ≈173 MHz | ≈259 MHz |
| Power total (dyn) W | 0.633 (0.041) | 0.621 (0.029) | 0.146 (0.043) | 0.138 (0.034) |
| FoM (total power) | 1.88×10⁻³ | 2.26×10⁻³ | 8.05×10⁻³ | **9.79×10⁻³** |

  Verdict: the DSP variant wins on *every* axis — the 50/DSP FoM penalty
  (9 DSPs = 450) is outweighed by the ~560 LUTs saved, and the DSP's hard
  registers absorb the product/partial-sum FFs (404→140) while cutting
  dynamic power and raising Fmax. **DSP mapping is the chosen
  configuration**; LUT-mult numbers retained to justify the choice.

- Frequency vs power: FoM throughput is per-cycle, so lower Fclk lowers
  power and *improves* FoM; Fmax reported separately for the timing criterion.
- Distributed RAM line buffers avoid the 100× BRAM FoM penalty at 32-px width.
- **Part choice dominates FoM through static power**: the ZU7EV's die
  leakage (0.59 W) swamps the ~41 mW the design actually uses; the same RTL
  on the Z7020 scores ≈4.3× better FoM. If the competition allows choosing
  the reported target, use the smallest part that fits (or the provided
  board's part).
