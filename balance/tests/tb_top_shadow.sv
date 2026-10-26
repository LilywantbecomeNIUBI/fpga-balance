`timescale 1ns/1ps
// Forced internal stimuli exercise integration only, never a physical motor model.
module tb_top_shadow;
 reg clk=0;always #10 clk=~clk;reg rst=0;
 wire [11:0] pwm;wire en1,en2,cal1,cal2;tri1 scl,sda;
 balance_top #(.ALLOW_DRIVE(0)) dut(.clk50m(clk),.reset_n(rst),.uart_rx(1'b1),
 .m1_pwm_ah(pwm[0]),.m1_pwm_al(pwm[1]),.m1_pwm_bh(pwm[2]),.m1_pwm_bl(pwm[3]),.m1_pwm_ch(pwm[4]),.m1_pwm_cl(pwm[5]),
 .m2_pwm_ah(pwm[6]),.m2_pwm_al(pwm[7]),.m2_pwm_bh(pwm[8]),.m2_pwm_bl(pwm[9]),.m2_pwm_ch(pwm[10]),.m2_pwm_cl(pwm[11]),
 .m1_drv_en(en1),.m2_drv_en(en2),.m1_cal(cal1),.m2_cal(cal2),.m1_fault_n(1'b1),.m2_fault_n(1'b1),
 .adc_busy(1'b0),.adc_dout_a(1'b0),.adc_dout_b(1'b0),.enc1_do(1'b0),.enc2_do(1'b0),.imu_i2c_scl(scl),.imu_i2c_sda(sda));
 reg [255:0] cfg=0;
 initial begin
 repeat(4)@(negedge clk);rst=1;repeat(4)@(negedge clk);
 cfg[221:220]=3;cfg[63:32]=1677722;cfg[159:144]=100;
 force dut.cfg=cfg;force dut.pitch=0;force dut.rate=0;force dut.av=0;force dut.cv=0;
 // Even a forced active control signal cannot bypass observation pin grounding.
 force dut.active=1;repeat(10)@(negedge clk);
 force dut.pitch=65536;force dut.av=1;@(negedge clk);force dut.av=0;
 repeat(12)@(negedge clk);
 if(dut.drive.commands.target_1!=-409 || dut.drive.commands.target_2!=-409)
 $fatal(1,"PD valid pipeline captured old output %d %d",dut.drive.commands.target_1,dut.drive.commands.target_2);
 if(dut.drive.CURRENT_REVERSE!=7 || dut.drive.GAIN_CH3_Q16!=217082 || dut.drive.GAIN_CH4_Q16!=220767)$fatal(1,"bench polarity/gains lost");
 cfg[217:216]=1;cfg[221:220]=2;cfg[239:224]=50;
 force dut.changed=1;@(negedge clk);force dut.changed=0;repeat(40)@(negedge clk);
 force dut.av=1;@(negedge clk);force dut.av=0;repeat(12)@(negedge clk);
 if(dut.drive.commands.target_1!=0 || dut.drive.commands.target_2!=204)$fatal(1,"M2 current mode routing");
 cfg[28]=1;force dut.av=1;@(negedge clk);force dut.av=0;repeat(12)@(negedge clk);
 if(dut.drive.commands.target_2!=-204)$fatal(1,"torque direction independent of Hall polarity");
 force dut.pwm=12'hfff;force dut.en=3;#1;
 if(pwm || en1 || en2 || cal1 || cal2)$fatal(1,"observation output inhibit bypassed");
 $display("PASS integrated PD publication timing and physical observe pin inhibit");$finish;
 end
 initial begin #200000;$fatal(1,"timeout");end
endmodule
