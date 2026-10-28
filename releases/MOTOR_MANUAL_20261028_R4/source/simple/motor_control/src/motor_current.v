// Four ACS712 channels; calibrated ADC signed counts -> signed Q15 I/I_BASE.
// gain_q16 = (5 V / (sensor V/A * I_BASE[A])) * 65536 for AD7606 +/-5V.
// For ACS712-05B, I_BASE=8A: nominal gain=221405. Calibrate the actual board.
// CURRENT_CB_MASK bit per axis: 0 = ADC pair A/B, 1 = ADC pair C/B.
// Calibration/gain/polarity remain indexed by physical ADC channel.
module motor_current #(parameter CAL_LOG2=10,MOTOR_MASK=2'b11,CURRENT_CB_MASK=2'b00,CURRENT_SWAP_MASK=2'b00)(
    input wire clk, rst_n, cal_start, frame_valid,
    input wire [63:0] raw,
    input wire [95:0] gain_q16,
    input wire [3:0] reverse,
    input wire [15:0] trip_q15,
    output reg calibrating, calibrated, valid, overcurrent,
    output reg [95:0] currents,
    output reg [63:0] offsets
);
    reg [CAL_LOG2-1:0] samples;
    reg signed [31:0] sum [0:3];
    reg signed [16:0] diff;
    reg signed [40:0] product;
    reg signed [31:0] scaled [0:3];
    reg signed [31:0] third;
    reg signed [31:0] average;
    integer k;
    function [15:0] sat16;
        input signed [31:0] value;
        begin
            if(value>32767) sat16=16'h7fff;
            else if(value< -32768) sat16=16'h8000;
            else sat16=value[15:0];
        end
    endfunction
    function exceeds;
        input signed [31:0] value;
        input [15:0] limit;
        begin exceeds=(value>$signed({1'b0,limit})) || (value< -$signed({1'b0,limit})); end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            samples<=0; calibrating<=0; calibrated<=0; valid<=0;
            offsets<=0; currents<=0; overcurrent<=0;
            for(k=0;k<4;k=k+1) sum[k]<=0;
        end else begin
            valid<=0; overcurrent<=0;
            if(cal_start) begin
                samples<=0; calibrating<=1; calibrated<=0; offsets<=0;
                for(k=0;k<4;k=k+1) sum[k]<=0;
            end else if(frame_valid) begin
                if(calibrating) begin
                    for(k=0;k<4;k=k+1) begin
                        sum[k]<=sum[k]+$signed(raw[k*16+:16]);
                        if(&samples) begin
                            average=($signed(sum[k])+$signed(raw[k*16+:16])) >>> CAL_LOG2;
                            offsets[k*16+:16]<=average[15:0];
                        end
                    end
                    if(&samples) begin calibrating<=0; calibrated<=1; end
                    else samples<=samples+{{(CAL_LOG2-1){1'b0}},1'b1};
                end else if(calibrated) begin
                    for(k=0;k<4;k=k+1) begin
                        diff=$signed({raw[k*16+15],raw[k*16+:16]})-
                             $signed({offsets[k*16+15],offsets[k*16+:16]});
                        product=diff*$signed(gain_q16[k*24+:24]);
                        scaled[k]=product >>> 16;
                        if(reverse[k]) scaled[k]=-scaled[k];
                        // A physically absent axis must neither publish fictitious
                        // current nor trip the selected motor on floating ADC pins.
                        if(!MOTOR_MASK[k/2]) scaled[k]=0;
                        else if(exceeds(scaled[k],trip_q15)) overcurrent<=1;
                    end
                    // Publish canonical A/B/C for the FOC IP and telemetry.
                    // Reconstruct in wide arithmetic and trip BEFORE saturation.
                    // Never use CBUS (a bus-current monitor) as phase C.
                    for(k=0;k<2;k=k+1) begin
                        third=-scaled[2*k]-scaled[2*k+1];
                        // Swap phase assignment AFTER physical-channel zero,
                        // gain, polarity and raw protection, never before them.
                        currents[k*48+:16]<=sat16(CURRENT_CB_MASK[k] ? third : scaled[2*k+CURRENT_SWAP_MASK[k]]);
                        currents[k*48+16+:16]<=sat16(scaled[2*k+1-CURRENT_SWAP_MASK[k]]);
                        currents[k*48+32+:16]<=sat16(CURRENT_CB_MASK[k] ? scaled[2*k+CURRENT_SWAP_MASK[k]] : third);
                        if(exceeds(third,trip_q15)) overcurrent<=1;
                    end
                    valid<=1;
                end
            end
        end
    end
endmodule
