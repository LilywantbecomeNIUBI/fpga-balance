// Clock-enable serial receive adapter. No fabric-generated clocks.
// Sample raw source-synchronous DO at scheduled falling SCLK edges.
module motor_serial_rx #(
    parameter BITS=64, HALF_CYCLES=5, IDLE_HIGH=1, CS_SETUP=10, CS_HOLD=10
)(
    input wire clk, rst_n, start,
    input wire din_a, din_b,
    output reg cs_n, sclk, busy, done, overrun,
    output reg [BITS-1:0] data_a, data_b
);
    localparam IDLE=0, LEAD=1, SHIFT=2, HOLD=3;
    reg [1:0] state;
    reg [31:0] timer;
    reg [15:0] captured;
    reg [BITS-1:0] shift_a, shift_b;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; timer<=0; captured<=0; cs_n<=1; sclk<=IDLE_HIGH;
            busy<=0; done<=0; overrun<=0; data_a<=0; data_b<=0;
            shift_a<=0; shift_b<=0;
        end else begin
            done<=0; overrun<=start && busy;
            case(state)
                IDLE: if(start) begin
                    busy<=1; cs_n<=0; sclk<=IDLE_HIGH;
                    timer<=CS_SETUP-1; captured<=0; shift_a<=0; shift_b<=0; state<=LEAD;
                end
                LEAD: if(timer!=0) timer<=timer-1;
                    else begin timer<=HALF_CYCLES-1; state<=SHIFT; end
                SHIFT: if(timer!=0) timer<=timer-1;
                    else begin
                        timer<=HALF_CYCLES-1;
                        sclk<=!sclk;
                        if(sclk) begin
                            shift_a<={shift_a[BITS-2:0],din_a};
                            shift_b<={shift_b[BITS-2:0],din_b};
                            captured<=captured+16'd1;
                            // CPOL=0 ends on the last falling edge. CPOL=1
                            // must also emit its final rising edge (64 full clocks).
                            if(!IDLE_HIGH && captured==BITS-1) begin
                                timer<=CS_HOLD-1; state<=HOLD;
                            end
                        end else if(IDLE_HIGH && captured==BITS) begin
                            timer<=CS_HOLD-1; state<=HOLD;
                        end
                    end
                HOLD: if(timer!=0) timer<=timer-1;
                    else begin
                        cs_n<=1; busy<=0; done<=1; state<=IDLE;
                        data_a<=shift_a; data_b<=shift_b;
                    end
                default: begin state<=IDLE; cs_n<=1; sclk<=IDLE_HIGH; busy<=0; end
            endcase
        end
    end
endmodule
