function out = conv_golden(img, ker, relu)
%CONV_GOLDEN Bit-exact MATLAB reference for the HyperConv accelerator.
%   out = CONV_GOLDEN(img, ker)
%   out = CONV_GOLDEN(img, ker, relu)   with relu=1: negatives clamp to 0
%   img : HxW matrix, unsigned 8-bit pixels (0..255)
%   ker : NxN matrix, signed 8-bit coefficients (-128..127)
%   out : (H-N+1)x(W-N+1) int32 result
%
%   Semantics (identical to conv_golden.py and the RTL):
%     - cross-correlation (no kernel flip), stride 1
%     - "valid" output only (no padding)
%     - full-precision accumulation (exact in doubles: |sum| << 2^53)
%     - saturation to signed 16-bit [-32768, +32767]
%     - optional ReLU: max(0, saturated result), matching RELU=1 RTL
%
%   Works in both MATLAB and GNU Octave.

if nargin < 3
    relu = false;
end

img = double(img);
ker = double(ker);
assert(all(img(:) >= 0 & img(:) <= 255), 'input pixels must be u8');
assert(all(ker(:) >= -128 & ker(:) <= 127), 'coefficients must be s8');

[H, W] = size(img);
N = size(ker, 1);
assert(isequal(size(ker), [N N]) && H >= N && W >= N);

OH = H - N + 1;
OW = W - N + 1;
out = zeros(OH, OW);
for r = 1:OH
    for c = 1:OW
        out(r, c) = sum(sum(img(r:r+N-1, c:c+N-1) .* ker));
    end
end

out = min(max(out, -32768), 32767);
if relu
    out = max(out, 0);
end
out = int32(out);
end
