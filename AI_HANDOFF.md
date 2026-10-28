# 接手说明：先读这里，再访问硬件

目标：基于这个独立工程，按“电流短测→直立PD→速度PI”协助调试。先读README、hardware/active_profile.json、docs/TUNING_GUIDE.md及evidence/VALIDATION.md。无需原聊天或fpga-FOC旧分支；不要将外部项目加进include路径。

2026-10-27更新：用户要求已确认配置固定并删除相应选择项，后续确认项同样收敛。目前IMU固定Y轴、前倾正、直立−Z（orientation=011），已删除上位机三个IMU方向选择，协议拒绝其他方向位。静态前/直/后姿态及两轮手持前后摆动的动态陀螺符号已确认；两轮纠偏/轮速方向尚未验收；axis_confirmed位用于已实测的IMU姿态与车轮前进轴向；不代表转矩纠偏验收。不要加载旧fpga-FOC/balance集成位流。修改后的候选须重新构建再下载。

当前固定：M1接口1/编码器1/CH1=C、CH2=B；M2接口2/编码器2/CH3=C、CH4=B。软件mask7：CH1/2/3取反，CH4不取反。两对C/B增益均217082/220767；M2新霍尔未独立测增益。PWM ABC，未交换D/Q。

2026-10-25的单轴证据：M1约30.002rpm，9.998秒；M2正常转动，9.998秒，目标30.029rpm、稳态均值31.343rpm、10ms标准差4.752rpm，串口相电流峰0.30225A。M2在90°末尾Id0.25819/Iq−0.00363A，在0°末尾Id0.25165/Iq0.00353A。这支持当前软件极性；不能据此声称增益已独立校准或整车已平衡。

成功M2独立位流SHA256：`27b59f2c2b0586965dfac8b288bca3cfcaef3aa126a3243fa1bfaf8b10a8bd7d`。该历史独立位流不是本新仓库的集成驱动版，不能混淆身份。新观察/驱动版的构建哈希见evidence；上板仍待授权与验收。

工作要求：

1. 运行03_selfcheck；有Icarus再运行04_tests；先01_demo查看三模式、配置与门禁。没有EDA也可读代码、用模拟，不要伪称构建通过。
2. 单一顶层balance_top；综合只用build脚本的生产列表，测试模型目录不能混入。Gowin通过本机合法安装恢复IP，不要使用行为模型驱动实物。
3. 最新接线确认优先于历史记录。电流极性、编码器方向与左右转矩方向分别验证；默认确认位false，不擅自勾选。
4. 上板先确认12V关闭、逻辑开启、位流SHA和Setup/Hold0/0。先observe验IMU/编码器/电流与输出关闭；再在用户授权的现场条件下做限时驱动。
5. 驱动需两轮架空或机身可靠支撑、人能断电，先校零静止检查再逐轴标定。异常立即停止，不删除保护、不自动清故障重试，不以“用户希望快点”为由绕过门禁。
6. 电流模式默认0mA；直立/速度增益默认0，不是最终参数。先电流响应，再确认纠偏方向，小范围逐步调PD，最后加低带宽速度PI。
7. 记录固件SHA、接线、参数JSON、原始遥测、保护和肉眼现象。区分RTL模型、STA、台架短测与整车验收。不得把串口均值低于过流阈值解释成FPGA误报；20kHz保护可能抓到200Hz遥测未见的峰。

本仓库补充了原速度外环运算的时序修复；不放宽时钟约束，不恢复历史PWM排列组合、D/Q旋转或换板映射。历史资料仅有精简成功证据，不能认为旧分支必须一并导入。

可复制给其他AI的提示：请先在本工程做离线自检，阅读README与调参手册，核对最新成功硬件配置，再分阶段协助调电流环、直立环和速度环。任何实物运动均先确认供电和现场条件，不自动试转或清故障。


## 2026-10-26 IMU观察采样更新

先前“未下载/未验收IMU”描述为历史状态。集成观察版现已通过启动顺序修复及两次SRAM下载后的12秒/60秒静止采样；原始读取率约1002.48Hz，错误为0。详见 evidence/imu_fix_20261026/REPORT.md。板上保留电机硬关闭观察版，Flash未写；驱动候选已过期须重建，运动和平衡仍未验收。

2026-10-27动态方向实测：用户按前倾→回中→后倾重复两轮，前倾峰值+39.71/+34.04度、后倾−27.79/−30.86度；运动段角速度与倾角导数符号一致率99.78%，相关系数0.974，IMU错误0。姿态校零后的回中约+0.26度（手扶）。证据：balance/results/20261027_163444_b51735/dynamic_direction_summary.json。保持观察版，12V断开，电机停止锁存仍保留，尚无电机运动验收。

2026-10-27用户确认：从车尾朝车头看，M1为右轮，双轮系统M2为左轮。已写入hardware/active_profile.json与界面标识；不更改PWM/编码器物理端口，轮速与转矩方向仍待确认。

2026-10-27轮速方向实测通过：只转右轮向前，编码器1净−82.661度；只转左轮向前，编码器2净+80.837度。已固定M1右轮取反/M2左轮不反，FPGA删除reverse1/reverse2接口与选择寄存器，上位机删除两项轮速方向选项，协议要求固定方向位01。仅影响速度反馈，不改FOC电角/霍尔极性/转矩命令符号。两轮转矩纠偏方向仍未确认。证据同会话下right_wheel_forward_summary.json和left_wheel_forward_summary.json。新源码须重建后换入，禁止混用先前候选。

