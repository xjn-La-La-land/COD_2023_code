#include "printf.h"
#include "trap.h"
#include "mul.h"
#include "div.h"
#include "perf_cnt.h"

#define FRAC_BIT 10					// 数据中小数部分的有效位数

#define RD_ADDR 135106448  			// 输入数据起始地址
#define RD_SIZE_D0 1 				// 输入数据组数
#define RD_SIZE_D1 1 				// 每组输入数据的通道数
#define RD_SIZE_D2 28 				// 每个通道的行数
#define RD_SIZE_D3 28 				// 每个通道的列数

#define WEIGHT_ADDR 134217728  		// 卷积核起始地址
#define WEIGHT_SIZE_D0 20 			// 卷积核组数
#define WEIGHT_SIZE_D1 1 			// 每组卷积核的个数
#define WEIGHT_SIZE_D2 5 			// 卷积核的行数
#define WEIGHT_SIZE_D3 5 			// 卷积核的列数

#define WR_ADDR 135108240  			// 输出数据起始地址
#define WR_SIZE_D0 1 				// 输出数据组数
#define WR_SIZE_D1 20 				// 每组输出数据的通道数
#define WR_SIZE_D2 12 				// 每个通道的行数
#define WR_SIZE_D3 12 				// 每个通道的列数

#define KERN_ATTR_CONV_PAD 0 		// 卷积边界宽度
#define KERN_ATTR_CONV_STRIDE 1		// 卷积步长
#define KERN_ATTR_POOL_PAD 0		// 池化边界宽度
#define KERN_ATTR_POOL_KERN_SIZE 2	// 池化块大小
#define KERN_ATTR_POOL_STRIDE 2		// 池化步长

//MMIO register address of DNN accelerator
#define GPIO_START_ADDR    0x60030000
#define GPIO_DONE_ADDR     0x60030008

#define MAX(A,B) ((A)>(B))? (A):(B) // 取出两个数中更大的值
#define SHORT_MIN -32768 // short型的最小值

struct size_vec4
{
	unsigned d0;
	unsigned d1;
	unsigned d2;
	unsigned d3;
};

struct mem_addr
{
	unsigned rd_addr;
	unsigned weight_addr;
	unsigned wr_addr;
};

int mul(short a, short b)
{
#ifndef USE_MUL
	int ans = mul_ll(a, b);
#else
	int ans = a * b;
#endif
	return ans;
}


struct mem_addr addr = {RD_ADDR, WEIGHT_ADDR, WR_ADDR};
struct size_vec4 rd_size = {RD_SIZE_D0, RD_SIZE_D1, RD_SIZE_D2, RD_SIZE_D3};
struct size_vec4 wr_size = {WR_SIZE_D0, WR_SIZE_D1, WR_SIZE_D2, WR_SIZE_D3};
struct size_vec4 weight_size = {WEIGHT_SIZE_D0, WEIGHT_SIZE_D1, WEIGHT_SIZE_D2, WEIGHT_SIZE_D3};

struct size_vec4 conv_size;

extern char _binary_data_result_bin_start[];
extern char _binary_data_result_bin_size[];

