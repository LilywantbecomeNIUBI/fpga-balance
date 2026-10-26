// Explicit, single-shot lifecycle. No automatic fault recovery or restart.
module balance_supervisor #(parameter ALLOW_DRIVE=0,CLK_HZ=50000000)(
    input wire clk,rst_n,command_valid,configured,config_changed,
    input wire [7:0] command,flags,
    input wire imu_ok,attitude_calibrated,attitude_calibrating,attitude_bad,
    input wire signed [31:0] pitch,
    input wire [15:0] cutoff_cdeg,start_cdeg,duration_ms,
    input wire current_calibrated,current_calibrating,commissioned,commissioning,
    input wire [11:0] motor_faults,
    output reg active,armed,clear_fault,calibrate,zero_start,commission_start,
    output wire estop,can_configure,
    output reg [15:0] stop_reason,
    output wire [15:0] gates,
    output reg [7:0] rejected_command);
    reg [31:0] lease_ticks,run_ticks,arm_ticks;
    wire heartbeat_ok=lease_ticks<CLK_HZ/10;
    reg signed [31:0] cutoff_q,start_q;
    reg [31:0] run_limit;
    always @(posedge clk or negedge rst_n)
    if(!rst_n) begin cutoff_q<=0;start_q<=0;run_limit<=0;end
    else begin
        cutoff_q<=($signed({1'b0,cutoff_cdeg})*32'sd167772)>>>8;
        start_q<=($signed({1'b0,start_cdeg})*32'sd167772)>>>8;
        run_limit<=(CLK_HZ/1000)*duration_ms;
    end
    wire tilt_ok=pitch<cutoff_q && pitch> -cutoff_q;
    wire start_ok=pitch<start_q && pitch> -start_q;
    assign gates={4'd0,(stop_reason==0),(motor_faults==0),heartbeat_ok,start_ok,
        flags[7],flags[6],flags[5],commissioned,current_calibrated,attitude_calibrated,imu_ok,(ALLOW_DRIVE!=0)};
    wire all_ready=&gates[11:0] && configured && !commissioning && !current_calibrating && !attitude_calibrating;
    assign can_configure=!active && !armed && !commissioning && !current_calibrating && !attitude_calibrating;
    assign estop=stop_reason!=0;
    always @(posedge clk or negedge rst_n)
    if(!rst_n) begin active<=0;armed<=0;clear_fault<=0;calibrate<=0;zero_start<=0;commission_start<=0;
        lease_ticks<=CLK_HZ/10;run_ticks<=0;arm_ticks<=0;stop_reason<=0;rejected_command<=0;end
    else begin
        clear_fault<=0;calibrate<=0;zero_start<=0;commission_start<=0;
        if(lease_ticks<CLK_HZ) lease_ticks<=lease_ticks+1'b1;
        if(command_valid || config_changed) lease_ticks<=0;
        if(armed) begin
            arm_ticks<=arm_ticks+1'b1;
            if(arm_ticks>=CLK_HZ || !all_ready || config_changed) armed<=0;
        end
        if(active) begin
            run_ticks<=run_ticks+1'b1;
            if(run_ticks>=run_limit-1) begin active<=0;armed<=0;end
        end
        if((active || commissioning) && (!heartbeat_ok || motor_faults!=0 ||
                !imu_ok || attitude_bad || (active && (!tilt_ok || !attitude_calibrated || !configured)))) begin
            active<=0;armed<=0;
            if(!heartbeat_ok) stop_reason<=16'h0002;
            else if(motor_faults!=0) stop_reason<=16'h0004;
            else if(!imu_ok || attitude_bad) stop_reason<=16'h0008;
            else if(!tilt_ok) stop_reason<=16'h0010;
            else stop_reason<=16'h0020;
        end
        if(config_changed) begin armed<=0;active<=0;end
        if(command_valid) begin
            if(command!=0) rejected_command<=0;
            case(command)
            0:begin end // heartbeat only
            1:begin active<=0;armed<=0;stop_reason<=16'h0001;end
            2:if(!active && !commissioning && !current_calibrating) begin
                stop_reason<=0;armed<=0;clear_fault<=1;
            end else rejected_command<=command;
            3:if(can_configure && configured && stop_reason==0 && motor_faults==0)
                calibrate<=1;else rejected_command<=command;
            4:if(can_configure && configured && imu_ok && stop_reason==0)
                zero_start<=1;else rejected_command<=command;
            5:if(ALLOW_DRIVE && can_configure && configured && current_calibrated &&
                imu_ok && stop_reason==0 && motor_faults==0 && heartbeat_ok && flags[5] && flags[6] && flags[7])
                commission_start<=1;else rejected_command<=command;
            6:if(all_ready) begin armed<=1;arm_ticks<=0;end else rejected_command<=command;
            7:if(armed && all_ready && arm_ticks<CLK_HZ) begin
                active<=1;armed<=0;run_ticks<=0;
            end else rejected_command<=command;
            default:rejected_command<=command;
            endcase
        end
    end
endmodule
