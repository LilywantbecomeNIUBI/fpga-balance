// Output current in A/4096, gains in A/deg and A/(deg/s), unsigned Q24.
module balance_pd(input wire clk,rst_n,input wire signed [31:0] pitch,rate,
    input wire signed [15:0] trim_cdeg,input wire [31:0] kp,kd,
    input wire [15:0] limit_ma,output reg signed [15:0] iq);
    reg signed [31:0] target,error_q,cap;
    reg signed [31:0] rate_q;
    reg signed [63:0] p,d;
    reg signed [35:0] raw;
    // 167772/256 = 655.359375 versus exact 655.36: <0.000005 deg at +/-5 deg.
    always @(posedge clk or negedge rst_n)
    if(!rst_n) begin target<=0;error_q<=0;cap<=0;rate_q<=0;p<=0;d<=0;raw<=0;iq<=0;end
    else begin
        target<=($signed(trim_cdeg)*32'sd167772)>>>8;
        cap<=limit_ma*32'd4096/1000;
        error_q<=target-pitch;rate_q<=rate;
        p<=$signed(error_q)*$signed({1'b0,kp});d<=$signed(rate_q)*$signed({1'b0,kd});
        raw<=($signed(p)-$signed(d))>>>28;
        iq<=raw>cap ? cap[15:0] : (raw < -cap ? -cap[15:0] : raw[15:0]);
    end
endmodule