2026-10-27澄清：此前界面将axis_confirmed误写成“两轮纠偏方向”导致与标定/电流短测的阶段含义混淆，现明确为已实测的IMU与车轮前进轴向；未删除任何固件/上位机门禁。转矩方向仍由m1_reverse/m2_reverse表示，须在后续受控电流短测中确认，未经该阶段不启动平衡PD。用户已明确准备好本次M1电角标定；仅执行一次标定，不解锁运行，不自动清错重试。

2026-10-27 16:58：用户明确授权12V开启下重试。先前M1标定请求被M2静止零偏约±50mA拦截，实际未发送commission，已停止。此次仅一次人工清错/重新校零，2314包约10秒静止检查按原门槛通过，随后一次M1电角标定成功：mask=01、state=6、faults/stop=0，右轮净−32.52度、左轮0度；200Hz相电流抽样峰0.40454A。未发送arm/start、未平衡、未清除成功标定。M2电角未标定，转矩方向未验收；当前12V保持开，用户此前确认两轮架空。源位流e2d525f5…，详见balance/results/20261027_164722_19786a/m1_retry_165801.json。重新校零后短测通过不证明长期漂移已消失。

2026-10-27 17:00：用户明确要求标定M2。500包静止预检通过，单次M2标定触发相过流(bit0x010)，随后停止故障0x011；已发送X，不自动清错/重试。右轮净0度，左轮净+15.47度；M2未完成，mask仍01。200Hz抽样相峰0.41943A，不代表未出现20kHz保护峰。M2退出busy后显示state6来自M1已完成状态，不能当成M2成功。已要求用户关闭12V、保持逻辑，尚未收到关闭确认。证据balance/results/20261027_164722_19786a/m2_commission_170044.json。

2026-10-27 17:07：用户明确允许M1→M2各一次。一次清错/重新校零后约10秒静止预检通过，M1电角标定FSM失败；首次failure样本motor_faults=0/stop_reason=0，随后按异常策略X停止，faults=1/stop=1。M2未启动。最终commissioned_mask=0，先前M1标定已因人工清错失效。200Hz相峰M1最大0.40332A，不能将此次失败称作过流。已要求12V关闭保留逻辑，尚未收到关闭确认。详见balance/results/20261027_164722_19786a/paired_commission_170700.json。

2026-10-27用户要求独立选择电角标定，已改为明确opcode9=M1右轮、10=M2左轮，支持M2先标；旧opcode5拒绝。motor_safe_drive在SELECTABLE_COMMISSION=1时使用单次commission_select，旧独立实例默认参数0保持原行为。集成顶层启用该参数，telemetry17.bit6声明能力，85.bit3:2报告所选电机，退出busy后仍显示该路状态。全局清错仍清两路；只标一路不得运行双轮。上位机旧固件能力缺失时禁用两按钮。当前12V用户已明确确认关闭，逻辑保留；本次修改尚待离线测试/新构建与下载，不得沿用旧位流说已部署。

2026-10-27独立标定改版已完成部署：11项RTL与16项上位机测试通过，最终驱动构建Setup/Hold0/0，SHA256 84a6f0b9a21ebc56fa15e6272efe5f3d6fef71a2a05cb8a6b53cc4e86d4a8b6c，仅下载SRAM。早先−0.174ns时序失败候选未下载，去掉生命周期使能冗余状态译码选择器后通过；物理fault/急停快速关断未延迟。新上位机已连接COM20，独立标定能力位为真，两路完成mask=0，active/armed/running/commissioning均false、Iq=0、IMU正常。用户已确认12V断开逻辑保留，未再次通电；本轮未发任何标定/运行命令，M1/M2独立标定尚未实物验收。证据evidence/engineering/independent_commission_20261027.json。后续只能用commission_m1或commission_m2，旧commission接口拒绝。

2026-10-27 17:39 独立M2实物标定通过：用户确认12V已通电并明确授权重新校零后再来一次。此前一次commission_m2被上位机静止电流偏置门限拦截，未发运动命令。此次仅current_zero一次，等待3秒静止后commission_m2一次；commission_axis=2,state=6,mask=2,failed=false,motor_faults=0,stop_reason=0，驱动自动退出active/armed/running/commissioning均false，未发送X停止以保留M2标定。M1编码器范围0tick，M2范围1491tick、净转角-30.7837deg；串口抽样M2三相峰值0.3562/0.3108/0.3362A（不是20kHz全量峰值）。证据balance/results/20261027_172003_26d69e/independent_m2_rezero_retry_20261027_173952.json。当前仅M2完成，M1本次未标，未做纠偏方向/平衡实物验收；保持停止，下一步需用户授权单独M1，不自动运行。12V最后用户状态仍ON。

