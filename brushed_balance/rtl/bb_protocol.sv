// Unique 48-byte protocol. Not compatible with the old FOC or motor console.
// B6 6B, version=1, opcode, sequence, reserved=0, 40-byte payload, CRC16 LE.
module bb_protocol #(parameter integer CLK_HZ=50000000)(
    input wire clk,reset_n,byte_valid,framing_error,
    input wire [7:0] byte_data,
    output reg command_valid,
    output reg [7:0] opcode,sequence_id,
    output reg [319:0] payload,
    output reg [15:0] bad_frames
);
    reg [367:0] body;
    reg [5:0] index;
    reg [15:0] crc;
    reg [7:0] crc_low;
    integer idle_cycles;
    function automatic [15:0] update_crc(input [15:0] old,input [7:0] value);
        reg [15:0] c;integer n;
        begin c=old^{value,8'b0};for(n=0;n<8;n=n+1)c=c[15]?(c<<1)^16'h1021:c<<1;update_crc=c;end
    endfunction
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin body<=0;index<=0;crc<=16'hffff;crc_low<=0;idle_cycles<=0;
            command_valid<=0;opcode<=0;sequence_id<=0;payload<=0;bad_frames<=0;end
        else begin
            command_valid<=0;
            if(framing_error || (index!=0 && idle_cycles>=CLK_HZ/50))begin
                index<=0;idle_cycles<=0;bad_frames<=bad_frames+1'b1;
            end else if(byte_valid)begin
                idle_cycles<=0;
                case(index)
                    0:if(byte_data==8'hb6)begin body[0+:8]<=byte_data;crc<=update_crc(16'hffff,byte_data);index<=1;end
                    1:if(byte_data==8'h6b)begin body[8+:8]<=byte_data;crc<=update_crc(crc,byte_data);index<=2;end
                      else if(byte_data==8'hb6)begin crc<=update_crc(16'hffff,byte_data);end
                      else index<=0;
                    46:begin crc_low<=byte_data;index<=47;end
                    47:begin
                        index<=0;
                        if({byte_data,crc_low}==crc && body[16+:8]==1 && body[40+:8]==0)begin
                            opcode<=body[24+:8];sequence_id<=body[32+:8];payload<=body[48+:320];command_valid<=1;
                        end else bad_frames<=bad_frames+1'b1;
                    end
                    default:begin body[index*8+:8]<=byte_data;crc<=update_crc(crc,byte_data);index<=index+1'b1;end
                endcase
            end else if(index!=0)idle_cycles<=idle_cycles+1;
        end
    end
endmodule
