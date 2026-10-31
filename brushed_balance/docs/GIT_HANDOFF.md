# Git分支交接

仓库：<https://github.com/LilywantbecomeNIUBI/fpga-balance>

分支：`codex/brushed-balance-p30-m2-20261031`。基于此前已提交的无刷R5交付，新增独立`brushed_balance`工程；新有刷入口为根目录`启动有刷平衡车.cmd`，也可直接运行`brushed_balance/start.cmd`。

## 新电脑使用

```powershell
git clone --single-branch --branch codex/brushed-balance-p30-m2-20261031 https://github.com/LilywantbecomeNIUBI/fpga-balance.git fpga-balance-brushed
cd fpga-balance-brushed\brushed_balance
python tools/selfcheck.py
python tools/run.py --demo
```

需要Python 3.10+。启动器会在当前工程创建`.venv`，使用附带pySerial 3.5 wheel离线安装，无需旧电脑的虚拟环境或其他仓库。默认页面为`http://127.0.0.1:8878/`；同机已有旧上位机时先结束旧进程，或加`--port 8879`使用另一端口。

实机入口：`python tools/run.py --live`。仍需在页面选择串口、连接和应用参数，不自动解锁。当前固件使用115200/8N1和独立48字节协议；旧无刷上位机和位流不适用于此程序。四路AB编码器和四路控制线按[M2接线表](M2_WIRING.md)连接。

## 交付内容

| 路径 | 内容 |
| --- | --- |
| rtl/ | 独立RTL及逐字节保留的复用模块 |
| host/ | 本地网页上位机、串口服务和协议 |
| config/ | 两种编码器配置、逐轮与平衡预设 |
| constraints/ | 完整物理管脚、载板原始映射及M2方案标识 |
| tools/、tests/ | 启动、完整Gowin工程生成、引脚审计及回归 |
| vendor/wheels/ | 离线pySerial依赖 |
| firmware/ | 两份已构建M2/GMR位流及SHA256 |
| evidence/m2_20261031/ | 构建/测试证据、生成顶层及约束快照 |
| docs/ | 接线、协议、来源、验证状态和演示截图 |

克隆后也可单独复制`brushed_balance`文件夹使用。文件内保存的旧盘符路径仅用于标明复用来源，构建和运行不读取这些外部路径。每个必需文件均由本工程`SOURCE_MANIFEST.json`校验。

## 重新测试与构建

```powershell
python tools/test.py
python tools/build.py --profile observe
python tools/build.py --profile drive
```

数字回归需要Icarus Verilog与Node.js；完整构建需合法安装Gowin V1.9.12.04，可用`GOWIN_HOME`指定安装目录。完整工程与新产物分别生成到`build/observe_p30_gmr_m2/`及`build/drive_p30_gmr_m2/`。

GitHub Actions会运行本工程离线自检和数字回归，不执行EDA、串口连接、下载或电机动作。提交内容保留了此次离线构建的固件；详细实机未完成项见[验证状态](validation.md)。源码变更后，需重新生成相关构建、测试证据和哈希清单，旧位流不能作为新代码的验证依据。
