# 2026 IEEE SSCS Egypt Student Design Competition — Project Plan

## Competition Overview

| Item | Detail |
|------|--------|
| **Organizer** | IEEE Solid-State Circuits Society (SSCS) — Egypt Chapter |
| **Theme** | FPGA-based Edge-AI vision accelerator |
| **Core task** | Design an **N×N CNN convolution** accelerator for a small grayscale image or feature map |
| **Registration deadline** | **July 25, 2026** |
| **Registration form** | https://forms.gle/qQUpg3hM5ZgPPDgw8 |
| **Team size** | 1–4 students |
| **Report submission** | **September 15, 2026** |
| **Winners announced** | **September 30, 2026** |

---

## Eligibility

- Undergraduate students from **public, private, or national universities in Egypt**
- Students **graduating in 2026 are not eligible**
- HDL choice is free: **Verilog, SystemVerilog, VHDL**, or any HDL
- Report must clearly explain digital architecture and implementation decisions

---

## Mandatory Technical Specifications

| # | Requirement | Notes |
|---|-------------|-------|
| 1 | **Input size** | Minimum **32×32** pixels; larger sizes allowed |
| 2 | **Input type** | Grayscale image or single-channel feature map |
| 3 | **Input precision** | **Fixed-point unsigned**; justify bit-width in report |
| 4 | **Kernel** | **N×N convolution**; coefficients must be **programmable/configurable** |
| 5 | **Kernel precision** | **8-bit signed** fixed-point or integer |
| 6 | **Stride** | **1** |
| 7 | **Output precision** | Minimum **16-bit signed**; document overflow/truncation/saturation/rounding |
| 8 | **Verification** | Golden reference in **Python, MATLAB, or C**; compare HW vs. reference |
| 9 | **FPGA results** | LUTs, FFs, DSPs, BRAMs, max frequency, timing status, power estimate |
| 10 | **Figure of Merit (FoM)** | Required metric (see below) |

### Optional Bonus Features

- ReLU activation (post-processing)
- Board demonstration
- One-output-pixel-per-cycle pipelined architecture
- Support for multiple kernels
- Edge-detection / industrial-inspection demo

---

## Figure of Merit (FoM)

Higher FoM = more efficient design.

```
FoM = Throughput / (Power × (LUTs + 50×DSPs + 100×BRAMs))
```

- **Throughput** = output pixels per cycle
- **Power** = estimated power from FPGA tools
- **LUTs, DSPs, BRAMs** = synthesis/implementation utilization

**Design implication:** Maximize throughput while minimizing power and FPGA resources (weighted toward DSPs and BRAMs).

---

## Evaluation Criteria

Designs are ranked on:

1. **Correctness** (mandatory)
2. **Digital design quality**
3. **FPGA resource usage** (LUTs, FFs, DSPs, BRAMs)
4. **Latency**
5. **Throughput**
6. **Timing closure**
7. **Power estimate**
8. **FoM**

All mandatory specifications must be met before competitive scoring applies.

---

## Deliverables Checklist

### Report (required)

- [ ] Accelerator architecture overview
- [ ] Block diagram
- [ ] Datapath description
- [ ] FSM state diagram
- [ ] Memory / buffer organization
- [ ] Line-buffer or window-generation method
- [ ] Fixed-point bit-width analysis
- [ ] RTL implementation details
- [ ] Testbench description
- [ ] Golden model description
- [ ] Waveform screenshots
- [ ] FPGA synthesis results
- [ ] Timing report
- [ ] Power report
- [ ] Design tradeoffs discussion
- [ ] **Table 1** (see below) filled with team results
- [ ] All assumptions stated explicitly

### Source & Artifacts (required)

- [ ] RTL source files
- [ ] Testbench
- [ ] Golden reference model (Python / MATLAB / C)
- [ ] Input test images or feature maps
- [ ] Expected output files
- [ ] FPGA reports (utilization, timing, power)
- [ ] Short presentation

### Optional Bonus

- [ ] Board demo
- [ ] 1 output pixel/cycle pipeline
- [ ] Multiple kernel support
- [ ] ReLU activation
- [ ] Edge-detection / inspection demo

---

## Required Report Table (Table 1)

| Parameter | Specification | Team Result | Units | Comments |
|-----------|---------------|-------------|-------|----------|
| Input image size | ≥ 32×32 | | pixels | |
| Input precision | Fixed-point unsigned | | bits | Justify choice |
| Kernel precision | 8-bit signed | | bits | |
| Architecture type | | | | e.g. systolic, line-buffer |
| Multipliers / MACs | | | | |
| Pipeline stages | | | | |
| Latency | | | cycles | |
| Throughput | | | pixels/cycle | |
| FPGA utilization | LUTs, FFs, DSPs, BRAMs | | | |
| Maximum frequency | | | MHz | |
| Power estimate | | | W or mW | |
| Verification status | Pass/Fail + cases | | | |
| FoM | Per formula | | | Higher is better |

---

## Awards

| Place | Prize |
|-------|-------|
| Gold | **$350 USD** |
| Silver | **$250 USD** |
| Bronze | **$150 USD** |

---

## Project Timeline

```
Jul 2  ─────────────────────────────────────────────────────────────► Sep 30
         │                    │                    │              │
    Start plan            Register by          Submit report   Winners
    & architecture        Jul 25, 2026         Sep 15, 2026    Sep 30, 2026
```

