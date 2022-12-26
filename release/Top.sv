`default_nettype none

// The softcore is hardcoded with the code to run.
// Make sure you have your ".ram" file placed in ????

// The IRQ signal is sourced by a Pico RP2040

module Top (
    input  logic clk,           // 25MHz Clock from board
    input  logic pm4a0,         // Interrupt (Active low)
    output logic led,
    output logic [5:0] blade1,
    output logic [11:0] tile1
);

localparam DATA_WIDTH = 32;
localparam PCSelectSize = 3;
localparam FlagSize = 4;

// ------------------------------------------------------------------------
// 18MHz PLL
// ------------------------------------------------------------------------
logic clk_18MHz;
logic locked;       // Active High

pll cpu_pll (
    .clk(clk),
    .clock_out(clk_18MHz),
    .locked(locked)
);

// ------------------------------------------------------------------------
// Slow cpu clock domain: CoreClk/(2^(N+1))
// N = 14 = 762Hz
// N = 18 = 48Hz
// ------------------------------------------------------------------------
`define N 22
logic [24:0] counter;

logic cpu_clock;
assign cpu_clock = clk_18MHz;

logic run_clock;
assign run_clock = counter[`N];

assign led = run_clock;

logic io_wr;
logic [7:0] data_out;

// ------------------------------------------------------------------------
// Data distribution based on IO Address
// ------------------------------------------------------------------------
DeMux4 #(.DATA_WIDTH(8)) data_demux
(
    .select(io_addr[1:0]),
    .data_i(data_out),
    .data0_o(data_par),
    .data1_o(data_seg)
);

// ------------------------------------------------------------------------
// LED Blade driven by cpu parallel out port
// ------------------------------------------------------------------------
logic [7:0] io_addr;
logic [7:0] par_out;
logic par_wr;
logic [7:0] data_par;

assign par_wr = ~(~io_wr & io_addr == 7'h0);

Register #(.DATA_WIDTH(8)) par_port
(
   .clk_i(cpu_clock),
   .ld_i(par_wr),
   .data_i(data_par),
   .data_o(par_out)
);

// 1'b0 = LED is on. (aka negative logic)
// So for Active high signals we invert signal to turn on.

// Red LEDs
assign blade1[0] = ~par_out[0];
assign blade1[1] = ~par_out[1];
// Yellow LEDs
assign blade1[2] = ~par_out[2];
assign blade1[3] = ~par_out[3];
// Green LEDs
assign blade1[4] = ~par_out[4];
assign blade1[5] = ~par_out[5];

// ------------------------------------------------------------------------
// 7Seg
// ------------------------------------------------------------------------
logic [3:0] digitOnes;
logic [3:0] digitTens;
logic seg_wr;
logic [7:0] data_seg;
logic [7:0] seg_reg_out;

assign seg_wr = ~(~io_wr & io_addr == 7'h1);

Register #(.DATA_WIDTH(8)) display_port
(
   .clk_i(cpu_clock),
   .ld_i(seg_wr),
   .data_i(data_seg),
   .data_o(seg_reg_out)
);

SevenSeg segs(
  .clk(clk),
  .digitL(4'b0),
  .digitM(digitTens),
  .digitR(digitOnes),
  .tile1(tile1)
);

logic [7:0] display_byte;

assign digitOnes = (seg_reg_out)       % 16;
assign digitTens = (seg_reg_out / 16)  % 16;

// ------------------------------------------------------------------------
// Softcore processor
// ------------------------------------------------------------------------
logic irq_trigger;  // Active low
logic reset;

RangerRiscProcessor cpu(
    .clk_i(cpu_clock),
    .reset_i(reset),
    .irq_i(pm4a0),
    .data_out(data_out),
    .io_wr(io_wr),
    .io_addr(io_addr)
);

// ------------------------------------------------------------------------
// State machine controlling module
// ------------------------------------------------------------------------
ControlState state = CSReset;
ControlState next_state = CSReset;

logic [1:0] cnt_byte;
logic [3:0] cnt_reset_hold;

always_ff @(posedge clk) begin
    counter <= counter + 1;

    case (state)
        CSReset: begin
            // Hold CPU in reset while Top module starts up.
            reset <= 1'b0;

            cnt_byte <= 0;
            cnt_reset_hold <= 0;
            next_state <= CSReset1;
        end

        CSReset1: begin
            reset <= 1'b0;
            
            if (locked)
                next_state <= CSResetComplete;
        end

        CSResetComplete: begin
            reset <= 1'b1;
            next_state <= CSIdle;
        end

        CSIdle: begin
        end

        default: begin
        end
    endcase

    state <= next_state;
end

endmodule

