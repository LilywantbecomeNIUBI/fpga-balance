`timescale 1ns/1ps
module tb_telemetry;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0;wire tx;
    bb_telemetry #(.CLK_HZ(1000000),.BAUD(100000),.DRIVE_ENABLE(1),.M2_HEADER(1)) dut(
        .clk(clk),.reset_n(reset_n),.armed(1'b0),.config_valid(1'b1),.calibrated(1'b1),.calibrating(1'b0),.imu_healthy(1'b1),
        .mode(8'd3),.last_sequence(8'd9),.config_sequence(8'd4),.stop_reason(8'd0),.faults(16'd0),.rejected(16'd2),
        .interval_us(16'd998),.bad_frames(16'd1),.pitch(32'sd163840),.rate(-32'sd212992),.left_position(-32'sd123),
        .right_position(32'sd456),.left_velocity(32'sd10),.right_velocity(-32'sd20),.speed_trim(32'sd32768),
        .left_applied(16'sd30),.right_applied(-16'sd40),.left_invalid(32'd7),.right_invalid(32'd8),
        .imu_diag_valid(1'b0),.imu_diag_frame(384'b0),.tx(tx));
    wire [7:0] data;wire valid,framing_error;
    uart_rx_byte #(.CLK_HZ(1000000),.BAUD(100000)) receiver(.clk(clk),.reset_n(reset_n),.rx(tx),.data(data),.valid(valid),.framing_error(framing_error));
    integer file,n=0;
    always @(negedge clk)begin
        if(framing_error)$fatal(1,"TX framing");
        if(valid)begin
            $fwrite(file,"%c",data);n=n+1;
            if(n==48)begin $fclose(file);$display("PASS coherent 48-byte UART telemetry captured for independent Python decoder");$finish;end
        end
    end
    initial begin file=$fopen("build/tests/telemetry.bin","wb");repeat(5)@(negedge clk);reset_n=1;end
    initial begin #1000000;$fatal(1,"telemetry timeout");end
endmodule