2026-10-27 17:41 独立M1实物标定通过且保留M2：用户授权重新电流校零后标M1；current_zero一次、静止等待3秒、commission_m1一次，无清故障/无自动重试。最终commission_axis=1,state=6,commissioned_mask=3,failed=false,motor_faults=0,stop_reason=0，active/armed/running/commissioning均false，IMU错误0，未发X以保留两路标定。M1范围1497tick、净角-32.4097deg，M2编码器范围0tick；串口抽样M1三相峰值0.4199/0.3472/0.3137A。证据balance/results/20261027_172003_26d69e/independent_m1_rezero_20261027_174131.json。当前两路电角标定完成，但电流静止偏置随时间漂移问题仍在，尚未进行Iq纠偏方向或平衡实物验证；下一步两轮架空、低电流短时逐轮确认纠偏力矩方向，须具体用户授权后执行。最后12V用户状态仍ON。

2026-10-27 17:42 M1首次低电流短测完成：用户授权下一步逐轮方向确认。保持两轮架空，配置mode1/test_axis1/target+50mA/limit50mA/duration200ms，姿态校零、电流校零并静止3秒后arm/start各一次。实际Iq1指令峰值0.049805A，Iq2始终0；无故障自动退出，mask3保留。M1编码器净-0.109863deg（仅5tick），M2净0，运动太小不能据此认定力矩方向已验收，等待用户观察确认；未发M2短测、未加大电流、未启动平衡。证据balance/results/20261027_172003_26d69e/m1_torque_50ma_200ms_20261027_174254.json。

2026-10-27 17:44 用户明确授权M1 Iq+0.2A/Id0/200ms单次短测：配置限流200mA，姿态/电流校零后arm/start各一次，M2指令始终0。M1发生实际转动，编码器净-48.8452deg、M2净0；实际Iq指令最大0.19995A。运行触发FPGA速度保护bit10=0x400，总motor_faults=0x489（含sensor/ready/stop连锁），最早记录stop_reason4，随后主机发送X停止stop_reason1，无重试无清故障。不是过流bit4，200Hz峰值不能作20kHz证明。motor_measurement_angle默认16帧0.8ms窗口位移32tick，对应约146.5RPM，也有单帧64tick检查；尚未区分触发哪项。M1编码器下降与已确认前进符号一致，但未获用户目视方向确认，未做M2或平衡。证据balance/results/20261027_172003_26d69e/m1_torque_200ma_200ms_20261027_174405.json。不要直接重试或放宽保护，先检查速度轨迹与短测时长。当前故障锁存、驱动停止，12V最后用户状态ON。

2026-10-27 17:47 用户授权M1 +0.2A/200ms再次短测。第一次准备脚本clear后立即读取旧故障帧误判并发stop，未发任何运动；已告知用户并修正等待新帧清故障回执。继续同次授权：clear/config/attitude_zero，M1和M2各重新校零后分别标定均通过(mask3)，再电流校零后arm/start各一次。M1再次触发相同0x489（速度bit0x400，非过流），主机stop，未再重试。Iq1最大0.19995A，Iq2始终0；短测含滑行净M1 -56.3599deg、M2 0.02197deg（1tick），串口M1相电流绝对峰0.18774/0.18604/0.16650A。证据balance/results/20261027_172003_26d69e/m1_200ma_retry_corrected_20261027_174705.json。目前故障锁存，不能原参数重复启动；两次速度保护复现需先调整短测方案而非直接放宽保护。用户尚未目视确认方向，未做M2短测或平衡。

2026-10-27 清故障保留电角标定改版已完成但未下载：motor_commission新增PRESERVE_CAL_ON_CLEAR参数，默认0保持单独版行为，集成top开启1。普通清故障保留已成功的done/zero/reverse，失败未完成的FSM清回IDLE；点已完成的一路9/10可明确重标，只有该路done失效，重标失败不得复用旧结果，复位/下载清空所有。byte17 bit7声明能力，host允许该能力下已完成轴重标，旧固件保持阻止，UI说明与协议已更新。原保护均保留，清故障不arm不自动重试。11项完整RTL回归+额外默认版/新版真实FSM对照仿真通过（12检查），16项host通过。驱动构建setup/hold0/0且source unchanged，SHA256 0e85a01a8a591a0ad4f1b0751b0d3e698411fb37a104b5c1e27ef6f836a1e615。证据evidence/engineering/preserve_commission_on_clear_20261027.json。当前板上仍旧84a6f0b9镜像、故障锁存中；12V最后用户状态ON。必须待用户确认12V已断后再下载SRAM并重启host，无需Flash写入。新版首次下载仍需两路电角标定，此后普通故障清除不再重标。未做硬件保留行为验收。

2026-10-27 用户确认12V已断后，已将0e85a01a8a591a0ad4f1b0751b0d3e698411fb37a104b5c1e27ef6f836a1e615新版下载至SRAM（programmer finished，Flash未写），下载前核对全部构建源哈希及STA0/0。重启host进程，session29715，18866，连接COM20，新运行日志见evidence/engineering/preserve_commission_on_clear_20261027.json deployment.log_dir。实测drive/independent_commission/preserve_commission_on_clear均true，active/armed/running/commissioning全false，Iq两路0，mask0，IMU正常errors0。fault1/stop1为连接时主动初始停止。未发校零/标定/运行。当前12V已断逻辑供电保留，等待用户上电；首次重新下载需要两路标定，后续清故障保留。旧浏览器建议刷新以加载新按钮逻辑。

