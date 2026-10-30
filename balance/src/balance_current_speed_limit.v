// Current-test governor; rpm inputs are signed 0.1rpm, refreshed at 50Hz.
// 0..75% ceiling: full Iq; 75..100%: linear derating; >=ceiling: zero Iq.
// This removes drive torque only, never commands reverse braking torque.
module balance_current_speed_limit(
 input wire clk,rst_n,enable,
 input wire signed [15:0] command,rpm1,rpm2,
 input wire [15:0] ceiling,
 output reg signed [15:0] iq1,iq2,
 output wire limiting1,limiting2);
 reg [3:0] state;reg start_div;reg signed [31:0] numerator;
 reg [15:0] denominator;wire busy,valid;wire signed [31:0] quotient;
 reg signed [15:0] held_command,result1;reg [16:0] speed1,speed2;reg [15:0] held_ceiling;
 wire [16:0] abs1=rpm1[15] ? -$signed({rpm1[15],rpm1}) : {1'b0,rpm1};
 wire [16:0] abs2=rpm2[15] ? -$signed({rpm2[15],rpm2}) : {1'b0,rpm2};
 wire [15:0] band=held_ceiling>>2;
 assign limiting1=enable && command!=0 && (iq1!=command);
 assign limiting2=enable && command!=0 && (iq2!=command);
 balance_sdiv div(clk,rst_n,start_div,numerator,denominator,busy,valid,quotient);
 always @(posedge clk or negedge rst_n)
 if(!rst_n)begin state<=0;start_div<=0;numerator<=0;denominator<=1;iq1<=0;iq2<=0;held_command<=0;held_ceiling<=0;speed1<=0;speed2<=0;result1<=0;end
 else begin
  start_div<=0;
  if(!enable)begin state<=0;iq1<=command;iq2<=command;end
  else case(state)
   0:if(!busy)begin held_command<=command;held_ceiling<=ceiling;speed1<=abs1;speed2<=abs2;state<=1;end
   1:begin
    if(held_ceiling==0 || speed1>=held_ceiling)begin result1<=0;state<=3;end
    else if(speed1<=held_ceiling-band)begin result1<=held_command;state<=3;end
    else begin numerator<=$signed(held_command)*$signed({1'b0,held_ceiling-speed1[15:0]});denominator<=band;start_div<=1;state<=2;end
   end
   2:if(valid)begin result1<=quotient[15:0];state<=3;end
   3:begin
    if(held_ceiling==0 || speed2>=held_ceiling)begin iq1<=result1;iq2<=0;state<=0;end
    else if(speed2<=held_ceiling-band)begin iq1<=result1;iq2<=held_command;state<=0;end
    else begin numerator<=$signed(held_command)*$signed({1'b0,held_ceiling-speed2[15:0]});denominator<=band;start_div<=1;state<=4;end
   end
   4:if(valid)begin iq1<=result1;iq2<=quotient[15:0];state<=0;end
   default:state<=0;
  endcase
 end
endmodule
