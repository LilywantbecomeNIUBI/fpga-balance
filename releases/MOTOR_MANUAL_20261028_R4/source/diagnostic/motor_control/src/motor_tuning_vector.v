// Independent post-slew M1 d/q envelope. Preserve |Id|+|Iq| <= LIMIT.
// This conservative bound also bounds the Euclidean vector magnitude.
module motor_tuning_vector #(parameter LIMIT=1024)(
    input wire signed [15:0] id_in,iq_in,
    output wire signed [15:0] id_out,iq_out
);
    assign iq_out=iq_in>LIMIT ? 16'(LIMIT) : (iq_in< -LIMIT ? -16'(LIMIT) : iq_in);
    wire [16:0] q_magnitude=iq_out[15] ? -$signed({iq_out[15],iq_out}) : {1'b0,iq_out};
    wire [16:0] remaining=LIMIT-q_magnitude;
    assign id_out=id_in<0 ? 16'sd0 : ({1'b0,id_in}>remaining ? remaining[15:0] : id_in);
endmodule
