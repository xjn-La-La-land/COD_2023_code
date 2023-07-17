`timescale 10ns / 1ns

`define CACHE_SET	8
`define CACHE_WAY	4
`define TAG_LEN		24
`define LINE_LEN	256

module dcache_top (
	input	      clk,
	input	      rst,
  
	//CPU interface
	/** CPU memory/IO access request to Cache: valid signal */
	input         from_cpu_mem_req_valid,
	/** CPU memory/IO access request to Cache: 0 for read; 1 for write (when req_valid is high) */
	input         from_cpu_mem_req,
	/** CPU memory/IO access request to Cache: address (4 byte alignment) */
	input  [31:0] from_cpu_mem_req_addr,
	/** CPU memory/IO access request to Cache: 32-bit write data */
	input  [31:0] from_cpu_mem_req_wdata,
	/** CPU memory/IO access request to Cache: 4-bit write strobe */
	input  [ 3:0] from_cpu_mem_req_wstrb,
	/** Acknowledgement from Cache: ready to receive CPU memory access request */
	output        to_cpu_mem_req_ready,
		
	/** Cache responses to CPU: valid signal */
	output        to_cpu_cache_rsp_valid,
	/** Cache responses to CPU: 32-bit read data */
	output [31:0] to_cpu_cache_rsp_data,
	/** Acknowledgement from CPU: Ready to receive read data */
	input         from_cpu_cache_rsp_ready,
		
	//Memory/IO read interface
	/** Cache sending memory/IO read request: valid signal */
	output        to_mem_rd_req_valid,
	/** Cache sending memory read request: address
	  * 4 byte alignment for I/O read 
	  * 32 byte alignment for cache read miss */
	output [31:0] to_mem_rd_req_addr,
        /** Cache sending memory read request: burst length
	  * 0 for I/O read (read only one data beat)
	  * 7 for cache read miss (read eight data beats) */
	output [ 7:0] to_mem_rd_req_len,
        /** Acknowledgement from memory: ready to receive memory read request */
	input	      from_mem_rd_req_ready,

	/** Memory return read data: valid signal of one data beat */
	input	      from_mem_rd_rsp_valid,
	/** Memory return read data: 32-bit one data beat */
	input  [31:0] from_mem_rd_rsp_data,
	/** Memory return read data: if current data beat is the last in this burst data transmission */
	input	      from_mem_rd_rsp_last,
	/** Acknowledgement from cache: ready to receive current data beat */
	output        to_mem_rd_rsp_ready,

	//Memory/IO write interface
	/** Cache sending memory/IO write request: valid signal */
	output        to_mem_wr_req_valid,
	/** Cache sending memory write request: address
	  * 4 byte alignment for I/O write 
	  * 4 byte alignment for cache write miss
      * 32 byte alignment for cache write-back */
	output [31:0] to_mem_wr_req_addr,
        /** Cache sending memory write request: burst length
          * 0 for I/O write (write only one data beat)
          * 0 for cache write miss (write only one data beat)
          * 7 for cache write-back (write eight data beats) */
	output [ 7:0] to_mem_wr_req_len,
        /** Acknowledgement from memory: ready to receive memory write request */
	input         from_mem_wr_req_ready,

	/** Cache sending memory/IO write data: valid signal for current data beat */
	output        to_mem_wr_data_valid,
	/** Cache sending memory/IO write data: current data beat */
	output [31:0] to_mem_wr_data,
	/** Cache sending memory/IO write data: write strobe
	  * 4'b1111 for cache write-back
	  * other values for I/O write and cache write miss according to the original CPU request*/ 
	output [ 3:0] to_mem_wr_data_strb,
	/** Cache sending memory/IO write data: if current data beat is the last in this burst data transmission */
	output        to_mem_wr_data_last,
	/** Acknowledgement from memory/IO: ready to receive current data beat */
	input	      from_mem_wr_data_ready
);

	localparam WAIT      = 13'b0000000000001, // 等待CPU访存指令						  // 001
			   TAG_RD	 = 13'b0000000000010, // 判断请求地址是否可缓存，以及是否命中		// 002
			   CACHE_WR  = 13'b0000000000100, // 读/写缓存								 // 004
			   RESP      = 13'b0000000001000, // CPU应答								 // 008
			   EVICT     = 13'b0000000010000, // 选取一块cache进行替换					  // 010
			   MEM_WR    = 13'b0000000100000, // 写内存响应								 // 020
			   WB        = 13'b0000001000000, // 将dirty的cache block写回内存			  // 040
			   MEM_RD    = 13'b0000010000000, // 读内存响应								 // 080
			   RECV      = 13'b0000100000000, // 接收从内存中读出的cache block			  // 100
			   REFILL    = 13'b0001000000000, // cache block重填						 // 200
			   LDST      = 13'b0010000000000, // 旁路内存读/写响应						  // 400
			   RDW       = 13'b0100000000000, // 接收从内存读出的1个字					  // 800
			   WRW       = 13'b1000000000000; // 将1个字写入内存						  // 1000

	reg [12:0]	current_state;
	reg [12:0]	next_state;

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
			if(from_cpu_mem_req_valid)
				next_state = TAG_RD;
			else
				next_state = WAIT;
			end
		TAG_RD:begin
			if(~accept)
				next_state = LDST;
			else if(req_reg == 1'b0 && (hit[0] | hit[1] | hit[2] | hit[3]))
				next_state = RESP;
			else if(req_reg == 1'b1 && (hit[0] | hit[1] | hit[2] | hit[3]))
				next_state = CACHE_WR;
			else
				next_state = EVICT;
		end
		CACHE_WR:
			next_state = WAIT;
		RESP:begin
			if(from_cpu_cache_rsp_ready)
				next_state = WAIT;
			else
				next_state = RESP;
		end
		EVICT:begin
			if(dirty_array[way_counter][addr_index] == 1'b1)// 若需要替换的cache block的dirty为1，则进入MEM_WR状态，将它先写回内存
				next_state = MEM_WR;
			else                                            // 若需要替换的cache block的dirty为0，则进入MEM_RD状态，开始替换
				next_state = MEM_RD;
		end
		MEM_WR:begin
			if(from_mem_wr_req_ready)
				next_state = WB;
			else
				next_state = MEM_WR;
		end
		WB:begin
			if(from_mem_wr_data_ready & to_mem_wr_data_last)
				next_state = MEM_RD;
			else
				next_state = WB;
		end
		MEM_RD:begin
			if(from_mem_rd_req_ready)
				next_state = RECV;
			else
				next_state = MEM_RD;
		end
		RECV:begin
			if(from_mem_rd_rsp_valid & from_mem_rd_rsp_last)
				next_state = REFILL;
			else
				next_state = RECV;
		end
		REFILL:begin
			if(req_reg == 1'b1)
				next_state = CACHE_WR;
			else
				next_state = RESP;
		end
		LDST:begin
			if(req_reg == 1'b0 && from_mem_rd_req_ready)
				next_state = RDW;
			else if(req_reg == 1'b1 && from_mem_wr_req_ready)
				next_state = WRW;
			else
				next_state = LDST;
		end
		RDW:begin
			if(from_mem_rd_rsp_valid & from_mem_rd_rsp_last)
				next_state = RESP;
			else
				next_state = RDW;
		end
		WRW:begin
			if(from_mem_wr_data_ready & to_mem_wr_data_last)
				next_state = WAIT;
			else
				next_state = WRW;
		end
		default:
			next_state = current_state;
		endcase
	end

	// dcache的tag域与data域写使能控制信号
	wire [ 3:0] cache_data_wen;
	wire [ 3:0] cache_tag_wen;
	// dcache每一组组内的读写地址
	wire [ 2:0] raddr;
	wire [ 2:0] waddr;
	// dcache每一组的tag域读写数据
	wire [23:0] rtag_0, rtag_1, rtag_2, rtag_3;
	wire [23:0] wtag;
	// dcache每一组的data域读写数据
	wire [255:0] rdata_0, rdata_1, rdata_2, rdata_3;
	wire [255:0] wdata;

	//wire [ 31:0] wword;
	//wire flag;

	// dchche中的valid_array
	reg [7:0] valid_array [3:0];
	// dcache中的dirty_array
	reg [7:0] dirty_array [3:0];
	// 例化dcache中的4个way上的tag_array和data_array
	tag_array tag_array_0(clk,waddr,raddr,cache_tag_wen[0],wtag,rtag_0);
	tag_array tag_array_1(clk,waddr,raddr,cache_tag_wen[1],wtag,rtag_1);
	tag_array tag_array_2(clk,waddr,raddr,cache_tag_wen[2],wtag,rtag_2);
	tag_array tag_array_3(clk,waddr,raddr,cache_tag_wen[3],wtag,rtag_3);

	data_array data_array_0(clk,waddr,raddr,cache_data_wen[0],wdata,rdata_0);
	data_array data_array_1(clk,waddr,raddr,cache_data_wen[1],wdata,rdata_1);
	data_array data_array_2(clk,waddr,raddr,cache_data_wen[2],wdata,rdata_2);
	data_array data_array_3(clk,waddr,raddr,cache_data_wen[3],wdata,rdata_3);

	// 在输入地址中截取相应位置的信号
	wire [ 2:0] addr_index      = addr_reg[ 7:5]; // 指令地址的index域，表示cache组内地址
	wire [ 4:0] addr_offset     = addr_reg[ 4:0]; // 指令地址的offset域，表示cache块内偏移地址
	wire [23:0] addr_tag        = addr_reg[31:8]; // 指令地址的tag域，用于和cache block中的标签tag进行比较
	
	// dcache中用来保存cpu输入信号的寄存器
	reg [31:0] addr_reg;    // 保存访存地址address
	reg [31:0] wdata_reg;   // 保存内存写数据data
	reg [ 3:0] strb_reg;    // 保存内存写的strb信号
	reg        req_reg;     // 保存访存请求为读还是写

	always @(posedge clk)begin  // addr_reg寄存器的赋值
		if(rst == 1'b1)
			addr_reg <= 32'b0;
		else if(current_state == WAIT && from_cpu_mem_req_valid)
			addr_reg <= from_cpu_mem_req_addr;
	end

	always @(posedge clk)begin  // wdata_reg寄存器的赋值
		if(rst == 1'b1)
			wdata_reg <= 32'b0;
		else if(current_state == WAIT && from_cpu_mem_req_valid)
			wdata_reg <= from_cpu_mem_req_wdata;
	end

	always @(posedge clk)begin  // strb_reg寄存器的赋值
		if(rst == 1'b1)
			strb_reg <= 4'b0;
		else if(current_state == WAIT && from_cpu_mem_req_valid)
			strb_reg <= from_cpu_mem_req_wstrb;
	end

	always @(posedge clk)begin  // req_reg寄存器的赋值
		if(rst == 1'b1)
			req_reg <= 1'b0;
		else if(current_state == WAIT && from_cpu_mem_req_valid)
			req_reg <= from_cpu_mem_req;
	end


	wire accept = (addr_reg[31:30] == 2'b0) && ~(addr_reg[29:5] == 25'b0);  // accept判断访问地址是否是可缓存的
	wire [3:0] hit;                                                         // hit的四位分别代表4路dcache的读/写是否命中
	assign hit[0] = accept & valid_array[0] [addr_index] & (addr_tag == rtag_0);
	assign hit[1] = accept & valid_array[1] [addr_index] & (addr_tag == rtag_1);
	assign hit[2] = accept & valid_array[2] [addr_index] & (addr_tag == rtag_2);
	assign hit[3] = accept & valid_array[3] [addr_index] & (addr_tag == rtag_3);
	wire [1:0] hit_index = {2{hit[3]}} & {2'b11} |
						   {2{hit[2]}} & {2'b10} |
						   {2{hit[1]}} & {2'b01} |
						   {2{hit[0]}} & {2'b00};                           // hit_index代表读/写命中的way的编号


	// valid_array 寄存器的赋值
	always@(posedge clk)begin
		if(rst == 1'b1)begin
			valid_array[0] <= 8'b0;
			valid_array[1] <= 8'b0;
			valid_array[2] <= 8'b0;
			valid_array[3] <= 8'b0;
		end
		else begin
			if(current_state == EVICT)
				valid_array[way_counter][addr_index] <= 1'b0; // 替换状态，将被替换的block对应的valid清0
			else if(current_state == REFILL)
				valid_array[way_counter][addr_index] <= 1'b1; // 重填阶段，将被重填的block对应的valid置1
		end
	end

	// dirty_array 寄存器的赋值
	always@(posedge clk)begin
		if(rst == 1'b1)begin
			dirty_array[0] <= 8'b0;
			dirty_array[1] <= 8'b0;
			dirty_array[2] <= 8'b0;
			dirty_array[3] <= 8'b0;
		end
		else begin
			if(current_state == CACHE_WR)
				dirty_array[hit_index][addr_index] <= 1'b1;
			else if(current_state == REFILL)
				dirty_array[way_counter][addr_index] <= 1'b0;
		end
	end


	reg [1:0] way_counter; // dcache 读写缺失的替换策略采用顺序替换，way_counter用来计数当前替换的way的编号
	always @(posedge clk)begin
		if(rst == 1'b1)begin
			way_counter <= 2'b0;
		end
		else if(current_state == TAG_RD && hit == 4'b0)
			way_counter <= way_counter + 2'b1;
	end


	reg [2:0] word_counter; // word_counter在向内存写数据时用于计数当前传到第几个字
	always @(posedge clk)begin
		if(rst == 1'b1)
			word_counter <= 3'b0;
		else if((current_state == WB && from_mem_wr_data_ready) || (current_state == RECV && from_mem_rd_rsp_valid))
			word_counter <= word_counter + 3'b001;
	end


	// dcache 向 cpu 的输出信号赋值
	assign to_cpu_mem_req_ready = (current_state == WAIT);            // 在WAIT阶段拉高to_cpu_mem_req_ready信号
	assign to_cpu_cache_rsp_valid = (current_state == RESP);          // 在RESP阶段拉高to_cpu_cache_rsp_valid端口信号
	assign to_cpu_cache_rsp_data  = accept? target_word : by_rd_data; // 在RESP阶段将要返回的数据输出到to_cpu_cache_rsp_data端口

	// 读命中时取出目标数据
	wire [255:0] target_block = {256{hit[0]}} & rdata_0 |             
						  	    {256{hit[1]}} & rdata_1 |
								{256{hit[2]}} & rdata_2 |
								{256{hit[3]}} & rdata_3;              // 从命中的way中读出整块cache_block

	wire [ 31:0] target_word  = target_block [{addr_offset,3'b0}+:32];// 从cache_block中截取出一个字

	// 写命中时修改读出的数据
	wire [ 31:0] changed_target_word = {{8{~strb_reg[3]}} & target_word[31:24] | {8{strb_reg[3]}} & wdata_reg[31:24],
										{8{~strb_reg[2]}} & target_word[23:16] | {8{strb_reg[2]}} & wdata_reg[23:16],
										{8{~strb_reg[1]}} & target_word[15: 8] | {8{strb_reg[1]}} & wdata_reg[15: 8],
										{8{~strb_reg[0]}} & target_word[ 7: 0] | {8{strb_reg[0]}} & wdata_reg[ 7: 0]};  // 根据strb将目标字中的对应字节更新

	
	wire [255:0] changed_target_block = {{32{addr_offset[4:2] == 3'b111}} & changed_target_word | {32{addr_offset[4:2] != 3'b111}} & target_block[255:224],
										 {32{addr_offset[4:2] == 3'b110}} & changed_target_word | {32{addr_offset[4:2] != 3'b110}} & target_block[223:192],
										 {32{addr_offset[4:2] == 3'b101}} & changed_target_word | {32{addr_offset[4:2] != 3'b101}} & target_block[191:160],
										 {32{addr_offset[4:2] == 3'b100}} & changed_target_word | {32{addr_offset[4:2] != 3'b100}} & target_block[159:128],
										 {32{addr_offset[4:2] == 3'b011}} & changed_target_word | {32{addr_offset[4:2] != 3'b011}} & target_block[127: 96],
										 {32{addr_offset[4:2] == 3'b010}} & changed_target_word | {32{addr_offset[4:2] != 3'b010}} & target_block[ 95: 64],
										 {32{addr_offset[4:2] == 3'b001}} & changed_target_word | {32{addr_offset[4:2] != 3'b001}} & target_block[ 63: 32],
										 {32{addr_offset[4:2] == 3'b000}} & changed_target_word | {32{addr_offset[4:2] != 3'b000}} & target_block[ 31:  0]};

	// dcache 读命中时相关信号的赋值
	assign raddr = addr_index;
	

	// dcache 写命中时相关信号的赋值
	assign waddr = addr_index;
	assign cache_data_wen = {4{current_state == CACHE_WR}} & hit |
							{4{current_state == REFILL}} & {{way_counter==2'b11},{way_counter==2'b10},{way_counter==2'b01},{way_counter==2'b00}};
	//assign wword = changed_target_word;
	//ssign flag  = (current_state == CACHE_WR);

	
	// dcache 向内存发送读请求时的输出信号赋值
	assign to_mem_rd_req_valid = (current_state == MEM_RD) || ((req_reg == 1'b0) && (current_state == LDST)); // 拉高to_mem_rd_req_valid
	assign to_mem_rd_req_len = {8{current_state == MEM_RD}} & 8'b111 | {8{current_state == LDST}} & 8'b0;
	assign to_mem_rd_req_addr = {32{current_state == MEM_RD || current_state == RECV}} & {addr_tag, addr_index, 5'b0} |
								{32{current_state == LDST || current_state == RDW}} & addr_reg;  // 在MEM_RD阶段向内存(to_mem_rd_req_addr)发送输入请求所在的cache block地址（32 byte对齐地址）

	assign to_mem_rd_rsp_ready = (current_state == RECV || current_state == RDW); // 在RECV阶段和RDW阶段拉高to_mem_rd_rsp_ready

	reg [255:0] new_block_data; // 每当from_mem_rd_rsp_valid拉高时，接收4-byte from_mem_rd_rsp_data，直至from_mem_rd_rsp_last标记的最后一个4-byte数据已接收
	always @(posedge clk)begin
		if(rst == 1'b1)
			new_block_data <= 256'b0;
		else if(current_state == RECV && from_mem_rd_rsp_valid)
			new_block_data[{word_counter,5'b0}+:32] <= from_mem_rd_rsp_data;
	end
	

	// dcache 向内存发送写请求时的输出信号
	assign to_mem_wr_req_valid = (current_state == MEM_WR) || ((req_reg == 1'b1) && (current_state == LDST)); // 在MEM_WR状态拉高to_mem_wr_req_valid，等待from_mem_wr_req_ready拉高
	assign to_mem_wr_req_len = {8{current_state == MEM_WR}} & 8'b111 |
							   {8{current_state == LDST}} & 8'b0;   // 向内存发送写字长to_mem_wr_req_len

	wire [23:0] target_tag = {24{way_counter == 2'b00}} & rtag_0 |
					  		 {24{way_counter == 2'b01}} & rtag_1 |
					  		 {24{way_counter == 2'b10}} & rtag_2 |
					  		 {24{way_counter == 2'b11}} & rtag_3;   // 需要写回的块的tag域

	assign to_mem_wr_req_addr = {32{current_state == MEM_WR || current_state == WB}} & {target_tag, addr_index, 5'b0} |
								{32{current_state == LDST || current_state == WRW}} & addr_reg; // 向内存发送写地址，to_mem_wr_req_addr需要32 byte对齐

	
	assign to_mem_wr_data_valid = (current_state == WB || current_state == WRW);  // 在WB状态，拉高to_mem_wr_data_valid
	assign to_mem_wr_data_strb = {4{current_state == WB}} & {4'b1111} |
								 {4{current_state == WRW}} & strb_reg;  // 写回时设置to_mem_wr_data_strb = 4'b1111;
	assign to_mem_wr_data_last = (current_state == WB) && (word_counter == 3'b111) || (current_state == WRW); 	// 当计数器word_counter==to_mem_wr_req_len时拉高last
	wire [255:0] target_data = {256{way_counter == 2'b00}} & rdata_0 |
							   {256{way_counter == 2'b01}} & rdata_1 |
							   {256{way_counter == 2'b10}} & rdata_2 |
							   {256{way_counter == 2'b11}} & rdata_3;
	
	assign to_mem_wr_data = {32{current_state == WB}} & target_data[{word_counter, 5'b0}+:32] |
							{32{current_state == WRW}} & wdata_reg;  // 每当from_mem_wr_data_ready拉高时，将cache block中4 byte的数据传给to_mem_wr_data，直至to_mem_wr_data_last标记的最后一个4-byte数据已接收
	
	
	// 重填阶段给tag_array和data_array的输入信号
	assign wdata = {256{current_state == CACHE_WR}} & changed_target_block |
				   {256{current_state == REFILL}} & new_block_data; // 在REFILL阶段将已收到的32-byte数据填入选中cache block
	assign wtag  = addr_tag;	  // tag域使用CPU输入地址的tag域
	assign cache_tag_wen = {4{current_state == REFILL}} & 
					   	   {{way_counter==2'b11},{way_counter==2'b10},{way_counter==2'b01},{way_counter==2'b00}};
	

	reg [31:0] by_rd_data; // by_rd_data寄存器存放旁路从内存中读出的数据
	always @(posedge clk)begin
		if(rst == 1'b1)
			by_rd_data <= 32'b0;
		else if(current_state == RDW && from_mem_rd_rsp_valid)
			by_rd_data <= from_mem_rd_rsp_data;
	end

endmodule