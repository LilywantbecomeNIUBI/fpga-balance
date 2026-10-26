// 50Hz speed PI -> pitch trim, pipelined at the real 50MHz clock.
// PERIOD is a simulation accelerator only; speed units assume20ms physically.
module balance_speed #(parameter PERIOD=1000000)(
 input wire clk,rst_n,enable,reset_loop,
 input wire [13:0] angle1,angle2,input wire reverse1,reverse2,
 input wire signed [15:0] target,input wire [7:0] kp,ki,
 output reg signed [15:0] rpm1,rpm2,trim_cdeg);
 reg [31:0] ticks;reg [13:0] prev1,prev2;reg primed,rev1,rev2;
 reg signed [13:0] delta1,delta2;
 reg signed [31:0] product1,product2,v1,v2,error,integral,p_product,i_product,next_i,p_term,total;
 reg signed [15:0] goal;reg [7:0] kp_hold,ki_hold;reg [3:0] state;
 reg div_start;reg signed [31:0] div_n;reg [15:0] div_d;wire div_busy,div_valid;wire signed [31:0] div_q;
 balance_sdiv divider(clk,rst_n,div_start,div_n,div_d,div_busy,div_valid,div_q);
 function signed [31:0] trunc14(input signed [31:0] value);
  trunc14=value<0 ? -((-value)>>>14) : value>>>14;
 endfunction
 always @(posedge clk or negedge rst_n)
 if(!rst_n)begin
  ticks<=0;prev1<=0;prev2<=0;primed<=0;integral<=0;rpm1<=0;rpm2<=0;trim_cdeg<=0;
  delta1<=0;delta2<=0;product1<=0;product2<=0;v1<=0;v2<=0;error<=0;p_product<=0;i_product<=0;
  next_i<=0;p_term<=0;total<=0;goal<=0;kp_hold<=0;ki_hold<=0;rev1<=0;rev2<=0;
  state<=0;div_start<=0;div_n<=0;div_d<=1;
 end else begin
  div_start<=0;
  if(ticks==PERIOD-1)begin
   ticks<=0;prev1<=angle1;prev2<=angle2;primed<=1;
   if(primed && state==0 && !div_busy)begin
    delta1<=angle1-prev1;delta2<=angle2-prev2;rev1<=reverse1;rev2<=reverse2;
    goal<=target;kp_hold<=kp;ki_hold<=ki;state<=1;
   end
  end else ticks<=ticks+1'b1;
  case(state)
   1:begin product1<=$signed(delta1)*32'sd30000;product2<=$signed(delta2)*32'sd30000;state<=2;end
   2:begin v1<=rev1 ? -trunc14(product1) : trunc14(product1);v2<=rev2 ? -trunc14(product2) : trunc14(product2);state<=3;end
   3:begin rpm1<=v1;rpm2<=v2;error<=$signed(goal)-(v1+v2)/2;state<=enable ? 4 : 0;end
   4:begin p_product<=error*$signed({1'b0,kp_hold});i_product<=error*$signed({1'b0,ki_hold});state<=5;end
   5:begin
    next_i<=(integral+i_product)>1500000 ? 1500000 : (integral+i_product)< -1500000 ? -1500000 : integral+i_product;
    div_n<=p_product;div_d<=100;div_start<=1;state<=6;
   end
   6:if(div_valid)begin p_term<=div_q;div_n<=next_i;div_d<=5000;div_start<=1;state<=7;end
   7:if(div_valid)begin total<=p_term+div_q;state<=8;end
   8:begin
    if((total<=300 && total>=-300)||(total>300 && error<0)||(total< -300 && error>0))integral<=next_i;
    trim_cdeg<=total>300 ? 300 : total< -300 ? -300 : total;state<=0;
   end
  endcase
  if(reset_loop || !enable)begin integral<=0;trim_cdeg<=0;if(state>=4)state<=0;end
 end
endmodule
