#!/usr/bin/env python3
"""HyperConv hybrid - baseline vs hybrid block diagram (matplotlib)."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

NAVY, ACCENT, LIGHT = "#1a365d", "#c55a11", "#f4f6f8"

def box(ax, x, y, w, h, text, fc=LIGHT, ec=NAVY, fs=9, bold=False):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02",
                                fc=fc, ec=ec, lw=1.4))
    ax.text(x + w/2, y + h/2, text, ha="center", va="center", fontsize=fs,
            color="#222", fontweight="bold" if bold else "normal")

def arrow(ax, x1, y1, x2, y2, color=NAVY, lw=1.6):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2),
                 arrowstyle="-|>", mutation_scale=14, color=color, lw=lw))

fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(11, 8.6))
for ax, title in ((ax1, "BASELINE  conv_top — 1 pixel/cycle, 9 DSP"),
                  (ax2, "HYBRID  conv_top_hybrid — 2 pixels/cycle, 9 DSP (DMP)")):
    ax.set_xlim(0, 12); ax.set_ylim(0, 3.4); ax.axis("off")
    ax.text(0.15, 3.15, title, fontsize=12, fontweight="bold",
            color=ACCENT if "HYBRID" in title else NAVY)

# ---- baseline row -----------------------------------------------------------
Y, H = 1.15, 0.85
box(ax1, 0.2, Y, 1.7, H, "px stream\n1 px/cyc", fc="#e8f0e8", bold=True)
box(ax1, 2.3, Y, 2.4, H, "window_gen\nN−1 line buffers (LUTRAM)\nN×N window regs")
box(ax1, 5.1, Y, 3.0, H, "mac_array\n9 × DSP48E1 mult\n2-stage adder tree")
box(ax1, 8.5, Y, 2.0, H, "sat + ReLU\ns16", fc="#fdece4")
box(ax1, 10.9, Y, 1.0, H, "out\n1 px/cyc", fc="#e8f0e8", bold=True)
box(ax1, 5.1, 2.35, 3.0, 0.65, "kernel_mem — 4 prog. sets", fs=8, fc="#fffbe8")
arrow(ax1, 1.9, Y+H/2, 2.3, Y+H/2)
arrow(ax1, 4.7, Y+H/2, 5.1, Y+H/2)
arrow(ax1, 8.1, Y+H/2, 8.5, Y+H/2)
arrow(ax1, 10.5, Y+H/2, 10.9, Y+H/2)
arrow(ax1, 6.6, 2.35, 6.6, Y+H)
ax1.text(6.0, 0.75, "6-stage MAC pipeline · latency 72 cyc (32×32, N=3) · "
         "248 LUT / 141 FF / 9 DSP / 0 BRAM · 0.135 W · FoM 10.6×10⁻³",
         fontsize=9, color="#555")

# ---- hybrid row -------------------------------------------------------------
box(ax2, 0.2, Y, 1.9, H, "px pairs\npx0,px1  2 px/cyc", fc="#e8f0e8", bold=True)
box(ax2, 2.5, Y, 2.6, H, "window_gen_2px\ninterleaved LUTRAM\n2 adjacent windows")
box(ax2, 5.5, Y, 3.3, H, "dmp_mac_array\n9 × DSP48E1, each computes\n"
    "BOTH windows (DMP packing)\n+ extraction & 2 adder trees", fs=8)
box(ax2, 9.2, Y, 1.9, H, "sat + ReLU\n×2  s16,s16", fc="#fdece4")
box(ax2, 11.4, Y, 0.8, H, "out\n2/cyc", fc="#e8f0e8", bold=True, fs=8)
box(ax2, 5.5, 2.35, 3.3, 0.65, "kernel_mem — 4 prog. sets (shared by both windows)",
    fs=8, fc="#fffbe8")
arrow(ax2, 2.1, Y+H/2, 2.5, Y+H/2)
arrow(ax2, 5.1, Y+H/2, 5.5, Y+H/2)
arrow(ax2, 8.8, Y+H/2, 9.2, Y+H/2)
arrow(ax2, 11.1, Y+H/2, 11.4, Y+H/2)
arrow(ax2, 7.15, 2.35, 7.15, Y+H)
ax2.text(4.1, 0.75, "A = {0, w1[k], 8'h00, w0[k]} · B = c[k]  →  "
         "P = w0·c + 2¹⁶·(w1·c)\np0 = P[15:0] · p1 = P[32:16] + P[15] (borrow)",
         fontsize=8.5, color=ACCENT, family="monospace",
         bbox=dict(fc="#fff6f0", ec=ACCENT, lw=0.8, boxstyle="round"))
ax2.text(0.2, 0.28, "7-stage MAC pipeline · 365 LUT / 532 FF / 9 DSP / 0 BRAM · "
         "0.164 W · FoM 14.96×10⁻³  (+41%)", fontsize=9, color="#555")

fig.suptitle("HyperConv baseline vs hybrid (DMP dual-multiply packing)",
             fontsize=13, fontweight="bold", color=NAVY, y=0.995)
plt.tight_layout(rect=[0, 0, 1, 0.97])
plt.savefig("docs/Images/block-diagram-hybrid.png", dpi=170)
print("saved docs/Images/block-diagram-hybrid.png")
