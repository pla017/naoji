%% ============================================================
%% 三分类 OVO-RCSP（单试次预测 + Web 控制联动）
%% 基于 dangeRCSP.m 改造，原文件保持不动
%% 预测类别映射：
%%   2 -> 全部握紧
%%   3 -> 全部松开
%%   4 -> 大拇指张开
%% ============================================================
clear; clc; close all;

%% 0. 参数配置
target_id = 1;
trial_idx = 19;   % 手动选择测试试次（1 ~ 20）

% 数据集目录
data_dir = '/Volumes/SSD/运动想象/数据集';

% Web 上报地址：
% 固定使用控制台默认 8000 端口；如需局域网联动，再手动改成启动窗口打印的上报地址。
server_url = 'http://127.0.0.1:8000/api/eeg_result';
naoji_root = '';
post_result_to_web = true;

%% 1. 加载数据
addpath(data_dir);

train_file = fullfile(data_dir, sprintf('sub%02d_Train40.mat', target_id));
test_file = fullfile(data_dir, sprintf('sub%02d_Test20.mat', target_id));

load(train_file);
X_train_target = TrainSet.trials;
y_train_target = TrainSet.y(:);

load(test_file);
X_test = TestSet.trials;
y_test = TestSet.y(:);

%% 2. 训练 OVO-RCSP + LDA
classes = unique(y_train_target);   % 期望 [2 3 4]
nClass = numel(classes);

csp_models = cell(nClass * (nClass - 1) / 2, 1);
lda_models = cell(nClass * (nClass - 1) / 2, 1);

feat_dim = 6;
pair_idx = 0;

% RCSP 参数设置（参考论文）
beta = 0.5;    % 通用池权重 (0=纯目标被试, 1=纯通用池)
gamma = 0.1;   % 特征值收缩系数 (0=无收缩)

fprintf('开始训练 OVO-RCSP (Target: sub%d, Beta: %.2f, Gamma: %.2f)...\n', target_id, beta, gamma);

for i = 1:nClass
    for j = i + 1:nClass
        pair_idx = pair_idx + 1;
        c1 = classes(i);
        c2 = classes(j);

        % 提取当前被试的配对数据
        idx_target = (y_train_target == c1) | (y_train_target == c2);
        X_pair_target = permute(X_train_target(idx_target, :, :), [3 2 1]);

        % 1. 计算目标被试的协方差
        C1_tgt = mean_cov(X_pair_target(:, :, y_train_target(idx_target) == c1));
        C2_tgt = mean_cov(X_pair_target(:, :, y_train_target(idx_target) == c2));

        % 2. 构建通用池协方差（排除当前被试）
        S_generic_C1 = zeros(size(C1_tgt));
        S_generic_C2 = zeros(size(C2_tgt));
        generic_count = 0;

        for sub = 1:8
            if sub == target_id
                continue;
            end

            generic_train_file = fullfile(data_dir, sprintf('sub%02d_Train40.mat', sub));
            load(generic_train_file);
            X_generic = TrainSet.trials;
            y_generic = TrainSet.y(:);

            idx_gen = (y_generic == c1) | (y_generic == c2);
            X_gen_pair = permute(X_generic(idx_gen, :, :), [3 2 1]);

            S_generic_C1 = S_generic_C1 + mean_cov(X_gen_pair(:, :, y_generic(idx_gen) == c1));
            S_generic_C2 = S_generic_C2 + mean_cov(X_gen_pair(:, :, y_generic(idx_gen) == c2));
            generic_count = generic_count + 1;

            clear TrainSet X_generic y_generic idx_gen X_gen_pair;
        end

        % 3. 正则化融合
        Omega1 = (1 - beta) * C1_tgt + beta * (S_generic_C1 / generic_count);
        Omega2 = (1 - beta) * C2_tgt + beta * (S_generic_C2 / generic_count);

        % 4. 特征值收缩
        N_ch = size(Omega1, 1);
        tr1 = trace(Omega1);
        tr2 = trace(Omega2);

        Sigma1 = (1 - gamma) * Omega1 + (gamma / N_ch) * tr1 * eye(N_ch);
        Sigma2 = (1 - gamma) * Omega2 + (gamma / N_ch) * tr2 * eye(N_ch);

        % 5. 执行 CSP
        C = Sigma1 + Sigma2;
        [U, D] = eig(C);
        d = diag(D);
        d(d <= 0) = eps;
        invD = diag(d .^ (-1 / 2));
        P = invD * U';

        C1w = P * Sigma1 * P';
        [V, ~] = eig(C1w);
        V = fliplr(V);

        m2 = feat_dim / 2;
        W = P' * [V(:, 1:m2), V(:, end - m2 + 1:end)];

        csp_models{pair_idx} = W;

        % 6. 特征提取与 LDA 训练
        feat_train = csp_extract(X_pair_target, W);
        lda = fitcdiscr(feat_train, y_train_target(idx_target), 'DiscrimType', 'diagLinear');
        lda_models{pair_idx} = lda;
    end
