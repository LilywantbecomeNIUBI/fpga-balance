// No proprietary FOC internals: bounded current-regulated rotating field.
// Exactly one motor per commissioning build. Direction is inferred from a full
// slow electrical revolution, then travel must agree with the configured poles.
// Zero is captured at stationary electrical angle zero, with PWM DISARMED before
// runtime calibration constants change. Reset always invalidates the result.
// Optional integrated lifecycle preserves completed constants on fault clear.
// An explicit new start invalidates only this axis before recalibration.
module motor_commission #(
    parameter POLE_PAIRS=11, SETTLE_FRAMES=10000, PREALIGN_FRAMES=0, SWEEP_FRAMES=20000,
              END_FRAMES=6000, QUIET_FRAMES=2000,HANDOFF_CYCLES=50000,
              MAX_RUN_CYCLES=120000000,PULSE_ONLY=0,PROBE_SWITCH_CYCLES=0,
              PRESERVE_CAL_ON_CLEAR=0,RELAXED_ACCEPTANCE=0
)(
    input wire clk,rst_n,start,clear_fault,calibrated,feedback_valid,running,
    input wire [13:0] mechanical,
    input wire signed [15:0] ia,ib,
    input wire [11:0] faults,
    output wire busy,
    output reg arm,done,failed,reverse,
    output reg [13:0] zero,
    output reg [15:0] theta,
    output reg [3:0] state
);
    localparam IDLE=0,ALIGN=1,SWEEP=2,SETTLE=3,OFF=4,HANDOFF=5,COMPLETE=6,FAIL=7,PULSE_COMPLETE=8;
    localparam EXPECTED=16384/POLE_PAIRS;
    reg [31:0] frames,cycles;
    reg [13:0] first_angle,quiet_angle;
    reg direction_candidate;
    reg [31:0] phase_remainder;
    reg start_pending;
    wire signed [13:0] travel=mechanical-first_angle;
    wire signed [13:0] quiet=mechanical-quiet_angle;
    wire [14:0] distance=travel[13] ? -$signed({travel[13],travel}) : {1'b0,travel};
    wire [32:0] phase_sum={1'b0,phase_remainder}+(65536%SWEEP_FRAMES);
    assign busy=state>=ALIGN && state<=HANDOFF;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;arm<=0;done<=0;failed<=0;reverse<=0;zero<=0;theta<=0;
            frames<=0;cycles<=0;first_angle<=0;quiet_angle<=0;direction_candidate<=0;start_pending<=0;phase_remainder<=0;
        end else if(clear_fault && !arm) begin
            state<=PRESERVE_CAL_ON_CLEAR && done ? COMPLETE : IDLE;
            done<=PRESERVE_CAL_ON_CLEAR && done;failed<=0;theta<=0;frames<=0;cycles<=0;start_pending<=0;
            if(!PRESERVE_CAL_ON_CLEAR || !done) begin reverse<=0;zero<=0;end
        end else if(PRESERVE_CAL_ON_CLEAR && start && state==COMPLETE && !arm && !(|faults)) begin
            // The selected completed axis may be explicitly recalibrated.
            state<=IDLE;done<=0;failed<=0;start_pending<=1;frames<=0;cycles<=0;theta<=0;
        end else if(busy && (|faults)) begin
            state<=FAIL;arm<=0;failed<=1;
        end else if(busy && cycles>=MAX_RUN_CYCLES) begin
            // Diagnostic one-shot never establishes a motor calibration and
            // cannot rearm until an explicit disarmed clear/reset.
            state<=PULSE_ONLY ? PULSE_COMPLETE : FAIL;
            arm<=0;failed<=!PULSE_ONLY;
        end else begin
            if(start && state==IDLE) start_pending<=1;
            if(busy) cycles<=cycles+1;
            case(state)
                IDLE: if((start || start_pending) && calibrated && feedback_valid) begin
                    state<=ALIGN;arm<=1;frames<=0;cycles<=0;
                    theta<=PULSE_ONLY || PREALIGN_FRAMES>0 ? 16'd16384 : 16'd0;start_pending<=0;
                end
                ALIGN: if(PULSE_ONLY) begin
                    // Optional second stationary vector within the SAME hard
                    // deadline; no sweep, calibration acceptance or runtime arm.
                    if(PROBE_SWITCH_CYCLES>0 && cycles>=PROBE_SWITCH_CYCLES) theta<=0;
                end else if(feedback_valid && running) begin
                    frames<=frames+1;
                    // Optional second vector within the existing ALIGN budget.
                    // Avoid a rotor remaining at the opposite equilibrium of
                    // a single stationary vector. Final checks remain at zero.
                    if(PREALIGN_FRAMES>0 && frames==PREALIGN_FRAMES-1) theta<=0;
                    if(frames==SETTLE_FRAMES-QUIET_FRAMES) quiet_angle<=mechanical;
                    if(frames==SETTLE_FRAMES-1) begin
                        // With theta=0, D-current should give Ia>0, Ib<0.
                        // Broad commissioning check; not a measured PI-bandwidth test.
                        if(!RELAXED_ACCEPTANCE && (quiet>16 || quiet< -16 || ia<128 || ia>1536 || ib>=0 || ib< -1024)) begin
                            state<=FAIL;arm<=0;failed<=1;
                        end else begin state<=SWEEP;frames<=0;first_angle<=mechanical;phase_remainder<=0;end
                    end
                end
                SWEEP: if(feedback_valid && running) begin
                    frames<=frames+1;
                    if(phase_sum>=SWEEP_FRAMES) begin
                        theta<=theta+16'(65536/SWEEP_FRAMES)+16'd1;
                        phase_remainder<=32'(phase_sum-SWEEP_FRAMES);
                    end else begin theta<=theta+16'(65536/SWEEP_FRAMES);phase_remainder<=phase_sum[31:0];end
                    if(frames==SWEEP_FRAMES-1) begin
                        theta<=0;frames<=0;direction_candidate<=travel[13];state<=SETTLE;
                    end
                end
                SETTLE: if(feedback_valid && running) begin
                    frames<=frames+1;
                    if(frames==END_FRAMES-QUIET_FRAMES) quiet_angle<=mechanical;
                    if(frames==END_FRAMES-1) begin
                        // Travel error widened 5x (15% -> 75%); current/quiet no longer reject.
                        if(distance<EXPECTED*(RELAXED_ACCEPTANCE ? 25 : 85)/100 ||
                           distance>EXPECTED*(RELAXED_ACCEPTANCE ? 175 : 115)/100 ||
                           travel[13]!=direction_candidate || (!RELAXED_ACCEPTANCE &&
                           (quiet>16 || quiet< -16 || ia<128 || ia>1536 || ib>=0 || ib< -1024))) begin
                            state<=FAIL;arm<=0;failed<=1;
                        end else begin arm<=0;cycles<=0;state<=OFF;end
                    end
                end
                // Two full clocks disarmed before changing configuration.
                OFF: if(cycles>=2) begin zero<=mechanical;reverse<=direction_candidate;state<=HANDOFF;cycles<=0;end
                HANDOFF: if(cycles>=HANDOFF_CYCLES) begin state<=COMPLETE;done<=1;end
                default: arm<=0;
            endcase
        end
    end
endmodule
