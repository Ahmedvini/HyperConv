function check_all_tests()
%CHECK_ALL_TESTS Verify HyperConv RTL outputs against the MATLAB reference.
%   For every testcase in sim/tests/<name>/ this script:
%     1. loads img.hex and kernel.hex,
%     2. recomputes the convolution with conv_golden.m,
%     3. compares against expected.hex (Python golden model), and
%     4. if present, compares against dut_out.hex (actual RTL outputs,
%        written by the testbench when run via sim/run_all.sh).
%   Prints PASS/FAIL per test; raises an error if anything fails, so
%   `matlab -batch check_all_tests` returns a nonzero exit code on failure.
%
%   Works in both MATLAB and GNU Octave (octave --eval check_all_tests).

here  = fileparts(mfilename('fullpath'));
tdir  = fullfile(fileparts(here), 'sim', 'tests');
list  = dir(tdir);
npass = 0; nfail = 0;

for i = 1:numel(list)
    name = list(i).name;
    if ~list(i).isdir || name(1) == '.'
        continue;
    end
    d = fullfile(tdir, name);
    p = read_params(fullfile(d, 'params.sh'));

    img = to_matrix(read_hex(fullfile(d, 'img.hex'),      8, false), p.H, p.W);
    ker = to_matrix(read_hex(fullfile(d, 'kernel.hex'),   8, true),  p.N, p.N);
    exp = to_matrix(read_hex(fullfile(d, 'expected.hex'), 16, true), ...
                    p.H - p.N + 1, p.W - p.N + 1);

    gold     = double(conv_golden(img, ker));
    ok_model = isequal(gold, exp);

    dut_file = fullfile(d, 'dut_out.hex');
    if exist(dut_file, 'file')
        dut    = to_matrix(read_hex(dut_file, 16, true), ...
                           p.H - p.N + 1, p.W - p.N + 1);
        ok_dut = isequal(gold, dut);
        dut_msg = sprintf('RTL vs MATLAB: %d mismatches', nnz(gold ~= dut));
    else
        ok_dut = true;   % no RTL dump present; model check only
        dut_msg = 'no dut_out.hex (run sim/run_all.sh first)';
    end

    if ok_model && ok_dut
        fprintf('PASS  %-16s (%s)\n', name, dut_msg);
        npass = npass + 1;
    else
        fprintf('FAIL  %-16s model_ok=%d  %s\n', name, ok_model, dut_msg);
        nfail = nfail + 1;
    end
end

fprintf('==================================================\n');
fprintf('MATLAB check: %d passed, %d failed\n', npass, nfail);
if nfail > 0 || npass == 0
    error('check_all_tests:failed', 'verification failed');
end
end

% ------------------------------------------------------------------ helpers
function m = to_matrix(v, rows, cols)
% hex files are row-major; MATLAB reshape is column-major, hence transpose
m = reshape(v, cols, rows)';
end

function v = read_hex(path, bits, signed)
% read one hex value per line, two's complement when signed
fh = fopen(path, 'r');
assert(fh > 0, 'cannot open %s', path);
c = textscan(fh, '%s');
fclose(fh);
v = hex2dec(c{1});
if signed
    wrap = v >= 2^(bits-1);
    v(wrap) = v(wrap) - 2^bits;
end
end

function p = read_params(path)
% parse simple KEY=VALUE lines from params.sh
fh = fopen(path, 'r');
assert(fh > 0, 'cannot open %s', path);
p = struct();
line = fgetl(fh);
while ischar(line)
    tok = regexp(strtrim(line), '^(\w+)=(-?\d+)$', 'tokens', 'once');
    if ~isempty(tok)
        p.(tok{1}) = str2double(tok{2});
    end
    line = fgetl(fh);
end
fclose(fh);
end
