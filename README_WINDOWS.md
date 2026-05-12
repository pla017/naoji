# Windows 现场启动说明

## 1. 需要预先安装

- Python 3.10 及以上
- MATLAB
- Chrome 或 Edge

建议安装 Python 时勾选 `Add python.exe to PATH`。

## 2. 启动

双击 `start_windows.bat`。

启动器会自动完成以下事情：

- 创建 `.venv` 虚拟环境
- 按 `requirements.txt` 自动安装缺失依赖
- 自动寻找空闲端口
- 自动打开控制页面

如果 MATLAB、被试页、控制页都在同一台电脑，默认启动即可。

如果局域网里的其他电脑也要访问被试页，或者 MATLAB 要从另一台电脑上报结果，请这样启动：

```bat
start_windows.bat --host 0.0.0.0
```

启动窗口会打印类似下面的地址：

```text
局域网控制页：http://192.168.x.x:8000/index.html
局域网被试页：http://192.168.x.x:8000/stimulus.html
MATLAB 上报地址：http://192.168.x.x:8000/api/eeg_result
```

## 3. MATLAB 找不到时

如果 MATLAB 没有加入系统 PATH，可以在命令行里这样启动：

```bat
start_windows.bat --matlab "C:\Program Files\MATLAB\R2026a\bin\matlab.exe"
```

或者先设置环境变量：

```bat
set MATLAB_BIN=C:\Program Files\MATLAB\R2026a\bin\matlab.exe
start_windows.bat
```

## 4. 实时联动

1. 打开控制页 `index.html`
2. 点击“打开被试页”，让被试页进入全屏
3. 点击“开始实时联动”
4. MATLAB 在线解码后，把结果 POST 到启动窗口显示的 `MATLAB 上报地址`

MATLAB 侧可以直接调用 `notify_web_result.m`：

```matlab
serverUrl = 'http://127.0.0.1:8000/api/eeg_result';
result = struct( ...
    'target', 'open', ...
    'recognized_freq', 8.50, ...
    'confidence_ratio', 3.2);
notify_web_result(serverUrl, result);
```

如果服务用 `--host 0.0.0.0` 启动，并且 MATLAB 在局域网另一台电脑上，把 `127.0.0.1` 换成启动窗口打印的局域网 IP。

## 5. 停止服务

关闭启动脚本对应的终端窗口，或者在窗口里按 `Ctrl + C`。
