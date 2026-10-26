# 来源与依赖

本独立仓库只保留生产依赖；历史fpga-FOC其他顶层与试验分支不包含。没有为团队源码另行授予开源许可证；新仓库默认私有。

`vendor/wheels/pyserial-3.5-py2.py3-none-any.whl`来自官方PyPI，包含BSD许可文件；为离线安装原样保留。Python、Icarus Verilog、Gowin IDE需自行安装。本仓库不分发Gowin厂商加密IP，恢复工具从合法本机安装读取。测试FOC行为模型不可用于驱动实物。

- FOC电流环、Clarke/Park、PI、SVPWM来自本机安装的Gowin FOC Current Loop Control Light。厂商原wrapper、加密核、宏文件由 `prepare_ip.py` 原样复制到忽略目录，记录SHA256。仓库不重新许可或分发该受保护实现；使用须符合Gowin授权。
- ADC流程参考本地ACG720第62章和ADI AD7606手册；SSI按MT6701 Rev1.8实现。UART位时序适配自本工作区已使用的 `src/uart_selftest.v`。
- `hardware/reference/` 仅保存本项目既有ACG720引脚约束及载板映射，用于独立构建。真实载板原理图/PCB须由团队另行提供。
- 开源调研材料仅保留研究说明，原研究目录及第三方开源RTL没有并入本仓库生产FOC实现。
- `tests/models/foc_contract_model.sv` 是本项目TEST ONLY接口模型，不能用于综合，也不是官方核替代品。
- `balance/vendor/imu/` 复制本团队 `fpga-sensor/imu_1khz/src` 已验证的 ICM-42688-P 核，文件 SHA256 与来源记在 `PROVENANCE.json`；未加入外部平衡算法源码。平衡 PD 与姿态 RTL 由本项目实现，未复制 ESP32/STM32 示例的硬件接口、增益或源码。
- `balance/tests/models/icm42688_model.sv` 和 `tb_imu_reader.sv` 来自同团队 `fpga-sensor/imu_1khz/sim`，用于真实开漏总线事务及故障注入仿真；仅测试使用，不进入综合。

这里没有为第三方资料或厂商IP授予新许可；本次上传也未另外设定项目源码的开源许可证。
