// Stable team boundary: only torque-current commands and lifecycle controls.
// Plant calibration, PI, hard phase trip and modulation ceiling are build-time
// constants; they are deliberately absent from the teammate's command bus.
module motor_safe_drive #(
    parameter CONFIG_CONFIRMED=0, MOTOR_MASK=2'b01, ALLOW_CURRENT_TUNING=0,DUAL_IQ_CONTROL=0,SELECTABLE_COMMISSION=0,PRESERVE_CAL_ON_CLEAR=0,TUNING_KI_MAX=16,TUNING_KP_MAX=8192,
              POLE_PAIRS_1=11,POLE_PAIRS_2=11,
              CURRENT_REVERSE=0,CURRENT_CB_MASK=2'b00,CURRENT_SWAP_MASK=2'b00,
              GAIN_Q16=221405, PHASE_TRIP=2048, IQ_LIMIT=1024,
              GAIN_CH1_Q16=GAIN_Q16,GAIN_CH2_Q16=GAIN_Q16,
              GAIN_CH3_Q16=GAIN_Q16,GAIN_CH4_Q16=GAIN_Q16,
              VOLTAGE_LIMIT=4096, KP=256,KI=1,KAW=1,
              CURRENT_LAG=0,ENCODER_LAG=0,MAX_WINDOW_TICKS=32,
              CAL_LOG2=10,WAKE_CYCLES=50000,CURRENT_AVERAGE=1,COMMAND_SLEW=4,
              COMM_SETTLE=10000,COMM_PREALIGN=0,COMM_SWEEP=20000,COMM_END=6000,COMM_QUIET=2000,COMM_HANDOFF=50000,
              COMM_PULSE_ONLY=0,COMM_MAX_RUN_CYCLES=120000000,COMM_PROBE_SWITCH_CYCLES=0,
              M2_PWM_ORDER=0,DYNAMIC_M2_PWM=0,DYNAMIC_M2_CURRENT=0,
              CMD_TIMEOUT=5000000,MAX_RUN_CYCLES=250000000
)(
    input wire clk,rst_n,request_arm,clear_fault,calibrate,estop,command_valid,commission_start,
    input wire [1:0] commission_select,
    input wire signed [15:0] iq_request_1,iq_request_2,
    input wire [1:0] drv_fault_n,
    input wire adc_busy,adc_dout_a,adc_dout_b,enc1_do,enc2_do,
    output wire adc_convst,adc_reset,adc_cs_n,adc_sclk,
    output wire enc1_cs_n,enc1_clk,enc2_cs_n,enc2_clk,
    output wire [11:0] pwm,
    output wire [1:0] drv_en,drv_cal,
    output wire running,calibrated,calibrating,feedback_valid,
    output wire [11:0] faults,
    output wire [95:0] phase_currents,
    output wire [27:0] mechanical_angles,
    output wire [31:0] frame_sequence,
    output wire commissioned,commissioning,commission_failed,
    output wire [1:0] commissioned_mask,
    output wire [3:0] commission_state,
    output wire [1:0] learned_reverse,
    output wire [27:0] learned_zero,
    output wire [255:0] diagnostic_m1_sample,
    output wire [127:0] raw_adc_frame,
    output wire [63:0] current_zero_offsets,
    input wire [15:0] tuning_kp,tuning_ki,
    input wire [2:0] m2_pwm_order,
    input wire m2_current_swap
);
    wire limited_arm;
    wire signed [15:0] iq1,iq2;
    wire [1:0] command_faults,measurement_faults;
    wire [7:0] core_faults;
    wire [1:0] comm_busy,comm_arm,comm_done,comm_failed,comm_reverse;
    wire [13:0] comm_zero1,comm_zero2;
    wire [15:0] comm_theta1,comm_theta2;
    wire [3:0] comm_state1,comm_state2;
    reg commission_request_pending;
    assign learned_reverse=comm_reverse;
    assign learned_zero={comm_zero2,comm_zero1};
    // Unselected commissioning FSMs must not enter the active drive cone.
    // This also removes the absent M2 state-to-EN path in M1-only builds.
    assign commissioning=|(comm_busy & MOTOR_MASK) || (SELECTABLE_COMMISSION && commission_request_pending);
    assign commissioned=&(comm_done | ~MOTOR_MASK);
    assign commissioned_mask=comm_done & MOTOR_MASK;
    assign commission_failed=|(comm_failed & MOTOR_MASK);
    // Explicit selection never starts the other axis as a prerequisite.
    // Legacy standalone instantiations retain sequential commissioning.
    wire selected_m1=commission_select==2'b01 && MOTOR_MASK[0] && (PRESERVE_CAL_ON_CLEAR || !comm_done[0]);
    wire selected_m2=commission_select==2'b10 && MOTOR_MASK[1] && (PRESERVE_CAL_ON_CLEAR || !comm_done[1]);
    wire explicit_start=commission_start && !commissioning && !request_arm && !running &&
                        !commission_failed && (selected_m1 || selected_m2);
    wire start_m1=SELECTABLE_COMMISSION ? explicit_start && selected_m1 : commission_start && (PRESERVE_CAL_ON_CLEAR || !comm_done[0]);
    wire start_m2=SELECTABLE_COMMISSION ? explicit_start && selected_m2 : commission_start && (comm_done[0] || !MOTOR_MASK[0]);
    // Reserve the chosen axis until its first feedback frame arrives. A second
    // request in that gap must never queue the other commissioning FSM.
    always @(posedge clk or negedge rst_n)
        if(!rst_n)commission_request_pending<=0;
        else if(clear_fault || estop || (|faults))commission_request_pending<=0;
        else if(SELECTABLE_COMMISSION && explicit_start)commission_request_pending<=1;
        else if(|comm_busy)commission_request_pending<=0;
    reg last_commission_m2;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)last_commission_m2<=0;
        else if(clear_fault && !lifecycle_arm)last_commission_m2<=0;
        else if(explicit_start)last_commission_m2<=selected_m2;
    assign commission_state=(SELECTABLE_COMMISSION ? last_commission_m2 :
                            (MOTOR_MASK==2'b10 || (comm_busy[1] && MOTOR_MASK[1]))) ? comm_state2 : comm_state1;
    wire commission_arm=|(comm_arm & MOTOR_MASK);
    wire [15:0] commission_theta=comm_busy[1] && MOTOR_MASK[1] ? comm_theta2 : comm_theta1;
    wire [1:0] active_mask=commissioning ? comm_busy & MOTOR_MASK : MOTOR_MASK;
    wire [11:0] core_pwm;
    wire [1:0] core_en;
    assign pwm=core_pwm & {{6{active_mask[1]}},{6{active_mask[0]}}};
    assign drv_en=core_en & active_mask;
    // Each FSM lowers its arm before leaving busy. Feed that registered arm
    // directly; only the separate runtime branch needs the busy interlock.
    // This removes a redundant state-decode mux from the fast output path.
    wire lifecycle_arm=commission_arm || (request_arm && commissioned && !commissioning);
    // Select fixed commissioning gains before any commission arm edge. Keep
    // them selected while motor_commission waits for its first feedback frame.
    // Restore runtime gains during the disarmed OFF/HANDOFF window, before
    // commissioned becomes true and permits a new runtime arm request.
    reg commission_gain_mode;
    wire use_commission_gains=ALLOW_CURRENT_TUNING && (commission_start || commission_gain_mode);
    always @(posedge clk or negedge rst_n)
        if(!rst_n) commission_gain_mode<=0;
        else if(commission_start) commission_gain_mode<=1;
        else if((commissioning && !commission_arm && (commission_state==4 || commission_state==5)) ||
                (!commissioning && (commissioned || commission_failed || clear_fault))) commission_gain_mode<=0;
    wire [15:0] active_kp=use_commission_gains ? 16'd300 : held_kp;
    wire [15:0] active_ki=use_commission_gains ? 16'd16 : held_ki;
    // Dedicated tuning profile: extra Q voltage only during runtime, never
    // during the fixed-PI commissioning scan. Legacy/team profiles unchanged.
    wire [15:0] active_q_voltage_limit=ALLOW_CURRENT_TUNING && !use_commission_gains ? 16'd24576 : 16'(VOLTAGE_LIMIT);
    reg [15:0] held_kp,held_ki;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) begin held_kp<=256;held_ki<=4;end
        else if(!lifecycle_arm) begin
            // Independent FPGA envelope: callers cannot change live gains or
            // exceed these compile-time bounds even by bypassing the parser.
            held_kp<=tuning_kp>TUNING_KP_MAX ? 16'(TUNING_KP_MAX) : tuning_kp;
            held_ki<=tuning_ki>TUNING_KI_MAX ? 16'(TUNING_KI_MAX) : tuning_ki;
        end
    // Single-motor tuning uses guard lane 1 for Iq and lane 2 for Id.
    // Route that pair only to the selected physical motor, never to both.
    // Normal two-motor profiles retain their original torque command routing.
    wire signed [15:0] tuning_id_limited,tuning_iq_limited;
    motor_tuning_vector #(.LIMIT(IQ_LIMIT)) vector_limit(.id_in(iq2),.iq_in(iq1),
        .id_out(tuning_id_limited),.iq_out(tuning_iq_limited));
    reg clear_pending;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) clear_pending<=0;
        else clear_pending<=clear_fault && !lifecycle_arm;
    // Clear the command fault first, then keep core clear asserted for another
    // cycle so its asynchronous kill latch can release after estop deasserts.
    wire core_clear=(clear_fault && !lifecycle_arm) || clear_pending;
    assign faults={measurement_faults,command_faults,core_faults};
    motor_command_guard #(.IQ_LIMIT(IQ_LIMIT),.CMD_TIMEOUT(CMD_TIMEOUT),.SLEW_PER_FRAME(COMMAND_SLEW),
        .MAX_RUN_CYCLES(MAX_RUN_CYCLES)) commands(
        .clk(clk),.rst_n(rst_n),.request_arm(lifecycle_arm),.clear_fault(clear_fault),
        .command_valid(command_valid || commission_start),.frame_valid(feedback_valid),
        .iq_request_1(commissioning || commission_start ? 16'sd1024 : iq_request_1),
        .iq_request_2(commissioning || commission_start ? 16'sd1024 : iq_request_2),
        .arm(limited_arm),.iq_1(iq1),.iq_2(iq2),.faults(command_faults));
    motor_commission #(.POLE_PAIRS(POLE_PAIRS_1),.SETTLE_FRAMES(COMM_SETTLE),.PREALIGN_FRAMES(COMM_PREALIGN),.SWEEP_FRAMES(COMM_SWEEP),
        .END_FRAMES(COMM_END),.QUIET_FRAMES(COMM_QUIET),.HANDOFF_CYCLES(COMM_HANDOFF),
        .PULSE_ONLY(COMM_PULSE_ONLY),.PROBE_SWITCH_CYCLES(COMM_PROBE_SWITCH_CYCLES),.MAX_RUN_CYCLES(COMM_MAX_RUN_CYCLES),
        .PRESERVE_CAL_ON_CLEAR(PRESERVE_CAL_ON_CLEAR)) commission1(
        .clk(clk),.rst_n(rst_n),.start(start_m1 && CONFIG_CONFIRMED && MOTOR_MASK[0] && (PRESERVE_CAL_ON_CLEAR || !comm_done[0])),
        .clear_fault(core_clear),.calibrated(calibrated),.feedback_valid(feedback_valid),.running(running),
        .mechanical(mechanical_angles[13:0]),.ia(phase_currents[15:0]),.ib(phase_currents[31:16]),.faults(faults),
        .busy(comm_busy[0]),.arm(comm_arm[0]),.done(comm_done[0]),.failed(comm_failed[0]),
        .reverse(comm_reverse[0]),.zero(comm_zero1),.theta(comm_theta1),.state(comm_state1));
    motor_commission #(.POLE_PAIRS(POLE_PAIRS_2),.SETTLE_FRAMES(COMM_SETTLE),.PREALIGN_FRAMES(COMM_PREALIGN),.SWEEP_FRAMES(COMM_SWEEP),
        .END_FRAMES(COMM_END),.QUIET_FRAMES(COMM_QUIET),.HANDOFF_CYCLES(COMM_HANDOFF),
        .PULSE_ONLY(COMM_PULSE_ONLY),.PROBE_SWITCH_CYCLES(COMM_PROBE_SWITCH_CYCLES),.MAX_RUN_CYCLES(COMM_MAX_RUN_CYCLES),
        .PRESERVE_CAL_ON_CLEAR(PRESERVE_CAL_ON_CLEAR)) commission2(
        .clk(clk),.rst_n(rst_n),.start(start_m2 && CONFIG_CONFIRMED && MOTOR_MASK[1] && (PRESERVE_CAL_ON_CLEAR || !comm_done[1])),
        .clear_fault(core_clear),.calibrated(calibrated),.feedback_valid(feedback_valid),.running(running),
        .mechanical(mechanical_angles[27:14]),.ia(phase_currents[63:48]),.ib(phase_currents[79:64]),.faults(faults),
        .busy(comm_busy[1]),.arm(comm_arm[1]),.done(comm_done[1]),.failed(comm_failed[1]),
        .reverse(comm_reverse[1]),.zero(comm_zero2),.theta(comm_theta2),.state(comm_state2));
    motor_adapter_core #(.MOTOR_MASK(MOTOR_MASK),.M2_PWM_ORDER(M2_PWM_ORDER),.DYNAMIC_M2_PWM(DYNAMIC_M2_PWM),.DYNAMIC_M2_CURRENT(DYNAMIC_M2_CURRENT),.SEPARATE_Q_LIMIT(ALLOW_CURRENT_TUNING),.CURRENT_CB_MASK(CURRENT_CB_MASK),.CURRENT_SWAP_MASK(CURRENT_SWAP_MASK),.MEASUREMENT_COMP(1),.ALLOW_ALIGNMENT(1),
        .SPEED_GUARD(1),.CURRENT_LAG(CURRENT_LAG),.ENCODER_LAG(ENCODER_LAG),
        .MAX_WINDOW_TICKS(MAX_WINDOW_TICKS),.CAL_LOG2(CAL_LOG2),.WAKE_CYCLES(WAKE_CYCLES),.CURRENT_AVERAGE(CURRENT_AVERAGE)) core(
        .clk(clk),.rst_n(rst_n),.arm(limited_arm),.clear_fault(core_clear),.m2_pwm_order(m2_pwm_order),.m2_current_swap(m2_current_swap),
        .calibrate(calibrate),.estop(estop || (|command_faults)),.config_valid(CONFIG_CONFIRMED!=0),
        .pole_pairs_1(8'(POLE_PAIRS_1)),.pole_pairs_2(8'(POLE_PAIRS_2)),
        .zero_1(comm_zero1),.zero_2(comm_zero2),.angle_reverse(comm_reverse),
        .current_reverse(4'(CURRENT_REVERSE)),
        .current_gain_q16({24'(GAIN_CH4_Q16),24'(GAIN_CH3_Q16),24'(GAIN_CH2_Q16),24'(GAIN_CH1_Q16)}),
        .current_trip_q15(16'(PHASE_TRIP)),.voltage_limit(16'(VOLTAGE_LIMIT)),.q_voltage_limit(active_q_voltage_limit),
        .kp(ALLOW_CURRENT_TUNING ? active_kp : 16'(KP)),.ki(ALLOW_CURRENT_TUNING ? active_ki : 16'(KI)),.kaw(16'(KAW)),
        .alignment_mode(commissioning),.alignment_theta(commission_theta),
        .id_ref_1(comm_busy[0] ? iq1 : (ALLOW_CURRENT_TUNING && !DUAL_IQ_CONTROL && MOTOR_MASK[0] ? tuning_id_limited : 16'sd0)),
        .iq_ref_1(!commissioning && MOTOR_MASK[0] ? (ALLOW_CURRENT_TUNING && !DUAL_IQ_CONTROL ? tuning_iq_limited : iq1) : 16'sd0),
        .id_ref_2(comm_busy[1] ? iq2 : (ALLOW_CURRENT_TUNING && !DUAL_IQ_CONTROL && MOTOR_MASK==2'b10 ? tuning_id_limited : 16'sd0)),
        .iq_ref_2(!commissioning && MOTOR_MASK[1] ? (ALLOW_CURRENT_TUNING && !DUAL_IQ_CONTROL && MOTOR_MASK==2'b10 ? tuning_iq_limited : iq2) : 16'sd0),
        .drv_fault_n(drv_fault_n | ~active_mask),.adc_busy(adc_busy),.adc_dout_a(adc_dout_a),
        .adc_dout_b(adc_dout_b),.enc1_do(enc1_do),.enc2_do(enc2_do),
        .adc_convst(adc_convst),.adc_reset(adc_reset),.adc_cs_n(adc_cs_n),.adc_sclk(adc_sclk),
        .enc1_cs_n(enc1_cs_n),.enc1_clk(enc1_clk),.enc2_cs_n(enc2_cs_n),.enc2_clk(enc2_clk),
        .pwm(core_pwm),.drv_en(core_en),.drv_cal(drv_cal),.running(running),
        .calibrated(calibrated),.calibrating(calibrating),.faults(core_faults),
        .feedback_valid(feedback_valid),.phase_currents(phase_currents),
        .zero_offsets(current_zero_offsets),.raw_frame(raw_adc_frame),.frame_time(),.frame_sequence(frame_sequence),
        .theta_1(),.theta_2(),.mechanical_angles(mechanical_angles),.measurement_faults(measurement_faults),
        .diagnostic_m1_sample(diagnostic_m1_sample));
endmodule
