#!/usr/bin/env python3
"""HyperConv hybrid - baseline vs hybrid architecture diagram (matplotlib).

Regenerates docs/Images/block-diagram-hybrid.png. Two panels:
  top    - baseline conv_top datapath (6-stage pipeline ruler)
  bottom - hybrid conv_top_hybrid datapath with dmp_mac_array internals
           (packed DSPs, extraction/borrow, dual adder trees) and the
           DMP packing equation (7-stage pipeline ruler)
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Circle

NAVY, ACCENT, LIGHT = "#1a365d", "#c55a11", "#f4f6f8"
GREEN, PINK, CREAM = "#e8f0e8", "#fdece4", "#fffbe8"

def box(ax, x, y, w, h, text, fc=LIGHT, ec=NAVY, fs=8.5, bold=False):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02",
                                fc=fc, ec=ec, lw=1.4))
    ax.text(x + w/2, y + h/2, text, ha="center", va="center", fontsize=fs,
            color="#222", fontweight="bold" if bold else "normal")

def arrow(ax, x1, y1, x2, y2, color=NAVY, lw=1.6):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2),
                 arrowstyle="-|>", mutation_scale=13, color=color, lw=lw,
                 shrinkA=0, shrinkB=0))

def stages(ax, y, x0, x1, labels):
    """pipeline ruler: numbered circles + labels between x0 and x1"""
    n = len(labels)
    dx = (x1 - x0) / (n - 1)
    ax.plot([x0, x1], [y, y], color=NAVY, lw=1.2, zorder=1)
    for i, lab in enumerate(labels):
        cx = x0 + i * dx
        ax.add_patch(Circle((cx, y), 0.17, fc=ACCENT, ec="white", zorder=3))
        ax.text(cx, y, str(i + 1), ha="center", va="center", fontsize=8,
                color="white", fontweight="bold", zorder=4)
        ax.text(cx, y - 0.42, lab, ha="center", va="top", fontsize=7.6,
                color="#333")

fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(11.5, 10.4))

# ============================================================== baseline ====
ax1.set_xlim(0, 12); ax1.set_ylim(0, 4.9); ax1.axis("off")
ax1.text(0.15, 4.62, "BASELINE  conv_top — 1 pixel/cycle, 9 DSP",
         fontsize=12.5, fontweight="bold", color=NAVY)

Y, H = 2.55, 1.15
box(ax1, 0.15, Y, 1.45, H, "px stream\n1 px/cyc", fc=GREEN, bold=True)
box(ax1, 1.95, Y, 2.55, H, "window_gen\nN−1 LUTRAM line buffers\n"
    "N×N window shifter\nposition counters")
# mac_array outer + sub-blocks
box(ax1, 4.85, Y, 4.95, H, "", fc="#ffffff")
ax1.text(7.32, Y + H + 0.14, "mac_array", ha="center", fontsize=8.5,
         style="italic", color=NAVY)
box(ax1, 4.95, Y + 0.08, 1.55, H - 0.16, "9 × DSP48E1\nu8×s8 mult\nMREG|PREG",
    fc="#eef2f8", fs=7.6)
box(ax1, 6.62, Y + 0.08, 1.55, H - 0.16, "adder tree\npartial sums of 3\n→ final sum\n(s20 exact)",
    fc="#eef2f8", fs=7.6)
box(ax1, 8.29, Y + 0.08, 1.42, H - 0.16, "saturate\n+ ReLU\n→ s16", fc=PINK, fs=7.6)
box(ax1, 10.15, Y, 1.35, H, "out stream\n1 px/cyc", fc=GREEN, bold=True)
box(ax1, 4.85, 3.95, 4.95, 0.55, "kernel_mem — 4 runtime-programmable sets, registered select mux",
    fs=8, fc=CREAM)
arrow(ax1, 1.60, Y+H/2, 1.95, Y+H/2)
arrow(ax1, 4.50, Y+H/2, 4.85, Y+H/2)
arrow(ax1, 6.50, Y+H/2, 6.62, Y+H/2)
arrow(ax1, 8.17, Y+H/2, 8.29, Y+H/2)
arrow(ax1, 9.71, Y+H/2, 10.15, Y+H/2)
arrow(ax1, 7.32, 3.95, 7.32, Y + H)
ax1.text(6.0, 0.95, "248 LUT / 141 FF / 9 DSP / 0 BRAM · WNS +0.441 @ 200 MHz · "
         "0.135 W · FoM 10.6×10⁻³", fontsize=9, color="#555", ha="center")
stages(ax1, 1.90, 2.6, 9.6,
       ["window regs", "DSP MREG", "DSP PREG", "partial sums",
        "final sum", "saturate/ReLU"])
ax1.text(0.15, 0.35, "latency 6 cyc + line-buffer ramp · 72 cyc total (32×32, N=3) · "
         "free-running: no datapath FSM, arbitrary input stalls",
         fontsize=8.5, color="#777")

# ================================================================ hybrid ====
ax2.set_xlim(0, 12); ax2.set_ylim(0, 5.4); ax2.axis("off")
ax2.text(0.15, 5.14, "HYBRID  conv_top_hybrid — 2 pixels/cycle, same 9 DSP (DMP)",
         fontsize=12.5, fontweight="bold", color=ACCENT)

Y, H = 2.95, 1.30
box(ax2, 0.15, Y, 1.45, H, "px pairs\npx0,px1\n2 px/cyc", fc=GREEN, bold=True)
box(ax2, 1.95, Y, 2.55, H, "window_gen_2px\neven/odd interleaved\nLUTRAM line buffers\n"
    "(N+1)-wide row shifter\n→ 2 adjacent windows", fs=7.8)
# dmp_mac_array outer + sub-blocks
box(ax2, 4.85, Y, 4.95, H, "", fc="#ffffff")
ax2.text(7.32, Y + H + 0.14, "dmp_mac_array", ha="center", fontsize=8.5,
         style="italic", color=ACCENT)
box(ax2, 4.95, Y + 0.08, 1.55, H - 0.16, "9 × DSP48E1\neach computes\nBOTH windows\n(DMP packed)",
    fc="#fdf0e8", fs=7.4)
box(ax2, 6.62, Y + 0.08, 1.55, H - 0.16, "extract\np0 = P[15:0]\np1 = P[32:16]\n+ P[15] borrow",
    fc="#eef2f8", fs=7.4)
box(ax2, 8.29, Y + 0.08, 1.42, H - 0.16, "2 adder trees\n→ s21 exact\nsat + ReLU ×2\n→ s16, s16",
    fc="#eef2f8", fs=7.4)
box(ax2, 10.15, Y, 1.35, H, "out pairs\nout0,out1\n2 px/cyc", fc=GREEN, bold=True, fs=8.5)
box(ax2, 4.85, 4.48, 4.95, 0.55, "kernel_mem — 4 sets, SHARED by both windows (same coefficients)",
    fs=8, fc=CREAM)
arrow(ax2, 1.60, Y+H/2, 1.95, Y+H/2)
arrow(ax2, 4.50, Y+H/2, 4.85, Y+H/2)
arrow(ax2, 6.50, Y+H/2, 6.62, Y+H/2)
arrow(ax2, 8.17, Y+H/2, 8.29, Y+H/2)
arrow(ax2, 9.71, Y+H/2, 10.15, Y+H/2)
arrow(ax2, 7.32, 4.48, 7.32, Y + H)
ax2.text(6.0, 1.35, "365 LUT / 532 FF / 9 DSP / 0 BRAM · WNS +0.502 @ 200 MHz · "
         "0.164 W · FoM 14.96×10⁻³   (+41% vs baseline)",
         fontsize=9, color="#555", ha="center")
stages(ax2, 2.30, 2.6, 9.6,
       ["window regs", "DSP MREG", "DSP PREG", "extract+borrow",
        "partial sums", "final sums", "sat/ReLU ×2"])
ax2.text(2.9, 0.98, "DMP packing (per DSP, per kernel position k — windows share c[k]):",
         fontsize=8.5, color=ACCENT, ha="center", fontweight="bold")
ax2.text(6.0, 0.40, "A = {0, w1[k], 8'h00, w0[k]}   B = c[k]   →   P = w0·c + 2¹⁶·(w1·c)\n"
         "p0 = $signed(P[15:0])  (exact s16)   p1 = $signed(P[32:16]) + P[15]  (borrow fix)",
         fontsize=8.5, color=ACCENT, family="monospace", ha="center",
         bbox=dict(fc="#fff6f0", ec=ACCENT, lw=0.8, boxstyle="round"))
ax2.text(0.15, 0.06, "verified: 101k-vector DMP probe (0 err) · 11/11 golden testcases bit-exact · "
         "board selftest bitstream: 579 LUT / 9 DSP / 0 BRAM, WNS +3.068 @ 100 MHz",
         fontsize=8, color="#777")

fig.suptitle("HyperConv — baseline vs hybrid architecture (DMP dual-multiply packing)",
             fontsize=13.5, fontweight="bold", color=NAVY, y=0.995)
plt.tight_layout(rect=[0, 0, 1, 0.97])
plt.savefig("docs/Images/block-diagram-hybrid.png", dpi=170)
print("saved docs/Images/block-diagram-hybrid.png")
