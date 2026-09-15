# HyperConv Hybrid Architecture — Results & Recommendation

Branch: `hybrid-dmp-multipumping` (baseline `main` untouched and fully reproducible)
Target: PYNQ-Z2, Zynq-7020, `xc7z020clg400-1`, Vivado 2025.2, OOC flow identical to baseline (`synth/build_hybrid.tcl` vs `synth/build.tcl`).

## 1. What was built

**conv_top_hybrid** — the proven HyperConv streaming architecture extended to
2 output pixels/cycle with **9 DSPs total** (same count as the 1-px baseline):

```
px0,px1 (2 px/cycle, even/odd column pair)
   ↓
window_gen_2px   interleaved LUTRAM line buffers (zero BRAM) +
                 (N+1)-wide row shifter → two adjacent N×N windows/beat
   ↓
dmp_mac_array    9 × DSP48E1, each computing BOTH windows' product for one
                 kernel position (dual-multiply packing), extraction +
                 borrow correction, two adder trees, dual saturation/ReLU
   ↓
out0,out1 (2 px/cycle, adjacent columns)
```

### 1.1 DMP: how two products fit in one DSP48E1

Packing two *arbitrary* 8×8 products into one DSP48E1 is **infeasible**: the
18-bit B port caps the operand stride at ~10 bits, and cross-terms then
contaminate the low product. But convolving two horizontally adjacent windows
multiplies **the same coefficient** with two different pixels — and that
packs exactly:

```
A = {1'b0, w1[k], 8'h00, w0[k]}      25-bit, never negative as signed
B = c[k]                              s8 (sign extension implicit)
P = A·B = w0[k]·c[k] + 2^16·(w1[k]·c[k])

p0[k] = $signed(P[15:0])              exact s16 (u8×s8 fits s16)
p1[k] = $signed(P[32:16]) + P[15]     +1 borrow correction when p0 < 0
```

Verified standalone (`experiments/dmp_probe`): 101,276 vectors (all corners
incl. 255×−128, full coefficient sweep, 100k random, continuous and gapped
valids) — **0 errors**, and synthesis infers **exactly 1 DSP48E1** per packed
multiply (3 LUT / 36 FF extraction overhead).

### 1.2 Why multipumping and DSP cascades were *not* used

* **DSP cascade accumulation** of the packed products is arithmetically
  impossible: cascading `ΣP_k = S0 + 2^16·S1` requires the window-0 sum S0
  (s19, up to ±9×32640) to fit below bit 16 — it does not. A stride ≥ 20
  would need a 36-bit A port (DSP48E1 has 25). The fabric adder tree after
  per-DSP extraction is the correct structure.
* **Multipumping (DSP @ 2×Fs)**: at 2 px/cycle the datapath needs 18
  multiplies/system-cycle. DMP already delivers exactly 18 on 9 DSPs in a
  single clock domain. Multipumping would deliver the same 18 (no gain) while
  adding an MMCM, 2× clock (~440 MHz on −1 fabric), and CDC on 36 product
  buses. Reaching 4 px/cycle (36 mults) would need 4-phase pumping
  (~880 MHz DSP clock) — not closable on this device. Multipumping is
  therefore **dominated** by static DMP for every reachable throughput.

## 2. Measured comparison (all numbers from Vivado, OOC @ 200 MHz)

| Architecture | LUT | FF | DSP | BRAM | WNS (ns) | Fmax | Power (W)* | px/cyc | FoM (×10⁻³) | Timing | Verif |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Baseline** `conv_top` | 248 | 141 | 9 | 0 | +0.441 | ~219 MHz | 0.135 | 1 | 10.60 | PASS | 11/11 |
| DMP probe (isolated) | 3 | 36 | 1 | 0 | — | — | — | n/a | n/a | — | 101k vec, 0 err |
| **Hybrid** `conv_top_hybrid` | 365 | 532 | 9 | 0 | **+0.502** | ~222 MHz | 0.164 | **2** | **14.96** | PASS | 11/11 |

