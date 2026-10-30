`default_nettype none
// Carrier_Hall_RevB + POWER_DRV8323HR x2 + ICM-42688-P.
// ALLOW_DRIVE=0 is the default and physically grounds all PWM/EN/CAL pins.
module balance_top #(parameter ALLOW_DRIVE=0)(
    input wire clk50m,reset_n,uart_rx,output wire uart_tx,output wire [7:0] led,
    output wire m1_pwm_ah,m1_pwm_al,m1_pwm_bh,m1_pwm_bl,m1_pwm_ch,m1_pwm_cl,
    output wire m2_pwm_ah,m2_pwm_al,m2_pwm_bh,m2_pwm_bl,m2_pwm_ch,m2_pwm_cl,
    output wire m1_drv_en,m2_drv_en,m1_cal,m2_cal,input wire m1_fault_n,m2_fault_n,
    output wire adc_convst,adc_reset,adc_cs_n,adc_sclk,input wire adc_busy,adc_dout_a,adc_dout_b,
    output wire enc1_cs_n,enc1_clk,enc2_cs_n,enc2_clk,input wire enc1_do,enc2_do,
    output wire lidar_uart_tx,lidar_moto_pwm,inout wire imu_i2c_scl,imu_i2c_sda);
    reg [2:0] release_reset;
    always @(posedge clk50m or negedge reset_n)
        if(!reset_n) release_reset<=0;else release_reset<={release_reset[1:0],1'b1};
    wire rst_n=release_reset[2];
    wire sv,imu_ready,imu_fault,imu_stale;
    wire signed [15:0] ax,ay,az,gx,gy,gz,temp;
    wire [31:0] imu_seq,commit_us,age_us,now_us;
    wire [15:0] imu_errors,imu_invalid;
    wire [7:0] who,last_error;
    imu_1khz_core imu(.clk(clk50m),.rst_n(rst_n),.imu_i2c_scl(imu_i2c_scl),.imu_i2c_sda(imu_i2c_sda),
        .ready(imu_ready),.fault(imu_fault),.sample_valid(sv),.sample_stale(imu_stale),.temperature_valid(),
        .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),.temperature_raw(temp),.sample_seq(imu_seq),
        .timestamp_us(),.commit_timestamp_us(commit_us),.sample_age_us(age_us),.now_us(now_us),
        .observe_to_commit_us(),.sample_interval_us(),.error_count(imu_errors),.invalid_count(imu_invalid),.who_am_i(who),.last_error(last_error));
    wire imu_ok=imu_ready && !imu_fault && !imu_stale && age_us<3000 && who==8'h47;
    wire rx_valid;wire [7:0] rx_byte;
    wire [1599:0] packet;
    motor_console #(.BAUD_DIV(54),.STATUS_CYCLES(250000),.PAYLOAD_BYTES(200)) uart(
        .clk(clk50m),.rst_n(rst_n),.rx(uart_rx),.tx(uart_tx),.status(packet),.command_valid(rx_valid),.command(rx_byte));
    wire cv,configured,changed,can_configure;wire [7:0] cmd,ack,result;wire [255:0] cfg;wire [15:0] rx_errors;
    wire active,armed,clear_fault,calibrate,zero_start,commission_start,estop;
    wire [1:0] commission_select;
    wire [15:0] stop_reason,gates;wire [7:0] rejected;
    balance_protocol protocol(.clk(clk50m),.rst_n(rst_n),.byte_valid(rx_valid),.byte_value(rx_byte),
        .can_configure(can_configure),.invalidate(clear_fault || stop_reason!=0),.command_valid(cv),.command(cmd),
        .configured(configured),.config_changed(changed),.config_body(cfg),.ack_seq(ack),.result(result),.rx_errors(rx_errors));
    wire av,att_cal,att_busy,att_bad;wire signed [31:0] pitch,rate;wire [15:0] interval_us,zero_progress;
    balance_attitude attitude(.clk(clk50m),.rst_n(rst_n),.sample_valid(sv),.zero_start(zero_start),
        .invalidate(clear_fault),.filter_shift(cfg[211:208]),
        .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),.commit_us(commit_us),
        .valid(av),.calibrated(att_cal),.calibrating(att_busy),.bad_sample(att_bad),.pitch(pitch),.rate(rate),
        .interval_us(interval_us),.zero_progress(zero_progress));
    wire signed [15:0] shadow_iq;
    wire [1:0] mode=cfg[217:216];
    wire signed [15:0] speed_trim,rpm1,rpm2;
    wire signed [16:0] trim_sum=$signed(cfg[143:128])+$signed(speed_trim);
    wire signed [15:0] effective_trim=trim_sum>500 ? 500 : trim_sum< -500 ? -500 : trim_sum[15:0];
    reg signed [31:0] direct_product;reg signed [15:0] direct_iq;reg direct_start;
    wire direct_valid,direct_busy;wire signed [31:0] direct_result;
    balance_sdiv current_units(clk50m,rst_n,direct_start,direct_product,16'd1000,direct_busy,direct_valid,direct_result);
    always @(posedge clk50m or negedge rst_n)
      if(!rst_n)begin direct_product<=0;direct_iq<=0;direct_start<=0;end
      else begin
        direct_product<=$signed(cfg[239:224])*32'sd4096;direct_start<=changed;
        if(direct_valid)direct_iq<=direct_result[15:0];
      end
    wire signed [15:0] control_iq=mode==1 ? direct_iq : shadow_iq;
    // Capture the new PD result only after its arithmetic pipeline has settled.
    // Heartbeats still refresh the independent guard during commissioning.
    reg [7:0] pd_valid_pipe;
    always @(posedge clk50m or negedge rst_n)
        if(!rst_n) pd_valid_pipe<=0;else pd_valid_pipe<={pd_valid_pipe[6:0],av};
    balance_pd pd(.clk(clk50m),.rst_n(rst_n),.pitch(pitch),.rate(rate),.trim_cdeg(effective_trim),.kp(cfg[63:32]),.kd(cfg[95:64]),
        .limit_ma(cfg[159:144]),.iq(shadow_iq));
    wire [11:0] faults,pwm;wire [1:0] en,cal,comm_mask;
    wire running,current_cal,current_busy,fv,comm_done,comm_busy,comm_failed;
    wire [95:0] currents;wire [27:0] angles;wire [31:0] motor_seq;wire [3:0] comm_state;
    wire signed [15:0] governed_iq1,governed_iq2;
    wire current_limit_active1,current_limit_active2;
    balance_current_speed_limit current_governor(.clk(clk50m),.rst_n(rst_n),.enable(active && mode==1),
        .command(direct_iq),.rpm1(rpm1),.rpm2(rpm2),.ceiling(cfg[255:240]),
        .iq1(governed_iq1),.iq2(governed_iq2),.limiting1(current_limit_active1),.limiting2(current_limit_active2));
    wire signed [15:0] iq1=active && (mode!=1 || cfg[220]) ? (mode==1 ? governed_iq1 : -control_iq) : 16'sd0;
    wire signed [15:0] iq2=active && (mode!=1 || cfg[221]) ? (mode==1 ? governed_iq2 : control_iq) : 16'sd0;
    balance_speed speed_loop(.clk(clk50m),.rst_n(rst_n),.enable(active && mode==2),
        .reset_loop(changed || clear_fault),.angle1(angles[13:0]),.angle2(angles[27:14]),
        .target(cfg[239:224]),.kp({7'd0,cfg[247:240],1'b0} >> (cfg[222] ? 0 : 1)),
        .ki({7'd0,cfg[255:248],1'b0} >> (cfg[222] ? 0 : 1)),
        .rpm1(rpm1),.rpm2(rpm2),.trim_cdeg(speed_trim));
    balance_supervisor #(.SIMPLE_PROTECTION(1),.ALLOW_DRIVE(ALLOW_DRIVE)) supervisor(.clk(clk50m),.rst_n(rst_n),
        .command_valid(cv),.command(cmd),.configured(configured),.config_changed(changed),
        .imu_ok(imu_ok),.attitude_calibrated(att_cal),.attitude_calibrating(att_busy),.attitude_bad(att_bad),
        .current_calibrated(current_cal),.current_calibrating(current_busy),.commissioned(comm_done),.commissioning(comm_busy),
        .motor_faults(faults),.active(active),.armed(armed),.clear_fault(clear_fault),.calibrate(calibrate),.zero_start(zero_start),
        .commission_start(commission_start),.commission_select(commission_select),.estop(estop),.can_configure(can_configure),.stop_reason(stop_reason),.gates(gates),.rejected_command(rejected));
    // Start serial peripherals only after the IMU has left soft reset and
    // completed interface configuration. Latch this once: a later IMU fault
    // must stop through the supervisor, never silently reset motor faults.
    reg peripherals_started;
    always @(posedge clk50m or negedge rst_n)
        if(!rst_n) peripherals_started<=0;
        else if(imu_ready) peripherals_started<=1;
    wire peripheral_rst_n=rst_n && peripherals_started;
    wire [255:0] m1_trace,m2_trace;wire [27:0] learned_zero;wire [1:0] learned_reverse;
    wire [1:0] physical_motor_mask=comm_busy || mode!=1 ? 2'b11 : cfg[221:220];
    motor_safe_drive #(.INDEPENDENT_TUNING(1),.TRACE_MOTOR2(1),.SIMPLE_PROTECTION(1),.IQ_LIMIT(4915),.PHASE_TRIP(4096),.CONFIG_CONFIRMED(1),.MOTOR_MASK(3),.CURRENT_CB_MASK(3),.CURRENT_REVERSE(7),
        .ALLOW_CURRENT_TUNING(1),.DUAL_IQ_CONTROL(1),.SELECTABLE_COMMISSION(1),.PRESERVE_CAL_ON_CLEAR(1),.TUNING_KP_MAX(16384),.TUNING_KI_MAX(256),
        .GAIN_CH1_Q16(217082),.GAIN_CH2_Q16(220767),.GAIN_CH3_Q16(217082),.GAIN_CH4_Q16(220767),
        .CURRENT_LAG(1000),.ENCODER_LAG(250),.MAX_WINDOW_TICKS(512),.COMMAND_SLEW(64),
        .COMM_ID_Q15(1434),.COMM_VOLTAGE_LIMIT(8192),.COMM_SETTLE(20000),.COMM_PREALIGN(6000),.MAX_RUN_CYCLES(250000000)) drive(
        .clk(clk50m),.rst_n(peripheral_rst_n),.request_arm(ALLOW_DRIVE && active),.clear_fault(clear_fault),
        .calibrate(calibrate),.estop(estop),.command_valid(cv || pd_valid_pipe[7]),.commission_start(ALLOW_DRIVE && commission_start),.commission_select(commission_select),
        .iq_request_1(iq1),.iq_request_2(iq2),.tuning_kp(cfg[111:96]),.tuning_ki(cfg[127:112]),
        .tuning_kp_m2(cfg[223] ? cfg[175:160] : cfg[111:96]),.tuning_ki_m2(cfg[223] ? cfg[191:176] : cfg[127:112]),
        .m2_pwm_order(3'd0),.m2_current_swap(1'b0),
        .drv_fault_n({m2_fault_n,m1_fault_n} | ~physical_motor_mask),.adc_busy(adc_busy),.adc_dout_a(adc_dout_a),.adc_dout_b(adc_dout_b),
        .enc1_do(enc1_do),.enc2_do(enc2_do),.adc_convst(adc_convst),.adc_reset(adc_reset),.adc_cs_n(adc_cs_n),.adc_sclk(adc_sclk),
        .enc1_cs_n(enc1_cs_n),.enc1_clk(enc1_clk),.enc2_cs_n(enc2_cs_n),.enc2_clk(enc2_clk),
        .pwm(pwm),.drv_en(en),.drv_cal(cal),.running(running),.calibrated(current_cal),.calibrating(current_busy),
        .feedback_valid(fv),.faults(faults),.phase_currents(currents),.mechanical_angles(angles),.frame_sequence(motor_seq),
        .commissioned(comm_done),.commissioned_mask(comm_mask),.commissioning(comm_busy),.commission_failed(comm_failed),
        .commission_state(comm_state),.learned_reverse(learned_reverse),.learned_zero(learned_zero),.diagnostic_m1_sample(m2_trace),.diagnostic_axis1_sample(m1_trace),.raw_adc_frame(),.current_zero_offsets());
    // Zero Iq still runs a current loop: disable the unselected physical driver.
    // Independent commissioning owns its axis inside motor_safe_drive.
    assign {m2_pwm_cl,m2_pwm_ch,m2_pwm_bl,m2_pwm_bh,m2_pwm_al,m2_pwm_ah,m1_pwm_cl,m1_pwm_ch,m1_pwm_bl,m1_pwm_bh,m1_pwm_al,m1_pwm_ah}=ALLOW_DRIVE ? pwm & {{6{physical_motor_mask[1]}},{6{physical_motor_mask[0]}}} : 12'd0;
    assign {m2_drv_en,m1_drv_en}=ALLOW_DRIVE ? en & physical_motor_mask : 2'd0;
    assign {m2_cal,m1_cal}=2'd0;
    assign lidar_uart_tx=1;assign lidar_moto_pwm=0;
    assign led=~{estop,comm_busy,current_cal,att_cal,imu_ok,configured,armed,active};
    reg [1583:0] telemetry;
    always @* begin
        telemetry=0;
        telemetry[0+:32]=32'hc8_02_b6_a5;
        telemetry[32+:32]=now_us;telemetry[64+:32]=imu_seq;telemetry[96+:32]=motor_seq;
        telemetry[128+:8]={comm_failed,comm_busy,running,current_busy,current_cal,att_busy,att_cal,(ALLOW_DRIVE!=0)};
        telemetry[136+:8]={1'b1,1'b1,configured,imu_ok,att_bad,estop,armed,active};
        telemetry[144+:16]=gates;telemetry[160+:16]=stop_reason;telemetry[176+:16]={4'd0,faults};
        telemetry[192+:32]=pitch;telemetry[224+:32]=rate;
        telemetry[256+:16]=shadow_iq;telemetry[272+:16]=iq1;telemetry[288+:16]=iq2;
        telemetry[304+:16]=interval_us;telemetry[320+:32]=age_us;
        telemetry[352+:16]=ax;telemetry[368+:16]=ay;telemetry[384+:16]=az;
        telemetry[400+:16]=gx;telemetry[416+:16]=gy;telemetry[432+:16]=gz;
        telemetry[448+:16]=temp;telemetry[464+:96]=currents;
        telemetry[560+:16]={2'd0,angles[13:0]};telemetry[576+:16]={2'd0,angles[27:14]};
        telemetry[592+:16]=zero_progress;telemetry[608+:16]=imu_errors;telemetry[624+:16]=imu_invalid;
        telemetry[640+:16]=rx_errors;telemetry[656+:8]=ack;telemetry[664+:8]=result;
        telemetry[672+:8]=rejected;telemetry[680+:8]={comm_state,commission_select,comm_mask};
        telemetry[688+:8]=who;telemetry[696+:8]=last_error;
        telemetry[704+:256]=cfg;
        telemetry[960+:16]=rpm1;telemetry[976+:16]=rpm2;telemetry[992+:16]=speed_trim;
        telemetry[1008+:256]=m2_trace;
        telemetry[1264+:16]={2'd0,learned_zero[13:0]};telemetry[1280+:16]={2'd0,learned_zero[27:14]};
        telemetry[1296+:8]={6'd0,learned_reverse};telemetry[1304+:8]=8'd2;
        telemetry[1312+:8]={3'd0,1'b1,current_limit_active2,current_limit_active1,1'b1,1'b1};telemetry[1320+:8]=8'hd2;
        telemetry[1328+:256]=m1_trace;
    end
    balance_telemetry #(.DATA_BYTES(198)) sender(.clk(clk50m),.rst_n(rst_n),.data(telemetry),.packet(packet));
endmodule
`default_nettype wire
