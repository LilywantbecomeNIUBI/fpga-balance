// Align position to the effective current-measurement epoch, NOT PWM actuation.
// One 20kHz frame = 2500 clocks. All timestamps have the same reset epoch.
// CURRENT_LAG includes analog group delay only; conversion/SSI readout is NOT
// subtracted twice. Its effect is already represented by the sample timestamp.
module motor_measurement_angle #(
    parameter CURRENT_LAG=0,ENCODER_LAG=0,FRAME_CYCLES=2500,
              MAX_STEP=64,MAX_EPOCH_DELTA=6250,WINDOW_LOG2=4,MAX_WINDOW_TICKS=32
)(
    input wire clk,rst_n,valid,
    input wire [13:0] mechanical,
    input wire [31:0] current_time,encoder_time,
    output reg [13:0] aligned,
    output reg signed [13:0] step,
    output reg speed_fault,timing_fault,
    output reg initialized,
    output reg aligned_valid
);
    reg [13:0] previous;
    reg [31:0] previous_time;
    reg [WINDOW_LOG2-1:0] window_count;
    reg signed [19:0] window_sum;
    wire signed [13:0] delta=mechanical-previous; // shortest modulo 16384
    wire [31:0] interval=encoder_time-previous_time;
    wire signed [31:0] epoch_delta=(current_time-CURRENT_LAG)-(encoder_time-ENCODER_LAG);
    reg [1:0] state;
    reg signed [13:0] delta_reg,epoch_reg;
    reg signed [27:0] product;
    reg [13:0] captured;
    reg negative;
    reg [27:0] dividend,quotient;
    reg [12:0] remainder;
    reg [5:0] bits_left;
    wire [13:0] trial={remainder,dividend[27]};
    wire quotient_bit=trial>=FRAME_CYCLES;
    wire [13:0] answer={quotient[12:0],quotient_bit};
    wire signed [20:0] total=$signed(window_sum)+$signed(delta);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            previous<=0;previous_time<=0;aligned<=0;step<=0;initialized<=0;
            speed_fault<=0;timing_fault<=0;window_count<=0;window_sum<=0;
            aligned_valid<=0;state<=0;delta_reg<=0;epoch_reg<=0;product<=0;
            captured<=0;negative<=0;dividend<=0;quotient<=0;remainder<=0;bits_left<=0;
        end else begin
          aligned_valid<=0;
          if(valid && state!=0) timing_fault<=1;
          case(state)
          0: if(valid) begin
            previous<=mechanical;previous_time<=encoder_time;aligned<=mechanical;
            captured<=mechanical;epoch_reg<=epoch_delta[13:0];
            delta_reg<=initialized ? delta : 14'sd0;state<=1;
            initialized<=1;
            if(initialized) begin
                step<=delta;
                if(interval!=FRAME_CYCLES || epoch_delta>MAX_EPOCH_DELTA ||
                   epoch_delta< -MAX_EPOCH_DELTA) timing_fault<=1;
                if(delta>MAX_STEP || delta< -MAX_STEP) speed_fault<=1;
                if(&window_count) begin
                    if(total>MAX_WINDOW_TICKS || total< -MAX_WINDOW_TICKS) speed_fault<=1;
                    window_count<=0;window_sum<=0;
                end else begin window_count<=window_count+1'b1;window_sum<=total[19:0];end
            end
          end
          1: begin product<=delta_reg*epoch_reg;state<=2;end
          2: begin
              negative<=product[27];dividend<=product[27] ? -product : product;
              quotient<=0;remainder<=0;bits_left<=28;state<=3;
          end
          3: begin
              dividend<={dividend[26:0],1'b0};quotient<={quotient[26:0],quotient_bit};
              remainder<=quotient_bit ? 13'(trial-FRAME_CYCLES) : trial[12:0];
              bits_left<=bits_left-1'b1;
              if(bits_left==1) begin
                  aligned<=negative ? captured-answer : captured+answer;
                  aligned_valid<=1;state<=0;
              end
          end
          endcase
        end
    end
endmodule
