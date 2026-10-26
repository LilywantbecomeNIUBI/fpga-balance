// Iterative vectoring CORDIC. Signed Q16 degrees; input raw acceleration.
module balance_atan(input wire clk,rst_n,start,
    input wire signed [16:0] x_in,y_in,
    output reg valid,output reg signed [31:0] angle);
    reg signed [35:0] x,y;
    reg signed [31:0] z;
    reg [4:0] step;
    reg busy;
    function signed [31:0] lut(input [4:0] i);
        case(i)
        0:lut=2949120;1:lut=1740967;2:lut=919879;3:lut=466945;
        4:lut=234379;5:lut=117304;6:lut=58666;7:lut=29335;
        8:lut=14668;9:lut=7334;10:lut=3667;11:lut=1833;
        12:lut=917;13:lut=458;14:lut=229;default:lut=115;
        endcase
    endfunction
    always @(posedge clk or negedge rst_n)
    if(!rst_n) begin x<=0;y<=0;z<=0;step<=0;busy<=0;valid<=0;angle<=0;end
    else begin
        valid<=0;
        if(start && !busy) begin
            // Preserve fractional precision during the last iterations.
            x<=x_in<0 ? -($signed(x_in)*36'sd65536) : $signed(x_in)*36'sd65536;
            y<=x_in<0 ? -($signed(y_in)*36'sd65536) : $signed(y_in)*36'sd65536;
            z<=x_in<0 ? (y_in<0 ? -32'sd11796480 : 32'sd11796480) : 0;
            step<=0;busy<=1;
        end else if(busy) begin
            if(y>0) begin x<=x+(y>>>step);y<=y-(x>>>step);z<=z+lut(step);end
            else begin x<=x-(y>>>step);y<=y+(x>>>step);z<=z-lut(step);end
            if(step==15) begin busy<=0;valid<=1;angle<=y>0 ? z+lut(step) : z-lut(step);end
            else step<=step+1'b1;
        end
    end
endmodule