2026-10-27 17:58 用户明确授权两路标定及清故障保留验证，已完成。新版0e85a01a：current_zero/M1一次通过(mask1)，current_zero/M2一次通过(mask3)，未自动重试；每次静止3秒。随后人工clear一次，实测mask3保留、current_calibrated=false且config_ack=false，active/armed/running/commissioning全false，motor_faults/stop_reason0。表明普通清故障保留成功完成位的硬件行为通过；未声称速度故障复现恢复/纠偏/平衡验收。证据balance/results/20261027_175443_e5626d/both_commission_clear_verify_20261027_175809.json。当前12V最后用户状态ON，两路电角已完成，准备参数/电流/姿态零点需重新应用。下一步需要调整方向测试脉冲方案，原0.2A/200ms两次触发速度保护，不能照原样反复；尚未获本轮运行授权。

2026-10-27 17:59 用户质疑目视未转，明确要求改0.15A。已执行M1 Iq+0.15A/Id0/200ms一次，config/姿态校零/电流校零/arm/start，Iq1指令最大0.149902A，Iq2全0，再次速度保护0x489，主机stop，故障保持，无重试。mask3仍保留。M1净编码器-64.7754deg（含滑行），M2仅1tick；三相串口绝对峰0.17383/0.16626/0.14160A。证据balance/results/20261027_175443_e5626d/m1_torque_150ma_200ms_20261027_175916.json含逐包encoder轨迹。用户目视尚未确认运动，不能将编码器变化当机械运动已验证；下一步优先查编码器/机械运动一致性和超速门限，不继续仅改Iq反复启动。当前两轮驱动关闭、故障锁存、12V最后用户状态ON。

2026-10-27 18:01 用户明确授权0.15A再试一次；保持原保护，clear后mask3保留（本次真实速度故障后的清除也未丢标定），config/姿态校零/电流校零/arm/start一次，再触发0x489速度保护并stop，无自动重试。Iq1最大0.149902A/Iq2全0；active抽样跨度70ms，M1角值14371连续下降到13116，首故障12916，含停机滑行净-67.1265deg，M2净0。M1相电流串口绝对峰0.23584/0.17529/0.14307A。证据balance/results/20261027_175443_e5626d/m1_torque_150ma_retry_20261027_180114.json。机械运动/目视方向仍待用户确认；故障锁存、驱动关闭、12V最后状态ON。

2026-10-27 用户要求阶段总结，已整理docs/调车阶段总结_20261027.md，涵盖已做工作、验证矩阵、全部电流短测、速度/过流区分、当前问题和后续验收。文档以最新逐包记录为准，纠正此前“实际转动”表述为“编码器变化、机械运动未目视验收”；列出active_profile.json的旧状态字段未更新问题，未改构建输入配置或执行硬件命令。

2026-10-27 本轮用户明确要求精简保护并澄清512指速度，Iq硬上限1A。当前集成top SIMPLE_PROTECTION=1, IQ_LIMIT=4096, PHASE_TRIP=4096, MAX_WINDOW_TICKS=512，软件速度/时间关系/过流/传感/同步/运行ready故障不再停机，保留硬件nFAULT、Stop、主机100ms心跳、倾角；运行IMU异常停机也关闭但启动仍需IMU就绪。独立模块默认仍旧策略。Host静止25mA/225mA只打印及记录Warning，取消500包静止门禁；参数确认和电流校零保留。标定禁用电流/静止终态拒绝、位移误差15%扩大5倍为75%，接受25%..175%及方向一致，先断PWM再交接zero/reverse后COMPLETE。Clear保留成功电角，仍清参数/电流/姿态零点。PD源码/增益未改。13项RTL和16项host测试通过，新增精简profile测试覆盖nFAULT M1/M2无连锁假故障、Stop、保留倾角/心跳、关闭速度时序、1A clamp、放宽标定及Clear保留。用户本轮确认12V OFF逻辑ON后SRAM下载成功，SHA256 805489cebf2f61b942ba3a02e1bb392cf83f4e3254a8f8226337cbec02e96a0c，全部构建源哈希核验且STA0/0；Flash未写。新host session46872，COM20连接，日志E:\Gowin_project\fpga_project\team_repos\fpga-balance\balance\results\20261027_215227_3f0bdf。初始Stop导致fault1/stop1，其余active/armed/running/commissioning均false，Iq0、IMU正常、mask0；未发标定/解锁/start。最后用户供电状态12V OFF，等待其上电确认。下一步两路重标后M2 +0.2A/200ms方向单次短测（测试上限200mA，1A只是硬上限），preset balance/presets/05_M2_positive_direction_200mA_200ms.json，m2_reverse=false保证原始Iq2为正，M1为0。未实测1000rpm或1A，未确认机械方向/平衡。证据evidence/engineering/simplified_profile_20261027.json；修改前源码备份evidence/engineering/simplified_20261027_before/。

2026-10-27 21:56 用户确认已上电后，精简版805489ce…执行一次完整M2方向试验：clear/config/attitude_zero，current_zero/M1标定成功(mask1)，current_zero/M2标定成功(mask3)，再次current_zero后arm/start各一次。M2原始Iq指令最大+0.199951A，M1指令全0，目标200ms，40个active样本跨度195ms，无fault/stop，自动结束active/armed/running均false。含约0.5s滑行观测编码器净M2 -0.065918deg、M1 -0.021973deg，运动不足以判定前后，尚无用户目视反馈；不得将这次判定为M2正Iq后退。M2串口相电流峰0.426514/0.402100/0.108154A（不是实测dq电流）；未加流、未重试、未平衡。证据balance/results/20261027_215227_3f0bdf/m2_positive_200ma_200ms_20261027_215631.json。两路标定保留，当前停止无故障，12V最后用户状态ON。