end

%% 3. 单试次预测
x_single = permute(X_test(trial_idx, :, :), [3 2 1]);
true_label = y_test(trial_idx);

vote = zeros(1, nClass);
pair_idx = 0;

for i = 1:nClass
    for j = i + 1:nClass
        pair_idx = pair_idx + 1;
        feat_single = csp_extract(x_single, csp_models{pair_idx});
        pred = predict(lda_models{pair_idx}, feat_single);
        vote(pred == classes) = vote(pred == classes) + 1;
    end
end

[~, idx] = max(vote);
pred_label = classes(idx);
confidence_ratio = vote_confidence_ratio(vote);
mapped_command = map_motion_command(pred_label);

%% 4. 输出结果
fprintf('\n========================================\n');
fprintf('单试次预测结果 (OVO-RCSP + Web 控制联动)\n');
fprintf('试次编号：%d\n', trial_idx);
fprintf('真实类别：%d\n', true_label);
fprintf('预测类别：%d\n', pred_label);
fprintf('投票结果：');
for k = 1:nClass
    fprintf(' [%d => %d]', classes(k), vote(k));
end
fprintf('\n');
fprintf('置信比：%.4f\n', confidence_ratio);
fprintf('映射动作：%s\n', mapped_command.command_name);
fprintf('目标 ID：%s\n', mapped_command.target);
fprintf('控制指令：%s\n', mapped_command.command_hex);

if pred_label == true_label
    fprintf('结果：✅ 预测正确\n');
else
    fprintf('结果：❌ 预测错误\n');
end
fprintf('========================================\n');

%% 5. 通知控制页执行动作
if post_result_to_web
    web_url = resolve_server_url(server_url, naoji_root);
    result = struct( ...
        'type', 'eeg_result', ...
        'source', 'matlab_ovo_rcsp_mi', ...
        'mode', 'mi', ...
        'trial_idx', trial_idx, ...
        'true_label', true_label, ...
        'predicted_class', pred_label, ...
        'target', mapped_command.target, ...
        'command_name', mapped_command.command_name, ...
        'command_hex', mapped_command.command_hex, ...
        'confidence_ratio', confidence_ratio, ...
        'timestamp_ms', floor(posixtime(datetime('now')) * 1000) ...
    );

    try
        fprintf('web_notify_url: %s\n', web_url);
        response = post_web_result(web_url, result);
        fprintf('web_notify_status: %d\n', response.status_code);
        if ~isempty(response.body)
            fprintf('web_notify_body: %s\n', response.body);
        end
    catch err
        fprintf(2, 'web_notify_error: %s\n', err.message);
        fprintf(2, 'web_notify_error_id: %s\n', err.identifier);
        if ~isempty(err.stack)
            fprintf(2, 'web_notify_error_at: %s:%d\n', err.stack(1).file, err.stack(1).line);
        end
    end
end

%% ============================================================
%% 辅助函数
%% ============================================================

function command = map_motion_command(pred_label)
switch pred_label
    case 2
        command = struct( ...
            'target', 'mi_close', ...
            'command_name', '全部握紧', ...
            'command_hex', 'A5 5A 02 0B 0F 01 01 01 01 01 DF');
    case 3
        command = struct( ...
            'target', 'mi_open', ...
            'command_name', '全部松开', ...
            'command_hex', 'A5 5A 02 0B 0F 00 00 00 00 00 E4');
    case 4
        command = struct( ...
            'target', 'mi_thumb', ...
            'command_name', '大拇指张开', ...
            'command_hex', 'A5 5A 02 0B 0F 00 02 02 02 02 E2');
    otherwise
        error('dangeRCSP_webcontrol:UnknownClass', '未定义的预测类别：%d', pred_label);
end
end

function ratio = vote_confidence_ratio(vote)
sorted_vote = sort(vote, 'descend');
if isempty(sorted_vote)
    ratio = 0;
elseif numel(sorted_vote) == 1
    ratio = sorted_vote(1);
else
    ratio = sorted_vote(1) / max(sorted_vote(2), eps);
end
end

