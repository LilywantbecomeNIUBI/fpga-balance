// UART 115200 8N1. RX/TX bit FSM adapted from this workspace's
// src/uart_selftest.v (already used on ACG720); motor commands/status added here.
// Snapshot packet: 26 bytes little-endian, followed by XOR of those 26 bytes.
module motor_console #(parameter BAUD_DIV=434,STATUS_CYCLES=5000000,PAYLOAD_BYTES=26)(
    input wire clk,rst_n,rx,
    input wire [PAYLOAD_BYTES*8-1:0] status,
    output wire tx,
    output reg command_valid,
    output reg [7:0] command
);
    reg [1:0] rx_sync,rx_state;
    reg [15:0] rx_timer,tx_timer;
    reg [2:0] rx_bit;
    reg [7:0] rx_byte,checksum;
    reg [9:0] tx_shift;
    reg [3:0] tx_bits;
    reg [31:0] status_timer;
    reg [PAYLOAD_BYTES*8-1:0] snapshot;
    reg [$clog2(PAYLOAD_BYTES+1)-1:0] byte_index;
    reg sending;
    assign tx=tx_bits==0 ? 1'b1 : tx_shift[0];
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rx_sync<=3;rx_state<=0;rx_timer<=0;rx_bit<=0;rx_byte<=0;
            command<=0;command_valid<=0;tx_timer<=0;tx_shift<=10'h3ff;tx_bits<=0;
            status_timer<=0;snapshot<=0;byte_index<=0;sending<=0;checksum<=0;
        end else begin
            command_valid<=0;rx_sync<={rx_sync[0],rx};
            case(rx_state)
                0: if(!rx_sync[1]) begin rx_state<=1;rx_timer<=BAUD_DIV/2-1;end
                1: if(rx_timer!=0) rx_timer<=rx_timer-1'b1;
                   else if(!rx_sync[1]) begin rx_state<=2;rx_timer<=BAUD_DIV-1;rx_bit<=0;end
                   else rx_state<=0;
                2: if(rx_timer!=0) rx_timer<=rx_timer-1'b1;
                   else begin
                       rx_byte[rx_bit]<=rx_sync[1];rx_timer<=BAUD_DIV-1;
                       if(rx_bit==7) rx_state<=3;else rx_bit<=rx_bit+1'b1;
                   end
                3: if(rx_timer!=0) rx_timer<=rx_timer-1'b1;
                   else begin
                       rx_state<=0;
                       if(rx_sync[1]) begin command<=rx_byte;command_valid<=1;end
                   end
            endcase
            if(status_timer==STATUS_CYCLES-1) begin
                status_timer<=0;
                if(!sending) begin snapshot<=status;byte_index<=0;checksum<=0;sending<=1;end
            end else status_timer<=status_timer+1;
            if(tx_bits!=0) begin
                if(tx_timer!=0) tx_timer<=tx_timer-1'b1;
                else begin tx_shift<={1'b1,tx_shift[9:1]};tx_bits<=tx_bits-1'b1;tx_timer<=BAUD_DIV-1;end
            end else if(sending) begin
                tx_shift<={1'b1,byte_index==PAYLOAD_BYTES ? checksum : snapshot[7:0],1'b0};
                tx_bits<=10;tx_timer<=BAUD_DIV-1;
                if(byte_index==PAYLOAD_BYTES) sending<=0;
                else begin
                    checksum<=checksum^snapshot[7:0];snapshot<={8'd0,snapshot[PAYLOAD_BYTES*8-1:8]};byte_index<=byte_index+1'b1;
                end
            end
        end
    end
endmodule
