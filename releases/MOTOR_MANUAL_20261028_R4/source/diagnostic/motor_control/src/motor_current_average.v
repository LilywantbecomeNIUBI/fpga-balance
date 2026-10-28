// Inter-frame FIR at 20kHz, NOT additional AD7606 conversions per PWM period.
// Protection must use the unfiltered input in motor_current/motor_drv_guard.
// Four taps add 75us group delay; the adapter shifts the measurement epoch.
module motor_current_average #(parameter TAPS=1)(
 input wire clk,rst_n,clear,valid,
 input wire [95:0] currents,
 output wire filtered_valid,output wire [95:0] filtered_currents);
 generate if(TAPS==1) begin:bypass
  assign filtered_valid=valid && !clear;
  assign filtered_currents=currents;
 end else begin:fir
  localparam SHIFT=$clog2(TAPS), COUNT_BITS=$clog2(TAPS+1);
  reg [SHIFT-1:0] pointer;
  reg [COUNT_BITS-1:0] count;
  reg signed [15:0] history[0:6*TAPS-1];
  reg signed [31:0] sum[0:5];
  reg [95:0] result;
  reg result_valid;
  reg signed [31:0] next_sum;
  integer lane,item;
  // Symmetric nearest rounding avoids a negative-current DC bias.
  function [15:0] mean;
   input signed [31:0] value;
   reg signed [31:0] rounded;
   begin
    rounded=value<0 ? -(((-value)+(TAPS/2))>>>SHIFT) : (value+(TAPS/2))>>>SHIFT;
    mean=rounded[15:0];
   end
  endfunction
  assign filtered_valid=result_valid;
  assign filtered_currents=result;
  always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin
    pointer<=0;count<=0;result<=0;result_valid<=0;
    for(item=0;item<6*TAPS;item=item+1) history[item]<=0;
    for(lane=0;lane<6;lane=lane+1) sum[lane]<=0;
   end else begin
    result_valid<=0;
    if(clear) begin
     pointer<=0;count<=0;result<=0;
     for(item=0;item<6*TAPS;item=item+1) history[item]<=0;
     for(lane=0;lane<6;lane=lane+1) sum[lane]<=0;
    end else if(valid) begin
     for(lane=0;lane<6;lane=lane+1) begin
      next_sum=sum[lane]+$signed(currents[lane*16+:16])-$signed(history[lane*TAPS+pointer]);
      sum[lane]<=next_sum;
      history[lane*TAPS+pointer]<=currents[lane*16+:16];
      result[lane*16+:16]<=mean(next_sum);
     end
     pointer<=pointer+1'b1;
     if(count<TAPS) count<=count+1'b1;
     if(count>=TAPS-1) result_valid<=1;
    end
   end
  end
 end endgenerate
endmodule
