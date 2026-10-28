// 32-step signed division, truncates toward zero. No combinational divider.
module balance_sdiv(input wire clk,rst_n,start,input wire signed [31:0] numerator,
 input wire [15:0] denominator,output reg busy,valid,output reg signed [31:0] quotient);
 reg [31:0] dividend,q;reg [16:0] remainder;reg [15:0] divisor;
 reg negative;reg [5:0] count;
 wire [16:0] shifted={remainder[15:0],dividend[31]};
 wire take=shifted>={1'b0,divisor};
 wire [31:0] q_next={q[30:0],take};
 always @(posedge clk or negedge rst_n)
 if(!rst_n)begin busy<=0;valid<=0;quotient<=0;dividend<=0;q<=0;remainder<=0;divisor<=1;negative<=0;count<=0;end
 else begin
  valid<=0;
  if(start && !busy)begin
   dividend<=numerator[31] ? -numerator : numerator;negative<=numerator[31];
   divisor<=denominator==0 ? 1 : denominator;remainder<=0;q<=0;count<=0;busy<=1;
  end else if(busy)begin
   dividend<=dividend<<1;remainder<=take ? shifted-{1'b0,divisor} : shifted;q<=q_next;
   if(count==31)begin quotient<=negative ? -$signed(q_next) : $signed(q_next);valid<=1;busy<=0;end
   else count<=count+1'b1;
  end
 end
endmodule
