`timescale 10 ns / 1 ns

`define DARRAY_DATA_WIDTH 256
`define DARRAY_ADDR_WIDTH 3

module data_array(
	input                             clk,
	input  [`DARRAY_ADDR_WIDTH - 1:0] waddr,
	input  [`DARRAY_ADDR_WIDTH - 1:0] raddr,
	input                             wen,
	input  [`DARRAY_DATA_WIDTH - 1:0] wdata,
	//input  [                    31:0] wword,
	//input  [                     4:0] offset,
	//input                             flag, // flag=1，写入一个字；flag=0，写入一个block
	output [`DARRAY_DATA_WIDTH - 1:0] rdata
);

	reg [`DARRAY_DATA_WIDTH-1:0] array[ (1 << `DARRAY_ADDR_WIDTH) - 1 : 0];
	
	always @(posedge clk)
	begin
		if(wen)begin
			//if(flag == 1'b0)
				array[waddr] <= wdata;
			//else
				//array[waddr][{offset,3'b0}+:32] <= wword;
		end
	end

assign rdata = array[raddr];

endmodule