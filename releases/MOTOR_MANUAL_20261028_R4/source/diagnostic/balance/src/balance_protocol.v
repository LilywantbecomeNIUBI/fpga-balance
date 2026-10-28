// @ + 64 hex characters + * + CRC16-CCITT (4 hex) + LF.
// CRC covers the 32 decoded bytes. Invalid/partial frames never mutate config.
module balance_protocol(input wire clk,rst_n,byte_valid,input wire [7:0] byte_value,
    input wire can_configure,invalidate,
    output reg command_valid,output reg [7:0] command,
    output reg configured,config_changed,
    output reg [255:0] config_body,
    output reg [7:0] ack_seq,result,
    output reg [15:0] rx_errors);
    reg [7:0] pos;
    reg [255:0] body;
    reg [15:0] crc,received_crc;
    reg [3:0] high_nibble;
    reg [19:0] idle_count;
    function [4:0] hex(input [7:0] c);
        if(c>="0" && c<="9") hex=c-"0";
        else if(c>="a" && c<="f") hex=c-"a"+10;
        else if(c>="A" && c<="F") hex=c-"A"+10;
        else hex=31;
    endfunction
    function [15:0] crc_byte(input [15:0] c,input [7:0] b);
        reg [15:0] v;integer i;begin v=c^{b,8'd0};for(i=0;i<8;i=i+1) v=v[15] ? (v<<1)^16'h1021 : v<<1;crc_byte=v;end
    endfunction
    wire [4:0] nibble=hex(byte_value);
    wire [7:0] opcode=body[23:16];
    // Orientation is fixed for this vehicle; reject old/incompatible profiles.
    wire valid_config=body[7:0]==2 && body[26:24]==3'b011 && body[63:32]<=32'd8388608 && body[95:64]<=32'd1677722 &&
        body[111:96]<=16384 && body[127:112]<=256 &&
        $signed(body[143:128])>=-500 && $signed(body[143:128])<=500 &&
        body[159:144]>0 && body[159:144]<=1000 &&
        body[175:160]>=500 && body[175:160]<=1500 &&
        body[191:176]>0 && body[191:176]<=500 && body[191:176]<body[175:160] &&
        body[207:192]>=100 && body[207:192]<=5000 &&
        body[215:208]>=4 && body[215:208]<=10 && body[217:216]<=2 && body[219:218]==2'b01 && body[223:222]==0 &&
        (body[217:216]!=1 || (body[221:220]!=0 && $signed(body[239:224])<= $signed({1'b0,body[159:144]}) &&
          $signed(body[239:224])>= -$signed({1'b0,body[159:144]}))) &&
        (body[217:216]!=2 || ($signed(body[239:224])>=-600 && $signed(body[239:224])<=600));
    always @(posedge clk or negedge rst_n)
    if(!rst_n) begin pos<=0;body<=0;crc<=16'hffff;received_crc<=0;high_nibble<=0;
        command_valid<=0;command<=0;configured<=0;config_changed<=0;config_body<=0;ack_seq<=0;result<=0;rx_errors<=0;idle_count<=0;end
    else begin
        command_valid<=0;config_changed<=0;
        if(invalidate) configured<=0;
        if(pos!=0) begin
            if(idle_count==999999) begin pos<=0;rx_errors<=rx_errors+1'b1;end
            else idle_count<=idle_count+1'b1;
        end
        if(byte_valid) begin
            idle_count<=0;
            if(byte_value=="@") begin pos<=1;body<=0;crc<=16'hffff;received_crc<=0;end
            else if(byte_value=="X") begin pos<=0;command<=8'd1;command_valid<=1;end
            else if(pos>=1 && pos<=64 && nibble!=31) begin
                if(pos[0]) high_nibble<=nibble[3:0];
                else begin body[((pos/2)-1)*8+:8]<={high_nibble,nibble[3:0]};crc<=crc_byte(crc,{high_nibble,nibble[3:0]});end
                pos<=pos+1'b1;
            end else if(pos==65 && byte_value=="*") pos<=66;
            else if(pos>=66 && pos<=69 && nibble!=31) begin received_crc<={received_crc[11:0],nibble[3:0]};pos<=pos+1'b1;end
            else if(pos==70 && byte_value==10 && crc==received_crc && body[7:0]==2) begin
                pos<=0;ack_seq<=body[15:8];result<=0;
                if(opcode==8) begin
                    if(can_configure && valid_config) begin config_body<=body;configured<=1;config_changed<=1;end
                    else result<=can_configure ? 2 : 3;
                end else if(((opcode<=7 && opcode!=5) || opcode==9 || opcode==10) && body[255:24]==0) begin command<=opcode;command_valid<=1;end
                else result<=2;
            end else begin
                if(pos!=0) rx_errors<=rx_errors+1'b1;
                pos<=0;
            end
        end
    end
endmodule
