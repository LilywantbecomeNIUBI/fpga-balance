// Carrier_Hall_RevB subsystem. Integrator supplies synchronous host controls.
// This is NOT a board top: host controls must never be auto-assigned to pins.
// IP configuration and this module assume a 50 MHz system clock, 20 kHz PWM.
module motor_adapter_core #(
    parameter SIMPLE_PROTECTION=0, CAL_LOG2=10, ADC_HALF_CYCLES=5, ENC_HALF_CYCLES=25,
              WAKE_CYCLES=50000, FRAME_TIMEOUT=2200, STALE_CYCLES=5000,
              MOTOR_MASK=2'b11, CURRENT_CB_MASK=2'b00, MEASUREMENT_COMP=0, CURRENT_LAG=0, ENCODER_LAG=0,
              SPEED_GUARD=0, MAX_WINDOW_TICKS=32, ALLOW_ALIGNMENT=0,SEPARATE_Q_LIMIT=0,
              CURRENT_AVERAGE=1,M2_PWM_ORDER=0,DYNAMIC_M2_PWM=0,CURRENT_SWAP_MASK=2'b00,DYNAMIC_M2_CURRENT=0
)(
    input wire clk, rst_n,
    input wire arm, clear_fault, calibrate, estop, config_valid,
    input wire [7:0] pole_pairs_1, pole_pairs_2,
    input wire [13:0] zero_1, zero_2,
    input wire [1:0] angle_reverse,
    input wire [3:0] current_reverse,
    input wire [95:0] current_gain_q16,
    input wire [15:0] current_trip_q15, voltage_limit,
    input wire [15:0] kp, ki, kaw,
    input wire signed [15:0] id_ref_1, iq_ref_1, id_ref_2, iq_ref_2,
    input wire alignment_mode,
    input wire [15:0] alignment_theta,
    input wire [1:0] drv_fault_n,
    input wire adc_busy, adc_dout_a, adc_dout_b, enc1_do, enc2_do,
    output wire adc_convst, adc_reset, adc_cs_n, adc_sclk,
    output wire enc1_cs_n, enc1_clk, enc2_cs_n, enc2_clk,
    output wire [11:0] pwm,
    output wire [1:0] drv_en, drv_cal,
    output wire running, calibrated, calibrating,
    output wire [7:0] faults,
    output wire feedback_valid,
    output wire [95:0] phase_currents,
    output wire [63:0] zero_offsets,
    output reg [127:0] raw_frame,
    output reg [31:0] frame_time,
    output reg [31:0] frame_sequence,
    output wire [15:0] theta_1, theta_2,
    output wire [27:0] mechanical_angles,
    output wire [1:0] measurement_faults,
    output wire [255:0] diagnostic_m1_sample,
    input wire [15:0] q_voltage_limit,
    input wire [2:0] m2_pwm_order,
    input wire m2_current_swap
);
    // Clear is permitted only while disarmed; it reinitializes acquisition and
    // zero calibration. Request a NEW calibration and NEW arm edge afterwards.
    wire data_rst_n=rst_n && !(clear_fault && !arm);
    wire adc_ready, adc_active, adc_valid, adc_fault, sample_started;
    wire enc1_busy, enc2_busy, enc1_valid, enc2_valid, enc1_fault, enc2_fault;
    wire [13:0] angle1,angle2;
    wire [3:0] status1,status2;
    wire [127:0] adc_channels;
    wire [31:0] adc_time;
    wire [31:0] encoder_time1,encoder_time2;
    wire head1,head2,peak1,peak2;
    wire [11:0] raw_pwm;
    wire [5:0] m2_ip_pwm;
    wire [2:0] active_pwm_order=DYNAMIC_M2_PWM ? m2_pwm_order : 3'(M2_PWM_ORDER);
    wire requested_current_swap=DYNAMIC_M2_CURRENT ? m2_current_swap : 1'b0;
    wire pwm_order_valid;
    // Freeze the route while armed. A caller changing the requested order
    // trips the existing config-change interlock instead of switching gates.
    motor_pwm_permutation pwm_map(.pwm_in(m2_ip_pwm),.order(DYNAMIC_M2_PWM ? disarmed_config[245:243] : 3'(M2_PWM_ORDER)),.pwm_out(raw_pwm[11:6]),.valid(pwm_order_valid));
    wire current_valid, overcurrent;
    reg transaction, join_valid;
    reg [2:0] received;
    reg [31:0] transaction_age, stale_age;
    reg [13:0] captured_angle1,captured_angle2;
    reg sensor_fault, sync_fault, last_calibrate, fresh;
    reg sample_trigger;
    wire selected_encoder_fault=(MOTOR_MASK[0] && enc1_fault) || (MOTOR_MASK[1] && enc2_fault);
    // One shared synchronization event starts both ADC groups simultaneously.
    // SSI starts one clk after the physical CONVST rising edge.
    always @(posedge clk or negedge data_rst_n)
        if(!data_rst_n) sample_trigger<=0;
        else sample_trigger<=peak1 && adc_ready;
    motor_ad7606 #(.HALF_CYCLES(ADC_HALF_CYCLES)) adc(
        .clk(clk),.rst_n(data_rst_n),.trigger(sample_trigger),
        .adc_busy(adc_busy),.dout_a(adc_dout_a),.dout_b(adc_dout_b),
        .convst(adc_convst),.adc_reset(adc_reset),.cs_n(adc_cs_n),.sclk(adc_sclk),
        .busy(adc_active),.ready(adc_ready),.sample_started(sample_started),
        .valid(adc_valid),.fault(adc_fault),.channels(adc_channels),.sample_time(adc_time));
    motor_mt6701 #(.HALF_CYCLES(ENC_HALF_CYCLES)) encoder1(
        .clk(clk),.rst_n(data_rst_n),.trigger(sample_started),.din(enc1_do),
        .cs_n(enc1_cs_n),.sclk(enc1_clk),.busy(enc1_busy),.valid(enc1_valid),
        .fault(enc1_fault),.angle(angle1),.status(status1),.sample_time(encoder_time1));
    motor_mt6701 #(.HALF_CYCLES(ENC_HALF_CYCLES)) encoder2(
        .clk(clk),.rst_n(data_rst_n),.trigger(sample_started),.din(enc2_do),
        .cs_n(enc2_cs_n),.sclk(enc2_clk),.busy(enc2_busy),.valid(enc2_valid),
        .fault(enc2_fault),.angle(angle2),.status(status2),.sample_time(encoder_time2));
    always @(posedge clk or negedge data_rst_n) begin
        if(!data_rst_n) begin
            transaction<=0; received<=0; transaction_age<=0; stale_age<=0;
            captured_angle1<=0; captured_angle2<=0; raw_frame<=0;
            frame_time<=0; frame_sequence<=0; join_valid<=0;
            sensor_fault<=0; sync_fault<=0; fresh<=0;
        end else begin
            join_valid<=0;
            if(head1!=head2 || peak1!=peak2) sync_fault<=1;
            if(adc_fault || selected_encoder_fault) sensor_fault<=1;
            if(adc_ready && stale_age<STALE_CYCLES) stale_age<=stale_age+1;
            if(adc_ready && stale_age==STALE_CYCLES) begin sensor_fault<=1; fresh<=0; end
            if(sample_started) begin
                if(transaction) sensor_fault<=1;
                else begin
                    transaction<=1;received<={!MOTOR_MASK[1],!MOTOR_MASK[0],1'b0};transaction_age<=0;
                end
            end else if(transaction) begin
                transaction_age<=transaction_age+1;
                if(transaction_age==FRAME_TIMEOUT-1) begin sensor_fault<=1; transaction<=0; end
                if(adc_valid) begin raw_frame<=adc_channels; frame_time<=adc_time; received[0]<=1; end
                if(enc1_valid && MOTOR_MASK[0]) begin captured_angle1<=angle1; received[1]<=1; end
                if(enc2_valid && MOTOR_MASK[1]) begin captured_angle2<=angle2; received[2]<=1; end
                if(&received) begin
                    transaction<=0;
                    if(SIMPLE_PROTECTION || (!sensor_fault && !adc_fault && !selected_encoder_fault)) begin
                        join_valid<=1; frame_sequence<=frame_sequence+1;
                        stale_age<=0; fresh<=1;
                    end
                end
            end else if(adc_valid || (enc1_valid && MOTOR_MASK[0]) || (enc2_valid && MOTOR_MASK[1])) sensor_fault<=1;
        end
    end
    always @(posedge clk or negedge data_rst_n)
        if(!data_rst_n) last_calibrate<=0;
        else last_calibrate<=calibrate;
    // Register the accepted disarmed calibration request. This keeps the long
    // arm-deadline comparator out of the current arithmetic D-input cone.
    // No enable/kill guard is delayed; only zero-calibration starts one cycle later.
    reg cal_start;
    always @(posedge clk or negedge data_rst_n)
        if(!data_rst_n)cal_start<=0;
        else cal_start<=calibrate && !last_calibrate && !arm && drv_en==0;
    wire [95:0] physical_phase_currents;
    motor_current #(.CAL_LOG2(CAL_LOG2),.MOTOR_MASK(MOTOR_MASK),.CURRENT_CB_MASK(CURRENT_CB_MASK),.CURRENT_SWAP_MASK(CURRENT_SWAP_MASK)) currents(
        .clk(clk),.rst_n(data_rst_n),.cal_start(cal_start),.frame_valid(join_valid),
        .raw(raw_frame[63:0]),.gain_q16(current_gain_q16),.reverse(current_reverse),
        .trip_q15(current_trip_q15),.calibrating(calibrating),.calibrated(calibrated),
        .valid(current_valid),.overcurrent(overcurrent),.currents(physical_phase_currents),.offsets(zero_offsets));
    // CB/BC changes only canonical B/C assignment. Raw per-channel and
    // reconstructed-A protection above remain independent of this selector.
    // The selector is frozen while armed just like the physical PWM route.
    assign phase_currents=(DYNAMIC_M2_CURRENT && disarmed_config[246]) ?
        {physical_phase_currents[79:64],physical_phase_currents[95:80],physical_phase_currents[63:0]} : physical_phase_currents;
    // Raw currents remain public. SIMPLE_PROTECTION bypasses software overcurrent stop. Only the FOC
    // feedback and its atomic trace use the optional inter-frame average.
    localparam AVERAGE_DELAY=(CURRENT_AVERAGE-1)*2500/2;
    wire [31:0] feedback_time=frame_time-AVERAGE_DELAY;
    wire [95:0] feedback_currents;
    wire averaged_valid;
    motor_current_average #(.TAPS(CURRENT_AVERAGE)) average(
        .clk(clk),.rst_n(data_rst_n),.clear(cal_start),.valid(current_valid),
        .currents(phase_currents),.filtered_valid(averaged_valid),.filtered_currents(feedback_currents));
    wire [13:0] aligned1,aligned2;
    wire speed_fault1,speed_fault2,timing_fault1,timing_fault2;
    wire aligned_valid1,aligned_valid2;
    reg frame_current_ready;
    always @(posedge clk or negedge data_rst_n)
        if(!data_rst_n) frame_current_ready<=0;
        else if(join_valid) frame_current_ready<=0;
        else if(averaged_valid) frame_current_ready<=1;
    motor_measurement_angle #(.CURRENT_LAG(CURRENT_LAG),.ENCODER_LAG(ENCODER_LAG),
        .CHECKS_ENABLED(!SIMPLE_PROTECTION),.MAX_STEP(SIMPLE_PROTECTION ? 512 : 64),.MAX_WINDOW_TICKS(MAX_WINDOW_TICKS)) align1(
        .clk(clk),.rst_n(data_rst_n),.valid(join_valid),.mechanical(captured_angle1),
        .current_time(feedback_time),.encoder_time(encoder_time1),.aligned(aligned1),
        .step(),.speed_fault(speed_fault1),.timing_fault(timing_fault1),.initialized(),.aligned_valid(aligned_valid1));
    motor_measurement_angle #(.CURRENT_LAG(CURRENT_LAG),.ENCODER_LAG(ENCODER_LAG),
        .CHECKS_ENABLED(!SIMPLE_PROTECTION),.MAX_STEP(SIMPLE_PROTECTION ? 512 : 64),.MAX_WINDOW_TICKS(MAX_WINDOW_TICKS)) align2(
        .clk(clk),.rst_n(data_rst_n),.valid(join_valid),.mechanical(captured_angle2),
        .current_time(feedback_time),.encoder_time(encoder_time2),.aligned(aligned2),
        .step(),.speed_fault(speed_fault2),.timing_fault(timing_fault2),.initialized(),.aligned_valid(aligned_valid2));
    assign mechanical_angles={captured_angle2,captured_angle1};
    assign measurement_faults={MEASUREMENT_COMP && ((timing_fault1 && MOTOR_MASK[0]) || (timing_fault2 && MOTOR_MASK[1])),
        SPEED_GUARD && ((speed_fault1 && MOTOR_MASK[0]) || (speed_fault2 && MOTOR_MASK[1]))};
    motor_angle a1(.mechanical(MEASUREMENT_COMP ? aligned1 : captured_angle1),.zero(zero_1),.pole_pairs(pole_pairs_1),
                   .reverse(angle_reverse[0]),.electrical(theta_1));
    motor_angle a2(.mechanical(MEASUREMENT_COMP ? aligned2 : captured_angle2),.zero(zero_2),.pole_pairs(pole_pairs_2),
                   .reverse(angle_reverse[1]),.electrical(theta_2));
    wire config_ok=config_valid && pwm_order_valid && active_pwm_order<6 &&
        (!DYNAMIC_M2_CURRENT || (CURRENT_CB_MASK[1] && !CURRENT_SWAP_MASK[1])) && pole_pairs_1!=0 && pole_pairs_2!=0 &&
        current_trip_q15!=0 && current_trip_q15<=16'd32767 &&
        voltage_limit!=0 && voltage_limit<=16'd32767 &&
        (!SEPARATE_Q_LIMIT || (q_voltage_limit!=0 && q_voltage_limit<=16'd32767)) &&
        current_gain_q16[23:0]!=0 && !current_gain_q16[23] &&
        current_gain_q16[47:24]!=0 && !current_gain_q16[47] &&
        current_gain_q16[71:48]!=0 && !current_gain_q16[71] &&
        current_gain_q16[95:72]!=0 && !current_gain_q16[95];
    wire [15:0] effective_q_limit=SEPARATE_Q_LIMIT ? q_voltage_limit : voltage_limit;
    wire [246:0] config_bus={requested_current_swap,active_pwm_order,config_valid,pole_pairs_1,pole_pairs_2,zero_1,zero_2,
        angle_reverse,current_reverse,current_gain_q16,current_trip_q15,voltage_limit,kp,ki,kaw,effective_q_limit};
    reg [246:0] disarmed_config;
    always @(posedge clk or negedge data_rst_n)
        if(!data_rst_n) disarmed_config<=0;
        else if(!arm) disarmed_config<=config_bus;
    wire config_changed=arm && config_bus!=disarmed_config;
    wire ready=calibrated && !calibrating && config_ok && (SIMPLE_PROTECTION || (fresh && !config_changed && !sensor_fault && !sync_fault && !(|measurement_faults)));
    assign feedback_valid=(MEASUREMENT_COMP ? (!MOTOR_MASK[0] || aligned_valid1) && (!MOTOR_MASK[1] || aligned_valid2) && frame_current_ready : averaged_valid)
        && (SIMPLE_PROTECTION || !overcurrent) && ready && faults==0;
    // CAL belongs to the unused low-side CSA. Hall zeroing must NOT toggle it.
    assign drv_cal=2'b00;
    wire [15:0] foc_theta_1=ALLOW_ALIGNMENT && alignment_mode ? alignment_theta : theta_1;
    wire [15:0] foc_theta_2=ALLOW_ALIGNMENT && alignment_mode ? alignment_theta : theta_2;
    wire trace_m2=MOTOR_MASK==2'b10;
    wire park_valid_1,pi_valid_1;
    wire park_valid_2,pi_valid_2;
    wire signed [15:0] park_id_1,park_iq_1,pi_ud_1,pi_uq_1;
    wire signed [15:0] park_id_2,park_iq_2,pi_ud_2,pi_uq_2;
    // Preserve the legacy port/packet layout. In a M2-only image its coherent
    // diagnostic sample comes entirely from M2, including the actual IP data.
    motor_foc_trace trace1(.clk(clk),.rst_n(data_rst_n),.valid(feedback_valid),
        .running(running),.alignment(ALLOW_ALIGNMENT && alignment_mode),
        .sequence_number(frame_sequence),.sample_time(feedback_time),.mechanical(trace_m2 ? captured_angle2 : captured_angle1),
        .theta(trace_m2 ? foc_theta_2 : foc_theta_1),.current_limit(current_trip_q15),.currents(trace_m2 ? feedback_currents[95:48] : feedback_currents[47:0]),
        .id_ref(trace_m2 ? id_ref_2 : id_ref_1),.iq_ref(trace_m2 ? iq_ref_2 : iq_ref_1),.park_valid(trace_m2 ? park_valid_2 : park_valid_1),.pi_valid(trace_m2 ? pi_valid_2 : pi_valid_1),
        .park_id(trace_m2 ? park_id_2 : park_id_1),.park_iq(trace_m2 ? park_iq_2 : park_iq_1),.pi_ud(trace_m2 ? pi_ud_2 : pi_ud_1),.pi_uq(trace_m2 ? pi_uq_2 : pi_uq_1),.sample(diagnostic_m1_sample));
    motor_foc_bridge #(.SEPARATE_Q_LIMIT(SEPARATE_Q_LIMIT)) foc1(.clk(clk),.rst_n(data_rst_n),.feedback_valid(feedback_valid),
        .enable(running),.theta(foc_theta_1),.ia(feedback_currents[15:0]),.ib(feedback_currents[31:16]),
        .q_voltage_limit(effective_q_limit),.id_ref(id_ref_1),.iq_ref(iq_ref_1),.kp(kp),.ki(ki),.kaw(kaw),.voltage_limit(voltage_limit),.current_limit(current_trip_q15),
        .head_sync(head1),.peak_sync(peak1),.pwm(raw_pwm[5:0]),
        .park_valid(park_valid_1),.pi_valid(pi_valid_1),.park_id(park_id_1),.park_iq(park_iq_1),.pi_ud(pi_ud_1),.pi_uq(pi_uq_1));
    motor_foc_bridge #(.SEPARATE_Q_LIMIT(SEPARATE_Q_LIMIT)) foc2(.clk(clk),.rst_n(data_rst_n),.feedback_valid(feedback_valid),
        .enable(running),.theta(foc_theta_2),.ia(feedback_currents[63:48]),.ib(feedback_currents[79:64]),
        .q_voltage_limit(effective_q_limit),.id_ref(id_ref_2),.iq_ref(iq_ref_2),.kp(kp),.ki(ki),.kaw(kaw),.voltage_limit(voltage_limit),.current_limit(current_trip_q15),
        .head_sync(head2),.peak_sync(peak2),.pwm(m2_ip_pwm),
        .park_valid(park_valid_2),.pi_valid(pi_valid_2),.park_id(park_id_2),.park_iq(park_iq_2),.pi_ud(pi_ud_2),.pi_uq(pi_uq_2));
    motor_drv_guard #(.SIMPLE_PROTECTION(SIMPLE_PROTECTION),.WAKE_CYCLES(WAKE_CYCLES),.MOTOR_MASK(MOTOR_MASK)) guard(
        .clk(clk),.rst_n(rst_n),.arm(arm),.clear_fault(clear_fault),.ready(ready),
        .estop(estop),.fault_n(drv_fault_n),.sensor_fault(sensor_fault || (|measurement_faults)),
        .overcurrent(overcurrent),.sync_fault(sync_fault),.pwm_in(raw_pwm),
        .pwm_out(pwm),.drv_en(drv_en),.running(running),.faults(faults));
endmodule
