# 集成 IMU 启动顺序修复与实测 · 2026-10-26

结论：最终集成观察版已两次仅下载 SRAM，分别完成12秒、60秒静止采样。电机输出硬关闭；未做电机标定、试转或平衡测试。未改动12V供电。

## 定位与修复

专用版和集成版的三个 IMU RTL 文件哈希一致，SCL=F19、SDA=F20，复位释放逻辑一致。原集成观察版12秒收到2412包且CRC为0，但IMU序号一直为0。400kHz总线及20ms软复位等待两个对照也未恢复采样；这些试验改动已撤回，最终保留原1MHz请求频率和2ms复位等待。

临时诊断固件捕获首次初始化：WHO_AM_I=0x47，软复位写入完成后，在step3访问INT_STATUS(0x2D)时NACK；后续重试的step0/step1错误会掩盖首次失败。诊断错误码已撤回，三个IMU文件保持原样。

有效修复位于balance/src/balance_top.v：ADC/编码器所在的motor_safe_drive先保持复位，等imu_ready后释放。peripherals_started只在整机复位时清除；运行中的IMU失效仍由supervisor停止，不重置电机故障或标定状态。串行外设释放后，IMU仍持续约1kHz读取，编码器角度和motor_seq正常更新。

对照结果支持故障与初始化期间的并发外设活动有关；未用示波器/逻辑分析仪定位具体的供电、耦合或接口切换机制，不能把这些推测写成已确认根因。当前修复验证范围为静止观察采样。

## 最终位流与实测

- SHA256：`d11c8de24fa92626c71b7262f2db34e4b7207e979832ec1feaff89e053da68a6`
- Setup/Hold：0/0；综合网表16个PWM/EN/CAL输出均接GND。
- 最终版本首次下载后12秒：2413包，原始读取率约1002.48756Hz。
- 同一最终版本再次下载后60秒：12001包，原始读取率约1002.48333Hz。
- 两轮CRC错误、遥测异常间隔、IMU错误、无效样本、last_error均为0；imu_ok始终为true，芯片ID始终0x47。
- 60秒加速度均值约(-0.00811, -0.01167, -0.99968)g，样本年龄1..1087us。
- 两轮drive/running/active/commissioning始终false；采集程序串口发送0字节。

原始字节、逐包记录及摘要见final_12s/、final_repeat_60s/；构建源哈希见final_build.json，下载日志为program_final*.log，身份记录见programmed_final.json。serial telemetry约200Hz，原始读取率由IMU序号变化计算，不能把遥测包数当作全部1kHz样本数。

## 回归与边界

10项RTL、13项上位机测试全部通过，见offline_tests.json。新增真实I2C从机模型验证初始化/六轴原子读取/故障处理；集成测试验证先IMU后外设、并发编码器时钟、观察版输出接地，以及IMU失效不自动复位电机保护。

板上最终保留本修复的集成观察版，未写Flash，串口采集已结束。旧驱动候选的本地构建报告已标记stale/download_allowed=false，需从当前源码重建。驱动版上板、动态姿态、双轮运动及整车平衡未验收；hardware/active_profile.json的整体集成验收标志仍为false。

参考：[TDK ICM-42688-P数据手册v1.7](https://invensense.tdk.com/wp-content/uploads/2022/12/DS-000347-ICM-42688-P-v1.7.pdf)，DEVICE_CONFIG要求软复位后至少等待1ms；本次20ms对照失败说明不能仅凭延长等待判定修复。

仓库分发范围：提交源码、逐包JSON/CSV、摘要和构建/下载日志；原始串口`.bin`、位流`.fs`及厂商IP按现有忽略规则仅保留在本机，不随Git推送。