2026-10-27 用户对M2 +0.2A/200ms短测目视反馈“向后轻动”。据此记录本次正Iq导致轻微后退；active期编码器2却先增加约52tick/1.14deg（全记录range1.384deg），与此前手动前转编码器2增加的结论矛盾，尚未分清受力初动/停机回弹观察时刻与编码器机械一致性，不能直接判定完整转矩方向验收。已补入本次JSON user_visual_observation/torque_direction_accepted=false。未发新的电机命令，未改PD或转矩符号，保持上次停止状态；12V最后用户状态ON。

2026-10-27 21:58 用户随即纠正上次“向后轻动”为“没看清楚”，请求多转一点；因此上一条目视方向不得当作确认。已执行一次M2原始Iq +0.3A/500ms，M1=0，沿用两路电角标定，重新config/attitude_zero/current_zero后arm/start各一次。100个active样本跨度495ms，无故障自动结束；末态active/armed/running=false，mask3，fault/stop0。Iq2最大+0.299805A，M2串口三相峰0.496094/0.458740/0.098633A；全记录M2编码器范围1.60400390625deg，含滑行净-0.021973deg，尚无持续旋转证据，待用户观察反馈。不自动加流重跑。证据balance/results/20261027_215227_3f0bdf/m2_positive_300ma_500ms_20261027_215844.json。当前12V最后用户ON。

2026-10-27 22:00 用户称仍未看到并请求持续转动。已说明当前协议最长5秒，执行一次M2 +0.3A/5000ms，M1=0，参数确认/姿态校零/电流校零/arm/start，无重标无重试。1000个active样本跨度4995ms，无故障正常退出，两路电角mask3保留；含滑行M2净0deg，编码器范围1.56005859375deg，仍无持续旋转证据。M2相电流串口峰0.467041/0.467773/0.101807A。延长时间未解决，需核对实际dq跟踪、电角零位/方向、相序/电流反馈，不应当直接宣布其中任何根因。证据balance/results/20261027_215227_3f0bdf/m2_positive_300ma_5000ms_20261027_220025.json。未改无限运行/未增加Iq；当前停止无故障、12V最后用户状态ON。

2026-10-27 22:07 用户观察5秒有声音无转动、仅最后一刻抖，要求检查M2电角/换相/电流反馈。本轮未新增硬件命令。离线发现M2扫角1395tick满足位移，但theta0末20包ABC均值+0.05465/-0.07214/+0.01749A，明显不同于10/25成功版+0.25202/-0.12295/-0.12907A；5秒末100包ABC均值-0.22743/+0.22787/-0.00044A。原先“标定通过”只代表放宽FSM COMPLETE，不能代表电流质量/电角物理验收。源码M2路由与历史成功基准一致(encoder2,ABC,CH3=C反,CH4=B正常,增益217082/220767,11pp)，未找到确定的软件相序错误。CH3/C近零是线索，不足以判Hall坏或桥臂断相。新增只读诊断候选：TRACE_MOTOR2=1选实际M2 IP Park/PI，V2 A8扩展169字节带32字节相干trace及两路learned_zero/reverse，host兼容旧129帧；FOC/PD参数和精简保护不变。15项RTL+18项host通过，STA0/0，候选SHA 6c71a09d55e70f278801772dec404123363f170aed88194bd1e8faeffb6bdba6，源哈希已核验。未下载：当前板上仍805489ce，最后用户12V ON，须用户先确认OFF逻辑保留后才能SRAM下载并重启host。上位机当前运行仍原已加载代码；磁盘新版解析器尚未加载。旧run_m2_direction_*脚本硬编码805489ce校验，不能直接用于诊断候选；后续应另写一次观测入口检查m2_diagnostic选中2、park_valid及overrun/sequence新鲜，先标定观察实际dq与Ud/Uq，再定运行，不盲目交换相序或加流。报告docs/M2有声不转诊断_20261027.md，结构化evidence/engineering/m2_no_rotation_diagnosis_20261027.json。

2026-10-27 22:11 用户确认12V已断后，诊断版6c71a09d55e70f278801772dec404123363f170aed88194bd1e8faeffb6bdba6核验全部构建源哈希/位流SHA/STA0/0后已SRAM下载成功，Flash未写，programmer Finished。上位机已重启session92624，18866，COM20，新日志E:\Gowin_project\fpga_project\team_repos\fpga-balance\balance\results\20261027_221113_a7a582；实测169字节诊断帧可解析，selected_motor2/simple_protection=true。active/armed/running/commissioning均false，Iq0，IMU正常errors0，mask0，current_calibrated=false，初始Stop令fault1/stop1。M2 trace sequence0/park_valid=false/全零是尚未电流校零且fault锁存的预期冻结状态，不能说已验证真实dq有效或电流零点。未发送校零/标定/运行。当前12V最后用户确认OFF，逻辑ON。下一步待用户上电确认后先单独M2电角标定并收集实际dq/电压/learned_zero/reverse，不直接恢复5秒试跑；新的上板后两路电角均清空。

