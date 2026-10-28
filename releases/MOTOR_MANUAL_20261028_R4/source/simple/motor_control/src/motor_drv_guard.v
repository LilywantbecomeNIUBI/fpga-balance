// One dual-motor interlock: a fault on either motor shuts down both.
// Inputs are synchronous EXCEPT physical fault_n and estop. Those also mask
// pins combinationally, so a between-clock fault cannot emit a full PWM pulse.
module motor_drv_guard #(parameter SIMPLE_PROTECTION=0, WAKE_CYCLES=50000, MOTOR_MASK=2'b11)(
    input wire clk, rst_n, arm, clear_fault, ready, estop,
    input wire [1:0] fault_n,
    input wire sensor_fault, overcurrent, sync_fault,
    input wire [11:0] pwm_in,
    output wire [11:0] pwm_out,
    output wire [1:0] drv_en,
    output wire running,
    output reg [7:0] faults
);
    localparam OFF=0, WAKING=1, RUN=2;
    reg [1:0] state;
    reg [31:0] wait_count;
    reg [1:0] fault_sync1, fault_sync2;
    reg arm_previous, arm_pending;
    wire [1:0] selected_fault_n=fault_n | ~MOTOR_MASK;
    // Asynchronous assertion captures short physical faults; synchronous
    // release. Ignore driver nFAULT during sleep/wakeup as board specifies.
    wire watch_driver=state==RUN;
    reg kill_latched;
    wire async_kill=estop || (watch_driver && !(&selected_fault_n));
    // Single asynchronous SET with synchronous reset/clear maps to a physical
    // FPGA FF. Do not infer simultaneous asynchronous set+reset.
    always @(posedge clk or posedge async_kill)
        if(async_kill) kill_latched<=1;
        else if(!rst_n || (clear_fault && !arm)) kill_latched<=0;
    wire overlap=(pwm_in[0]&&pwm_in[1]) || (pwm_in[2]&&pwm_in[3]) ||
                 (pwm_in[4]&&pwm_in[5]) || (pwm_in[6]&&pwm_in[7]) ||
                 (pwm_in[8]&&pwm_in[9]) || (pwm_in[10]&&pwm_in[11]);
    wire live_kill=estop || kill_latched || (state==RUN && !(&selected_fault_n)) ||
        (!SIMPLE_PROTECTION && (sensor_fault || overcurrent || sync_fault ||
                              (state==RUN && (!ready || overlap))));
    assign running=rst_n && state==RUN && arm && ready && faults==0 && !live_kill;
    assign pwm_out=running ? pwm_in & {{6{MOTOR_MASK[1]}},{6{MOTOR_MASK[0]}}} : 12'b0;
    assign drv_en=(rst_n && (state==WAKING || state==RUN) && arm && faults==0 && !live_kill) ? MOTOR_MASK : 2'b00;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=OFF; wait_count<=0; faults<=0; fault_sync1<=0;
            fault_sync2<=0; arm_previous<=0; arm_pending<=0;
        end else begin
            fault_sync1<=selected_fault_n; fault_sync2<=fault_sync1;
            arm_previous<=arm;
            if(!arm) arm_pending<=0;
            else if(!arm_previous && ready && faults==0) arm_pending<=1;
            if(clear_fault && !arm && !estop && (&fault_sync2)) begin
                faults<=0; state<=OFF; arm_pending<=0;
            end else if(live_kill) begin
                state<=OFF; arm_pending<=0;
                if(estop || (!SIMPLE_PROTECTION && kill_latched)) faults[0]<=1;
                if(watch_driver && !selected_fault_n[0]) faults[1]<=1;
                if(watch_driver && !selected_fault_n[1]) faults[2]<=1;
                if(!SIMPLE_PROTECTION && (sensor_fault)) faults[3]<=1;
                if(!SIMPLE_PROTECTION && (overcurrent)) faults[4]<=1;
                if(!SIMPLE_PROTECTION && (watch_driver && overlap)) faults[5]<=1;
                if(!SIMPLE_PROTECTION && (sync_fault)) faults[6]<=1;
                if(!SIMPLE_PROTECTION && (watch_driver && !ready)) faults[7]<=1;
            end else if(!arm || faults!=0) begin state<=OFF; wait_count<=0; end
            else case(state)
                OFF: if(arm_pending && ready) begin state<=WAKING; wait_count<=0; end
                WAKING: if(!ready) begin state<=OFF; arm_pending<=0; end
                    else if(wait_count==WAKE_CYCLES-1) begin
                        if(&fault_sync2) state<=RUN;
                        else begin faults[2:1]<=~fault_sync2; state<=OFF; arm_pending<=0; end
                    end else wait_count<=wait_count+1;
                RUN: state<=RUN;
                default: state<=OFF;
            endcase
        end
    end
endmodule
