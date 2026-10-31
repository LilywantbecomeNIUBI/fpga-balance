// CB BC / version 1 / last command seq / flags / mode / faults / payload / CRC.
// 50 Hz x 48 bytes = 24 kbit/s including 8N1, within the 115200 baud link.
module bb_telemetry #(
    parameter integer CLK_HZ=50000000,BAUD=115200,DRIVE_ENABLE=0,CPR_LEFT=60000,CPR_RIGHT=60000,M2_HEADER=0
)(
    input wire clk,reset_n,armed,config_valid,calibrated,calibrating,imu_healthy,
    input wire [7:0] mode,last_sequence,config_sequence,stop_reason,
    input wire [15:0] faults,rejected,interval_us,bad_frames,
    input wire signed [31:0] pitch,rate,left_position,right_position,left_velocity,right_velocity,speed_trim,
    input wire signed [15:0] left_applied,right_applied,
    input wire [31:0] left_invalid,right_invalid,
    input wire imu_diag_valid,input wire [383:0] imu_diag_frame,
    output wire tx
);
    integer divider;
    reg [15:0] packet_count;
    reg [367:0] body;
    reg capture;
    function automatic signed [15:0] sat16(input signed [63:0] value);
        sat16=value>32767 ? 16'sd32767 : value< -32768 ? -16'sd32768 : value[15:0];
    endfunction
    reg signed [15:0] pitch_cdeg,rate_cdeg,trim_cdeg;
    wire [7:0] status_flags={1'(M2_HEADER),1'(DRIVE_ENABLE),1'b0,imu_healthy,config_valid,calibrating,calibrated,armed};
    wire [383:0] frame;wire valid;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin divider<=0;packet_count<=0;body<=0;capture<=0;pitch_cdeg<=0;rate_cdeg<=0;trim_cdeg<=0;end
        else begin
            pitch_cdeg<=sat16(($signed(pitch)*64'sd100)>>>16);
            rate_cdeg<=sat16(($signed(rate)*64'sd100)>>>16);
            trim_cdeg<=sat16(($signed(speed_trim)*64'sd100)>>>16);
            capture<=0;
            if(divider==CLK_HZ/50-1)begin
                divider<=0;capture<=1;packet_count<=packet_count+1'b1;
                body<={packet_count,(rejected+bad_frames),interval_us,stop_reason,config_sequence,trim_cdeg,
                    right_invalid[15:0],left_invalid[15:0],right_applied,left_applied,
                    sat16(right_velocity),sat16(left_velocity),right_position,left_position,
                    rate_cdeg,pitch_cdeg,16'(CPR_RIGHT),16'(CPR_LEFT),faults,mode,status_flags,last_sequence,8'h01,8'hbc,8'hcb};
            end else divider<=divider+1;
        end
    end
    frame_crc crc(.clk(clk),.reset_n(reset_n),.capture(capture),.body_in(body),.frame(frame),.valid(valid));
    frame_uart_mux #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) uart(.clk(clk),.reset_n(reset_n),.motor_valid(valid),.motor_frame(frame),
        .imu_valid(imu_diag_valid),.imu_frame(imu_diag_frame),.aux_valid(1'b0),.aux_frame(384'b0),.tx(tx),.aux_drops(),.imu_drops());
endmodule
