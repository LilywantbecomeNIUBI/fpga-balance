// 1 kHz estimator; actual commit intervals, no host timing in the loop.
module balance_attitude #(parameter ZERO_LOG2=10)(
    input wire clk,rst_n,sample_valid,zero_start,invalidate,
    input wire [3:0] filter_shift,
    input wire signed [15:0] ax,ay,az,gx,gy,gz,
    input wire [31:0] commit_us,
    output reg valid,calibrated,calibrating,bad_sample,
    output reg signed [31:0] pitch,rate,
    output reg [15:0] interval_us,
    output reg [15:0] zero_progress);
    // Fixed vehicle installation: Y pitch axis, front positive, upright -Z.
    // Extend before negation to handle the signed16 minimum without overflow.
    wire signed [16:0] x=-$signed({az[15],az});
    wire signed [16:0] y=-$signed({ax[15],ax});
    wire signed [31:0] gyro_signed=-$signed({{16{gy[15]}},gy});
    wire [33:0] norm2=$signed(ax)*$signed(ax)+$signed(ay)*$signed(ay)+$signed(az)*$signed(az);
    wire stationary=norm2>34'd48486154 && norm2<34'd88751472 &&
        gx>-100 && gx<100 && gy>-100 && gy<100 && gz>-100 && gz<100;
    wire angle_valid;wire signed [31:0] acc_angle;
    balance_atan atan(.clk(clk),.rst_n(rst_n),.start(sample_valid),.x_in(x),.y_in(y),.valid(angle_valid),.angle(acc_angle));
    reg [31:0] last_commit,dt;
    reg have_time,pending_stationary;
    reg signed [31:0] pending_gyro,bias,zero_angle,first_angle;
    reg signed [47:0] gyro_sum,angle_sum;
    reg signed [31:0] corrected_rate;
    reg signed [63:0] integrated;
    reg signed [31:0] delta;
    // Constant reciprocal of 1e6, rounded. Error <0.0008% over accepted dt.
    wire signed [95:0] delta_product=integrated*32'sd4295;
    function signed [31:0] wrap(input signed [32:0] a);
        if(a>11796480) wrap=a-23592960;
        else if(a < -11796480) wrap=a+23592960;
        else wrap=a;
    endfunction
    wire signed [31:0] acc_relative=wrap($signed(acc_angle)-$signed(zero_angle));
    reg signed [31:0] prediction,relative_q,innovation;
    reg [1:0] update_stage;
    always @(posedge clk or negedge rst_n)
    if(!rst_n) begin
        valid<=0;calibrated<=0;calibrating<=0;bad_sample<=0;pitch<=0;rate<=0;
        last_commit<=0;dt<=0;have_time<=0;pending_stationary<=0;pending_gyro<=0;
        bias<=0;zero_angle<=0;first_angle<=0;gyro_sum<=0;angle_sum<=0;interval_us<=0;zero_progress<=0;
        corrected_rate<=0;integrated<=0;delta<=0;prediction<=0;relative_q<=0;innovation<=0;update_stage<=0;
    end else begin
        valid<=0;
        corrected_rate<=(pending_gyro-bias)*32'sd2000;
        integrated<=$signed(corrected_rate)*$signed({1'b0,dt[15:0]});
        delta<=delta_product>>>32;
        if(invalidate) begin calibrated<=0;calibrating<=0;bad_sample<=0;have_time<=0;update_stage<=0;end
        else if(zero_start) begin calibrated<=0;calibrating<=1;zero_progress<=0;gyro_sum<=0;angle_sum<=0;bad_sample<=0;have_time<=0;update_stage<=0;end
        else begin
            if(update_stage==1) begin innovation<=wrap($signed(relative_q)-$signed(prediction));update_stage<=2;end
            else if(update_stage==2) begin
                pitch<=wrap($signed(prediction)+($signed(innovation)>>>filter_shift));
                rate<=corrected_rate;valid<=1;update_stage<=0;
            end
            if(sample_valid) begin
                dt<=have_time ? commit_us-last_commit : 1000;
                interval_us<=have_time ? commit_us-last_commit : 1000;
                last_commit<=commit_us;have_time<=1;pending_gyro<=gyro_signed;pending_stationary<=stationary;
            end
            if(angle_valid && have_time) begin
                if(dt<500 || dt>2500) begin bad_sample<=1;calibrated<=0;calibrating<=0;update_stage<=0;end
                else if(calibrating) begin
                    if(!pending_stationary || (zero_progress!=0 && (acc_angle-first_angle>65536 || acc_angle-first_angle < -65536))) begin
                        zero_progress<=0;gyro_sum<=0;angle_sum<=0;
                    end else begin
                        if(zero_progress==0) first_angle<=acc_angle;
                        gyro_sum<=gyro_sum+pending_gyro;angle_sum<=angle_sum+acc_angle;
                        zero_progress<=zero_progress+1'b1;
                        if(zero_progress==(1<<ZERO_LOG2)-1) begin
                            bias<=($signed(gyro_sum)+$signed(pending_gyro))>>>ZERO_LOG2;
                            zero_angle<=($signed(angle_sum)+$signed(acc_angle))>>>ZERO_LOG2;
                            calibrated<=1;calibrating<=0;pitch<=0;rate<=0;
                        end
                    end
                end else if(calibrated) begin
                    prediction<=wrap($signed(pitch)+$signed(delta));relative_q<=acc_relative;update_stage<=1;
                end
            end
        end
    end
endmodule
