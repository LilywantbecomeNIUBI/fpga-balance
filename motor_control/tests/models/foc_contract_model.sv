// TEST ONLY: validates wiring/handshakes, NEVER the FOC algorithm or deadtime.
// The synthesis project uses the real encrypted Gowin implementation instead.
module motor_gowin_foc_light(
    input wire clk,rstn,ce,in_feedback_valid,
    input wire [15:0] in_theta,
    input wire signed [15:0] in_adc_Ia,in_adc_Ib,
    input wire in_pid_init,
    input wire signed [15:0] in_Id_ref,in_Iq_ref,
    input wire [15:0] in_Id_kp,in_Id_ki,in_Id_kaw,
    input wire signed [15:0] in_Id_min,in_Id_max,
    input wire [15:0] in_Iq_kp,in_Iq_ki,in_Iq_kaw,
    input wire signed [15:0] in_Iq_min,in_Iq_max,
    input wire in_pwm_enable,
    output wire out_pwm_head_sync,out_pwm_peak_sync,out_pwm_tail_sync,
    output wire out_pwm_a_p,out_pwm_a_n,out_pwm_b_p,out_pwm_b_n,out_pwm_c_p,out_pwm_c_n,
    output reg out_pt_I_valid,out_pi_valid,
    output reg signed [15:0] out_pt_Id,out_pt_Iq,out_pi_Ud,out_pi_Uq
);
    reg [11:0] count;
    always @(posedge clk or negedge rstn)
        if(!rstn) count<=0;
        else if(ce) count<=count==2499 ? 0 : count+1;
    assign out_pwm_head_sync=count==0;
    assign out_pwm_peak_sync=count==1250;
    assign out_pwm_tail_sync=count==2499;
    assign {out_pwm_c_n,out_pwm_c_p,out_pwm_b_n,out_pwm_b_p,out_pwm_a_n,out_pwm_a_p}=
           in_pwm_enable ? 6'b010101 : 6'b000000;
    // Contract-only debug latency: NOT a numerical Park/PI model.
    reg debug_pending;
    always @(posedge clk or negedge rstn)
        if(!rstn) begin
            out_pt_I_valid<=0;out_pi_valid<=0;debug_pending<=0;
            out_pt_Id<=0;out_pt_Iq<=0;out_pi_Ud<=0;out_pi_Uq<=0;
        end else begin
            out_pt_I_valid<=in_feedback_valid;debug_pending<=in_feedback_valid;
            out_pi_valid<=debug_pending;
            if(in_feedback_valid) begin out_pt_Id<=in_adc_Ia;out_pt_Iq<=in_adc_Ib;end
            if(debug_pending) begin out_pi_Ud<=in_Id_ref;out_pi_Uq<=in_Iq_ref;end
        end
endmodule