void convolution()
{
	// 输入数据、卷积核以及输出数据的基地址
	short *in = (short *)addr.rd_addr;
	short *weight = (short *)addr.weight_addr;
	short *out = (short *)addr.wr_addr;
	
	// 首先计算卷积输出矩阵的大小
	unsigned pad = KERN_ATTR_CONV_PAD;
	unsigned pad_len = pad << 1;

	unsigned extended_in_w = rd_size.d3 + pad_len;
	unsigned extended_in_h = rd_size.d2 + pad_len;

	unsigned conv_out_w = extended_in_w - weight_size.d3;
	unsigned conv_out_h = extended_in_h - weight_size.d2;

	unsigned stride = KERN_ATTR_CONV_STRIDE;

	conv_out_w = div(conv_out_w, stride);
	conv_out_h = div(conv_out_h, stride);

	conv_out_w++;
	conv_out_h++;

	conv_size.d0 = wr_size.d0;
	conv_size.d1 = wr_size.d1;
	conv_size.d2 = conv_out_h;
	conv_size.d3 = conv_out_w;

	//wr_size=(1,20,12,12)
	//rd_size=(1,1,28,28)
	//weight_size=(20,1,5,5)

	short input_size = (short)mul((short)rd_size.d2,(short)rd_size.d3);// 一个输入矩阵的大小
	short core_size = (short)(mul((short)weight_size.d2,(short)weight_size.d3)+1);// 一个卷积核的大小

	unsigned na; // 当前输入数据组数
	unsigned no, ni;// 当前输入、输出通道数
	unsigned x, y;// 当前输出数据在conv矩阵中的行数和列数
	
	short* input_base_1;// 当前使用的输入矩阵所在组的起始地址(input_base_1 = in + na * rd_size.d1 * input_size)
	short* input_base_2;// 当前使用的输入矩阵的起始地址(input_base_2 = input_base_1 + ni * input_size)
	short* core_base_1;// 当前使用的卷积核所在行的起始地址(core_base_1 = out + no * weight_size.d1 * core_size)
	short* core_base_2;// 当前使用的卷积核的起始地址(core_base_2 = core_base_1 + ni * core_size)

	unsigned kx, ky;// 当前乘法所用的权重值在卷积核矩阵中的行和列
	int temp_data;// 暂存乘法与加法的中间结果
	unsigned head_line, head_column;// 在扩展了边界后的输入矩阵中与weight相乘的一块的起始行与列
	unsigned real_line, real_column;// 在实际输入矩阵中与weight相乘的一块的起始行与列
	short* input_target_cell, * weight_target_cell, * output_target_cell;
	// 输入指针指向当前乘法所用的数据位置；权重指针指向当前乘法所用的权重值的位置；输出指针指向当前输出数据的位置
	
	output_target_cell = out;// 输出指针每次加1，顺序地计算各个卷积输出矩阵的每一个单元

	for(na = 0, input_base_1 = in; na < rd_size.d0; na++, input_base_1 += mul((short)rd_size.d1,input_size)){
		for(no = 0, core_base_1 = weight; no < wr_size.d1; no++, core_base_1 += mul((short)weight_size.d1,core_size)){
			for(x = 0, head_line = 0; x < conv_out_h; x++){
				if(head_line < pad)
					real_line = 0;
				else if(head_line >= extended_in_h - pad)
					real_line = rd_size.d2 - 1;
				else
					real_line = head_line - pad;
				for(y = 0, head_column = 0; y < conv_out_w; y++){
					if(head_column < pad)
						real_column = 0;
					else if(head_column >= extended_in_w - pad)
						real_column = rd_size.d3 - 1;
					else
						real_column = head_column - pad;

					core_base_2 = core_base_1;
					input_base_2 = input_base_1;
					for(ni = 0; ni < rd_size.d1; ni++, input_base_2 += input_size, core_base_2 += core_size){
						// bias值的处理
						weight_target_cell = core_base_2;
						if(ni == 0)
							*output_target_cell = *weight_target_cell;// 先加上bias值
						// 卷积的处理
						weight_target_cell ++;// 移动到卷积核的权重值区域
						for(kx = 0, temp_data = 0; kx < weight_size.d2; kx++){
							// 将输入指针指向输入中下一行的开始位置
							input_target_cell = input_base_2 + mul((short)(real_line + kx),(short)rd_size.d3) + real_column;

							for(ky = 0; ky < weight_size.d3; ky++, weight_target_cell++){
								if(!(head_line + kx < pad||
									 head_column + ky < pad||
									 head_line + kx >= extended_in_h - pad||
									 head_column + ky >= extended_in_w - pad))
								{
									temp_data += mul(*input_target_cell,*weight_target_cell);
									input_target_cell++;
								}
							}
						}
						temp_data = temp_data >> FRAC_BIT;
						*output_target_cell += (short)temp_data; // 将temp_data加到输出矩阵对应的位置上
					}
					head_column += stride; // 起始列数加上步长
					output_target_cell++;
				}
				head_column = 0; // 起始列数归零
				head_line += stride; // 起始行数加上步长
			}
		}
	}
}

