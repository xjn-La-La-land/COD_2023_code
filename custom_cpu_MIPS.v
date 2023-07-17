`timescale 10ns / 1ns

module custom_cpu(
	input         clk,
	input         rst,

	//Instruction request channel
	output [31:0] PC,
	output        Inst_Req_Valid,
	input         Inst_Req_Ready,

	//Instruction response channel
	input  [31:0] Instruction,
	input         Inst_Valid,
	output        Inst_Ready,

	//Memory request channel
	output [31:0] Address,
	output        MemWrite,
	output [31:0] Write_data,
	output [ 3:0] Write_strb,
	output        MemRead,
	input         Mem_Req_Ready,

	//Memory data response channel
	input  [31:0] Read_data,
	input         Read_data_Valid,
	output        Read_data_Ready,

	input         intr,

	output [31:0] cpu_perf_cnt_0,
	output [31:0] cpu_perf_cnt_1,
	output [31:0] cpu_perf_cnt_2,
	output [31:0] cpu_perf_cnt_3,
	output [31:0] cpu_perf_cnt_4,
	output [31:0] cpu_perf_cnt_5,
	output [31:0] cpu_perf_cnt_6,
	output [31:0] cpu_perf_cnt_7,
	output [31:0] cpu_perf_cnt_8,
	output [31:0] cpu_perf_cnt_9,
	output [31:0] cpu_perf_cnt_10,
	output [31:0] cpu_perf_cnt_11,
	output [31:0] cpu_perf_cnt_12,
	output [31:0] cpu_perf_cnt_13,
	output [31:0] cpu_perf_cnt_14,
	output [31:0] cpu_perf_cnt_15,

	output [69:0] inst_retire
);

/* The following signal is leveraged for behavioral simulation, 
* which is delivered to testbench.
*
* STUDENTS MUST CONTROL LOGICAL BEHAVIORS of THIS SIGNAL.
*
* inst_retired (70-bit): detailed information of the retired instruction,
* mainly including (in order) 
* { 
*   reg_file write-back enable  (69:69,  1-bit),
*   reg_file write-back address (68:64,  5-bit), 
*   reg_file write-back data    (63:32, 32-bit),  
*   retired PC                  (31: 0, 32-bit)
* }
*
*/

// TODO: Please add your custom CPU code here

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
	wire	    RF_wen;
	wire [ 4:0] RF_waddr;
	wire [31:0]	RF_wdata;

	alu alu_u0(opnumber_1,opnumber_2,ALUop,overflow,carryout,zero,result_1);//例化算术逻辑单元
	shifter shifter_u0(shift_data,shift_amount,shiftop,result_2);//例化移位器
	reg_file reg_file_u0(clk,RF_waddr,RF_raddr1,RF_raddr2,RF_wen,RF_wdata,RF_rdata1,RF_rdata2);//例化32*32bit 2读1写理想寄存器堆

/*====================================================================================*/
// 在每条指令完成提交时，对执行结果的统计
	assign inst_retire = {RF_wen,RF_waddr,RF_wdata,PC_retired};
/*====================================================================================*/

// 多周期需要加入的一些寄存器
	reg  [31:0] IR; //Instruction Register
	reg  [31:0] MDR; //Memory Data Register
	reg  [31:0] PC_reg; //PC Register
	reg  [31:0] PC_retired; //store the PC of the retired instruction
	reg  [31:0] ALUout; //ALU Register用于存储ALU计算的结果
	reg  [31:0] EPC_reg; // 存储中断前的PC
	reg         intr_mask; //中断屏蔽信号

// 控制信号的定义
    // 截取指令中的不同字段，用于译码时使用
	wire [ 5:0] opcode      = IR[31:26];
	wire [ 4:0] rs          = IR[25:21];
	wire [ 4:0] rt          = IR[20:16];
	wire [ 4:0] rd          = IR[15:11];
	wire [ 4:0] shamt       = IR[10: 6];
	wire [ 5:0] func        = IR[ 5: 0];
	wire [15:0] offset      = IR[15: 0];
	wire [25:0] instr_index = IR[25: 0];

	// 指令分类阶段
	// 首先将NOP（no operation）指令分出来
	wire NOP               = (IR==32'b0);
	// 然后分出ERET指令
	wire ERET              = opcode[4];
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

	// 对指令功能进行分类
	wire calculate         = R_calculate||I_calculate;
	wire branch            = REGIMM_type||I_branch;
	wire jump              = R_jump||J_type;
	//还有shift，move，load，store前面已经有过了

    // control unit输出的一些信号
	wire [1:0] ALUsrcA     = {(current_state[3:1]==3'b000), current_state[3]||current_state[2]||current_state[1]}; // opnumber1的赋值使能信号(对状态分类)
	wire [2:0] ALUsrcB     = {(current_state[3:1]==3'b000), current_state[3],current_state[2]||current_state[1]}; // opnumber2的赋值使能信号(对状态分类)
	wire [1:0] ALUsrcD     = {move,jump}; // opnumber1的赋值使能信号(对指令功能分类)，是PC(jump)还是32'b0(move)还是RF_rdata1(others)
	wire [2:0] ALUsrcC     = {store||load||I_calculate,branch,jump}; // opnumber2的赋值使能信号，是RF_rdata2(R)还是immediate number(I),PC+8(jal/jalr)还是PC+4+offset(branch)
	wire ExtendType        = I_calculate && opcode[2]; // offset扩展位宽的类型（符号扩展还是零扩展）
	wire [2:0] RegDst      = {~R_type&&~J_type,J_type,R_type}; // 寄存器堆写入数据的来源
	wire MemWriteType      = (opcode[2:0]==3'b011); // 内存写的数据是否需要先经过移位操作

// 状态机控制

	// 状态机各个状态的one-hot编码
	localparam INIT      = 10'b0000000001, //起始状态
			   IF        = 10'b0000000010, //取指状态
			   IW        = 10'b0000000100, //指令等待状态
			   ID        = 10'b0000001000, //指令译码状态
			   EX        = 10'b0000010000, //执行状态
			   STORE     = 10'b0000100000, //内存写状态
			   LOAD      = 10'b0001000000, //内存读状态
			   RDW       = 10'b0010000000, //读数据等待状态
			   WB        = 10'b0100000000, //写回（寄存器）状态
			   INTR      = 10'b1000000000; //终端状态
	
	// 状态机的现态和次态
	reg [9:0] current_state;
	reg [9:0] next_state;

    // 状态机第一段：描述状态寄存器current_state的同步状态更新
	always @(posedge clk)begin
		if(rst==1'b1)
			current_state <= INIT;
		else
			current_state <= next_state;
	end

    // 状态机第二段：根据current_state和输入信号，对next_state赋值
	wire EXtoIF = REGIMM_type||I_branch||J_type&&~opcode[0]||ERET; //执行状态跳转到取指状态的情况
	wire EXtoWB = R_type||I_calculate||J_type&&opcode[0];    	   //执行状态跳转到写回状态的情况
	wire EXtoST = store;                                     	   //执行状态跳转到内存写状态的情况
	wire EXtoLD = load;                                      	   //执行状态跳转到内存读状态的情况

	always @(*)begin
		if(rst==1'b1)
			next_state = INIT;
		else begin
			case(current_state)
			INIT: 
				next_state = IF; //初始状态后下一状态为取指状态

			IF:   begin
				if(intr & intr_mask == 1'b1)
					next_state = INTR;
				else if(Inst_Req_Ready == 1'b1) //取指状态需要等待Inst_Req_Ready拉高（内存控制器接收请求）后才能进入指令等待状态
					next_state = IW;
				else
					next_state = IF;
			end

			IW:   begin
				if(Inst_Valid==1'b1) //指令等待状态需要等待Inst_Valid拉高（内存控制器返回指令码）后才能进入译码阶段
					next_state = ID;
				else
					next_state = IW;
			end

			ID:   begin
				if(NOP==1'b1) //译码完成后非NOP指令进入执行状态，NOP指令回到取指状态
					next_state = IF;
				else
					next_state = EX;
			end

			EX:   begin
				if(EXtoIF==1'b1)
					next_state = IF;
				else if(EXtoWB==1'b1)
					next_state = WB;
				else if(EXtoST==1'b1)
					next_state = STORE;
				else if(EXtoLD==1'b1)
					next_state = LOAD;
				else
					next_state = EX;
			end

			STORE:begin
				if(Mem_Req_Ready==1'b1) //内存写状态需要等待Mem_Req_Ready拉高后才能回到取指状态
					next_state = IF;
				else
					next_state = STORE;
			end

			LOAD: begin
				if(Mem_Req_Ready==1'b1) //内存读状态需要等待Mem_Req_Ready拉高，才能进入读数据等待状态
					next_state = RDW;
				else
					next_state = LOAD;
			end

			RDW:  begin
				if(Read_data_Valid==1'b1) //读数据等待状态需要等待Read_data_Valid拉高，才能进入写回状态
					next_state = WB;
				else
					next_state = RDW;
			end

			WB:
				next_state = IF; //写回状态可以无条件地回到取指状态

			INTR:
				next_state = IF;

			default:
				next_state = INIT;
		endcase
		end
	end

    // 状态机第三段：根据current_state，描述不同输出的同步变化
  // 时序逻辑部分

	// PC寄存器的赋值
	wire branch_condition = REGIMM_type&&(rt[0]^RF_rdata1[31]) || I_branch&&(~opcode[1]&&(opcode[0]^zero) || opcode[1]&&(opcode[0]^(zero||RF_rdata1[31])));//跳转条件

	always @(posedge clk)begin
		if(current_state == INIT)
			PC_reg <= 32'b0;
		else if(current_state == INTR)
			PC_reg <= 32'b100000000;
		else if(current_state == IW && Inst_Valid)
			PC_reg <= ALUout;
		else if(current_state == EX)begin
			if(J_type)
				PC_reg[27:0] <= {instr_index,2'b0};	//J_type指令的跳转
			else if(R_jump)
				PC_reg <= RF_rdata1;			    //R_jump指令的跳转
			else if(branch_condition)
				PC_reg <= ALUout;                   //branch指令的跳转
			else if(ERET)
				PC_reg <= EPC_reg;					//ERET指令的跳转
		end
	end

	// PC_retired寄存器的赋值
	always @(posedge clk)begin
		if(current_state == INIT)
			PC_retired <= 32'b0;
		else if(current_state == IW && Inst_Valid)
			PC_retired <= PC_reg;       // PC更新之前，将退休指令的PC保存下来
	end

    // IR寄存器的赋值
	always @(posedge clk)begin
		if(current_state == IW && Inst_Valid)
			IR <= Instruction;
	end

    // MDR寄存器的赋值
	always @(posedge clk)begin
		if(current_state == RDW && Read_data_Valid)
			MDR <= Read_data;
	end

    // ALUout寄存器的赋值
	always @(posedge clk)begin
		ALUout <= result_1;
	end

	// EPC寄存器的赋值
	always @(posedge clk)begin
		if(current_state == INIT)
			EPC_reg <= 32'b0;
		else if(current_state == INTR)
			EPC_reg <= PC_reg;
	end

	// intr_mask 寄存器的赋值
	always @(posedge clk)begin
		if(current_state == INIT)
			intr_mask <= 1'b1;
		else if(current_state == INTR)
			intr_mask <= 1'b0;
		else if(ERET)
			intr_mask <= 1'b1;
	end

  // 组合逻辑部分
	assign PC=PC_reg;

    // 1.reg_file模块控制信号赋值
	// 1.1 读操作
	assign RF_raddr1       = rs;
	assign RF_raddr2       = rt;
	// 1.2 写操作
	wire   write_condition = calculate||shift||load||R_jump&&func[0]||move&&(func[0]^zero)||J_type&&opcode[0];
	assign RF_wen          = (current_state == WB)&&(write_condition);
	assign RF_waddr        = {5{RegDst[0]}} & rd | {5{RegDst[1]}} & {5'b11111} | {5{RegDst[2]}} & rt;

		// 寄存器堆写入数据的情况比较复杂，所以将RF_wdata信号分为几个信号之和，每一个信号代表了一类情况
	wire [31:0] calculate_wdata = {32{calculate}} & ((opcode[3:0]==4'b1111)?{offset,{16{1'b0}}}:ALUout);
	wire [31:0] move_wdata      = {32{move}} & RF_rdata1;
	wire [31:0] shift_wdata     = {32{shift}} & result_2;
	wire [31:0] jump_wdata      = {32{jump}} & ALUout;
	wire [31:0] load_wdata; 
	// load型指令写入数据比较复杂，每一条指令的操作都不一样，同样将load_wdata分成几个信号之和来处理

	wire [ 7:0] target_byte     = MDR[{ALUout[1:0],3'b0}+:8];
	wire [15:0] target_halfword = MDR[{ALUout[1:0],3'b0}+:16];
	wire [31:0] zeroextended_target_byte = {{24{1'b0}},target_byte};
	wire [31:0] zeroextended_target_halfword = {{16{1'b0}},target_halfword};
	wire [31:0] signextended_target_byte = {{24{target_byte[7]}},target_byte};
	wire [31:0] signextended_target_halfword = {{16{target_halfword[15]}},target_halfword};

	wire [31:0] lwl_wdata       = {32{ALUout[1:0]==2'b11}} & MDR |
	                              {32{ALUout[1:0]==2'b10}} & {MDR[23:0],RF_rdata2[7:0]} |
								  {32{ALUout[1:0]==2'b01}} & {MDR[15:0],RF_rdata2[15:0]} |
								  {32{ALUout[1:0]==2'b00}} & {MDR[7:0],RF_rdata2[23:0]};
	
	wire [31:0] lwr_wdata       = {32{ALUout[1:0]==2'b11}} & {RF_rdata2[31:8],MDR[31:24]} |
	                              {32{ALUout[1:0]==2'b10}} & {RF_rdata2[31:16],MDR[31:16]} |
								  {32{ALUout[1:0]==2'b01}} & {RF_rdata2[31:24],MDR[31:8]} |
								  {32{ALUout[1:0]==2'b00}} & MDR;
	
	assign load_wdata           = {32{load}} &
								  {{32{(opcode[2:0]==3'b000)}} & signextended_target_byte |
	                               {32{(opcode[2:0]==3'b001)}} & signextended_target_halfword |
								   {32{(opcode[2:0]==3'b011)}} & MDR |
								   {32{(opcode[2:0]==3'b100)}} & zeroextended_target_byte |
								   {32{(opcode[2:0]==3'b101)}} & zeroextended_target_halfword |
								   {32{(opcode[2:0]==3'b010)}} & lwl_wdata |
								   {32{(opcode[2:0]==3'b110)}} & lwr_wdata};

	// RF_wdata信号等于几个分信号之和
	assign RF_wdata             = load_wdata | calculate_wdata | move_wdata | shift_wdata | jump_wdata;

    // 2.ALU模块控制信号赋值
	assign opnumber_1               = {32{ALUsrcA[0]}} & PC_reg |
									  {32{ALUsrcA[1]}} & {
										{32{ALUsrcD[0]}} & PC_reg |
									    {32{ALUsrcD[1]}} & 32'b0 |
										{32{ALUsrcD==2'b00}} & RF_rdata1};
		//在IW和ID状态时，ALU分别计算PC+4和PC+offset；其他状态时，ALU计算单周期时需要计算的内容
	
	wire [31:0] zeroextended_offset = {{16{1'b0}},offset};
	wire [31:0] signextended_offset = {{16{offset[15]}},offset};
	wire [31:0] extraextended_offset= {{14{offset[15]}},offset,{2'b0}};
	wire [31:0] extended_offset     = (ExtendType)? zeroextended_offset:signextended_offset;
	assign opnumber_2               = {32{ALUsrcB[0]}} & {32'b100} |
									  {32{ALUsrcB[1]}} & {{32{ALUsrcC[1]}} & extraextended_offset | {32{ALUsrcC[0]}} & {32'b100}} |
									  {32{ALUsrcB[2]}} & {
										{32{ALUsrcC[0]}} & {32'b100} |
										{32{ALUsrcC[2]}} & extended_offset |
										{32{~ALUsrcC[2]&&~ALUsrcC[0]}} & RF_rdata2
									  };

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
	wire [2:0] ALUop_branch    = {3{branch}} & {3'b110};
	wire [2:0] ALUop_defult    = {3{~R_calculate&&~I_calculate&&~I_branch}} & {3'b010};
	assign ALUop               = {3{current_state[1] ||current_state[2] || current_state[3]}} & {3'b010} |
								 {3{current_state[3:1]==3'b000}} & {ALUop_Rcal | ALUop_Ical | ALUop_branch | ALUop_defult};

    // 3.shifter模块控制信号赋值
	assign shift_data   = RF_rdata2;
	assign shift_amount = {5{shift}} & {{5{func[2]}} & RF_rdata1[4:0] | {5{~func[2]}} & shamt} |
						  {5{store}} & {((opcode[2:0]==3'b010)?~ALUout[1:0]:ALUout[1:0]),3'b0};
	assign shiftop      = shift? func[1:0]:{(opcode[2:0]==3'b010),1'b0};

    // 4.内存读写控制信号赋值
	assign Inst_Req_Valid = current_state[1]; //&& ~(intr & intr_mask); // 在跑dma时在进入中断时不要拉高此信号！但是在跑cache时要把intr注释掉，它的测试程序会把intr拉高！
	assign Inst_Ready     = current_state[0] | current_state[2];
	assign Read_data_Ready= current_state[0] | current_state[7];
	assign MemRead        = current_state[6];
	assign MemWrite       = current_state[5];

	assign Address        = {32{current_state == IF}} & PC_reg |
						    {32{current_state == STORE || current_state == LOAD || current_state == RDW}} & {ALUout[31:2],{2'b0}};
	
	assign Write_data     = (MemWriteType)? RF_rdata2:result_2;
	// 将Write_strb的每一位写成有关量的最简逻辑表达式
	wire strb_3           = opcode[2]||opcode[1]&&opcode[0]||(!opcode[0])&&ALUout[1]&&ALUout[0]||opcode[0]&&ALUout[1];
	wire strb_2           = opcode[1]&&opcode[0]||opcode[2]&&(~ALUout[1]||~ALUout[0])||~opcode[2]&&opcode[1]&&ALUout[1]||~opcode[2]&&(opcode[0]&&(ALUout[1]||ALUout[0])||~opcode[0]&&ALUout[1]&&~ALUout[0]);
	wire strb_1           = opcode[1]&&opcode[0]||opcode[2]&&~ALUout[1]||~opcode[2]&&opcode[1]&&~opcode[0]&&(ALUout[1]||ALUout[0])||~opcode[1]&&~opcode[0]&&~ALUout[1]&&ALUout[0]||opcode[0]&&~ALUout[1];
	wire strb_0           = ~opcode[2]&&opcode[1]||~ALUout[1]&&~ALUout[0];
	assign Write_strb     = store? {strb_3,strb_2,strb_1,strb_0}:{4'b0};

// 性能计数器
	// 周期计数器
	reg [31:0] cycle_cnt;
	always @(posedge clk)begin
		if(rst==1'b1)
			cycle_cnt <= 32'b0;
		else
			cycle_cnt <= cycle_cnt+32'b1;
	end
	assign cpu_perf_cnt_0 = cycle_cnt;
	// 内存访问指令(load/store)计数器
	reg [31:0] mem_cycle_cnt;
	always @(posedge clk)begin
		if(rst==1'b1)
			mem_cycle_cnt <= 32'b0;
		else if((current_state[6] || current_state[5]) && Mem_Req_Ready) // load状态或store状态，只有内存访问指令会经历这两个状态
			mem_cycle_cnt <= mem_cycle_cnt+32'b1;
	end
	assign cpu_perf_cnt_1 = mem_cycle_cnt;
	// 指令周期计数器，统计执行的指令条数
	reg [31:0] inst_cycle_cnt;
	always @(posedge clk)begin
		if(rst==1'b1)
			inst_cycle_cnt <= 32'b0;
		else if(current_state[1] && Inst_Req_Ready) // IF取指状态
			inst_cycle_cnt <= inst_cycle_cnt+32'b1;
	end
	assign cpu_perf_cnt_2 = inst_cycle_cnt;

endmodule