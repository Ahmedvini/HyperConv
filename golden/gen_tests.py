#!/usr/bin/env python3
"""
Generate all HyperConv test cases (stimulus + golden expected outputs).

Each test case is a directory under sim/tests/<name>/ containing:
  img.hex       input image, row-major, u8 hex
  kernel.hex    kernel, row-major, s8 two's-complement hex
  expected.hex  golden output, row-major, s16 two's-complement hex
  params.sh     shell-sourceable parameters for the sim runner

Test plan (from plan.md, section 5 "Verification Strategy"):
  identity_n3     identity kernel -> output equals cropped input (sanity)
  hand_4x4        4x4 image, all-ones 3x3 kernel, hand-verifiable
  random_n3       full 32x32 random image, random kernel
  random_n3_gaps  same vectors, but the TB inserts random px_valid bubbles
  sobel_x/sobel_y edge-detection demo on a synthetic test scene
  saturate_max    all-255 image x all(+127) kernel -> clips to +32767
  saturate_min    all-255 image x all(-128) kernel -> clips to -32768
  random_n5       5x5 kernel on 32x32 image (proves N parameterization)
"""

import os
import numpy as np
from conv_golden import conv2d_sat, write_hex_u8, write_hex_s8, write_hex_s16

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(ROOT, "sim", "tests")

SOBEL_X = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]])
SOBEL_Y = np.array([[-1, -2, -1], [0, 0, 0], [1, 2, 1]])


def edge_scene(h=32, w=32):
    """Synthetic scene with strong edges for the Sobel demo: dark/bright
    halves, a bright square, and a gradient strip."""
    img = np.full((h, w), 30, dtype=int)
    img[:, w // 2:] = 200                       # vertical step edge
    img[6:14, 6:14] = 240                       # bright square on dark half
    img[20:28, 4:12] = 90                       # mid-gray square
    img[24:, w // 2:] = np.linspace(60, 220, w - w // 2, dtype=int)  # gradient rows
    return img


def emit(name, img, ker, ksel=0, gaps=0):
    d = os.path.join(TESTS, name)
    os.makedirs(d, exist_ok=True)
    img = np.asarray(img, dtype=int)
    ker = np.asarray(ker, dtype=int)
    exp = conv2d_sat(img, ker)
    write_hex_u8(os.path.join(d, "img.hex"), img)
    write_hex_s8(os.path.join(d, "kernel.hex"), ker)
    write_hex_s16(os.path.join(d, "expected.hex"), exp)
    h, w = img.shape
    n = ker.shape[0]
    with open(os.path.join(d, "params.sh"), "w") as f:
        f.write(f"N={n}\nW={w}\nH={h}\nKSEL={ksel}\nGAPS={gaps}\n")
    print(f"  {name:16s} img {h}x{w}  N={n}  out {h-n+1}x{w-n+1}"
          f"  range [{exp.min()}, {exp.max()}]  ksel={ksel} gaps={gaps}")
    return exp


def main():
    rng = np.random.default_rng(2026)
    os.makedirs(TESTS, exist_ok=True)
    print("Generating HyperConv test vectors:")

    img32 = rng.integers(0, 256, (32, 32))

    ident = np.zeros((3, 3), dtype=int)
    ident[1, 1] = 1
    emit("identity_n3", img32, ident, ksel=1)

    emit("hand_4x4", np.arange(1, 17).reshape(4, 4), np.ones((3, 3), dtype=int))

    kr3 = rng.integers(-128, 128, (3, 3))
    emit("random_n3", img32, kr3, ksel=2)
    emit("random_n3_gaps", img32, kr3, ksel=2, gaps=1)

    scene = edge_scene()
    emit("sobel_x", scene, SOBEL_X, ksel=3)
    emit("sobel_y", scene, SOBEL_Y, ksel=0)

    emit("saturate_max", np.full((32, 32), 255), np.full((3, 3), 127))
    emit("saturate_min", np.full((32, 32), 255), np.full((3, 3), -128))

    emit("random_n5", rng.integers(0, 256, (32, 32)), rng.integers(-128, 128, (5, 5)))

    # Optional PNG dumps of the edge-detection demo for the report.
    try:
        from PIL import Image
        d = os.path.join(TESTS, "sobel_x")
        Image.fromarray(scene.astype(np.uint8)).resize((256, 256), Image.NEAREST) \
             .save(os.path.join(d, "scene.png"))
        for nm, k in (("sobel_x", SOBEL_X), ("sobel_y", SOBEL_Y)):
            e = np.abs(conv2d_sat(scene, k))
            e = (255 * e / max(1, e.max())).astype(np.uint8)
            Image.fromarray(e).resize((256, 256), Image.NEAREST) \
                 .save(os.path.join(TESTS, nm, "edges.png"))
        print("  (PNG demo images written for the report)")
    except ImportError:
        print("  (PIL not installed - skipping PNG demo images)")


if __name__ == "__main__":
    main()
