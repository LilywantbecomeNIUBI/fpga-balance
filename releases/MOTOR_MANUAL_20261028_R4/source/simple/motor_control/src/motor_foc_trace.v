// Read-only coherent M1 input trace. Captures the values presented to FOC on
// the SAME feedback_valid clock edge; it does not calculate/control PWM.
module motor_foc_trace(
    input wire clk,rst_n,valid,running,alignment,
    input wire [31:0] sequence_number,sample_time,
    input wire [13:0] mechanical,
    input wire [15:0] theta,current_limit,
    input wire [47:0] currents,
    input wire signed [15:0] id_ref,iq_ref,
    input wire park_valid,pi_valid,
    input wire signed [15:0] park_id,park_iq,pi_ud,pi_uq,
    output reg [255:0] sample
);
    reg [183:0] pending_sample;
    reg pending,park_seen,active_overrun;
    reg signed [15:0] captured_id,captured_iq;
    function signed [15:0] limited;
        input signed [15:0] value;
        reg signed [15:0] limit_value;
        begin
            limit_value=$signed(current_limit);
            if(!running) limited=0;
            else if(value>limit_value) limited=limit_value;
            else if(value< -limit_value) limited=-limit_value;
            else limited=value;
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            sample<=0;pending_sample<=0;pending<=0;park_seen<=0;active_overrun<=0;
            captured_id<=0;captured_iq<=0;
        end else if(valid) begin
            if(pending && pending_sample[176]) active_overrun<=1;
            pending_sample<={6'd0,alignment,running,limited(iq_ref),limited(id_ref),
                currents,theta,2'd0,mechanical,sample_time,sequence_number};
            pending<=1;park_seen<=0;
        end else if(pending) begin
            if(park_valid) begin captured_id<=park_id;captured_iq<=park_iq;park_seen<=1;end
            if(pi_valid) begin
                sample<={6'd0,active_overrun,(park_seen || park_valid),pi_uq,pi_ud,
                    park_valid ? park_iq : captured_iq,park_valid ? park_id : captured_id,pending_sample};
                pending<=0;park_seen<=0;
            end
        end
    end
endmodule
