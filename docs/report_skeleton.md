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

Golden model: `golden/conv_golden.py` (numpy, bit-exact including
saturation). Vector generator: `golden/gen_tests.py`. Self-checking TB
compares every output pixel; 9 testcases, all **PASS** (Vivado 2025.2 xsim):

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

Post-route (N=3, 32×32, 4 kernel sets), from synth/reports/:

| Metric | Value |
|---|---|
| CLB LUTs | 899 (801 logic + 98 LUTRAM) — 0.39 % |
| CLB Registers | 349 — 0.08 % |
| DSPs | **0** (Vivado mapped the 9 small u8×s8 multipliers to LUTs) |
| BRAMs | **0** (line buffers in distributed RAM, by design) |
| Timing | WNS **+0.865 ns** at 300 MHz → met; **Fmax ≈ 405 MHz** |
| Power | 0.635 W total = 0.592 W static (die leakage) + **0.043 W dynamic** |
| Power confidence | Medium (vectorless, default toggle rates) |

FoM = Throughput / (Power × (LUTs + 50·DSPs + 100·BRAMs))
    = 1 / (0.635 × 899) = **1.75 × 10⁻³** (total power)
    = 1 / (0.043 × 899) = 25.9 × 10⁻³ (dynamic-only, for discussion)

Note: static leakage of the large ZU7EV die dominates the power term and
therefore the FoM. See the Artix-7 comparison in section 8 — the same RTL
on a small part scores dramatically better.

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
| FPGA utilization | LUTs, FFs, DSPs, BRAMs | 899 / 349 / 0 / 0 | | ZCU106, post-route |
| Maximum frequency | — | 405 (WNS +0.865 @ 300 MHz) | MHz | timing met |
| Power estimate | — | 635 (43 dynamic + 592 static) | mW | report_power, vectorless |
| Verification status | Pass/Fail + cases | PASS, 9/9 cases | | bit-exact vs golden |
| FoM | Thr / (P × (LUT+50·DSP+100·BRAM)) | 1.75×10⁻³ | | ZCU106; see §8 for small-part FoM |

## 7. Assumptions (state all)

- Part: xczu7ev-ffvc1156-2-e (ZCU106); tool: Vivado 2025.2; OOC flow
  (accelerator is a core; pin/board integration out of scope)
- Clock target 300 MHz; power is vectorless estimate at default toggle rates
- Pixels stream row-major from the testbench (no bus interface); kernel
  loaded via dedicated write port before the frame
- k_sel stable ≥1 cycle before first pixel of a frame (registered mux)
- Zero padding **not** used — valid convolution, documented above
- Cross-correlation convention (no kernel flip), matching golden model

## 8. Tradeoffs discussion (TODO: expand)

- DSP vs LUT multipliers: Vivado chose LUTs for the small u8×s8 products
  (0 DSPs). FoM-wise 9 DSPs would add 450 to the denominator vs ~600 LUTs
  saved — roughly a wash; measure both with `(* use_dsp *)` if time allows.
- Frequency vs power: FoM throughput is per-cycle, so lower Fclk lowers
  power and *improves* FoM; Fmax reported separately for the timing criterion.
- Distributed RAM line buffers avoid the 100× BRAM FoM penalty at 32-px width.
- **Part choice dominates FoM through static power** (same RTL, post-route):

| | ZCU106 (XCZU7EV -2) | PYNQ-Z2/Zybo (XC7Z020 -1) |
|---|---|---|
| LUTs / FFs / DSPs / BRAMs | 899 / 349 / 0 / 0 | 942 / 387 / 0 / 0 |
| Fmax | ≈405 MHz | ≈183 MHz (WNS −0.476 @ 200 MHz; met at 166 MHz) |
| Power (total = static + dyn) | 0.635 = 0.592 + 0.043 W | 0.145 = 0.103 + 0.041 W |
| FoM (total power) | 1.75×10⁻³ | **7.3×10⁻³** (≈4.2× better) |

  The ZU7EV's die leakage (0.59 W) swamps the 43 mW the design actually
  uses. If the competition allows choosing the reported target, use the
  smallest part that fits (or the provided board's part).
