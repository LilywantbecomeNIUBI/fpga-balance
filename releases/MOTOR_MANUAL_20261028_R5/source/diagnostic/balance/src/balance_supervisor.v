// Continuous tuning lifecycle; only dedicated current tests have a deadline.
module balance_supervisor #(parameter SIMPLE_PROTECTION=0,ALLOW_DRIVE=0,CLK_HZ=50000000)(
    input wire clk,rst_n,command_valid,configured,config_changed,
    input wire [7:0] command,
    input wire imu_ok,attitude_calibrated,attitude_calibrating,attitude_bad,
    input wire current_calibrated,current_calibrating,commissioned,commissioning,
    input wire [11:0] motor_faults,
    output reg active,armed,clear_fault,calibrate,zero_start,commission_start,
    output wire estop,can_configure,
    output reg [15:0] stop_reason,
    output wire [15:0] gates,
    output reg [7:0] rejected_command,
    output reg [1:0] commission_select);
    reg [31:0] lease_ticks,arm_ticks;
    wire heartbeat_ok=lease_ticks<CLK_HZ/10;
    assign gates={4'd0,(stop_reason==0),(motor_faults==0),heartbeat_ok,1'b0,
        3'b000,commissioned,current_calibrated,attitude_calibrated,imu_ok,(ALLOW_DRIVE!=0)};
    wire all_ready=((gates & 16'h0e1f)==16'h0e1f) && configured && !commissioning && !current_calibrating && !attitude_calibrating;
    assign can_configure=!active && !armed && !commissioning && !current_calibrating && !attitude_calibrating;
    assign estop=stop_reason!=0;
    always @(posedge clk or negedge rst_n)
    if(!rst_n) begin active<=0;armed<=0;clear_fault<=0;calibrate<=0;zero_start<=0;commission_start<=0;
        lease_ticks<=CLK_HZ/10;arm_ticks<=0;stop_reason<=0;rejected_command<=0;commission_select<=0;end
    else begin
        clear_fault<=0;calibrate<=0;zero_start<=0;commission_start<=0;
        if(lease_ticks<CLK_HZ) lease_ticks<=lease_ticks+1'b1;
        if(command_valid || config_changed) lease_ticks<=0;
        if(armed) begin
            arm_ticks<=arm_ticks+1'b1;
            if(arm_ticks>=CLK_HZ || !all_ready || config_changed) armed<=0;
        end
        if((active || commissioning) && (!heartbeat_ok || motor_faults!=0 ||
                (!SIMPLE_PROTECTION && (!imu_ok || attitude_bad || (active && (!attitude_calibrated || !configured)))))) begin
            active<=0;armed<=0;
            if(!heartbeat_ok) stop_reason<=16'h0002;
            else if(motor_faults!=0) stop_reason<=16'h0004;
            else if(!SIMPLE_PROTECTION && (!imu_ok || attitude_bad)) stop_reason<=16'h0008;
            else stop_reason<=16'h0020;
        end
        if(config_changed) begin armed<=0;active<=0;end
        if(command_valid) begin
            if(command!=0) rejected_command<=0;
            case(command)
            0:begin end // heartbeat only
            1:begin active<=0;armed<=0;stop_reason<=16'h0001;end
            11:begin active<=0;armed<=0;end // normal end; no fault clear or calibration invalidation
            2:if(!active && !commissioning && !current_calibrating) begin
                stop_reason<=0;armed<=0;clear_fault<=1;commission_select<=0;
            end else rejected_command<=command;
            3:if(can_configure && configured && stop_reason==0 && motor_faults==0)
                calibrate<=1;else rejected_command<=command;
            4:if(can_configure && configured && imu_ok && stop_reason==0)
                zero_start<=1;else rejected_command<=command;
            9,10:if(ALLOW_DRIVE && can_configure && configured && current_calibrated &&
                imu_ok && stop_reason==0 && motor_faults==0 && heartbeat_ok)
                begin commission_start<=1;commission_select<=command==9 ? 2'b01 : 2'b10;end
                else rejected_command<=command;
            6:if(all_ready) begin armed<=1;arm_ticks<=0;end else rejected_command<=command;
            7:if(armed && all_ready && arm_ticks<CLK_HZ) begin
                active<=1;armed<=0;
            end else rejected_command<=command;
            default:rejected_command<=command;
            endcase
        end
    end
endmodule
