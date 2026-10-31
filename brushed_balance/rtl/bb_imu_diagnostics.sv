// Read-only, 5 Hz CB BD 01 packets; no feedback into sensor or drive control.
// Low counts sample the two synchronized pins at 1 kHz over a 200ms window.
// They diagnose stuck levels, not analog rise time or I2C signal integrity.
module bb_imu_diagnostics #(parameter integer CLK_HZ=50000000)(
    input wire clk,reset_n,scl,sda,ready,fault,stale,temperature_valid,
    input wire [7:0] who_am_i,last_error,
    input wire [31:0] sample_seq,sample_age_us,now_us,commit_us,
    input wire [15:0] error_count,invalid_count,
    input wire signed [15:0] ax,ay,az,gx,gy,gz,
    output wire [383:0] frame,output wire valid
);
    (* syn_preserve=1 *) reg [1:0] line_meta,line_sync;
    reg [7:0] sample_count,scl_low,sda_low;
    reg [15:0] sequence_id;
    integer divider;
    reg [367:0] body;
    reg capture;
    wire [7:0] flags={2'b0,line_sync,temperature_valid,stale,fault,ready};
    wire [15:0] scl_low_permille=16'((scl_low+(line_sync[1] ? 0 : 1))*5);
    wire [15:0] sda_low_permille=16'((sda_low+(line_sync[0] ? 0 : 1))*5);
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            line_meta<=3;line_sync<=3;sample_count<=0;scl_low<=0;sda_low<=0;sequence_id<=0;
            divider<=0;body<=0;capture<=0;
        end else begin
            line_meta<={scl,sda};line_sync<=line_meta;capture<=0;
            if(divider==CLK_HZ/1000-1)begin
                divider<=0;
                if(sample_count==199)begin
                    sample_count<=0;scl_low<=0;sda_low<=0;sequence_id<=sequence_id+1'b1;capture<=1;
                    body<={sequence_id,commit_us,now_us,gz,gy,gx,az,ay,ax,sda_low_permille,scl_low_permille,
                        invalid_count,error_count,sample_age_us,sample_seq,8'h00,8'h69,flags,who_am_i,last_error,8'h01,8'hbd,8'hcb};
                end else begin
                    sample_count<=sample_count+1'b1;
                    if(!line_sync[1])scl_low<=scl_low+1'b1;
                    if(!line_sync[0])sda_low<=sda_low+1'b1;
                end
            end else divider<=divider+1;
        end
    end
    frame_crc crc(.clk(clk),.reset_n(reset_n),.capture(capture),.body_in(body),.frame(frame),.valid(valid));
endmodule
