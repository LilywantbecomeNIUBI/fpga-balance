// MT6701 Rev1.8 sec7.8: 14 angle + 4 status + CRC6 x^6+x+1,
// MSB first, SPI mode 1. Only complete CRC/status-valid frames are published.
module motor_mt6701 #(parameter HALF_CYCLES=25)(
    input wire clk, rst_n, trigger, din,
    output wire cs_n, sclk, busy,
    output reg valid, fault,
    output reg [13:0] angle,
    output reg [3:0] status,
    output reg [31:0] sample_time
);
    reg [31:0] clock_count;
    // CS falls at this acceptance edge in motor_serial_rx. AD7606 uses the
    // same free-running counter/reset origin, so the epochs are comparable.
    always @(posedge clk or negedge rst_n)
        if(!rst_n) begin clock_count<=0;sample_time<=0;end
        else begin
            clock_count<=clock_count+1;
            if(trigger && !busy) sample_time<=clock_count;
        end
    wire done, overrun;
    wire [23:0] data, unused;
    function [5:0] crc6;
        input [17:0] payload;
        reg [5:0] crc;
        integer bit_index;
        begin
            crc=0;
            for(bit_index=17;bit_index>=0;bit_index=bit_index-1)
                if(crc[5]^payload[bit_index]) crc={crc[4:0],1'b0}^6'h03;
                else crc={crc[4:0],1'b0};
            crc6=crc;
        end
    endfunction
    motor_serial_rx #(.BITS(24),.HALF_CYCLES(HALF_CYCLES),.IDLE_HIGH(0),
                     .CS_SETUP(10),.CS_HOLD(HALF_CYCLES+5)) rx(
        .clk(clk),.rst_n(rst_n),.start(trigger),.din_a(din),.din_b(1'b0),
        .cs_n(cs_n),.sclk(sclk),.busy(busy),.done(done),.overrun(overrun),
        .data_a(data),.data_b(unused));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin valid<=0; fault<=0; angle<=0; status<=0; end
        else begin
            valid<=0; fault<=overrun;
            if(done) begin
                status<=data[9:6];
                // Reject weak/strong/invalid field, push and overspeed status.
                if(crc6(data[23:6])!=data[5:0] || data[9:6]!=0) fault<=1;
                else begin angle<=data[23:10]; valid<=1; end
            end
        end
    end
endmodule
