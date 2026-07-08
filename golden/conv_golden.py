#!/usr/bin/env python3
"""
HyperConv golden reference model.

Bit-exact software reference for the RTL accelerator:
  - N x N kernel, stride 1, "valid" output (no padding): (H-N+1) x (W-N+1)
  - Cross-correlation (no kernel flip), matching CNN-framework convention
  - Input pixels : unsigned 8-bit (0..255)
  - Coefficients : signed 8-bit (-128..127)
  - Accumulation : full precision (no intermediate overflow possible)
  - Output       : signed 16-bit with saturation to [-32768, 32767]
"""

import numpy as np

OUT_BITS = 16
OUT_MIN = -(1 << (OUT_BITS - 1))
OUT_MAX = (1 << (OUT_BITS - 1)) - 1


def conv2d_sat(img, kernel):
    """Golden convolution. img: HxW uint8-range ints, kernel: NxN int8-range ints.

    Returns (H-N+1) x (W-N+1) int32 array saturated to signed 16-bit.
    """
    img = np.asarray(img, dtype=np.int64)
    ker = np.asarray(kernel, dtype=np.int64)
    assert img.min() >= 0 and img.max() <= 255, "input pixels must be u8"
    assert ker.min() >= -128 and ker.max() <= 127, "coefficients must be s8"
    h, w = img.shape
    n = ker.shape[0]
    assert ker.shape == (n, n) and h >= n and w >= n
    oh, ow = h - n + 1, w - n + 1
    out = np.empty((oh, ow), dtype=np.int64)
    for r in range(oh):
        for c in range(ow):
            out[r, c] = int(np.sum(img[r:r + n, c:c + n] * ker))
    return np.clip(out, OUT_MIN, OUT_MAX).astype(np.int32)


# ---------------------------------------------------------------- hex file I/O
# One value per line, row-major, two's-complement hex ($readmemh compatible).

def write_hex_u8(path, arr):
    with open(path, "w") as f:
        for v in np.asarray(arr).flatten():
            f.write(f"{int(v) & 0xFF:02x}\n")


def write_hex_s8(path, arr):
    with open(path, "w") as f:
        for v in np.asarray(arr).flatten():
            f.write(f"{int(v) & 0xFF:02x}\n")


def write_hex_s16(path, arr):
    with open(path, "w") as f:
        for v in np.asarray(arr).flatten():
            f.write(f"{int(v) & 0xFFFF:04x}\n")


def read_hex(path, bits):
    vals = []
    sign = 1 << (bits - 1)
    with open(path) as f:
        for line in f:
            line = line.split("//")[0].strip()
            if not line:
                continue
            v = int(line, 16)
            if v & sign:
                v -= 1 << bits
            vals.append(v)
    return np.array(vals, dtype=np.int64)


if __name__ == "__main__":
    # Quick self-check: identity kernel returns the cropped image.
    rng = np.random.default_rng(0)
    img = rng.integers(0, 256, (32, 32))
    ident = np.zeros((3, 3), dtype=int)
    ident[1, 1] = 1
    assert np.array_equal(conv2d_sat(img, ident), img[1:-1, 1:-1])
    # Saturation check.
    sat = conv2d_sat(np.full((4, 4), 255), np.full((3, 3), 127))
    assert sat.max() == OUT_MAX and sat.min() == OUT_MAX
    print("conv_golden self-check: OK")