void pooling()
{
	short *out = (short *)addr.wr_addr;
	unsigned pad = KERN_ATTR_POOL_PAD;
	unsigned pad_len = pad << 1;

	unsigned pad_w_test = conv_size.d3 - KERN_ATTR_POOL_KERN_SIZE;
	unsigned pad_h_test = conv_size.d2 - KERN_ATTR_POOL_KERN_SIZE;

	unsigned pool_out_w = pad_w_test + pad_len;
	unsigned pool_out_h = pad_h_test + pad_len;

	unsigned stride = KERN_ATTR_POOL_STRIDE;

	unsigned pad_w_test_remain = pad_w_test - mul(div(pad_w_test, stride), stride);
	unsigned pad_h_test_remain = pad_h_test - mul(div(pad_h_test, stride), stride);

	pool_out_w = div(pool_out_w, stride);
	pool_out_h = div(pool_out_h, stride);
	pool_out_w++;
	pool_out_h++;

	if ((!pad) && (pad_w_test_remain || pad_h_test_remain))
	{
		pool_out_w++;
		pool_out_h++;
	}

	short conv_core_size = (short)mul((short)conv_size.d2,(short)conv_size.d3); // 一个卷积矩阵的大小

	unsigned na, ni;				// 当前输入conv矩阵的数据组数和通道数(na为0~conv_size.d0;ni为0~conv_size.d1)
	unsigned x, y;					// 当前输出矩阵位置的行和列(x为0~pool_out_h;y为0~pool_out_w)

	short* conv_base;				// 当前卷积矩阵的起始地址(conv_base=out+na*conv_size.d1*conv_core_size+ni*conv_core_size)

	unsigned kx, ky;				// 当前正在池化的一块的行、列的循环变量(kx,ky的取值为0~KERN_ATTR_POOL_KERN_SIZE)
	short temp_max;					// 临时变量暂存池化快的最大值

	unsigned head_line, head_column;// 在边界扩展后的conv矩阵中正在池化的一块的起始行与列
	// (head_line的取值为0~conv_size.d2+pad_len;head_column的取值为0~conv_size.d3+pad_len)
	unsigned real_line, real_column;// 在实际conv矩阵中正在池化的一块的起始行与列
	// (real_line的取值为0~conv_size.d2;real_column的取值为0~conv_size.d3)

	short* conv_traget_cell, * output_target_cell;// 分别指向当前conv矩阵的目标位置和池化输出矩阵的目标位置
	
	
	output_target_cell = out;// 输出指针每次加1，顺序地计算各个池化输出矩阵的每一个单元

	for(na = 0, conv_base = out; na < conv_size.d0; na++){
		for(ni = 0; ni < conv_size.d1; ni++, conv_base += conv_core_size){
			for(x = 0, head_line = 0; x < pool_out_h; x++, head_line += stride){
				if(head_line < pad) // 池化快相对于边界padding的3种情况
					real_line = 0;
				else if(head_line >= conv_size.d2 + pad)
					real_line = conv_size.d2 - 1;
				else
					real_line = head_line - pad;
				for(y = 0, head_column = 0; y < pool_out_w; y++, head_column += stride){
					if(head_column < pad) // 池化快相对于边界padding的3种情况
						real_column = 0;
					else if(head_column >= conv_size.d3 + pad)
						real_column = conv_size.d3 - 1;
					else
						real_column = head_column - pad;

					temp_max = SHORT_MIN; // 池化快的极大值的初值设为最小
					for(kx = 0; kx < KERN_ATTR_POOL_KERN_SIZE; kx++){
						conv_traget_cell = conv_base + mul((short)(real_line + kx),(short)conv_size.d3) + real_column;
						for(ky = 0; ky < KERN_ATTR_POOL_KERN_SIZE; ky++){
							if(!(head_line+kx < pad||
								 head_column+ky < pad||
								 head_line+kx >= conv_size.d2+pad||
								 head_column+ky >= conv_size.d3+pad))
							{
								temp_max = MAX(*conv_traget_cell,temp_max);
								conv_traget_cell++;
							}
							else {
								temp_max = MAX(0,temp_max);
							}
						}
					}
					*output_target_cell = temp_max;
					output_target_cell++;
				}
			}
		}
	}
}

#ifdef USE_HW_ACCEL
void launch_hw_accel()
{
	volatile int* gpio_start = (void*)(GPIO_START_ADDR);
	volatile int* gpio_done = (void*)(GPIO_DONE_ADDR);

	//TODO: Please add your implementation here
	*gpio_start = *gpio_start | 1;// 将START寄存器的第0位置为1，启动加速器
	while(*gpio_done & 1);
	*gpio_start = *gpio_start ^ 1;// 将START寄存器的第0位置为0
}
#endif

int comparing()
{
	char *out = (char *)addr.wr_addr;
	char *result = (char *)_binary_data_result_bin_start;

#ifdef USE_HW_ACCEL
	int count = (int)_binary_data_result_bin_size + 
		    (16 - WR_SIZE_D3) * 2 * WR_SIZE_D2 * WR_SIZE_D1;
#else
	int count = (int)_binary_data_result_bin_size;
#endif

	for (int i = 0, j = 0; i < count; i++)
	{
#ifdef USE_HW_ACCEL
		int alignment = i & 0x0000001f;
		if (alignment >= (WR_SIZE_D3 << 1))
			continue;
#endif
		if (*(out + i) != *(result + j))
		{
			printf("Failed! at address %x and %x with data %x and %x\n", out + i, result + j, *(out + i), *(result + j));
			return 1;
		}
		j++;
	}

	printf("Passed!\n");
	return 0;
}

int main()
{
	Result res;// 性能计数器存储结构体
	bench_prepare(&res);

#ifdef USE_HW_ACCEL
	printf("Launching task...\n");
	launch_hw_accel();
#else
	printf("starting convolution\n");
	convolution();
	printf("starting pooling\n");
	pooling();
#endif

	int result = comparing();

	bench_done(&res);
	printf("cycle number:%u\n", res.msec);
	printf("mem_cycle number:%u\n", res.mem_cycle);
	printf("inst_cycle number:%u\n", res.inst_cycle);

	printf("benchmark finished\n");

	if (result == 0) {
		hit_good_trap();
	} else {
		nemu_assert(0);
	}

	return 0;
}