// Modes: 0 observe, 1 single-wheel PWM bench, 2 single-wheel speed PI,
// 3 upright PD -> PWM, 4 speed PI -> angle target -> upright PD -> PWM.
// Balance bypasses the bench wheel-speed loop and its 100ms reversal wait.
module bb_core #(
    parameter integer CLK_HZ=50000000,DRIVE_ENABLE=0,CPR_LEFT=60000,CPR_RIGHT=60000,
    parameter integer PWM_HARD_LIMIT=300,WATCHDOG_MS=250,FILTER_CYCLES=8
)(
    input wire clk,reset_n,left_enc_a,left_enc_b,right_enc_a,right_enc_b,
    input wire command_valid,input wire [7:0] opcode,sequence_id,input wire [319:0] payload,
    input wire imu_healthy,attitude_valid,attitude_calibrated,attitude_calibrating,
    input wire signed [31:0] pitch,rate,
    output reg zero_start,
    output wire [3:0] filter_shift,
    output wire left_in1,left_in2,right_in1,right_in2,
    output reg armed,config_valid,
    output reg [7:0] mode,last_sequence,config_sequence,stop_reason,
    output reg [15:0] faults,rejected,
    output wire signed [31:0] left_position,right_position,left_velocity,right_velocity,speed_trim,
    output wire signed [15:0] left_applied,right_applied,
    output wire [31:0] left_invalid,right_invalid
);
    localparam integer WINDOW=CLK_HZ/100;
    localparam integer WD_CYCLES=(CLK_HZ/1000)*WATCHDOG_MS;
    localparam integer MAX_LEFT=(CPR_LEFT*800)/6000,MAX_RIGHT=(CPR_RIGHT*800)/6000;
    reg [7:0] flags,axis;
    reg [3:0] filter_q;
    reg [15:0] pwm_limit,angle_kp,angle_kd,wheel_kp,wheel_ki,speed_kp,speed_ki;
    reg signed [15:0] trim_cdeg,target_left,target_right,target_rpm;
    reg [15:0] start_cdeg,fall_cdeg,speed_limit_cdeg,duration_ms;
    reg have_sequence;
    integer divider,watchdog,run_cycles,attitude_age,stall_left,stall_right;
    reg sample_tick,control_tick,speed_tick,half_speed;
    reg [31:0] invalid_left_q,invalid_right_q;
    wire [7:0] seq_delta=sequence_id-last_sequence;
    wire fresh=!have_sequence || (seq_delta!=0 && seq_delta<128);
    wire balance_mode=mode==3 || mode==4;
    wire bench_mode=mode==1 || mode==2;
    wire signed [31:0] abs_pitch=pitch<0 ? -pitch : pitch;
    wire signed [31:0] start_q16=($signed({1'b0,start_cdeg})*32'sd167772)>>>8;
    wire signed [31:0] fall_q16=($signed({1'b0,fall_cdeg})*32'sd167772)>>>8;
    wire balance_ready=imu_healthy && attitude_calibrated && !attitude_calibrating && attitude_age<CLK_HZ/100;
    wire drive_active=DRIVE_ENABLE && reset_n && armed && faults==0 &&
        (!balance_mode || (balance_ready && abs_pitch<fall_q16));
    assign filter_shift=filter_q;

    wire [7:0] new_mode=payload[0+:8],new_flags=payload[8+:8],new_axis=payload[16+:8],new_filter=payload[24+:8];
    wire [15:0] new_limit=payload[32+:16],new_kp=payload[48+:16],new_kd=payload[64+:16];
    wire [15:0] new_wkp=payload[80+:16],new_wki=payload[96+:16];
    wire [15:0] new_skp=payload[112+:16],new_ski=payload[128+:16];
    wire signed [15:0] new_trim=payload[144+:16];
    wire [15:0] new_start=payload[160+:16],new_fall=payload[176+:16];
    wire [15:0] new_speed_cap=payload[192+:16],new_duration=payload[208+:16];
    wire config_ok=new_mode<=4 && new_flags<32 && new_filter>=2 && new_filter<=10 &&
        new_limit>0 && new_limit<=PWM_HARD_LIMIT && new_kp<=25600 && new_kd<=5120 &&
        new_wkp>0 && new_wkp<=4096 && new_wki<=1024 && new_skp<=32768 && new_ski<=1311 &&
        new_trim>=-500 && new_trim<=500 && new_start>=100 && new_start<=1000 &&
        new_fall>new_start && new_fall<=6000 && new_speed_cap<=600 && payload[224+:96]==0 &&
        ((new_mode==0 && new_axis==0 && new_duration==0) ||
         ((new_mode==1 || new_mode==2) && (new_axis==1 || new_axis==2) && new_duration>=100 && new_duration<=5000) ||
         ((new_mode==3 || new_mode==4) && new_axis==3 && new_duration==0));
    wire signed [15:0] new_left=payload[0+:16],new_right=payload[16+:16],new_rpm=payload[32+:16];
    wire targets_ok=payload[48+:272]==0 &&
        ((bench_mode && new_rpm==0 && ((axis==1 && new_right==0)||(axis==2 && new_left==0)) &&
            (mode==1 ? (new_left<= $signed(pwm_limit) && new_left>=-$signed(pwm_limit) &&
                        new_right<= $signed(pwm_limit) && new_right>=-$signed(pwm_limit)) :
                       (new_left>=-4096 && new_left<=4096 && new_right>=-4096 && new_right<=4096))) ||
         (balance_mode && new_left==0 && new_right==0 && new_rpm>=-30720 && new_rpm<=30720 &&
             (mode==4 || new_rpm==0)));

    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin divider<=0;sample_tick<=0;control_tick<=0;speed_tick<=0;half_speed<=0;end
        else begin
            sample_tick<=0;control_tick<=sample_tick;speed_tick<=0;
            if(divider==WINDOW-1)begin divider<=0;sample_tick<=1;end else divider<=divider+1;
            if(sample_tick)begin half_speed<=!half_speed;if(half_speed)speed_tick<=1;end
        end
    end
    bb_encoder #(.FILTER_CYCLES(FILTER_CYCLES)) enc_l(.clk(clk),.reset_n(reset_n),.a(left_enc_a),.b(left_enc_b),
        .tick(sample_tick),.reverse(flags[2]),.position(left_position),.velocity(left_velocity),.invalid_count(left_invalid));
    bb_encoder #(.FILTER_CYCLES(FILTER_CYCLES)) enc_r(.clk(clk),.reset_n(reset_n),.a(right_enc_a),.b(right_enc_b),
        .tick(sample_tick),.reverse(flags[3]),.position(right_position),.velocity(right_velocity),.invalid_count(right_invalid));
    wire signed [15:0] pi_left,pi_right,common_pwm;
    bb_wheel_pi #(.PWM_LIMIT(PWM_HARD_LIMIT)) wheel_l(.clk(clk),.reset_n(reset_n),.tick(control_tick),
        .enable(drive_active && mode==2 && axis==1),.motor_reverse(flags[0]),.target(target_left),
        .velocity(left_velocity),.kp(wheel_kp),.ki(wheel_ki),.pwm_limit(pwm_limit),.applied(pi_left));
    bb_wheel_pi #(.PWM_LIMIT(PWM_HARD_LIMIT)) wheel_r(.clk(clk),.reset_n(reset_n),.tick(control_tick),
        .enable(drive_active && mode==2 && axis==2),.motor_reverse(flags[1]),.target(target_right),
        .velocity(right_velocity),.kp(wheel_kp),.ki(wheel_ki),.pwm_limit(pwm_limit),.applied(pi_right));
    bb_speed #(.CPR_LEFT(CPR_LEFT),.CPR_RIGHT(CPR_RIGHT)) speed(.clk(clk),.reset_n(reset_n),.tick(speed_tick),
        .enable(drive_active && mode==4),.left_velocity(left_velocity),.right_velocity(right_velocity),
        .target_rpm_q8(target_rpm),.kp(speed_kp),.ki_tick(speed_ki),.limit_cdeg(speed_limit_cdeg),.trim_q16(speed_trim));
    reg signed [31:0] trim_q16,target_angle;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin trim_q16<=0;target_angle<=0;end
        else begin trim_q16<=($signed(trim_cdeg)*32'sd167772)>>>8;target_angle<=trim_q16+speed_trim;end
    end
    bb_pd pd(.clk(clk),.reset_n(reset_n),.enable(drive_active && balance_mode),.reverse(flags[4]),
        .pitch(pitch),.rate(rate),.target(target_angle),.kp(angle_kp),.kd(angle_kd),.pwm_limit(pwm_limit),.demand(common_pwm));
    wire signed [15:0] raw_left=mode==1 ? (flags[0] ? -target_left : target_left) :
        mode==2 ? pi_left : (flags[0] ? -common_pwm : common_pwm);
    wire signed [15:0] raw_right=mode==1 ? (flags[1] ? -target_right : target_right) :
        mode==2 ? pi_right : (flags[1] ? -common_pwm : common_pwm);
    function automatic signed [15:0] limited(input signed [15:0] value);
        limited=value>$signed(pwm_limit) ? $signed(pwm_limit) : value<-$signed(pwm_limit) ? -$signed(pwm_limit) : value;
    endfunction
    assign left_applied=drive_active && (balance_mode || axis==1) ? limited(raw_left) : 16'sd0;
    assign right_applied=drive_active && (balance_mode || axis==2) ? limited(raw_right) : 16'sd0;
    generate if(DRIVE_ENABLE)begin : drive_build
        at8236_pwm #(.CLK_HZ(CLK_HZ)) pwm_l(.clk(clk),.reset_n(reset_n),.enable(drive_active),.command(left_applied),.in1(left_in1),.in2(left_in2));
        at8236_pwm #(.CLK_HZ(CLK_HZ)) pwm_r(.clk(clk),.reset_n(reset_n),.enable(drive_active),.command(right_applied),.in1(right_in1),.in2(right_in2));
    end else begin : observe_build
        assign left_in1=0,left_in2=0,right_in1=0,right_in2=0;
    end endgenerate
    wire [15:0] fault_event=(watchdog>=WD_CYCLES-1 ? 16'h0002 : 0) |
        (balance_mode && !balance_ready ? 16'h0004 : 0) |
        (balance_mode && abs_pitch>=fall_q16 ? 16'h0008 : 0) |
        (control_tick && ((left_invalid-invalid_left_q)>8 || (right_invalid-invalid_right_q)>8) ? 16'h0010 : 0) |
        (control_tick && (left_velocity>MAX_LEFT || left_velocity< -MAX_LEFT || right_velocity>MAX_RIGHT || right_velocity< -MAX_RIGHT) ? 16'h0020 : 0) |
        (stall_left>=50 || stall_right>=50 ? 16'h0040 : 0);
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            zero_start<=0;armed<=0;config_valid<=0;mode<=0;flags<=0;axis<=0;filter_q<=6;
            last_sequence<=0;config_sequence<=0;stop_reason<=0;faults<=1;rejected<=0;have_sequence<=0;
            pwm_limit<=100;angle_kp<=0;angle_kd<=0;wheel_kp<=256;wheel_ki<=0;speed_kp<=0;speed_ki<=0;
            trim_cdeg<=0;start_cdeg<=500;fall_cdeg<=3500;speed_limit_cdeg<=300;duration_ms<=0;
            target_left<=0;target_right<=0;target_rpm<=0;
            watchdog<=0;run_cycles<=0;attitude_age<=CLK_HZ/100;stall_left<=0;stall_right<=0;
            invalid_left_q<=0;invalid_right_q<=0;
        end else begin
            zero_start<=0;
            if(attitude_valid)attitude_age<=0;else if(attitude_age<CLK_HZ)attitude_age<=attitude_age+1;
            if(armed)begin watchdog<=watchdog+1;run_cycles<=run_cycles+1;end
            else begin watchdog<=0;run_cycles<=0;stall_left<=0;stall_right<=0;end
            if(control_tick)begin
                invalid_left_q<=left_invalid;invalid_right_q<=right_invalid;
                if(armed)begin
                    stall_left<=(left_applied>=100 || left_applied<=-100) && left_velocity==0 ? stall_left+1 : 0;
                    stall_right<=(right_applied>=100 || right_applied<=-100) && right_velocity==0 ? stall_right+1 : 0;
                end
            end
            if(command_valid)begin
                if(opcode==0)begin armed<=0;faults<=faults|16'h0001;stop_reason<=1;target_left<=0;target_right<=0;target_rpm<=0;end
                else if(!fresh)rejected<=rejected+1'b1;
                else if(opcode==1 && !armed && payload==0)begin faults<=0;stop_reason<=0;last_sequence<=sequence_id;have_sequence<=1;end
                else if(opcode==2 && !armed && config_ok)begin
                    mode<=new_mode;flags<=new_flags;axis<=new_axis;filter_q<=new_filter;
                    pwm_limit<=new_limit;angle_kp<=new_kp;angle_kd<=new_kd;wheel_kp<=new_wkp;wheel_ki<=new_wki;
                    speed_kp<=new_skp;speed_ki<=new_ski;trim_cdeg<=new_trim;start_cdeg<=new_start;fall_cdeg<=new_fall;
                    speed_limit_cdeg<=new_speed_cap;duration_ms<=new_duration;
                    target_left<=0;target_right<=0;target_rpm<=0;config_valid<=1;config_sequence<=sequence_id;
                    last_sequence<=sequence_id;have_sequence<=1;
                end else if(opcode==3 && !armed && imu_healthy && payload==0)begin
                    zero_start<=1;last_sequence<=sequence_id;have_sequence<=1;
                end else if(opcode==4 && !armed && DRIVE_ENABLE && config_valid && mode!=0 && faults==0 &&
                    payload==0 && (!balance_mode || (balance_ready && abs_pitch<=start_q16)))begin
                    armed<=1;watchdog<=0;run_cycles<=0;target_left<=0;target_right<=0;target_rpm<=0;
                    last_sequence<=sequence_id;have_sequence<=1;stop_reason<=0;
                end else if(opcode==5 && armed && targets_ok)begin
                    target_left<=new_left;target_right<=new_right;target_rpm<=new_rpm;
                    watchdog<=0;last_sequence<=sequence_id;have_sequence<=1;
                end else if(opcode==6 && payload==0)begin watchdog<=0;last_sequence<=sequence_id;have_sequence<=1;end
                else rejected<=rejected+1'b1;
            end
            // Hardware evidence wins over a command arriving at the same edge.
            if(armed && fault_event!=0)begin
                armed<=0;faults<=faults|fault_event;stop_reason<=2;
                target_left<=0;target_right<=0;target_rpm<=0;
            end else if(armed && bench_mode && run_cycles>=(CLK_HZ/1000)*duration_ms-1)begin
                armed<=0;stop_reason<=3;target_left<=0;target_right<=0;target_rpm<=0;
            end
        end
    end
endmodule
