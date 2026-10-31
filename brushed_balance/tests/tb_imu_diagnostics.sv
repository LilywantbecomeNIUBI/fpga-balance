`timescale 1ns/1ps
module tb_imu_diagnostics;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,scl=1,sda=0;
    wire [383:0] frame;wire valid,tx;
    bb_imu_diagnostics #(.CLK_HZ(1000000)) diag(.clk(clk),.reset_n(reset_n),.scl(scl),.sda(sda),
        .ready(1'b0),.fault(1'b1),.stale(1'b1),.temperature_valid(1'b0),.who_am_i(8'h47),.last_error(8'h01),
        .sample_seq(32'd123),.sample_age_us(32'd4000),.now_us(32'd9999),.commit_us(32'd5999),.error_count(16'd7),.invalid_count(16'd2),
        .ax(16'sd0),.ay(16'sd4096),.az(-16'sd8192),.gx(16'sd33),.gy(-16'sd66),.gz(16'sd99),.frame(frame),.valid(valid));
    bb_telemetry #(.CLK_HZ(1000000),.BAUD(100000)) sender(.clk(clk),.reset_n(reset_n),
        .armed(1'b0),.config_valid(1'b0),.calibrated(1'b0),.calibrating(1'b0),.imu_healthy(1'b0),.mode(8'd0),
        .last_sequence(8'd0),.config_sequence(8'd0),.stop_reason(8'd0),.faults(16'd1),.rejected(16'd0),.interval_us(16'd0),.bad_frames(16'd0),
        .pitch(32'sd0),.rate(32'sd0),.left_position(32'sd0),.right_position(32'sd0),.left_velocity(32'sd0),.right_velocity(32'sd0),
        .speed_trim(32'sd0),.left_applied(16'sd0),.right_applied(16'sd0),.left_invalid(32'd0),.right_invalid(32'd0),
        .imu_diag_valid(valid),.imu_diag_frame(frame),.tx(tx));
    wire [7:0] data;wire rx_valid,framing_error;
    uart_rx_byte #(.CLK_HZ(1000000),.BAUD(100000)) rx(.clk(clk),.reset_n(reset_n),.rx(tx),.data(data),.valid(rx_valid),.framing_error(framing_error));
    integer file,captures=0;
    always @(negedge clk)begin
        if(framing_error)$fatal(1,"mixed telemetry framing");
        if(rx_valid)$fwrite(file,"%c",data);
        if(valid)begin
            if(frame[0+:24]!=24'h01bdcb)$fatal(1,"diagnostic magic");
            if(frame[160+:16]!=0)$fatal(1,"SCL stuck-high accounting");
            if(captures==0 && frame[176+:16]!=1000)$fatal(1,"SDA stuck-low accounting");
            if(captures==1 && frame[176+:16]!=0)$fatal(1,"line recovery window");
            captures=captures+1;sda=1;
        end
    end
    initial begin
        file=$fopen("build/tests/imu_mux.bin","wb");repeat(5)@(negedge clk);reset_n=1;
        repeat(440000)@(negedge clk);
        if(captures!=2)$fatal(1,"diagnostic frame rate");
        $fclose(file);$display("PASS read-only IMU diagnostics: line stuck/recovery counters and status+diagnostic UART arbitration");$finish;
    end
endmodule