function C = mean_cov(X)
% X : (channels × time × trials)
    [n_ch, T, N] = size(X);
    Cmat = zeros(n_ch, n_ch);
    for n = 1:N
        x = X(:, :, n);
        x = x - mean(x, 2);
        Cmat = Cmat + (x * x') / (T - 1);
    end
    C = Cmat / N;
end

function feat = csp_extract(X, W)
% X : (channels × time × trials)
% W : CSP 投影矩阵
    [~, T, N] = size(X);
    m = size(W, 2);
    feat = zeros(N, m);
    for n = 1:N
        z = W' * X(:, :, n);
        var_z = sum(z .^ 2, 2) / T + 1e-6;
        feat(n, :) = log(var_z);
    end
end

function url = resolve_server_url(server_url, naoji_root)
url = strtrim(char(server_url));
if ~isempty(url)
    return;
end

env_url = strtrim(getenv('SSVEP_WEB_URL'));
if isempty(env_url)
    env_url = strtrim(getenv('EEG_RESULT_URL'));
end
if ~isempty(env_url)
    url = normalize_server_url(env_url);
    return;
end

candidate_files = {};
if ~isempty(naoji_root)
    candidate_files{end + 1} = fullfile(naoji_root, 'web_bridge_url.txt');
end
candidate_files{end + 1} = fullfile('/Users/jack/MyCode/naoji', 'web_bridge_url.txt');
candidate_files{end + 1} = fullfile('C:\Users\jack\MyCode\naoji', 'web_bridge_url.txt');

for i = 1:numel(candidate_files)
    file_path = candidate_files{i};
    if exist(file_path, 'file')
        url = normalize_server_url(fileread(file_path));
        if ~isempty(url)
            return;
        end
    end
end

url = 'http://127.0.0.1:8000/api/eeg_result';
end

function response = post_web_result(server_url, result)
payload = jsonencode(result);
payload_file = [tempname, '.json'];
response_file = [tempname, '.txt'];
cleanup_payload = onCleanup(@() delete_if_exists(payload_file)); %#ok<NASGU>
cleanup_response = onCleanup(@() delete_if_exists(response_file)); %#ok<NASGU>

write_text_file(payload_file, payload);

command = build_curl_command(server_url, payload_file, response_file);
[exit_code, command_output] = system(command);

body_text = '';
if exist(response_file, 'file')
    body_text = strtrim(fileread(response_file));
end

response = struct( ...
    'status_code', parse_status_code(command_output), ...
    'status_line', strtrim(command_output), ...
    'body', body_text);

if exit_code ~= 0
    error('dangeRCSP_webcontrol:CurlError', 'curl 发送失败，退出码 %d：%s', exit_code, strtrim(command_output));
end

if ~isnan(response.status_code) && response.status_code >= 400
    error('dangeRCSP_webcontrol:HTTPError', 'HTTP %d: %s', response.status_code, response.status_line);
end
end

function command = build_curl_command(server_url, payload_file, response_file)
if ispc
    curl_bin = 'curl.exe';
else
    curl_bin = 'curl';
end

command = sprintf('%s -sS -X POST -H %s --data-binary %s -o %s -w %s %s', ...
    shell_quote(curl_bin), ...
    shell_quote('Content-Type: application/json; charset=utf-8'), ...
    shell_quote(['@', payload_file]), ...
    shell_quote(response_file), ...
    shell_quote('%{http_code}'), ...
    shell_quote(server_url));
end

function write_text_file(file_path, content)
fid = fopen(file_path, 'w', 'n', 'UTF-8');
if fid < 0
    error('dangeRCSP_webcontrol:FileError', '无法写入临时 JSON 文件：%s', file_path);
end
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s', content);
end

function delete_if_exists(file_path)
if exist(file_path, 'file')
    delete(file_path);
end
end

function quoted = shell_quote(value)
text = char(value);
text = strrep(text, '"', '\"');
quoted = ['"', text, '"'];
end

function url = normalize_server_url(value)
url = strtrim(char(value));
prefix = 'EEG_RESULT_URL=';
prefix_index = strfind(url, prefix);
if ~isempty(prefix_index)
    url = strtrim(url(prefix_index(1) + length(prefix):end));
end

http_index = regexp(url, 'https?://', 'once');
if ~isempty(http_index) && http_index > 1
    url = strtrim(url(http_index:end));
end
end

function status_code = parse_status_code(status_line)
status_code = NaN;
token = regexp(char(status_line), '\d{3}', 'match', 'once');
if ~isempty(token)
    parsed = sscanf(token, '%d');
    if ~isempty(parsed)
        status_code = parsed(1);
    end
end
end
