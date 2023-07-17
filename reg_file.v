`timescale 10 ns / 1 ns

`define DATA_WIDTH 32
`define ADDR_WIDTH 5

module reg_file(
	input                       clk,
	input  [`ADDR_WIDTH - 1:0]  waddr,
	input  [`ADDR_WIDTH - 1:0]  raddr1,
	input  [`ADDR_WIDTH - 1:0]  raddr2,
	input                       wen,
	input  [`DATA_WIDTH - 1:0]  wdata,
	output [`DATA_WIDTH - 1:0]  rdata1,
	output [`DATA_WIDTH - 1:0]  rdata2
);

	// TODO: Please add your logic design here
	reg [`DATA_WIDTH-1:0] rf [31:0];
	always @(posedge clk)
	begin
		if(wen==1'b1 && waddr!=5'b0)//仅当wen=1且waddr不等于0时，才可以向waddr对应的寄存器写入wdata
		rf [waddr]<= wdata;//时序逻辑使用阻塞赋值
	end

	
	assign rdata1=(raddr1==0)?0:rf[raddr1];
	assign rdata2=(raddr2==0)?0:rf[raddr2];//若raddr=0，则直接将32'b0输出，防止0号寄存器未初始化时读出无意义的值

endmodule