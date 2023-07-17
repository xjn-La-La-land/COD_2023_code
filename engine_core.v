`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Xu Zhang (zhangxu415@mails.ucas.ac.cn)
// 
// Create Date: 06/14/2018 11:39:09 AM
// Design Name: 
// Module Name: dma_core
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module engine_core #(
	parameter integer  DATA_WIDTH       = 32
)
(
// 其他信号
	input    clk,
	input    rst,
	output   intr,
	
// 控制/状态寄存器与处理器的互连端口
	output [31:0]       src_base,
	output [31:0]       dest_base,
	output [31:0]       tail_ptr,
	output [31:0]       head_ptr,
	output [31:0]       dma_size,
	output [31:0]       ctrl_stat,

	input  [31:0]	    reg_wr_data,
	input  [ 5:0]       reg_wr_en,
  
  
// 读引擎与内存控制器的互连端口
	output [31:0]       rd_req_addr,
	output [ 4:0]       rd_req_len,
	output              rd_req_valid,
	
	input               rd_req_ready,
	input  [31:0]       rd_rdata,
	input               rd_last,
	input               rd_valid,
	output              rd_ready,

// 写引擎与与内存控制器的互连端口
	output [31:0]       wr_req_addr,
	output [ 4:0]       wr_req_len,
	output              wr_req_valid,

	input               wr_req_ready,
	output [31:0]       wr_data,
	output              wr_valid,
	input               wr_ready,
	output              wr_last,

// 读/写引擎与FIFO队列接口信号
	output              fifo_rden,
	output [31:0]       fifo_wdata,
	output              fifo_wen,
	
	input  [31:0]       fifo_rdata,
	input               fifo_is_empty,
	input               fifo_is_full
);
	// TODO: Please add your logic design here

	localparam IDLE     = 5'b00001,// dma闲置状态
			   RD_REQ   = 5'b00010,// 等待burst读请求应答状态
			   RD       = 5'b00100,// dma内存读状态(向fifo中写入数据)
			   WR_REQ   = 5'b01000,// 等待burst写请求应答状态
			   WR       = 5'b10000;// dma内存写状态(从fifo中读出数据)

	reg [4:0] current_state;// dma当前状态
	reg [4:0] next_state;	// dma次态

	// dma读写引擎状态机
	always @(posedge clk)begin
		if(rst == 1'b1)
			current_state <= IDLE;
		else
			current_state <= next_state;
	end

	always @(*)begin
		if(rst == 1'b1)
			next_state = IDLE;
		else begin
			case(current_state)
			IDLE:begin
				if((head_ptr_reg != tail_ptr_reg) && (ctrl_stat_reg[0] == 1'b1))begin
					next_state = RD_REQ;
				end
				else begin
					next_state = IDLE;
				end
				end
			RD_REQ:begin
				if(rd_req_ready)begin
					next_state = RD;
				end
				else begin
					next_state = RD_REQ;
				end
				end
			RD:begin
				if(rd_ready && rd_valid && rd_last && (~fifo_is_full))begin
					next_state = RD_REQ;
				end
				else if(rd_ready && rd_valid && rd_last && fifo_is_full)begin
					next_state = WR_REQ;
				end
				else begin
					next_state = RD;
				end
				end
			WR_REQ:begin
				if(wr_req_ready)begin
					next_state = WR;
				end
				else begin
					next_state = WR_REQ;
				end
				end
			WR:begin
				if(wr_valid && wr_ready && wr_last && (~fifo_is_empty))begin
					next_state = WR_REQ;
				end
				else if(wr_valid && wr_ready && wr_last && fifo_is_empty)begin
					next_state = IDLE;
				end
				else begin
					next_state = WR;
				end
				end
			default:begin
				next_state = current_state;
				end
			endcase
		end
	end


	reg [31:0] rd_counter; // dma读引擎传输数据量统计,以字节为单位
	reg        rd_finished; // dma子缓冲区读内存完成标志
	always @(posedge clk)begin
		if(rst == 1'b1)begin
			rd_counter <= 32'b0;
		end
		else if(rd_ready && rd_valid && rd_last)begin
			rd_counter <= rd_counter + 32'b100000;// 每次dma突发读完成后rd_counter += 32
		end
		else if(rd_counter == dma_size_reg)begin
			rd_counter <= 32'b0;
		end
	end

	always @(posedge clk)begin
		if(rst == 1'b1)begin
			rd_finished <= 1'b0;
		end
		else if(rd_counter == dma_size_reg)begin
			rd_finished <= 1'b1;
		end
		else if(subbuffer_finished)begin
			rd_finished <= 1'b0;
		end
	end

	reg [31:0] wr_counter;	// dma写引擎传输数据量统计,以字节为单位
	reg        wr_finished; // dma子缓冲区写内存完成标志

	always @(posedge clk)begin
		if(rst == 1'b1)begin
			wr_counter <= 32'b0;
		end
		else if(wr_valid && wr_ready && wr_last)begin
			wr_counter <= wr_counter + 32'b100000;// 每次dma突发写完成后wr_counter += 32
		end
		else if(wr_counter == dma_size_reg)begin
			wr_counter <= 32'b0;
		end
	end

	always @(posedge clk)begin
		if(rst == 1'b1)begin
			wr_finished <= 1'b0;
		end
		else if(wr_counter == dma_size_reg)begin
			wr_finished <= 1'b1;
		end
		else if(subbuffer_finished)begin
			wr_finished <= 1'b0;
		end
	end

	wire subbuffer_finished = rd_finished && wr_finished;

	reg [31:0] src_base_reg;
	reg [31:0] dest_base_reg;
	reg [31:0] head_ptr_reg;
	reg [31:0] tail_ptr_reg;
	reg [31:0] dma_size_reg;
	reg [31:0] ctrl_stat_reg;

	// CPU 和 dma 对I/O寄存器的赋值
	always @(posedge clk)begin
		if(rst == 1'b1)begin
			src_base_reg <= 32'b0;
			dest_base_reg <= 32'b0;
			head_ptr_reg <= 32'b0;
			tail_ptr_reg <= 32'b0;
			dma_size_reg <= 32'b1;// dma_size的初值不能取为0，否则初始时会导致subbuffer_finished=1，直接开始中断
			ctrl_stat_reg <= 32'b0;
		end
		else if(subbuffer_finished)begin
			tail_ptr_reg <= tail_ptr_reg + dma_size_reg;
			ctrl_stat_reg[31] <= 1'b1;
		end
		else begin
			case(reg_wr_en)
			6'b000001:begin
				src_base_reg <= reg_wr_data;
			end
			6'b000010:begin
				dest_base_reg <= reg_wr_data;
			end
			6'b000100:begin
				tail_ptr_reg <= reg_wr_data;
			end
			6'b001000:begin
				head_ptr_reg <= reg_wr_data;
			end
			6'b010000:begin
				dma_size_reg <= reg_wr_data;
			end
			6'b100000:begin
				ctrl_stat_reg <= reg_wr_data;
			end
			endcase
		end
	end

	
	// dma突发内存写数据计数器
	reg [2:0] wr_word_counter;
	always @(posedge clk)begin
		if(rst == 1'b1)begin
			wr_word_counter <= 3'b0;
		end
		else if(current_state == WR && wr_ready)begin
			wr_word_counter = wr_word_counter + 3'b1;
		end
	end


	always @(posedge clk)begin
		if(current_state != next_state)begin
			$display("current_state = %x\n", current_state);
			$display("next_state = %x\n", next_state);
		end
	end

	// I/O寄存器的输出
	assign src_base = src_base_reg;
	assign dest_base = dest_base_reg;
	assign tail_ptr = tail_ptr_reg;
	assign head_ptr = head_ptr_reg;
	assign dma_size = dma_size_reg;
	assign ctrl_stat = {ctrl_stat_reg[31:25], current_state, rd_counter[12:5], wr_counter[12:5], ctrl_stat_reg[3:0]};

	// 读引擎到内存控制器的输出赋值
	assign rd_req_valid = (current_state == RD_REQ);
	assign rd_req_addr = src_base_reg + tail_ptr_reg + rd_counter;
	assign rd_req_len = 5'b111;

	assign rd_ready = (current_state == RD);

	// 写引擎到内存控制器的输出赋值
	assign wr_req_valid = (current_state == WR_REQ);
	assign wr_req_addr = dest_base_reg + tail_ptr_reg + wr_counter;
	assign wr_req_len = 5'b111;

	assign wr_valid = (current_state == WR);
	assign wr_data = fifo_rdata;
	assign wr_last = (wr_word_counter == wr_req_len[2:0]);

	// 读、写引擎与fifo队列接口输出信号的赋值
	assign fifo_rden = ((current_state == WR_REQ) && wr_req_ready) || ((current_state == WR) && wr_ready && ~wr_last);

	assign fifo_wen = (current_state == RD) && rd_valid;
	assign fifo_wdata = rd_rdata;

	assign intr = ctrl_stat_reg[31];

endmodule