2026-10-27 22:13 用户确认上电后，诊断版6c71a09d…仅clear/config(target0)/current_zero/commission_m2各一次，未发M1标定或arm/start，无重试。FSM COMPLETE(mask2)但电流质量明确不通过：theta90末100ms真实IP Id=-0.01405/Iq=+0.00543A，Ud+.125/Uq-.07534；首次theta0 Id+.04652/Iq-.03735，Ud/Uq均+.125顶限幅；末theta0 Id+.10455/Iq-.03279，Ud/Uq仍+.125顶限幅（参考Id+.25/Iq0）。460条活动trace序号唯一、parkvalid有效、overrun0，ABC按同theta重算Park与IP误差RMS0.2825/0.1458mA，排除显示dq错读/该批数据M1M2混淆。扫码总位移约-1480tick接近名义1489.45，learned_reverse2/zero2=6731；因标定电流矢量不正确，电角零位不能判为物理合格。核心故障收敛为固定角电流闭环不跟踪，尚不能分相电流物理反馈链路与桥端实际输出/相线；不直接归因霍尔坏或随意交换极性。结束active/armed/running/commissioning=false，fault/stop0，mask2质量未接受，12V最后用户ON。下一步先断12V核对UVW/ABC、B/C霍尔方向与OUT到CH3/4，若一致需独立观测电压/电流，不继续单纯加流。原始+分析balance/results/20261027_221113_a7a582/m2_commission_real_dq_20261027_221322.json，报告已追加。

2026-10-27 用户要求固定刚才两个程序并提供独立启动入口。已封存releases/MOTOR_MANUAL_20261027_R1：精简版由诊断改动前RTL快照独立重建，SHA41f4a6aca4e5af24bc53577402e2a61a342bb8c884f43eb756a47aef531e5c07（不是原805489ce文件）；诊断版6c71a09d…原位流封存，两版STA0/0，精确source_sha256逐项核对。含独立source/simple/source/diagnostic快照、firmware/.fs及build.json、固定host、presets、MANIFEST.json和使用说明.txt。入口E:/Gowin_project/fpga_project/启动电机调试.cmd，仓库根另有同名入口，均指向包START.cmd/launcher.py。菜单1默认打开固定host，2诊断版/3精简版仅SRAM下载需用户手动断12V输入OFF，4记录5说明。普通启动无自动连接/下载/运动。固定host新增可见真实M2 dq/电压/零位/方向/有效标志和CSV诊断列，19项host测试、JS语法及启动HTTP/已有实例复用测试通过，文件hash校验通过。旧root host已停，固定host已启动session60532、18866、release_id=MOTOR_MANUAL_20261027_R1、目前未连接串口。未新增电机命令或下载；板上仍6c71a09d诊断SRAM，M2问题未修复。该入口依赖本机仓库.venv和Gowin，不是跨电脑免安装包。日志位于包app/results。用户之后自行操作，无自动任务。

2026-10-27 用户要求标定M2旁新增一键试转按钮；原请求3秒/2000ms/1秒矛盾，经async用户明确选择2秒。已创建R2保留R1不变，入口E:/Gowin_project/fpga_project/启动电机调试.cmd及仓库根同名入口改指R2。新增醒目“M2一键试转2秒”与结果卡片，前端m2_test.js自动设mode1/axis2/目标400mA/上限500mA/duration2000/m2_reverse=false/PD速度增益0，等待config_ack后自动姿态/电流校零，再arm/start各一次，等待结束用只读/api/m2-test-samples获取200Hz完整抽样，处理14bit回绕统计ΔEncoder。已有双电角mask3和确认项门禁保留；不自动清故障/标定/重复。Stop/Esc/断开取消后续流程，异常Stop。绿色需覆盖>=1750ms、>=20包、abs净位移>256tick且4段中3段沿净方向>=16tick，拒绝一次抖动/往复；绿色文案只说明检测到持续转动，不能声称标定相序完全有效。红色提示相序/缺相/零位或电流不跟踪。20项host+Node命令顺序/参数/回绕/抖动/取消/故障测试通过，JS语法通过。未改FPGA位流、未实物点试转。切换前只读确认R1电机/校准全idle，停R1后启动R2 session42832，18866，当前默认未连接串口；用户需重新连接和人工清故障。已用浏览器刷新tab2验证按钮与结果卡片，截图evidence/engineering/m2_one_click_R2_20261027.jpg，未点任何电机控制按钮。R2 MANIFEST更新且校验通过。

