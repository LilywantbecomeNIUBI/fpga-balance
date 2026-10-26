// Snapshot 126 bytes, append CRC16 LE; motor_console adds legacy XOR byte.
// CRC is sequential, keeping long checksum logic out of the 50 MHz timing cone.
module balance_telemetry #(parameter PERIOD=250000)(input wire clk,rst_n,
    input wire [1007:0] data,output reg [1023:0] packet);
    reg [31:0] timer;
    reg [1007:0] snapshot;
    reg [7:0] index;
    reg [15:0] crc;
    reg busy;
    function [15:0] next_crc(input [15:0] c,input [7:0] b);
        reg [15:0] v;integer i;begin v=c^{b,8'd0};for(i=0;i<8;i=i+1) v=v[15] ? (v<<1)^16'h1021 : v<<1;next_crc=v;end
    endfunction
    wire [15:0] updated=next_crc(crc,snapshot[index*8+:8]);
    always @(posedge clk or negedge rst_n)
    if(!rst_n) begin timer<=0;snapshot<=0;index<=0;crc<=16'hffff;busy<=0;packet<=0;end
    else begin
        if(timer==PERIOD-1) timer<=0;else timer<=timer+1'b1;
        if(timer==1000) begin snapshot<=data;index<=0;crc<=16'hffff;busy<=1;end
        else if(busy) begin
            crc<=updated;
            if(index==125) begin packet<={updated,snapshot};busy<=0;end
            else index<=index+1'b1;
        end
    end
endmodule
