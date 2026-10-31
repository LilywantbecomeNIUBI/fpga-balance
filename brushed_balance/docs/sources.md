# 复用与参数依据（2026-10-31）

所有生产 HDL 都在本文件夹内，不读取兄弟目录。`reused_sources.json` 保存原始来源路径和逐文件 SHA256，可移走旧工程后构建。

- `rtl/reused/at8236_pwm.sv`、UART 和帧发送器，来自最近的 `fpga-system-integration/fpga/motor`。
- ICM-42688-P 三个采集模块来自其 `fpga/imu`。约1kHz、±4g、±1000°/s、I2C地址0x69及1MHz沿用旧硬件参数。
- `balance_attitude.v`、`balance_atan.v` 来自 `fpga-balance/balance/src`，保持原文；固定旧车IMU安装方向。
- `bb_wheel_pi.sv` 从旧 `wheel_control.sv` 派生：将输出和积分限幅改为本次可配置上限。原文件保留作复用依据。
- 新写标准 AB x4、双轮平衡核心、PD/速度外环、独立协议、板级顶层、上位机与构建/测试工具。没有 FOC、电角零位、极对数或旧编码器方向补偿。

## 原载板M2物理映射依据

- `D:/活动/比赛/电赛/FPGA/Carrier_Hall_RevB/GPIO_40Pin_映射.csv`：J_DRV2-23～30对应P7-18/19/10/13/14/15/16/17，球号C15/B15/E14/C13/B13/D14/D15/C14。源文件SHA256冻结在`constraints/pin_profile.json`。
- 同目录`接口与丝印说明.md`、`BOM.csv`及`carrier_hall_revb.kicad_pcb`：确认M2为32针DRV2接口及地脚；R_CAL2和R_PD21～26为已装配10k下拉，因此新编码器输入M2-24/29/30分别受到R_CAL2/R_PD25/R_PD26负载。
- 本工程`constraints/carrier_drv2_reference.csv`仅保存八个针脚的原始物理事实，与有刷逻辑分配分开核对，不依赖外部目录参与构建。新接线和实机未验收状态见`docs/M2_WIRING.md`。

## 厂家资料

1. `D:/活动/比赛/电赛/FPGA/硬件资料/WHEELTEC 直流电机附送资料/WHEELTEC 直流电机附送资料_2024.12.23/1.直流电机开发手册与编码器测试教程/轮趣直流有刷电机产品说明手册（尺寸、参数、线序）_2026.07.28.pdf`
   - PDF第4页：MG513P30，标称1:30，8V/12V两档，减速后空载约366rpm。
   - 第5页：GMR 500ppr、霍尔13ppr；3.3~5V；两款6Pin线序图不同。
   - SHA256：`ea0aaa36b3d1826a5701e23ae1e96949c4c99b484c8219b2d6865bb95d5b4890`。
2. 同目录 `WHEELTEC 直流电机开发手册_2026.07.28.pdf`
   - 第7页：编码器带上拉到供电VCC；第9页：GMR只引出AB，未引出Z；第10~13页：电平和四倍频/减速比测速关系。
   - SHA256：`69606b02ee3f4e77eff1cc4c1d5d77ac4fba93ae677fe4b92851945984c740ac`。
3. `D:/活动/比赛/电赛/FPGA/硬件资料/【WHEELTEC】AT8236驱动模块附送资料/【WHEELTEC】AT8236驱动模块附送资料_V2.8_2026.07.25/1.用户手册与教程视频/电机驱动模块使用手册—AT8236-2025.08.27.pdf`
   - 第7页：推荐PWM 10kHz；第8页：D157B双电机6Pin/AB引出和电源分压说明。
   - SHA256：`56ec9aefff8635d37a1f39efac2e2b910c8ee8b6a983c2c162011fed76ea3178`。

P30 CPR=60000/1560是根据厂家标称减速比和分辨率**推算**，不是本车测量。电机实物究竟为GMR或霍尔、8V或12V，仍需接入前按标签核对。未将资料中的电流额定值当作软件限流能力。
