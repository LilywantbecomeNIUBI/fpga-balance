# Balance V2 UART

921600 8N1，50 MHz 波特率分频 54，实际 925925.9 baud（约 +0.47%，沿用原工程）。所有多字节字段 little endian。CRC16-CCITT-FALSE：初值 FFFF，多项式 1021，无反射，无终异或。

## 主机命令

固定 71 个 ASCII 字节：`@` + 32 字节 body 的 64 个大写 hex + `*` + CRC 的 4 个 hex（高位先）+ LF。CRC 覆盖解码后的 32 字节。帧内空闲超过 20 ms、非法字符、CRC 错误和未知操作均拒绝。任意位置单独的 `X` 立即终止当前解析并请求停止；X 不是合法 hex 字符。

| body 偏移 | 长度 | 字段 |
|---|---|---|
| 0 | 1 | version=2 |
| 1 | 1 | 请求序号，0..255 |
| 2 | 1 | opcode：0 心跳、1 停止、2 人工清故障、3 电流零点、4 姿态/陀螺零点、5 下一路电角标定、6 解锁、7 单次启动、8 应用配置 |
| 3 | 1 | 配置 flags：bit0 轴Y、1 俯仰反向、2 直立Z正、3 M1反向、4 M2反向、5 方向已确认、6 M1验收、7 M2验收 |
| 4 | 4 | 平衡 Kp，unsigned Q24 A/° |
| 8 | 4 | 平衡 Kd，unsigned Q24 A/(°/s) |
| 12 | 2 | FOC Kp unsigned Q12 |
| 14 | 2 | FOC Ki unsigned Q12 |
| 16 | 2 | trim signed 0.01° |
| 18 | 2 | 运行 Iq 上限 mA |
| 20 | 2 | 倾倒停机角 0.01° |
| 22 | 2 | 允许启动角 0.01° |
| 24 | 2 | 单次运行 ms |
| 26 | 1 | 互补滤波 shift，4..10 |
| 27 | 1 | mode bit1:0：0直立、1电流短测、2直立+速度；bit2/3：编码器1/2轮速反向；bit5:4：电流测试轴1/2/3；bit7:6必须0 |
| 28 | 2 | signed：mode1为Iq mA；mode2为速度0.1rpm；mode0不使用 |
| 30 | 1 | 速度Kp，0.001°/rpm |
| 31 | 1 | 速度Ki，0.001°/(rpm·s) |

非配置命令 body[3:32] 必须全零。应用是原子的；已解锁、运行、校零或电角标定时不能修改配置。不自动重发解锁、启动、清故障、标定。心跳 25 ms 一次，FPGA 100 ms 超时。解锁 token 1 s 内使用一次。

## FPGA 遥测

129 字节一帧，200 Hz。前 126 字节一致快照，随后 CRC16 LE 两字节，再附 XOR8（原 motor_console 的帧校验，覆盖前 128 字节）。同步头为 `A5 B6 02 80`，版本/长度均参与 CRC。解析失败逐字节重同步。

| 偏移 | 长度 | 字段 |
|---|---|---|
| 0 | 4 | magic/version/length |
| 4,8,12 | 各4 | now_us，IMU sample_seq，motor frame_seq |
| 16 | 1 | bit0 drive构建，1姿态已校准，2姿态校准中，3电流已校零，4电流校零中，5驱动running，6电角标定中，7电角失败 |
| 17 | 1 | bit0平衡active，1已解锁，2停止锁存，3姿态时序异常，4IMU有效，5配置有效 |
| 18 | 2 | gate bits 0..11，顺序见 host/protocol.py GATES |
| 20,22 | 各2 | 停机原因，原 motor_safe_drive 12-bit faults |
| 24,28 | 各4 | signed Q16 俯仰 °，角速度 °/s |
| 32,34,36 | 各2 | signed 影子 Iq、送入命令保护器的 Iq1/Iq2，单位 A/4096；后两者不是实测电流或斜坡后的实际参考 |
| 38 | 2 | 实际提交间隔 μs |
| 40 | 4 | IMU sample_age_us |
| 44..54 | 各2 | raw ax/ay/az/gx/gy/gz，signed |
| 56 | 2 | raw温度 signed，°C=raw/132.48+25 |
| 58..68 | 各2 | 六相实测电流 signed A/4096，M1 ABC / M2 ABC |
| 70,72 | 各2 | 两路机械角 unsigned 0..16383/圈 |
| 74,76,78,80 | 各2 | 静态校准进度、IMU error_count、invalid_count、RX帧错误计数 |
| 82,83,84 | 各1 | 最新已解析请求序号、解析结果（0成功/2非法/3忙）、最新被生命周期拒绝的非心跳命令（0无） |
| 85 | 1 | bit1:0 两路电角完成位，bit7:4 当前电角FSM状态 |
| 86,87 | 各1 | WHO_AM_I，IMU last_error |
| 88 | 32 | 最近应用的完整配置 body 回显；配置失效后仍保留历史值，必须同时检查 configured 位 |
| 120 | 6 | 保留 0 |
| 126 | 2 | CRC16 LE，覆盖0..125 |
| 128 | 1 | XOR8，覆盖0..127 |

停机原因：0 正常/限时完成，1 X 停止，2 心跳超时，4 电机故障，8 IMU异常，0x10 过倾，0x20 运行条件失效。原因是锁存的首轮停机结果之一；详细电机位定义沿用原工程。电角 FSM 自身的 failed 位也必须检查，即使原 faults 字段为0也不能当作标定成功。

## V2 extension

Telemetry offsets120/122: signed int16 wheel speed0.1rpm, 50Hz held value;124: signed pitch correction0.01deg. These bytes are inside the existing CRC and XOR. V2 rejects V1 identity/commands. Encoder feedback direction bits are separate from torque signs and Hall polarity. Speed loop50Hz, encoder wrap14bits, average signed wheel speed, PI output clamp±3deg, total trim clamp±5deg, integrator reset when disabled and conditional antiwindup. Current mode bypasses attitude PD for its Iq request but retains IMU/tilt/commissioning/host/duration gates. Default current target, balance gains and speed gains all zero.
