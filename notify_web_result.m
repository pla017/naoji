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

serverUrl = normalize_server_url(serverUrl);
payload = jsonencode(result);
payloadFile = [tempname, '.json'];
responseFile = [tempname, '.txt'];
cleanupPayload = onCleanup(@() delete_if_exists(payloadFile));
cleanupResponse = onCleanup(@() delete_if_exists(responseFile));

write_text_file(payloadFile, payload);

curlCommand = build_curl_command(serverUrl, payloadFile, responseFile);
[exitCode, commandOutput] = system(curlCommand);
bodyText = '';
if exist(responseFile, 'file')
    bodyText = strtrim(fileread(responseFile));
end

statusCode = parse_status_code(commandOutput);
response = struct( ...
    'status_code', statusCode, ...
    'status_line', strtrim(commandOutput), ...
    'body', bodyText);

if exitCode ~= 0
    error('notify_web_result:CurlError', 'curl 发送失败，退出码 %d：%s', exitCode, strtrim(commandOutput));
end

if ~isempty(bodyText) && (strncmp(bodyText, '{', 1) || strncmp(bodyText, '[', 1))
    try
        response.json = jsondecode(bodyText);
    catch
        response.json_text = bodyText;
    end
end

if ~isnan(response.status_code) && response.status_code >= 400
    if isfield(response, 'json') && isstruct(response.json) && isfield(response.json, 'error')
        error('notify_web_result:HTTPError', 'HTTP %d: %s', response.status_code, char(response.json.error));
    end
    error('notify_web_result:HTTPError', 'HTTP %d: %s', response.status_code, response.status_line);
end
end

function command = build_curl_command(serverUrl, payloadFile, responseFile)
if ispc
    curlBin = 'curl.exe';
else
    curlBin = 'curl';
end

command = sprintf('%s -sS -X POST -H %s --data-binary %s -o %s -w %s %s', ...
    shell_quote(curlBin), ...
    shell_quote('Content-Type: application/json; charset=utf-8'), ...
    shell_quote(['@', payloadFile]), ...
    shell_quote(responseFile), ...
    shell_quote('%{http_code}'), ...
    shell_quote(serverUrl));
end

function write_text_file(filePath, content)
fid = fopen(filePath, 'w', 'n', 'UTF-8');
if fid < 0
    error('notify_web_result:FileError', '无法写入临时 JSON 文件：%s', filePath);
end
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s', content);
end

function delete_if_exists(filePath)
if exist(filePath, 'file')
    delete(filePath);
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
prefixIndex = strfind(url, prefix);
if ~isempty(prefixIndex)
    url = strtrim(url(prefixIndex(1) + length(prefix):end));
end

httpIndex = regexp(url, 'https?://', 'once');
if ~isempty(httpIndex) && httpIndex > 1
    url = strtrim(url(httpIndex:end));
end
end

function statusCode = parse_status_code(statusLine)
statusCode = NaN;
token = regexp(char(statusLine), '\d{3}', 'match', 'once');
if ~isempty(token)
    parsed = sscanf(token, '%d');
    if ~isempty(parsed)
        statusCode = parsed(1);
    end
end
end
