clc; clear; close all;

dataFile = fullfile(fileparts(mfilename('fullpath')), 'ts-35-fbcca_10311619DATA_online.mat');
load(dataFile);

data_index = 3;
Fs = 1200;
len_delay = 0;
nn = 3;
webBridgeUrl = strtrim(getenv('SSVEP_WEB_URL'));
webBridgeUrlFile = fullfile(fileparts(mfilename('fullpath')), 'web_bridge_url.txt');
if isempty(webBridgeUrl) && exist(webBridgeUrlFile, 'file')
    webBridgeUrl = strtrim(fileread(webBridgeUrlFile));
end
if isempty(webBridgeUrl)
    webBridgeUrl = 'http://127.0.0.1:8000/api/eeg_result';
end

candidateFps = 8:0.25:16.5;

% Pick two targets from the full SSVEP paradigm for pneumatic hand control.
% These indices can be changed after Fuda confirms the final target layout.
configFile = fullfile(fileparts(mfilename('fullpath')), 'ssvep_config.mat');
if exist(configFile, 'file')
    load(configFile, 'commandTable');
else
    commandTable = struct( ...
        'name', {'手张开', '手握紧'}, ...
        'targetIndex', {3, 4}, ...
        'freq', {candidateFps(3), candidateFps(4)}, ...
        'hex', {'A5 5A 02 0B 0F 00 00 00 00 00 E4', ...
                'A5 5A 02 0B 0F 01 01 01 01 01 DF'} ...
    );
end

fps = candidateFps;
Nfps1 = length(fps);
rmax = zeros(1, Nfps1);

bufferData = Data_SSMVEP{data_index};
SSMVEPData = bufferData(len_delay * Fs + 1:round(nn * Fs), :);
Nsample = size(SSMVEPData, 1);
t = (0:1/Fs:(Nsample - 1)/Fs)';
SSMVEPData = detrend(SSMVEPData, 'constant');
SSMVEPData = double(SSMVEPData);

for kf = 1:Nfps1
    rad0 = pi * fps(kf) * t * 2;
    radd = [rad0, rad0 * 2, rad0 * 4];
    coskf = cos(radd);
    sinkf = sin(radd);
    [~, ~, r1] = canoncorr(SSMVEPData, [coskf, sinkf]);
    rmax(kf) = r1(1);
end

[Rmax, ind] = sort(rmax, 'descend');
confidence_ratio = Rmax(1) / Rmax(2);
recognized_freq_index = ind(1);
recognized_freq = fps(recognized_freq_index);
freqTolerance = 0.125;
commandIndex = find(abs([commandTable.freq] - recognized_freq) <= freqTolerance, 1);

fprintf('recognized_freq: %.2f Hz\n', recognized_freq);
fprintf('recognized_freq_index: %d\n', recognized_freq_index);
fprintf('confidence_ratio: %.4f\n', confidence_ratio);

if isempty(commandIndex)
    fprintf('command_name: 未映射\n');
    fprintf('command_hex: \n');
    command_name = '未映射';
    command_hex = '';
else
    recognized_command = commandTable(commandIndex);
    fprintf('command_name: %s\n', recognized_command.name);
    fprintf('command_hex: %s\n', recognized_command.hex);
    command_name = recognized_command.name;
    command_hex = recognized_command.hex;
end

result = struct( ...
    'type', 'eeg_result', ...
    'source', 'matlab_testCCA', ...
    'recognized_freq', recognized_freq, ...
    'recognized_freq_index', recognized_freq_index, ...
    'confidence_ratio', confidence_ratio, ...
    'command_name', command_name, ...
    'command_hex', command_hex, ...
    'timestamp_ms', floor(posixtime(datetime('now')) * 1000) ...
);

try
    fprintf('web_notify_url: %s\n', webBridgeUrl);
    fprintf('web_notify_func: %s\n', which('notify_web_result'));
    response = notify_web_result(webBridgeUrl, result);
    if isfield(response, 'json') && isstruct(response.json) ...
            && isfield(response.json, 'ok') && response.json.ok
        fprintf('web_notify: ok -> %s\n', webBridgeUrl);
        if isfield(response.json, 'subscribers')
            fprintf('web_notify_subscribers: %d\n', response.json.subscribers);
        end
    else
        fprintf('web_notify: sent -> %s\n', webBridgeUrl);
    end
catch error
    fprintf(2, 'web_notify_error: %s\n', error.message);
    fprintf(2, 'web_notify_error_id: %s\n', error.identifier);
    if ~isempty(error.stack)
        fprintf(2, 'web_notify_error_at: %s:%d\n', error.stack(1).file, error.stack(1).line);
    end
end
