// 14-bit mechanical angle -> unsigned full-turn 16-bit electrical angle.
module motor_angle(
    input wire [13:0] mechanical, zero,
    input wire [7:0] pole_pairs,
    input wire reverse,
    output wire [15:0] electrical
);
    wire [13:0] delta=reverse ? zero-mechanical : mechanical-zero;
    wire [21:0] product=delta*pole_pairs;
    assign electrical={product[13:0],2'b00};
endmodule