2026-10-28 用户授权帮其执行测试、增加M1按钮并永久保存参数。已创建releases/MOTOR_MANUAL_20261028_R3，保留R1/R2；通用前端run/measure支持axis1/2，分别用angles[axis-1]及test_axis，双按钮都原始正Iq400mA、上限500mA、2秒。20项host回归和Node双轴路由/编码器测试通过。M1第一次准备Clear旧帧误判未运行，修正新帧等待后+0.4A/2s一次完成（400 active样本1995ms，编码器1 -5504.37deg，M2命令0）；用户没看清要求慢点，再+0.15A/2s一次（上限.2A，-5243.4deg约14.6圈，M2命令0，均无故障），降低Iq并未可靠降低转速，不要承诺电流测试等于恒低速。用户最终明确M1“向前”；前一轮用户明确M2“向后”。故方向确认：M1原始正Iq前、M2原始正Iq后；车体向前映射m1_reverse=false/m2_reverse=true，已保存R3/vehicle_parameters.json及hardware/confirmed_direction_parameters_20261028.json，含FOC16384/256、11pp、gain217082/220767、currentreverse7/cb3、实际测试配置及会话learned_zero[6914,3690]/learned_reverse3。快照不得复位/下载后直接复用；普通Clear仍保留。前进预设R3/presets/forward_M1_150mA_2s.json及forward_M2_400mA_2s.json，页面自动载入方向默认，方向卡片可见；双方向按钮仍强制原始正Iq，不能误以为前进按钮。入口原路径已指R3。R2测试原始日志在R2/app/results/20261027_232105_1f07dd/m1_positive_400ma_2s_20261028_002150.json及m1_positive_150ma_2s_20261028_002340.json（后者用户forward已写入）。切换R3 host session43287/18866，COM20连接，先初始Stop再Clear、确认mask3保留，未新增运动。浏览器刷新时页面心跳间断又产生人工Stop1，当前停止；需要继续操作时先Clear但不重标。未动FPGA。PD暂未启用：正control_iq按上述映射为前进，而现有PD target-pitch及负rate在正前倾时给负control_iq，须在后续启用平衡前统一整个PD符号，不能直接沿用正Kp/Kd运行；该项审计已写参数JSON，当前增益0。

2026-10-28 00:50 用户授权开始PD方向验证。采用现有固件不改RTL、不下载、不重做电角：PD仍target-pitch与负rate，专用转矩flags M1反/M2不反，使正前倾负common_iq→M1正/M2负→两轮前进。与电流模式前进flags M1不反/M2反不同，不能混用。Kp .05/Kd0，cap150mA，速度PI0。等待用户摆姿态时页面心跳停止曾两次导致未启动；首个4分钟只读保活也到期，没有电机启动。最终在用户确认小幅前倾后，为避免中间等待失效，利用Stop后旧attitude_cal还有效，记录旧pitch-trim误差，在同一heldpose重校零并等量平移目标trim，保持原物理直立目标，连续clear/config/姿态零/电流零/arm/start。首次前倾0.5秒M1前转573.86deg而M2仅1.1deg，用户没看清要求2秒；前倾2秒成功，M1 -4404.99deg/M2 +2482.45deg，用户明确“两轮都向前”。参考误差约+1.893deg，trim-1.89；末100样本M2ref-.08938/actual-.08762A。后倾首次姿态超预设未启动，随后仅放宽支撑后倾输入到4.8度（限流/时长不变）；实际旧直立参照误差-3.533deg、trim+3.53，2秒M1+5292.60deg/M2-4.92deg，用户“M1向后，M2没明显转”。M2真实ref+.1499/actual+.00438A，Uq+.75顶限幅。曾建议退出归零，但用户明确“不要退出，再试一次”，因此未执行退出/归零。授权同参数重试后，误差-3.03075deg，trim+3.03，2秒M1+5268.38deg/M2-4787.82deg，用户明确“两轮都向后”；M2末100样本ref+.1499/actual+.15158A，但Id-.05948A、Ud+.125、Uq+.72155，仍不证明电流环稳定。当前前后PD方向已接受，PD增益/整车平衡/速度PI未验收，M2间歇欠跟踪仍开放。所有试验已正常时限结束、无硬件fault，未额外Stop/归零退出；目前临时姿态零位在后倾heldpose，目标补偿trim+3.03保持原直立目标，下一阶段务必先实际回直立、trim0重新姿态校零再调参，不得直接将现相对0当直立。旧页面/心跳可能再次Stop1，应先查当前状态。参数hardware/pd_direction_parameters_20261028.json、hardware/confirmed_direction_parameters_20261028.json；中性目标preset balance/presets/07_PD_verified_direction_150mA_2s.json（必须实际直立校零后用）。原始PD记录在R3/app/results/20261028_002521_c5e241/pd_front_referenced_2s_20261028_004521.json、pd_rear_referenced_2s_20261028_004802.json（失败）及pd_rear_referenced_2s_20261028_005000.json（重试通过）。

2026-10-28 用户确认“车身已实际直立”。已执行pd_restore_upright_20261028.py：clear/config(trim0，PD专用M1反/M2不反，Kp.05/Kd0，cap150mA，duration2000，速度PI0)/attitude_zero/current_zero，无arm/start。最终pitch-0.00766deg、rate+.1831deg/s，mask3保留，fault/stop0，active/armed/running/commissioning均false，gates4095。本轮后倾临时零位和trim+3.03补偿已消除，现可用真实直立参考继续后续诊断；电角未重标。证据evidence/engineering/pd_upright_restored_20261028.json。hardware/pd_direction_parameters_20261028.json已更新upright_reference_restored=true/compensation0。M2间歇正Iq欠跟踪问题仍开放，PD电流上限/增益未继续增加，整车平衡未验收。


