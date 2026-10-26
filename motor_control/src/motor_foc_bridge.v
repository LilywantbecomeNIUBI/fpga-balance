// Thin binding to the REAL Gowin FOC Light IP, configured as two-current input.
// Q15 currents/references; Q12 PI gains; signed normalized voltage limits.
module motor_foc_bridge #(parameter SEPARATE_Q_LIMIT=0)(
    input wire clk, rst_n, feedback_valid, enable,
    input wire [15:0] theta,
    input wire signed [15:0] ia, ib, id_ref, iq_ref,
    input wire [15:0] kp, ki, kaw, voltage_limit, current_limit,
    output wire head_sync, peak_sync,
    output wire [5:0] pwm,
    output wire park_valid,pi_valid,
    output wire signed [15:0] park_id,park_iq,pi_ud,pi_uq,
    input wire [15:0] q_voltage_limit
);
    wire signed [15:0] vmin=-$signed(voltage_limit);
    wire [15:0] qmax=SEPARATE_Q_LIMIT ? q_voltage_limit : voltage_limit;
    wire signed [15:0] qmin=-$signed(qmax);
    wire signed [15:0] imin=-$signed(current_limit);
    wire signed [15:0] id_limited=id_ref>$signed(current_limit) ? current_limit :
                                 id_ref<imin ? imin : id_ref;
    wire signed [15:0] iq_limited=iq_ref>$signed(current_limit) ? current_limit :
                                 iq_ref<imin ? imin : iq_ref;
    motor_gowin_foc_light ip(
        .clk(clk),.rstn(rst_n),.ce(1'b1),
        .in_feedback_valid(feedback_valid),.in_theta(theta),.in_adc_Ia(ia),.in_adc_Ib(ib),
        .in_pid_init(!enable),
        .in_Id_ref(enable ? id_limited : 16'sd0),.in_Iq_ref(enable ? iq_limited : 16'sd0),
        .in_Id_kp(kp),.in_Id_ki(ki),.in_Id_kaw(kaw),.in_Id_min(vmin),.in_Id_max(voltage_limit),
        .in_Iq_kp(kp),.in_Iq_ki(ki),.in_Iq_kaw(kaw),.in_Iq_min(qmin),.in_Iq_max(qmax),
        .in_pwm_enable(enable),.out_pwm_head_sync(head_sync),.out_pwm_peak_sync(peak_sync),.out_pwm_tail_sync(),
        .out_pt_I_valid(park_valid),.out_pt_Id(park_id),.out_pt_Iq(park_iq),
        .out_pi_valid(pi_valid),.out_pi_Ud(pi_ud),.out_pi_Uq(pi_uq),
        .out_pwm_a_p(pwm[0]),.out_pwm_a_n(pwm[1]),
        .out_pwm_b_p(pwm[2]),.out_pwm_b_n(pwm[3]),
        .out_pwm_c_p(pwm[4]),.out_pwm_c_n(pwm[5]));
endmodule