| Phase | Target Date | Milestone |
|-------|-------------|-----------|
| **Phase 0 — Setup** | Jul 2–10 | Form team, register, pick FPGA board & tools |
| **Phase 1 — Architecture** | Jul 10–25 | Block diagram, fixed-point analysis, memory plan |
| **Phase 2 — Golden Model** | Jul 15–Aug 5 | Python/C reference for N×N conv, stride=1 |
| **Phase 3 — RTL** | Jul 25–Aug 20 | Datapath, FSM, line-buffer/window gen, configurable kernel |
| **Phase 4 — Verification** | Aug 15–Sep 1 | Testbench, multi-case HW vs. golden, waveforms |
| **Phase 5 — Synthesis** | Aug 25–Sep 5 | Place & route, timing closure, power report |
| **Phase 6 — FoM & Report** | Sep 1–12 | Fill Table 1, tradeoffs, presentation |
| **Phase 7 — Submit** | **Sep 15** | Report + RTL + artifacts + presentation |
| **Phase 8 — Results** | **Sep 30** | Winner announcement |

---

## Implementation Plan

### 1. Architecture Decisions (to lock early)

| Decision | Recommendation | Rationale |
|----------|------------------|-----------|
| Kernel size N | Start with **3×3** (extendable) | Common for edge-AI; simpler window logic |
| Input size | **32×32** (minimum) | Meets spec; keeps BRAM usage manageable |
| Input precision | **8-bit unsigned** | Matches typical grayscale; document in report |
| Output precision | **16-bit signed** | Meets minimum; define rounding/saturation |
| Architecture | **Line-buffer + sliding window** | Standard for conv accelerators; good for report |
| Target FPGA | Choose one board early | Affects BRAM/DSP budgets and timing |

### 2. Datapath Components

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐    ┌──────────────┐
│ Input BRAM  │───►│ Line Buffers │───►│ Window Gen  │───►│ MAC Array    │
│ (32×32×8b)  │    │ (2 or N-1    │    │ (N×N regs)  │    │ (N×N × 8b)   │
└─────────────┘    │  rows)       │    └─────────────┘    └──────┬───────┘
                   └──────────────┘                                │
┌─────────────┐    ┌──────────────┐    ┌─────────────┐           │
│ Kernel Regs │───►│ Config IF    │    │ Accumulator │◄──────────┘
│ (N×N×8s)    │    │ (load coeffs)│    │ (16-bit s)  │
└─────────────┘    └──────────────┘    └──────┬───────┘
                                              │
                                       ┌──────▼───────┐
                                       │ Output BRAM  │
                                       │ (optional    │
                                       │  ReLU bonus) │
                                       └──────────────┘
```

### 3. Control FSM States (draft)

1. **IDLE** — wait for start
2. **LOAD_KERNEL** — shift in N×N configurable coefficients
3. **LOAD_IMAGE** — fill input buffer / stream pixels
4. **COMPUTE** — iterate output positions (stride=1)
5. **WRITE_OUTPUT** — store 16-bit signed results
6. **DONE** — assert done flag

### 4. Fixed-Point Analysis (report section)

- Define: input (UQm.n), kernel (SQm.n, 8-bit), accumulator width, output (SQm.n, ≥16-bit)
- Document: product width, sum tree depth, overflow policy (saturation vs. wrap)
- Show numeric example for one convolution step

### 5. Verification Strategy

| Test case | Purpose |
|-----------|---------|
| Single pixel + identity-like kernel | Sanity check |
| 3×3 kernel on 4×4 patch | Hand-verifiable |
| Full 32×32 image, random kernel | Full functional test |
| Edge kernel (Sobel-like) | Realistic edge-AI use case |
| Max/min input values | Overflow & saturation behavior |

Golden model flow:
```
input_image + kernel → conv2d(stride=1) → round/sat → 16-bit signed → compare RTL
```

### 6. FPGA Optimization for FoM

| Lever | Action |
|-------|--------|
| Throughput ↑ | Pipeline MAC stages; target **1 pixel/cycle** (bonus) |
| Power ↓ | Clock gating, reduce toggle rate, lower Fmax if acceptable |
| LUTs ↓ | Share multipliers, time-multiplex if needed |
| DSPs ↓ | Map MACs to DSP48 blocks efficiently |
| BRAMs ↓ | Minimal line buffers; dual-port BRAM for input/output |

### 7. Report Assumptions (document all)

- Target FPGA part number and tool version
- Clock frequency target
- Input loading mechanism (AXI, custom interface, or testbench direct)
- Kernel loading protocol
- Padding policy (zero-padding assumed unless stated otherwise)
- Power estimation method (Xilinx Power Estimator / Intel Power Analyzer)

---

## Risk Register

| Risk | Mitigation |
|------|------------|
| Timing not closing | Pipeline earlier; reduce Fmax target; simplify control |
| BRAM overflow | Use minimum 32×32; optimize buffer depth |
| Fixed-point mismatch vs. golden | Lock bit-widths before RTL; bit-exact model |
| Late registration | Submit form before **Jul 25** |
| Incomplete verification | Start golden model in Phase 2, parallel with RTL |

---

## Immediate Next Steps

1. **Register team** at https://forms.gle/qQUpg3hM5ZgPPDgw8 before July 25, 2026
2. **Select FPGA board** and install synthesis toolchain
3. **Choose N** (kernel size) and input/output bit-widths
4. **Write golden model** (Python recommended for speed)
5. **Draw architecture block diagram** and FSM
6. **Begin RTL** with line-buffer and configurable kernel interface

---

## Key Constraints Summary

> Design a **configurable N×N convolution accelerator** on FPGA for **≥32×32 grayscale** input, **8-bit unsigned** activations, **8-bit signed** kernel, **stride 1**, **≥16-bit signed** output — verified against a software golden model, with full FPGA utilization/timing/power reports and FoM calculation.
