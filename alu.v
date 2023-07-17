`timescale 10 ns / 1 ns

`define DATA_WIDTH 32

module alu(
	input  [`DATA_WIDTH - 1:0]  A,
	input  [`DATA_WIDTH - 1:0]  B,
	input  [              2:0]  ALUop,
	output                      Overflow,
	output                      CarryOut,
	output                      Zero,
	output [`DATA_WIDTH - 1:0]  Result
);
	// TODO: Please add your logic design here
	wire CarryIn = (ALUop[2]==1'b1||ALUop[1:0]==2'b11);								//若要做减法或SLT，则将进位设为1
	wire [`DATA_WIDTH :0] A_Extended = {A[`DATA_WIDTH - 1],A};	//将A,B的符号位扩展为双符号位
	wire [`DATA_WIDTH :0] B_Extended = {B[`DATA_WIDTH - 1],B};
	wire [`DATA_WIDTH :0] B_Convert = (ALUop[2]==1'b1||ALUop[1:0]==2'b11)? ~B_Extended : B_Extended;//若要做减法或SLT，将B逐位取反
	wire [`DATA_WIDTH + 1:0] C = A_Extended+B_Convert+CarryIn;	//将扩展后的A和B相加的结果放在C中，其中C的最高位用来存第32位的进位
	wire [`DATA_WIDTH - 1:0] Less;

	assign Result=({`DATA_WIDTH{ALUop==3'b000}}&(A&B))
				|({`DATA_WIDTH{ALUop==3'b001}}&(A|B))
				|({`DATA_WIDTH{ALUop==3'b100}}&(A^B))
				|({`DATA_WIDTH{ALUop==3'b101}}&~(A|B))
				|({`DATA_WIDTH{ALUop[1:0]==2'b10}}&(C[`DATA_WIDTH - 1:0]))
				|({`DATA_WIDTH{ALUop[1:0]==2'b11}}&(Less));
	//对于ALUop的每一种输入，例如ALUop==3'b000，将它判断的结果与相应的计算结果的每一位进行按位与，最后所有情况按位或。这样对于ALUop的每一种情况，只有对应的计算结果（&1）可以在result上输出，其他计算结果都（&0）被忽略
	assign Zero=(Result==`DATA_WIDTH'b0);
	assign CarryOut=(ALUop[2]||ALUop[1:0])^C[`DATA_WIDTH+1];
	//无符号数作加法时，最高位产生了进位说明A+B>=2^n，说明产生了进位；无符号数作减法时，最高位如果没有产生进位就说明A+2^n-B<2^n，说明有借位
	assign Overflow=C[`DATA_WIDTH]^C[`DATA_WIDTH-1];				//overflow等于两个符号位的异或
	assign Less={{(`DATA_WIDTH-1){1'b0}},(ALUop[2]&&C[`DATA_WIDTH])||((~ALUop[2])&&CarryOut)};
	//当ALUop最高位为1时表示有符号数的SLT操作，Less的最低位等于结果的最高符号位，代表结果真正的符号
	//当ALUop最高位为0时表示无符号数的SLT操作，Less的最低位等于是否发生借位
endmodule