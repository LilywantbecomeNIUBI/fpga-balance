// Immutable commissioning envelope. Runtime controllers supply only Iq targets.
// Units: signed Q15 I/8A. A fresh valid pulse is required every CMD_TIMEOUT clocks.
module motor_command_guard #(
    parameter IQ_LIMIT=1024, SLEW_PER_FRAME=4,
              CMD_TIMEOUT=5000000, MAX_RUN_CYCLES=250000000
)(
    input wire clk,rst_n,request_arm,clear_fault,command_valid,frame_valid,
    input wire signed [15:0] iq_request_1,iq_request_2,
    output wire arm,
    output reg signed [15:0] iq_1,iq_2,
    output reg [1:0] faults
);
    reg [31:0] command_age,run_age;
    reg seen_command;
    // A separately built supervised profile may set zero to disable only the
    // total run deadline. Command freshness, faults, clamp and slew still apply.
    wire run_expired=(MAX_RUN_CYCLES!=0) && run_age>=MAX_RUN_CYCLES;
    reg signed [15:0] target_1,target_2;
    function signed [15:0] clipped;
        input signed [15:0] x;
        begin
            if(x>IQ_LIMIT) clipped=IQ_LIMIT;
            else if(x< -IQ_LIMIT) clipped=-IQ_LIMIT;
            else clipped=x;
        end
    endfunction
    function signed [15:0] slew;
        input signed [15:0] old_value,target;
        reg signed [16:0] difference;
        begin
            difference=$signed({target[15],target})-$signed({old_value[15],old_value});
            if(difference>SLEW_PER_FRAME) slew=old_value+16'(SLEW_PER_FRAME);
            else if(difference< -SLEW_PER_FRAME) slew=old_value-16'(SLEW_PER_FRAME);
            else slew=target;
        end
    endfunction
    // Also remove arm combinationally at a deadline, before the fault FF updates.
    assign arm=rst_n && request_arm && seen_command && command_age<CMD_TIMEOUT &&
               !run_expired && faults==0;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            command_age<=CMD_TIMEOUT;run_age<=0;seen_command<=0;
            iq_1<=0;iq_2<=0;faults<=0;target_1<=0;target_2<=0;
        end else if(clear_fault && !request_arm) begin
            command_age<=CMD_TIMEOUT;run_age<=0;seen_command<=0;
            iq_1<=0;iq_2<=0;faults<=0;target_1<=0;target_2<=0;
        end else begin
            if(command_valid) begin
                command_age<=0;seen_command<=1;
                target_1<=clipped(iq_request_1);target_2<=clipped(iq_request_2);
            end
            else if(command_age<CMD_TIMEOUT) command_age<=command_age+1;
            if(!request_arm) begin run_age<=0;iq_1<=0;iq_2<=0;end
            else begin
                if(command_age>=CMD_TIMEOUT || !seen_command) faults[0]<=1;
                if(run_expired) faults[1]<=1;
                else if(MAX_RUN_CYCLES!=0) run_age<=run_age+1;
                if(!arm) begin iq_1<=0;iq_2<=0;end
                else if(frame_valid) begin
                    iq_1<=slew(iq_1,target_1);
                    iq_2<=slew(iq_2,target_2);
                end
            end
        end
    end
endmodule