\* Vectorless estimates, same methodology both designs (static 0.103 W,
hybrid dynamic 0.060 W vs baseline 0.032 W).

```
FoM = throughput / [power × (LUT + 50·DSP + 100·BRAM)]
baseline: 1 / [0.135 × (248 + 450)]        = 10.60×10⁻³
hybrid:   2 / [0.164 × (365 + 450)]        = 14.96×10⁻³   (+41%)
```

Eliminated candidates (analytically dominated, see §1.2):
* DMP bit-packing with *separate* coefficients — infeasible (18-bit B port).
* Multipumped 1-px (5 DSP): 1/[P×(LUT+250)] ≈ 12×10⁻³ best case — below
  hybrid, plus MMCM/CDC risk.
* 4-px + multipumping — needs ~880 MHz DSP clock, not closable on −1.
* 2-px without DMP (18 DSP): denominator +450 → FoM ≈ 10.6×10⁻³, no gain.

## 3. Verification

Identical golden model and testcases as baseline (`golden/`, `sim/tests/`),
run through `sim/run_all_hybrid.sh`:

| Test | Result | | Test | Result |
|---|---|---|---|---|
| identity_n3 | PASS | | saturate_max | PASS |
| hand_4x4 | PASS | | saturate_min | PASS |
| random_n3 | PASS | | relu_random | PASS |
| random_n3_gaps | PASS | | relu_neg | PASS |
| random_n5 | PASS | | sobel_x | PASS |
| | | | sobel_y | PASS |

**11/11 PASS, bit-exact** against the same expected files (interleaved
out0/out1 reassembled in row-major order). Overlapping windows, row/frame
boundaries, valid gaps, kernel-set isolation (decoy set), odd N (5×5) all
covered by the existing cases under the 2-px interface.

Pipeline: 7 cycles total (1 window register + 6 MAC stages: MREG, PREG,
extract, partial sums, final sum, saturate/ReLU). Steady state 2 px/cycle;
drain = 7 cycles. First-pair→first-output-pair incl. line-buffer ramp:
40 cycles (32×32, N=3), 73 cycles (N=5), 12 cycles (4×4, N=3).

RTL constraints (documented, satisfied by every testcase and the 32×32
minimum spec): `IMG_W` even, `N` odd (all competition kernels 3×3/5×5).
Then every beat produces exactly two valid outputs (`IMG_W−N+1` even).

## 4. Preserved features

Mandatory: ≥32×32 input ✓ (32×32 default, parameterizable), u8 input ✓, s8
kernel ✓, programmable N×N (N odd) ✓, stride 1 ✓, s16 saturated output ✓,
overflow handling ✓ (saturate_max/min pass), Python/MATLAB golden ✓
(unchanged files), bit-exact ✓.

Bonuses: board-demo capable (same kernel/valid/streaming protocol, needs a
2-px wrapper — not yet built), **2 px/cycle** ✓ (was 1), 4 programmable
kernel sets ✓, ReLU ✓, Sobel demo ✓ (same testcases).

## 5. Recommendation

**SUBMIT HYBRID** — if the submission window allows swapping the core:
+41% FoM (14.96 vs 10.60 ×10⁻³), same DSP count, same BRAM count, timing
closure with *more* slack than baseline, all 11 tests bit-exact, every
mandatory/bonus feature preserved, single clock domain (no MMCM/CDC risk).

**KEEP BASELINE** — if the deadline has passed or the board-demo bitstream
must ship as-is: `main` is untouched; the hybrid lives on
`hybrid-dmp-multipumping` with its own reports and can be demonstrated
later. The baseline board bitstream (`synth/board/build/hyperconv_selftest.bit`)
remains valid.

Remaining work to make the hybrid board-demo ready (not required for the
core competition numbers): `board_top_hybrid` wrapper feeding px0/px1 from
the selftest ROM + `board.xdc` reuse — estimated < 1 hour.
