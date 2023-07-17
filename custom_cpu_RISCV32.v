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

// 多周期需要加入的一些寄存器
	reg  [31:0] IR; //Instruction Register
	reg  [31:0] MDR; //Memory Data Register
	reg  [31:0] PC_reg; //PC Register
	reg  [31:0] PC_next_reg; //PC+4 is is first stored here(RISCV新增加的寄存器，用于支持jal/jalr指令的写回)
	reg  [31:0] ALUout; //ALU Register用于存储ALU计算的结果

// 控制信号的定义
    // 截取指令中的不同字段，用于译码时使用
	wire [ 6:0] opcode      = IR[ 6: 0];
	wire [ 4:0] rd          = IR[11: 7];
	wire [ 2:0] funct3      = IR[14:12];
	wire [ 4:0] rs1         = IR[19:15];
	wire [ 4:0] rs2         = IR[24:20];
	wire [ 6:0] funct7      = IR[31:25];
	wire [11:0] I_immediate = IR[31:20];
	wire [11:0] S_immediate = {IR[31:25],IR[11:7]};
	wire [12:0] B_immediate = {IR[31],IR[7],IR[30:25],IR[11:8],1'b0};
	wire [31:0] U_immediate = {IR[31:12],12'b0};
	wire [20:0] J_immediate = {IR[31],IR[19:12],IR[20],IR[30:21],1'b0};

	// 指令分类阶段
	// 对指令格式进行分类
	wire R_type            = opcode[5] && opcode[4] && ~opcode[2];
	wire I_type            = ~opcode[5] && opcode[4] && ~opcode[2];
	// 对指令功能进行分类
	wire R_calculate       = R_type && ~R_shift && ~multiply;
	wire R_shift           = R_type && (funct3[1:0]==2'b01);
	wire multiply          = R_type && (funct7[0]);
	wire I_calculate       = I_type && ~I_shift;
	wire I_shift           = I_type && (funct3[1:0]==2'b01);
	wire calculate         = R_calculate || I_calculate;
	wire shift             = R_shift || I_shift;
	wire jump              = opcode[6] && opcode[2];
	wire branch            = opcode[6] && ~opcode[2];
	wire load              = ~opcode[5] && ~opcode[4];
	wire store             = ~opcode[6] && opcode[5] && ~opcode[4];
	wire load_imm          = ~opcode[6] && opcode[2];
	wire jal               = jump && opcode[3];
	wire jalr              = jump && ~opcode[3];

    // control unit输出的一些信号
	wire [2:0] ALUsrc_state = {(current_state[3:1]==3'b000), current_state[3],current_state[2]||current_state[1]}; // opnumber1的赋值使能信号(对状态分类)
	wire [1:0] ALUsrcA      = {jalr,load_imm};
	wire [2:0] ALUsrcB1     = {branch,jal,jalr};
	wire [3:0] ALUsrcB2     = {load_imm,branch || R_calculate || multiply,load || I_calculate,store};


// 状态机控制

	// 状态机各个状态的one-hot编码
	localparam INIT      = 9'b000000001, //起始状态
			   IF        = 9'b000000010, //取指状态
			   IW        = 9'b000000100, //指令等待状态
			   ID        = 9'b000001000, //指令译码状态
			   EX        = 9'b000010000, //执行状态
			   STORE     = 9'b000100000, //内存写状态
			   LOAD      = 9'b001000000, //内存读状态
			   RDW       = 9'b010000000, //读数据等待状态
			   WB        = 9'b100000000; //写回（寄存器）状态

	// 状态机的现态和次态
	reg [8:0] current_state;
	reg [8:0] next_state;

    // 状态机第一段：描述状态寄存器current_state的同步状态更新
	always @(posedge clk)begin
		if(rst==1'b1)
			current_state <= INIT;
		else
			current_state <= next_state;
	end

	// 状态机第二段：根据current_state和输入信号，对next_state赋值
	always @(*)begin
		if(rst==1'b1)
			next_state = INIT;
		else begin
			case(current_state)
			INIT: 
				next_state = IF; //初始状态后下一状态为取指状态

			IF:   begin
				if(Inst_Req_Ready==1'b1) //取指状态需要等待Inst_Req_Ready拉高（内存控制器接收请求）后才能进入指令等待状态
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

			ID:   
				next_state = EX; //RISCV指令集通过ADDI x0,x0,0来实现NOP指令，所以NOP指令不需要单独跳转

			EX:   begin
				if(branch)
					next_state = IF;
				else if(calculate||shift||jump||load_imm||multiply)
					next_state = WB;
				else if(store)
					next_state = STORE;
				else if(load)
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
				next_state = IF;

			endcase
		end
	end

	// 状态机第三段：根据current_state，描述不同输出的同步变化
  
  // 时序逻辑部分
	// PC_next寄存器的赋值
	always @(posedge clk)begin
		if(current_state==INIT) // 初态置零
			PC_next_reg <= 32'b0;
		else if(current_state==IF || current_state==IW) // 从IF取指就可以开始计算PC+4了，开始之后经过2个时钟周期可以将结果传入PC_next寄存器中
			PC_next_reg <= ALUout;
	end
	// PC寄存器的赋值
	wire [2:0] branch_type = {funct3[2:1]==2'b00,funct3[2:1]==2'b10,funct3[2:1]==2'b11};
	wire branch_condition = branch_type[2] && (funct3[0]^zero) ||
							branch_type[1] && (funct3[0]^result_1[0]) ||
							branch_type[0] && (funct3[0]^carryout); // branch跳转条件
	always @(posedge clk)begin
		if(current_state==INIT)
			PC_reg <= 32'b0;
		else if(current_state==ID && ~jump && ~branch)
			PC_reg <= PC_next_reg;
		else if(current_state==EX)begin
			if(branch && branch_condition)
				PC_reg <= ALUout;
			else if(branch && ~branch_condition)
				PC_reg <= PC_next_reg;
			else if(jump)
				PC_reg <= ALUout;
		end
	end

	// IR寄存器的赋值
	always @(posedge clk)begin
		if(current_state[2] && Inst_Valid)
			IR <= Instruction;
	end

	// MDR寄存器的赋值
	always @(posedge clk)begin
		if(current_state[7] && Read_data_Valid)
			MDR <= Read_data;
	end

	// ALUout寄存器的赋值
	always @(posedge clk)begin
		ALUout <= result_1;
	end

  // 组合逻辑部分
	assign PC = PC_reg;

	// 1.reg_file模块控制信号赋值
	// 1.1 读操作
	assign RF_raddr1       = rs1;
	assign RF_raddr2       = rs2;
	// 1.2 写操作
	wire   write_condition = calculate||shift||load||load_imm||jump||multiply;
	assign RF_wen          = (current_state == WB)&&(write_condition);
	assign RF_waddr        = rd;

		// 寄存器堆写入数据的情况比较复杂，所以将RF_wdata信号分为几个信号之和，每一个信号代表了一类情况
	wire [31:0] calculate_wdata = {32{calculate}} & ALUout;
	wire [31:0] shift_wdata     = {32{shift}} & result_2;
	wire [63:0] full_multiply_result = RF_rdata1*RF_rdata2;
	wire [31:0] multiply_wdata  = {32{multiply}} & full_multiply_result[31:0];
	wire [31:0] jump_wdata      = {32{jump}} & PC_next_reg;
	wire [31:0] load_imm_wdata  = {32{load_imm}} & (opcode[5]? U_immediate:ALUout);
	wire [31:0] load_wdata; 
	// load型指令写入数据比较复杂，每一条指令的操作都不一样，同样将load_wdata分成几个信号之和来处理

	wire [ 7:0] target_byte     = MDR[{ALUout[1:0],3'b0}+:8];
	wire [15:0] target_halfword = MDR[{ALUout[1:0],3'b0}+:16];
	wire [31:0] zeroextended_target_byte = {{24{1'b0}},target_byte};
	wire [31:0] zeroextended_target_halfword = {{16{1'b0}},target_halfword};
	wire [31:0] signextended_target_byte = {{24{target_byte[7]}},target_byte};
	wire [31:0] signextended_target_halfword = {{16{target_halfword[15]}},target_halfword};
	
	assign load_wdata           = {32{load}} &
								  {{32{(funct3==3'b000)}} & signextended_target_byte |
	                               {32{(funct3==3'b001)}} & signextended_target_halfword |
								   {32{(funct3==3'b010)}} & MDR |
								   {32{(funct3==3'b100)}} & zeroextended_target_byte |
								   {32{(funct3==3'b101)}} & zeroextended_target_halfword};

	// RF_wdata信号等于几个分信号之和
	assign RF_wdata             = load_wdata | calculate_wdata | shift_wdata | multiply_wdata |jump_wdata | load_imm_wdata;

    // 2.ALU模块控制信号赋值
	assign opnumber_1               = {32{ALUsrc_state[0]}} & PC_reg |
									  {32{ALUsrc_state[1]}} & (ALUsrcA[1]? RF_rdata1:PC_reg) |
									  {32{ALUsrc_state[2]}} & (ALUsrcA[0]? PC_reg:RF_rdata1);
		//在IW和ID状态时，ALU分别计算PC+4和PC+offset；其他状态时，ALU计算单周期时需要计算的内容
	
	wire [31:0] signextended_Iimm   = {{20{I_immediate[11]}},I_immediate};
	wire [31:0] signextended_Jimm   = {{11{J_immediate[20]}},J_immediate};
	wire [31:0] signextended_Bimm   = {{19{B_immediate[12]}},B_immediate};
	wire [31:0] signextended_Simm   = {{20{S_immediate[11]}},S_immediate};
	assign opnumber_2               = {32{ALUsrc_state[0]}} & 32'b100 |
									  {32{ALUsrc_state[1]}} & {
										{32{ALUsrcB1[0]}} & signextended_Iimm |
										{32{ALUsrcB1[1]}} & signextended_Jimm |
										{32{ALUsrcB1[2]}} & signextended_Bimm } |
									  {32{ALUsrc_state[2]}} & {
										{32{ALUsrcB2[0]}} & signextended_Simm |
										{32{ALUsrcB2[1]}} & signextended_Iimm |
										{32{ALUsrcB2[2]}} & RF_rdata2 |
										{32{ALUsrcB2[3]}} & U_immediate};

	// 将ALUop信号的情况分为几类，在将这几类的信号按位或起来组成ALUop
	wire ADD_type              = (funct3==3'b000);
	wire AND_type              = funct3[2];
	wire SLT_type              = (funct3[2:1]==2'b01);
	wire [2:0] AND_op          = {~funct3[1],1'b0,funct3[1:0]==2'b10};
	wire [2:0] SLT_op          = {~funct3[0],2'b11};
	wire [2:0] ALUop_Rcal      = {3{R_calculate}} &
							     {{3{ADD_type}} & {funct7[5],2'b10} |
	                              {3{AND_type}} & AND_op |
							      {3{SLT_type}} & SLT_op};
	wire [2:0] ALUop_Ical      = {3{I_calculate}} &
								 {{3{ADD_type}} & {3'b010} |
								  {3{AND_type}} & AND_op |
								  {3{SLT_type}} & SLT_op};
	wire [2:0] ALUop_branch    = {3{branch}} &
								 {{3{~funct3[2]}} & 3'b110 |
								  {3{funct3[2:1]==2'b10}} & 3'b111 |
								  {3{funct3[1]}} & 3'b011};
	assign ALUop               = {3{ALUsrc_state[0] || ALUsrc_state[1]}} & {3'b010} |
								 {3{ALUsrc_state[2]}} & {
									{3{jump||load||store||load_imm}} & {3'b010} |
									ALUop_branch | ALUop_Rcal | ALUop_Ical
								 };
	
	// 3.shifter模块控制信号赋值
	assign shift_data   = shift? RF_rdata1 : RF_rdata2;
	assign shift_amount = {5{R_shift}} & RF_rdata2[4:0] |
						  {5{I_shift}} & I_immediate[4:0] |
						  {5{store}} & {ALUout[1:0],3'b000};
	assign shiftop      = {2{shift}} & {funct3[2],funct7[5]} |
						  {2{store}} & {2'b00};

	// 4.内存读写控制信号赋值
	assign Inst_Req_Valid = current_state[1];
	assign Inst_Ready     = current_state[0] | current_state[2];
	assign Read_data_Ready= current_state[0] | current_state[7];
	assign MemRead        = current_state[6];
	assign MemWrite       = current_state[5];

	assign Address        = {32{current_state[1]}} & PC_reg |
						    {32{current_state[5] || current_state[6]}} & {ALUout[31:2],{2'b0}};
	
	assign Write_data     = result_2;
	// 将Write_strb的每一位写成有关量的最简逻辑表达式
	wire [3:0] sb_strb    = {4{funct3[1:0]==2'b00}} & {ALUout[1:0]==2'b11,ALUout[1:0]==2'b10,ALUout[1:0]==2'b01,ALUout[1:0]==2'b00};
	wire [3:0] sh_strb    = {4{funct3[0]}} & {{2{ALUout[1]}},{2{~ALUout[1]}}};
	wire [3:0] sw_strb    = {4{funct3[1]}} & {4'b1111};
	assign Write_strb     = {4{store}} & (sb_strb | sh_strb | sw_strb);

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