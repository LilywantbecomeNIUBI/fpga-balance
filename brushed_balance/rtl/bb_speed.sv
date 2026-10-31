// Outer loop, 50 Hz. kp and ki_tick are unsigned Q16 degree/rpm.
// ki_tick = Ki[degree/(rpm*s)] / 50. Output is signed Q16 degrees.
// CPR describes the output shaft AFTER AB x4; no additional gearing is applied.
module bb_speed #(parameter integer CPR_LEFT=60000,CPR_RIGHT=60000)(
    input wire clk,reset_n,tick,enable,
    input wire signed [31:0] left_velocity,right_velocity,
    input wire signed [15:0] target_rpm_q8,
    input wire [15:0] kp,ki_tick,limit_cdeg,
    output reg signed [31:0] trim_q16
);
    localparam signed [31:0] GAIN_L=(64'd393216000+CPR_LEFT/2)/CPR_LEFT;
    localparam signed [31:0] GAIN_R=(64'd393216000+CPR_RIGHT/2)/CPR_RIGHT;
    reg [3:0] state;
    reg signed [63:0] vl,vr,p,i;
    reg signed [31:0] rpm_l,rpm_r,error_q8,integral,cap,candidate,p_q16,raw;
    reg signed [15:0] target_q;
    reg [15:0] kp_q,ki_q;
    function automatic signed [31:0] clamp(input signed [31:0] value,input signed [31:0] bound);
        clamp=value>bound ? bound : value< -bound ? -bound : value;
    endfunction
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=0;vl<=0;vr<=0;p<=0;i<=0;rpm_l<=0;rpm_r<=0;error_q8<=0;
            integral<=0;cap<=0;candidate<=0;p_q16<=0;raw<=0;trim_q16<=0;
            target_q<=0;kp_q<=0;ki_q<=0;
        end else if(!enable)begin state<=0;integral<=0;trim_q16<=0;end
        else case(state)
            0:if(tick)begin
                vl<=left_velocity*GAIN_L;vr<=right_velocity*GAIN_R;
                target_q<=target_rpm_q8;kp_q<=kp;ki_q<=ki_tick;
                cap<=($signed({1'b0,limit_cdeg})*32'sd167772)>>>8;state<=1;
            end
            1:begin rpm_l<=vl>>>8;rpm_r<=vr>>>8;state<=2;end
            2:begin error_q8<=$signed(target_q)-(($signed(rpm_l)+$signed(rpm_r))>>>1);state<=3;end
            3:begin p<=error_q8*$signed({1'b0,kp_q});i<=error_q8*$signed({1'b0,ki_q});state<=4;end
            4:begin p_q16<=p>>>8;candidate<=clamp(integral+(i>>>8),cap);state<=5;end
            5:begin raw<=p_q16+candidate;state<=6;end
            6:begin
                trim_q16<=clamp(raw,cap);
                if((raw<=cap && raw>=-cap)||(raw>cap && error_q8<0)||(raw< -cap && error_q8>0))integral<=candidate;
                state<=0;
            end
            default:state<=0;
        endcase
    end
endmodule
