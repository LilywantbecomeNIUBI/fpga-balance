// UART bytes/valid are synchronous. Never feed their combinational decode into
// an asynchronous SET pin: inter-bit skew can transiently decode X/R when a
// legitimate command changes. Register one complete valid command first.
module motor_host_estop(
    input wire clk,rst_n,command_valid,
    input wire [7:0] command,
    output reg estop
);
    always @(posedge clk or negedge rst_n)
        if(!rst_n) estop<=0;
        else estop<=command_valid && (command=="X" || command=="R");
endmodule
