// Order names describe the IP phase delivered to physical driver A/B/C.
// Always move a high/low pair together; never invert either gate waveform.
module motor_pwm_permutation(
    input wire [5:0] pwm_in,
    input wire [2:0] order,
    output reg [5:0] pwm_out,
    output wire valid
);
    assign valid=order<6;
    always @* begin
        case(order)
            0:pwm_out={pwm_in[5:4],pwm_in[3:2],pwm_in[1:0]}; // ABC
            1:pwm_out={pwm_in[3:2],pwm_in[5:4],pwm_in[1:0]}; // ACB
            2:pwm_out={pwm_in[5:4],pwm_in[1:0],pwm_in[3:2]}; // BAC
            3:pwm_out={pwm_in[1:0],pwm_in[5:4],pwm_in[3:2]}; // BCA
            4:pwm_out={pwm_in[3:2],pwm_in[1:0],pwm_in[5:4]}; // CAB
            5:pwm_out={pwm_in[1:0],pwm_in[3:2],pwm_in[5:4]}; // CBA
            default:pwm_out=0;
        endcase
    end
endmodule

// Twelve complete candidates: 0..5 are CB, 6..11 are BC. UART tokens
// 0..9,a,b do not overlap the uppercase lifecycle/stop commands.
module motor_pwm_current_candidate(
    input wire clk,rst_n,command_valid,can_select,disarmed,
    input wire [7:0] command,
    output reg [3:0] candidate,
    output reg selected,rejected
);
    wire token=(command>="0" && command<="9") || command=="a" || command=="b";
    wire [3:0] decoded=command=="a" ? 4'd10 : (command=="b" ? 4'd11 : 4'(command-"0"));
    always @(posedge clk or negedge rst_n)
        if(!rst_n) begin candidate<=15;selected<=0;rejected<=0;end
        else if(command_valid && command=="R" && disarmed) begin candidate<=15;selected<=0;rejected<=0;end
        else if(command_valid && token) begin
            if(can_select && !selected) begin candidate<=decoded;selected<=1;end
            else rejected<=1;
        end
endmodule

// One selection per explicit disarmed reset/clear. UART digits are accepted
// only outside a CRC packet by the existing protocol decoder.
module motor_pwm_candidate(
    input wire clk,rst_n,command_valid,can_select,disarmed,
    input wire [7:0] command,
    output reg [2:0] order,
    output reg selected,rejected
);
    always @(posedge clk or negedge rst_n)
        if(!rst_n) begin order<=7;selected<=0;rejected<=0;end
        else if(command_valid && command=="R" && disarmed) begin order<=7;selected<=0;rejected<=0;end
        else if(command_valid && command>="0" && command<="5") begin
            if(can_select && !selected) begin order<=3'(command-"0");selected<=1;end
            else rejected<=1;
        end
endmodule
