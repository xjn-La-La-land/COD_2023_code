`timescale 10 ns / 1 ns

`define DATA_WIDTH 32

module shifter (
	input  [`DATA_WIDTH - 1:0] A,
	input  [              4:0] B,
	input  [              1:0] Shiftop,
	output [`DATA_WIDTH - 1:0] Result
);
	// TODO: Please add your logic code here
	localparam Left_logical     = 2'b00;
	localparam Right_logical    = 2'b10;
	localparam Right_arthimetic = 2'b11;

	wire   [2*`DATA_WIDTH-1:0] extended_data = {{`DATA_WIDTH{A[`DATA_WIDTH-1]}},A};
	assign Result = {`DATA_WIDTH{Shiftop==Left_logical}} & (A<<B) |
	                {`DATA_WIDTH{Shiftop==Right_logical}} & (A>>B) |
					{`DATA_WIDTH{Shiftop==Right_arthimetic}} & extended_data[{1'b0,B}+:`DATA_WIDTH];
	
endmodule
