// AD7606-F4 dual-DOUT adapter; protocol reference: local ACG720 ch62
// (CONVST/BUSY/atomic channels) and ADI AD7606 serial-interface timing.
// Module must be strapped PAR/SER=1, DB15=0, RANGE=0, OS=000, VDRIVE=3.3V.
module motor_ad7606 #(
    parameter HALF_CYCLES=5, RESET_CYCLES=50, SETTLE_CYCLES=50,
              CONV_LOW_CYCLES=5, BUSY_TIMEOUT=1000
)(
    input wire clk, rst_n, trigger, adc_busy, dout_a, dout_b,
    output reg convst, adc_reset,
    output wire cs_n, sclk,
    output wire busy,
    output reg ready, sample_started, valid, fault,
    output reg [127:0] channels,
    output reg [31:0] sample_time
);
    localparam RESET=0, SETTLE=1, IDLE=2, CONV=3, WAIT_HIGH=4,
               WAIT_LOW=5, READ=6, FAILED=7;
    reg [2:0] state;
    reg [31:0] count, clock_count;
    reg [1:0] busy_sync;
    reg serial_start;
    wire serial_busy, serial_done, serial_overrun;
    wire [63:0] a,b;
    assign busy = state!=IDLE;
    motor_serial_rx #(.BITS(64),.HALF_CYCLES(HALF_CYCLES),.IDLE_HIGH(1)) rx(
        .clk(clk),.rst_n(rst_n),.start(serial_start),.din_a(dout_a),.din_b(dout_b),
        .cs_n(cs_n),.sclk(sclk),.busy(serial_busy),.done(serial_done),
        .overrun(serial_overrun),.data_a(a),.data_b(b));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin busy_sync<=0; clock_count<=0; end
        else begin busy_sync<={busy_sync[0],adc_busy}; clock_count<=clock_count+1; end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=RESET; count<=0; convst<=1; adc_reset<=1;
            ready<=0; valid<=0; sample_started<=0; fault<=0;
            serial_start<=0; channels<=0; sample_time<=0;
        end else begin
            valid<=0; sample_started<=0; serial_start<=0;
            if(trigger && ready && state!=IDLE) begin fault<=1; state<=FAILED; end
            else case(state)
                RESET: if(count==RESET_CYCLES-1) begin
                    count<=0; adc_reset<=0; state<=SETTLE;
                end else count<=count+1;
                SETTLE: if(count==SETTLE_CYCLES-1) begin
                    count<=0; ready<=1; state<=IDLE;
                end else count<=count+1;
                IDLE: if(trigger) begin
                    if(busy_sync[1]) begin fault<=1; state<=FAILED; end
                    else begin convst<=0; count<=0; state<=CONV; end
                end
                CONV: if(count==CONV_LOW_CYCLES-1) begin
                    convst<=1; sample_started<=1; sample_time<=clock_count;
                    count<=0; state<=WAIT_HIGH;
                end else count<=count+1;
                WAIT_HIGH: if(busy_sync[1]) begin count<=0; state<=WAIT_LOW; end
                    else if(count==BUSY_TIMEOUT-1) begin fault<=1; state<=FAILED; end
                    else count<=count+1;
                WAIT_LOW: if(!busy_sync[1]) begin
                    count<=0; serial_start<=1; state<=READ;
                end else if(count==BUSY_TIMEOUT-1) begin fault<=1; state<=FAILED; end
                    else count<=count+1;
                READ: if(serial_done) begin
                    // packed little channel index: CH1=[15:0], CH8=[127:112].
                    channels<={b[15:0],b[31:16],b[47:32],b[63:48],
                               a[15:0],a[31:16],a[47:32],a[63:48]};
                    valid<=1; state<=IDLE;
                end
                FAILED: begin ready<=0; convst<=1; end
                default: begin state<=FAILED; fault<=1; ready<=0; end
            endcase
        end
    end
endmodule