2026-10-28 01:00 用户要求检测M2正负电流。执行balance/tools/m2_current_pair_20261028.py，原始正负Iq各150mA/2000ms，指令上限200mA，M1指令全0，PD和速度PI全0，FOC16384/256。Clear后保留mask3，仅首次电流校零；两次各参数确认/姿态零，期间确认滑行停稳后再反向，无电角重标/下载/额外重试。两次各400 active样本1995ms，无trace overrun。正向M2净-4804.519deg（13.35圈），末100样本ref+.149902/actual+.150991A，但Id-.073799A、Ud+.125全程顶限、Uq+.723817（尾段59%顶限）。负向净+1.09863deg，后1.5秒基本停在1467tick，ref-.149902/actual-.151130A，Id+.292446A而refId0，Ud-.125全程顶限、Uq-.508336。因此不能只凭Iq均值判电流环正常，正负都可靠旋转尚未验收，历史间歇失败仍开放，不能直接加大PD或落地平衡。证据evidence/engineering/m2_current_pair_20261028_010012.json含逐包相电流/电角/IdIq/电压；hardware/pd_direction_parameters_20261028.json更新最新摘要。两次正常限时退出，最后主动Stop，active/armed/running=false，mask3，fault/stop1为人工停止而非硬件nFAULT；12V仍ON。当前配置是M2负电流测试模式，非PD；今后须重新配置和按门禁校零。

2026-10-28 M2空载阻尼排查：用户明确停驱动后手转M2也明显比M1涩。只读确认fresh、active/armed/running/commissioning=false、rpm两路0、mask3、manualStop1。源码两路共用FOC kp16384/ki256，Stop屏蔽PWM并关闭drv_en（源码事实，未实测物理引脚）。本轮未改参数/未发运动。已请用户断12V等指示灯熄灭后比较两轮手感，暂不拔相线；等待该观察再决定机械/电气路径，不能将手涩直接归因PI或认定机械坏。记录hardware/m2_damping_investigation_20261028.json。

2026-10-28 用户确认12V已断，M2手转仍明显更涩。无运动/下载/参数更改。下一步保持断电，标记UVW后断开M2三相并隔离线端，再比较M2手感，以区分驱动/线束电气负载与电机本体/安装；当前不能直接断言机械故障。等待用户结果，禁止假定已重新上电。

2026-10-28 02:35 用户反馈断M2三相后仍基本一样涩，猜制造问题（仅用户猜测，未确认制造缺陷）；授权新增上位机手动多参数试验。本轮软件交付R4 releases/MOTOR_MANUAL_20261028_R4，R1/R2/R3保留；两个启动电机调试.cmd入口已指R4。新增右侧“电机参数对照测试”：单轴M1/M2、原始有符号Iq±1000mA、指令上限1～1000mA、100～5000ms、电流PI kp0～16384/ki0～256，默认M2/+150/上限200/2000ms/16384/256。自动等待两轮停稳750ms/参数确认/姿态零/可选电流零/arm/start单次；强制电流模式、两路转矩映射false、PD速度增益0、trim0/start3/cutoff15/filter8；另一轴Iq0。共用PI，非每路独立PI。保留校零门禁、人工Clear、电角标定/确认门禁、Stop/Esc取消；不自动Clear/重标/循环。新增未持久化“接回UVW/架空/电源准备”勾选，因12V仍OFF、M2相线当前断开。UI可沿用有效电流零点做参数对照。
新增motor_tests.py纯记录模块，受同源/token约束的POST /api/motor-tests只保存不发命令，GET历史和单记录JSON。每次尝试start后配置/备注/原始样本/故障/编码器净位移/抽样相峰值/末100有效真实M2dq均值/电压限幅占比永久保存app/results/motor_tests；显示最近40组，支持载入参数（不发送命令）、下载JSON。M1明确无实际dq，不冒用M2或指令值；启动前准备失败仍留原始串口日志。24项Python回归、Node含自定义负Iq/不重校零/时长/无效参数/取消的流程测试通过；初次沙箱localhost和temp清理被系统限制，升级权限后离线全通过。R4 MANIFEST校验通过，位流没改/未下载/未启动任何电机。
切换R4时旧/api/state record已None，无活动驱动记录；断开脚本因此未发送命令；随后只停止精确匹配R3 server的进程。当前R4 host session15646/18866，默认未连接，未发串口命令。IAB tab2已刷新R4并确认测试区字段与断开禁用状态，截图evidence/engineering/motor_test_panel_R4_20261028.jpg。FPGA当前状态因未连接未验证，不保证mask3仍存在；若逻辑复位须正常电角标定。用户之后按断电原序接回UVW、上电架空、连接/人工Clear和门禁后自测；不要据用户制造猜测宣称根因已定。

2026-10-28 用户授权上传当前FPGA/R4上位机/启动程序到原GitHub fpga-balance。准备分支codex/motor-manual-r4-20261028，保留根RTL/上位机和R4当前快照/两份位流/参数/工程证据；旧R1R2R3、本地运行日志、venv和厂商加密IP不上传（不删除本地文件）。仓库实际公开。根启动cmd和R4 START改成相对路径，新增tools/manual.py离线建venv/安装wheel后运行R4，避免固定E盘路径；--check通过。发布MANIFEST排除不分发的IP，SOURCE_MANIFEST仅包含可上传文件。离线RTL全部通过（含简化保护/双轴/标定保留/诊断），根host18项通过，R4 host24项与Node流程此前通过，实物问题状态保留未验收。本轮没有电机或下载命令。
