module brushed_balance_top #(
    parameter integer DRIVE_ENABLE=0,
    parameter integer CPR_LEFT=60000,CPR_RIGHT=60000,
    parameter integer CLK_HZ=50000000,BAUD=115200
)(
    input wire clk50m,reset_n,uart_rx,
    inout wire imu_i2c_scl,imu_i2c_sda,
    input wire left_enc_a,left_enc_b,right_enc_a,right_enc_b,
    output wire left_in1,left_in2,right_in1,right_in2,uart_tx,
    output wire legacy_m1_disable,
    output wire [5:0] legacy_m1_pwm_disabled,
    output wire legacy_m1_cal_disabled,
    output wire [7:0] led
);
    (* syn_preserve=1 *) reg reset_meta,reset_sync;
    always @(posedge clk50m or negedge reset_n)
        if(!reset_n)begin reset_meta<=0;reset_sync<=0;end
        else begin reset_meta<=1;reset_sync<=reset_meta;end
    wire [7:0] byte_data,opcode,sequence_id;
    wire byte_valid,framing_error,command_valid;
    wire [319:0] payload;
    wire [15:0] bad_frames;
    uart_rx_byte #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) rx(.clk(clk50m),.reset_n(reset_sync),.rx(uart_rx),
        .data(byte_data),.valid(byte_valid),.framing_error(framing_error));
    bb_protocol #(.CLK_HZ(CLK_HZ)) protocol(.clk(clk50m),.reset_n(reset_sync),.byte_data(byte_data),
        .byte_valid(byte_valid),.framing_error(framing_error),.command_valid(command_valid),
        .opcode(opcode),.sequence_id(sequence_id),.payload(payload),.bad_frames(bad_frames));

    wire imu_ready,imu_fault,sample_valid,sample_stale;
    wire signed [15:0] ax,ay,az,gx,gy,gz;
    wire [31:0] commit_us;
    wire [31:0] imu_seq,imu_age,imu_now;
    wire [15:0] imu_errors,imu_invalids;
    wire [7:0] imu_who,imu_error;
    wire imu_temp_valid;
    imu_1khz_core #(.CLK_HZ(CLK_HZ)) imu(.clk(clk50m),.rst_n(reset_sync),
        .imu_i2c_scl(imu_i2c_scl),.imu_i2c_sda(imu_i2c_sda),.ready(imu_ready),.fault(imu_fault),
        .sample_valid(sample_valid),.sample_stale(sample_stale),.temperature_valid(imu_temp_valid),
        .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),.temperature_raw(),
        .sample_seq(imu_seq),.timestamp_us(),.commit_timestamp_us(commit_us),.sample_age_us(imu_age),.now_us(imu_now),
        .observe_to_commit_us(),.sample_interval_us(),.error_count(imu_errors),.invalid_count(imu_invalids),.who_am_i(imu_who),.last_error(imu_error));
    wire [383:0] imu_diag_frame;wire imu_diag_valid;
    bb_imu_diagnostics #(.CLK_HZ(CLK_HZ)) diagnostics(.clk(clk50m),.reset_n(reset_sync),.scl(imu_i2c_scl),.sda(imu_i2c_sda),
        .ready(imu_ready),.fault(imu_fault),.stale(sample_stale),.temperature_valid(imu_temp_valid),.who_am_i(imu_who),.last_error(imu_error),
        .sample_seq(imu_seq),.sample_age_us(imu_age),.now_us(imu_now),.commit_us(commit_us),.error_count(imu_errors),.invalid_count(imu_invalids),
        .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),.frame(imu_diag_frame),.valid(imu_diag_valid));
    wire imu_healthy=imu_ready && !imu_fault && !sample_stale;
    wire zero_start,attitude_valid,calibrated,calibrating,bad_sample;
    wire signed [31:0] pitch,rate;
    wire [15:0] interval_us;
    wire [3:0] filter_shift;
    balance_attitude attitude(.clk(clk50m),.rst_n(reset_sync),.sample_valid(sample_valid),.zero_start(zero_start),
        .invalidate(!imu_ready || imu_fault),.filter_shift(filter_shift),.ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),
        .commit_us(commit_us),.valid(attitude_valid),.calibrated(calibrated),.calibrating(calibrating),.bad_sample(bad_sample),
        .pitch(pitch),.rate(rate),.interval_us(interval_us),.zero_progress());
    wire armed,config_valid;
    wire [7:0] mode,last_sequence,config_sequence,stop_reason;
    wire [15:0] faults,rejected;
    wire signed [31:0] left_position,right_position,left_velocity,right_velocity,speed_trim;
    wire signed [15:0] left_applied,right_applied;
    wire [31:0] left_invalid,right_invalid;
    bb_core #(.CLK_HZ(CLK_HZ),.DRIVE_ENABLE(DRIVE_ENABLE),.CPR_LEFT(CPR_LEFT),.CPR_RIGHT(CPR_RIGHT)) core(
        .clk(clk50m),.reset_n(reset_sync),.left_enc_a(left_enc_a),.left_enc_b(left_enc_b),.right_enc_a(right_enc_a),.right_enc_b(right_enc_b),
        .command_valid(command_valid),.opcode(opcode),.sequence_id(sequence_id),.payload(payload),
        .imu_healthy(imu_healthy),.attitude_valid(attitude_valid),.attitude_calibrated(calibrated),.attitude_calibrating(calibrating),
        .pitch(pitch),.rate(rate),.zero_start(zero_start),.filter_shift(filter_shift),.left_in1(left_in1),.left_in2(left_in2),
        .right_in1(right_in1),.right_in2(right_in2),.armed(armed),.config_valid(config_valid),.mode(mode),.last_sequence(last_sequence),
        .config_sequence(config_sequence),.stop_reason(stop_reason),.faults(faults),.rejected(rejected),
        .left_position(left_position),.right_position(right_position),.left_velocity(left_velocity),.right_velocity(right_velocity),
        .speed_trim(speed_trim),.left_applied(left_applied),.right_applied(right_applied),.left_invalid(left_invalid),.right_invalid(right_invalid));
    bb_telemetry #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.DRIVE_ENABLE(DRIVE_ENABLE),.CPR_LEFT(CPR_LEFT),.CPR_RIGHT(CPR_RIGHT),.M2_HEADER(1)) telemetry(
        .clk(clk50m),.reset_n(reset_sync),.armed(armed),.config_valid(config_valid),.calibrated(calibrated),.calibrating(calibrating),
        .imu_healthy(imu_healthy),.mode(mode),.last_sequence(last_sequence),.config_sequence(config_sequence),.stop_reason(stop_reason),
        .faults(faults),.rejected(rejected),.interval_us(interval_us),.bad_frames(bad_frames),.pitch(pitch),.rate(rate),
        .left_position(left_position),.right_position(right_position),.left_velocity(left_velocity),.right_velocity(right_velocity),
        .speed_trim(speed_trim),.left_applied(left_applied),.right_applied(right_applied),.left_invalid(left_invalid),.right_invalid(right_invalid),
        .imu_diag_frame(imu_diag_frame),.imu_diag_valid(imu_diag_valid),.tx(uart_tx));
    // All eight former M2 outputs now belong to the brushed motor/encoder ports.
    // Do not retain output aliases on encoder pins. Only old M1 is grounded.
    assign legacy_m1_disable=0,legacy_m1_pwm_disabled=0,legacy_m1_cal_disabled=0;
    assign led={faults[3:0],imu_healthy,calibrated,armed,reset_sync};
endmodule
