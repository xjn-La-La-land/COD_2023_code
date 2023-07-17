`timescale 10ns / 1ns

module simple_cpu(
	input             clk,
	input             rst,

	output [31:0]     PC,
	input  [31:0]     Instruction,

	output [31:0]     Address,
	output            MemWrite,
	output [31:0]     Write_data,
	output [ 3:0]     Write_strb,

	input  [31:0]     Read_data,
	output            MemRead
);

	// THESE THREE SIGNALS ARE USED IN OUR TESTBENCH
	// PLEASE DO NOT MODIFY SIGNAL NAMES
	// AND PLEASE USE THEM TO CONNECT PORTS
	// OF YOUR INSTANTIATION OF THE REGISTER FILE MODULE
	wire			RF_wen;
	wire [ 4:0]		RF_waddr;
	wire [31:0]		RF_wdata;

	// TODO: PLEASE ADD YOUR CODE BELOW

// 各个模块需要用到的输入输出信号
	wire [31:0] opnumber_1, opnumber_2;
	wire [ 2:0] ALUop;
	wire overflow,carryout,zero;
	wire [31:0] result_1;
	wire [31:0] shift_data;
	wire [ 4:0] shift_amount;
	wire [ 1:0] shiftop;
	wire [31:0] result_2;
	wire [ 4:0] RF_raddr1;
	wire [ 4:0] RF_raddr2;
	wire [31:0] RF_rdata1, RF_rdata2;

	alu alu_u0(opnumber_1,opnumber_2,ALUop,overflow,carryout,zero,result_1);//例化算术逻辑单元
	shifter shifter_u0(shift_data,shift_amount,shiftop,result_2);//例化移位器
	reg_file reg_file_u0(clk,RF_waddr,RF_raddr1,RF_raddr2,RF_wen,RF_wdata,RF_rdata1,RF_rdata2);//例化32*32bit 2读1写理想寄存器堆

// 组合逻辑部分
	// 截取指令中的不同字段，用于译码时使用
	wire [ 5:0] opcode      = Instruction[31:26];
	wire [ 4:0] rs          = Instruction[25:21];
	wire [ 4:0] rt          = Instruction[20:16];
	wire [ 4:0] rd          = Instruction[15:11];
	wire [ 4:0] shamt       = Instruction[10: 6];
	wire [ 5:0] func        = Instruction[ 5: 0];
	wire [15:0] offset      = Instruction[15: 0];
	wire [25:0] instr_index = Instruction[25: 0];

	// 指令分类阶段
	// 将所有指令进行分为4类：R_type,REGIMM_type,J_type,I_type
	wire R_type            = (opcode==6'b0);
	wire REGIMM_type       = (opcode==6'b1);
	wire J_type            = (opcode[5:1]==5'b1);
	// 对I_type指令进行分类
	wire I_calculate       = (~opcode[5])&&opcode[3];
	wire I_branch          = (~opcode[5])&&(~opcode[3])&&opcode[2];
	wire load              = opcode[5]&&(~opcode[3]);
	wire store             = opcode[5]&&opcode[3];
	// 对R_type指令进行进一步的分类
	wire R_calculate       = R_type&&func[5];
	wire shift             = R_type&&(~func[5])&&(~func[3]);
	wire R_jump            = R_type&&func[3]&&(~func[1]);
	wire move              = R_type&&(~func[5])&&func[3]&&func[1];

	// control unit的输出信号赋值阶段
	
	// 1.reg_file模块控制信号赋值
	// 1.1 读操作
	assign RF_raddr1       = rs;
	assign RF_raddr2       = rt;
	// 1.2 写操作
	assign RF_wen          = R_calculate||shift||I_calculate||load||R_jump&&func[0]||move&&(func[0]^zero)||J_type&&opcode[0];
	assign RF_waddr        = R_type? rd:(J_type?5'b11111:rt);
		// 寄存器堆写入数据的情况比较复杂，所以将RF_wdata信号分为几个信号之和，每一个信号代表了一类情况
	wire [31:0] calculate_wdata = {32{R_calculate}} & result_1 |
								  {32{I_calculate}} & ((opcode[3:0]==4'b1111)?{offset,{16{1'b0}}}:result_1);
	wire [31:0] move_wdata      = {32{move}} & RF_rdata1;
	wire [31:0] shift_wdata     = {32{shift}} & result_2;
	wire [31:0] jump_wdata      = {32{J_type||R_jump}} & (PC+32'b1000);
	wire [31:0] load_wdata; 
	// load型指令写入数据比较复杂，每一条指令的操作都不一样，同样将load_wdata分成几个信号之和来处理

	wire [ 7:0] target_byte     = Read_data[{result_1[1:0],3'b0}+:8];
	wire [15:0] target_halfword = Read_data[{result_1[1:0],3'b0}+:16];
	wire [31:0] zeroextended_target_byte = {{24{1'b0}},target_byte};
	wire [31:0] zeroextended_target_halfword = {{16{1'b0}},target_halfword};
	wire [31:0] signextended_target_byte = {{24{target_byte[7]}},target_byte};
	wire [31:0] signextended_target_halfword = {{16{target_halfword[15]}},target_halfword};

	wire [31:0] lwl_wdata       = {32{result_1[1:0]==2'b11}} & Read_data |
	                              {32{result_1[1:0]==2'b10}} & {Read_data[23:0],RF_rdata2[7:0]} |
								  {32{result_1[1:0]==2'b01}} & {Read_data[15:0],RF_rdata2[15:0]} |
								  {32{result_1[1:0]==2'b00}} & {Read_data[7:0],RF_rdata2[23:0]};
	
	wire [31:0] lwr_wdata       = {32{result_1[1:0]==2'b11}} & {RF_rdata2[31:8],Read_data[31:24]} |
	                              {32{result_1[1:0]==2'b10}} & {RF_rdata2[31:16],Read_data[31:16]} |
								  {32{result_1[1:0]==2'b01}} & {RF_rdata2[31:24],Read_data[31:8]} |
								  {32{result_1[1:0]==2'b00}} & Read_data;
	
	assign load_wdata           = {32{load}} &
								  {{32{(opcode[2:0]==3'b000)}} & signextended_target_byte |
	                               {32{(opcode[2:0]==3'b001)}} & signextended_target_halfword |
								   {32{(opcode[2:0]==3'b011)}} & Read_data |
								   {32{(opcode[2:0]==3'b100)}} & zeroextended_target_byte |
								   {32{(opcode[2:0]==3'b101)}} & zeroextended_target_halfword |
								   {32{(opcode[2:0]==3'b010)}} & lwl_wdata |
								   {32{(opcode[2:0]==3'b110)}} & lwr_wdata};

	// RF_wdata信号等于几个分信号之和
	assign RF_wdata             = load_wdata | calculate_wdata | move_wdata | shift_wdata | jump_wdata;

	// 2.ALU模块控制信号赋值
	assign opnumber_1               = (move)? 32'b0:RF_rdata1;
	wire [31:0] zeroextended_offset = {{16{1'b0}},offset};
	wire [31:0] signextended_offset = {{16{offset[15]}},offset};
	assign opnumber_2               = {32{R_type||REGIMM_type||J_type||I_branch}} & RF_rdata2 |
	                                  {32{store||load||I_calculate&&~opcode[2]}} & signextended_offset |
								      {32{I_calculate&&opcode[2]}} & zeroextended_offset;
	// 将ALUop信号的情况分为几类，在将这几类的信号按位或起来组成ALUop
	localparam [1:0] ADD_type  = 2'b00;
	localparam [1:0] AND_type  = 2'b01;
	localparam [1:0] SLT_type  = 2'b10;
	localparam [1:0] ANDI_type = 2'b11;
	wire [2:0] ALUop_Rcal      = {3{R_calculate}} &
							     {{3{func[3:2]==ADD_type}} & {func[1],2'b10} |
	                              {3{func[3:2]==AND_type}} & {func[1],1'b0,func[0]} |
							      {3{func[3:2]==SLT_type}} & {~func[0],2'b11}};
	wire [2:0] ALUop_Ical      = {3{I_calculate}} &
								 {{3{opcode[3:2]==SLT_type}} & {~opcode[0],1'b1,opcode[1]} |
								  {3{opcode[3:2]==ANDI_type}} & {opcode[1],1'b0,opcode[0]}};
	wire [2:0] ALUop_branch    = {3{I_branch}} & {~opcode[1],2'b10};
	wire [2:0] ALUop_defult    = {3{~R_calculate&&~I_calculate&&~I_branch}} & {3'b010};
	assign ALUop               = ALUop_Rcal | ALUop_Ical | ALUop_branch | ALUop_defult;

	// 3.shifter模块控制信号赋值
	assign shift_data   = RF_rdata2;
	assign shift_amount = {5{shift}} & {{5{func[2]}} & RF_rdata1[4:0] | {5{~func[2]}} & shamt} |
						  {5{store}} & {((opcode[2:0]==3'b010)?~result_1[1:0]:result_1[1:0]),3'b0};
	assign shiftop      = shift? func[1:0]:{(opcode[2:0]==3'b010),1'b0};

	// 4.内存读写控制信号赋值
	assign Address    = {result_1[31:2],{2'b0}};
	assign MemRead    = load;
	assign MemWrite   = store;
	assign Write_data = (opcode[2:0]==3'b011)? RF_rdata2:result_2;
	// 将Write_strb的每一位写成有关量的最简逻辑表达式
	wire strb_3       = opcode[2]||opcode[1]&&opcode[0]||(!opcode[0])&&result_1[1]&&result_1[0]||opcode[0]&&result_1[1];
	wire stru_2       = opcode[1]&&opcode[0]||opcode[2]&&(~result_1[1]||~result_1[0])||~opcode[2]&&opcode[1]&&result_1[1]||~opcode[2]&&(opcode[0]&&(result_1[1]||result_1[0])||~opcode[0]&&result_1[1]&&~result_1[0]);
	wire stru_1       = opcode[1]&&opcode[0]||opcode[2]&&~result_1[1]||~opcode[2]&&opcode[1]&&~opcode[0]&&(result_1[1]||result_1[0])||~opcode[1]&&~opcode[0]&&~result_1[1]&&result_1[0]||opcode[0]&&~result_1[1];
	wire stru_0       = ~opcode[2]&&opcode[1]||~result_1[1]&&~result_1[0];
	assign Write_strb = store? {strb_3,stru_2,stru_1,stru_0}:{4'b0};
	
// 时序逻辑部分
	reg [31:0] PC_reg;

	wire branch_condition = REGIMM_type&&(rt[0]^RF_rdata1[31]) || I_branch&&(~opcode[1]&&(opcode[0]^zero) || opcode[1]&&(opcode[0]^(zero||RF_rdata1[31])));//跳转条件
	// PC的变化受时钟信号控制，写在always块中
	always @(posedge clk)begin	//在clk和rst的上升沿更新
		if(rst==1)begin
			PC_reg<=32'b0;
		end										//初始化将PC置为0（初始时rst有一个上升沿，持续一个周期之后就恒定为0）
		else if(J_type)begin
			PC_reg[27:0]<={instr_index,2'b0};	//J_type指令的跳转
		end
		else if(R_jump)begin
			PC_reg<=RF_rdata1;					//R_jump指令的跳转
		end
		else if(branch_condition)begin
			PC_reg<=PC_reg+32'b100+{{14{offset[15]}},offset,{2'b0}};//branch指令的跳转
		end
		else begin
			PC_reg<=PC_reg+32'b100;				//其他非跳转指令PC+4(指令字长)
		end
	end

	assign PC=PC_reg;
	
endmodule