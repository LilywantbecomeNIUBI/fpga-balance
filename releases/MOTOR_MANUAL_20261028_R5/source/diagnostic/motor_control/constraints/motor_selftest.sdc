create_clock -name sys50 -period 20 [get_ports {clk50m}]
# Asynchronous external events: only RX/BUSY/FAULT synchronizers and reset/kill.
# Physical nFAULT also has an intentional asynchronous output kill path.
set_false_path -from [get_ports {reset_n uart_rx adc_busy m1_fault_n m2_fault_n}]
# Source-synchronous serial receivers use scheduled CE sampling in a 50MHz
# domain, not SCLK as an internal clock. Board round-trip budgets are verified
# separately by tools/check_serial_budget.py; these are not synchronous inputs
# with a 20ns setup requirement. Do not describe these exceptions as I/O closure.
set_false_path -from [get_ports {adc_dout_a adc_dout_b enc1_do enc2_do}]
# 10ns clock-to-pad budget. This bounds SCLK/CS/PWM/CONVST path skew and is
# included in the serial round-trip budget; it is not an external latch model.
set_output_delay -clock sys50 -max 10 [get_ports {adc_convst adc_reset adc_cs_n adc_sclk enc1_cs_n enc1_clk enc2_cs_n enc2_clk}]
set_output_delay -clock sys50 -min 0 [get_ports {adc_convst adc_reset adc_cs_n adc_sclk enc1_cs_n enc1_clk enc2_cs_n enc2_clk}]
# Driver PWM/EN are asynchronous level inputs. Require clock-to-pad <= one
# 20ns system cycle (max=0 consumes none of that cycle at an external latch).
# The combinational asynchronous fault kill is preserved, not registered away.
set_output_delay -clock sys50 -max 0 [get_ports {m1_pwm_* m2_pwm_* m1_drv_en m2_drv_en m1_cal m2_cal}]
set_output_delay -clock sys50 -min 0 [get_ports {m1_pwm_* m2_pwm_* m1_drv_en m2_drv_en m1_cal m2_cal}]
# Static auxiliary pins/status UART have no synchronous board receiver.
set_false_path -to [get_ports {led[*] uart_tx lidar_uart_tx lidar_moto_pwm imu_i2c_scl imu_i2c_sda}]
