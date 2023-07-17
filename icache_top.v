`timescale 10ns / 1ns

`define CACHE_SET	8
`define CACHE_WAY	4
`define TAG_LEN		24
`define LINE_LEN	256

module icache_top (
	input	      clk,
	input	      rst,
	
	//CPU interface
	/** CPU instruction fetch request to Cache: valid signal */
	input         from_cpu_inst_req_valid,
	/** CPU instruction fetch request to Cache: address (4 byte alignment) */
	input  [31:0] from_cpu_inst_req_addr,
	/** Acknowledgement from Cache: ready to receive CPU instruction fetch request */
	output        to_cpu_inst_req_ready,
	
	/** Cache responses to CPU: valid signal */
	output        to_cpu_cache_rsp_valid,
	/** Cache responses to CPU: 32-bit Instruction value */
	output [31:0] to_cpu_cache_rsp_data,
	/** Acknowledgement from CPU: Ready to receive Instruction */
	input	      from_cpu_cache_rsp_ready,

	//Memory interface (32 byte aligned address)
	/** Cache sending memory read request: valid signal */
	output        to_mem_rd_req_valid,
	/** Cache sending memory read request: address (32 byte alignment) */
	output [31:0] to_mem_rd_req_addr,
	/** Acknowledgement from memory: ready to receive memory read request */
	input         from_mem_rd_req_ready,

	/** Memory return read data: valid signal of one data beat */
	input         from_mem_rd_rsp_valid,
	/** Memory return read data: 32-bit one data beat */
	input  [31:0] from_mem_rd_rsp_data,
	/** Memory return read data: if current data beat is the last in this burst data transmission */
	input         from_mem_rd_rsp_last,
	/** Acknowledgement from cache: ready to receive current data beat */
	output        to_mem_rd_rsp_ready
);

	localparam   WAIT     = 8'b00000001,  // 等待CPU
				 TAG_RD   = 8'b00000010,  // 读标记
				 CACHE_RD = 8'b00000100,  // 读缓存
				 RESP     = 8'b00001000,  // CPU应答
				 EVICT    = 8'b00010000,  // 替换
				 MEM_RD   = 8'b00100000,  // 读内存
				 RECV     = 8'b01000000,  // 接收读数据
				 REFILL   = 8'b10000000;  // cache block重填

	reg [7:0]   current_state;
	reg [7:0]   next_state;

	// 状态机第一段：描述状态寄存器current_state的同步状态更新
	always @(posedge clk)begin
		if(rst == 1'b1)
			current_state <= WAIT;
		else
			current_state <= next_state;
	end

	// 状态机第二段：根据current_state和输入信号，对next_state赋值
	always @(*)begin
		case(current_state)
		WAIT:begin
			if(from_cpu_inst_req_valid)
				next_state = TAG_RD;
			else
				next_state = WAIT;
			end
		TAG_RD:begin
			if(read_hit[0] | read_hit[1] | read_hit[2] | read_hit[3])
				next_state = CACHE_RD;
			else
				next_state = EVICT;
			end
		CACHE_RD:
			next_state = RESP;
		RESP:begin
			if(from_cpu_cache_rsp_ready)
				next_state = WAIT;
			else
				next_state = RESP;
			end
		EVICT:
			next_state = MEM_RD;
		MEM_RD:begin
			if(from_mem_rd_req_ready)
				next_state = RECV;
			else
				next_state = MEM_RD;
			end
		RECV:begin
			if(from_mem_rd_rsp_valid && from_mem_rd_rsp_last)
				next_state = REFILL;
			else
				next_state = RECV;
			end
		REFILL:
			next_state = RESP;
		default:
			next_state = current_state;
		
		endcase
	end

	// icache的tag域与data域写使能控制信号
	wire [ 3:0] cache_wen;
	// icache每一组组内的读写地址
	wire [ 2:0] raddr;
	wire [ 2:0] waddr;
	// icache每一组的tag域读写数据
	wire [23:0] rtag_0, rtag_1, rtag_2, rtag_3;
	wire [23:0] wtag;
	// icache每一组的data域读写数据
	wire [255:0] rdata_0, rdata_1, rdata_2, rdata_3;
	wire [255:0] wdata;

	//wire [ 31:0] wword = 32'b0;
	//wire flag = 1'b0;

	// ichche中的valid_array
	reg [7:0] valid_array [3:0];
	// 例化icache中的4个way上的tag_array和data_array
	tag_array tag_array_0(clk,waddr,raddr,cache_wen[0],wtag,rtag_0);
	tag_array tag_array_1(clk,waddr,raddr,cache_wen[1],wtag,rtag_1);
	tag_array tag_array_2(clk,waddr,raddr,cache_wen[2],wtag,rtag_2);
	tag_array tag_array_3(clk,waddr,raddr,cache_wen[3],wtag,rtag_3);

	data_array data_array_0(clk,waddr,raddr,cache_wen[0],wdata,rdata_0);
	data_array data_array_1(clk,waddr,raddr,cache_wen[1],wdata,rdata_1);
	data_array data_array_2(clk,waddr,raddr,cache_wen[2],wdata,rdata_2);
	data_array data_array_3(clk,waddr,raddr,cache_wen[3],wdata,rdata_3);

	// 在输入地址中截取相应位置的信号
	wire [ 2:0] addr_index      = from_cpu_inst_req_addr[ 7:5]; // 指令地址的index域，表示cache组内地址
	wire [ 4:0] addr_offset     = from_cpu_inst_req_addr[ 4:0]; // 指令地址的offset域，表示cache块内偏移地址
	wire [23:0] addr_tag        = from_cpu_inst_req_addr[31:8]; // 指令地址的tag域，用于和cache block中的标签tag进行比较

	// icache中需要的一些寄存器
	reg [  2:0] waddr_reg;
	reg [255:0] new_block_data;


	// 在WAIT阶段拉高to_cpu_inst_req_ready信号
	assign to_cpu_inst_req_ready = (current_state == WAIT);

	// 在TAG_RD阶段，根据输入地址index域，读出4路valid+tag，并与输入地址的tag域比较，产生Read Hit/Read miss信号
	assign raddr = addr_index;
	wire [3:0] read_hit;
	assign read_hit[0] = valid_array[0] [addr_index] && (addr_tag == rtag_0);
	assign read_hit[1] = valid_array[1] [addr_index] && (addr_tag == rtag_1);
	assign read_hit[2] = valid_array[2] [addr_index] && (addr_tag == rtag_2);
	assign read_hit[3] = valid_array[3] [addr_index] && (addr_tag == rtag_3);

	// 在CACHE_RD阶段，从命中的cache block中读出32 byte，并根据输入地址的offset域，选择出要返回的指令码
	wire [255:0] target_block = {256{read_hit[0]}} & rdata_0 |
						  	    {256{read_hit[1]}} & rdata_1 |
								{256{read_hit[2]}} & rdata_2 |
								{256{read_hit[3]}} & rdata_3;
	
	
	// 在RESP阶段拉高to_cpu_cache_rsp_valid端口信号，并将要返回的指令码输出，到to_cpu_cache_rsp_data端口
	assign to_cpu_cache_rsp_valid = (current_state == RESP);
	assign to_cpu_cache_rsp_data  = target_block [{addr_offset,3'b0}+:32];

	// 在EVICT阶段根据替换算法，从4路cache block中选择一个进行替换，将被替换block对应的valid清0

	reg [1:0] way_counter;

	always @(posedge clk)begin
		if(rst == 1'b1)
			way_counter <= 2'b0;
		else if(current_state == EVICT)
			way_counter <= way_counter + 2'b1;
	end

	// valid_array寄存器更新
	always @(posedge clk)begin // valid_array寄存器的赋值
		if(rst == 1'b1)begin
			valid_array[0] <= 8'b0; // 初始全部设为0
			valid_array[1] <= 8'b0;
			valid_array[2] <= 8'b0;
			valid_array[3] <= 8'b0;
		end
		else begin
			case(current_state)
			EVICT:begin
				valid_array[way_counter][addr_index] <= 1'b0;
				end
			REFILL:begin
				valid_array[way_counter][addr_index] <= 1'b1;
				end
			endcase
		end
	end

	// 在MEM_RD阶段向内存发送输入请求所在的cache block地址（32 byte对齐地址），拉高to_mem_rd_req_valid
	assign to_mem_rd_req_valid = (current_state == MEM_RD);
	assign to_mem_rd_req_addr = {from_cpu_inst_req_addr[31:5],5'b0};

	// 在RECV阶段拉高to_mem_rd_rsp_ready
	assign to_mem_rd_rsp_ready = (current_state == RECV);

	// 每当from_mem_rd_rsp_valid拉高时，接收4-byte from_mem_rd_rsp_data，直至from_mem_rd_rsp_last标记的最后一个4-byte数据已接收
	
	// waddr_reg寄存器的更新
	always@(posedge clk)begin
		if(rst == 1'b1)
			waddr_reg <= 3'b000;
		else if(current_state == RECV && from_mem_rd_rsp_valid)
			waddr_reg <= waddr_reg + 3'b001;
	end
	// new_block_data寄存器的更新
		always@(posedge clk)begin
		if(rst == 1'b1)
			new_block_data <= 256'b0;
		else if(current_state == RECV && from_mem_rd_rsp_valid)
			new_block_data[{waddr_reg,5'b0}+:32] <= from_mem_rd_rsp_data;
	end
	
	// 在REFILL阶段将已收到的32-byte数据填入选中cache block，同时更新对应的tag和valid，并根据输入地址offset域，返回指令码
	assign wtag  = addr_tag;	  // tag域使用CPU输入地址的tag域
	assign wdata = new_block_data;
	assign cache_wen = {4{current_state == REFILL}} & 
					   {{way_counter==2'b11},{way_counter==2'b10},{way_counter==2'b01},{way_counter==2'b00}};
	assign waddr = addr_index;   // 写入位置对应于CPU发送地址的的index域(0~7)

endmodule