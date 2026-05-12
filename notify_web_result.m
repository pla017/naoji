function response = notify_web_result(serverUrl, result)
% notify_web_result  Send one online EEG recognition result to the web bridge.
%
% Example:
%   result = struct( ...
%       'target', 'open', ...
%       'recognized_freq', 8.50, ...
%       'confidence_ratio', 3.2);
%   notify_web_result('http://127.0.0.1:8000/api/eeg_result', result);

if nargin < 1 || isempty(serverUrl)
    serverUrl = 'http://127.0.0.1:8000/api/eeg_result';
end

if nargin < 2 || isempty(result)
    result = struct( ...
        'target', 'open', ...
        'recognized_freq', 8.50, ...
        'confidence_ratio', 3.2);
end

if ~isfield(result, 'timestamp_ms')
    result.timestamp_ms = floor(posixtime(datetime('now')) * 1000);
end

if ~isfield(result, 'source')
    result.source = 'matlab';
end

options = weboptions( ...
    'MediaType', 'application/json', ...
    'Timeout', 5);
response = webwrite(serverUrl, result, options);
end
