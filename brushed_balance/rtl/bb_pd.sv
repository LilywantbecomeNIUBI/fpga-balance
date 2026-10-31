// pitch/rate/target: signed Q16 degrees and degrees/s.
// kp/kd: unsigned Q8 PWM-per-mille per degree (or degree/s).
// Positive lean/rate produces positive common wheel demand (forward convention).
module bb_pd(
    input wire clk,reset_n,enable,reverse,
    input wire signed [31:0] pitch,rate,target,
    input wire [15:0] kp,kd,pwm_limit,
    output reg signed [15:0] demand
);
    reg signed [32:0] error_q,rate_q;
    reg signed [63:0] p,d,sum;
    reg signed [31:0] raw;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin error_q<=0;rate_q<=0;p<=0;d<=0;sum<=0;raw<=0;demand<=0;end
        else if(!enable)begin error_q<=0;rate_q<=0;p<=0;d<=0;sum<=0;raw<=0;demand<=0;end
        else begin
            error_q<=$signed(pitch)-$signed(target);rate_q<=rate;
            p<=error_q*$signed({1'b0,kp});d<=rate_q*$signed({1'b0,kd});
            sum<=p+d;raw<=reverse ? -(sum>>>24) : sum>>>24;
            demand<=raw>$signed({1'b0,pwm_limit}) ? $signed(pwm_limit) :
                raw< -$signed({1'b0,pwm_limit}) ? -$signed(pwm_limit) : raw[15:0];
        end
    end
endmodule
