.data
last_tail_ptr:
        .word 0

.globl intr_handler
	.align  2
	.type intr_handler, @function
	.section .exception

intr_handler:
	# TODO: Please add your own interrupt handler for DMA engine 
	
	li  $k0, 0x60020014             #将ctrl_stat寄存器的地址加载到k0中
	lw  $k1, 0($k0)                 #将ctrl_stat寄存器的值加载到k1寄存器中
	li  $k0, 0x7fffffff             #将011...11存入k0寄存器中
	and $k1, $k1, $k0               #将k0中的值与k1中的值按位与，存入k1中
	li  $k0, 0x60020014             #将ctrl_stat寄存器的地址加载到k0中
	sw  $k1, 0($k0)                 #将k0寄存器中的值存入ctrl_stat寄存器中，至此完成了将ctrl_stat寄存器INTR标志位清0

cycle:
	li  $k0, 0x60020008             #将tail_ptr寄存器的地址加载到k0中
	lw  $k0, 0($k0)                 #将tail_ptr寄存器的值加载到k0寄存器中

	la  $k1, last_tail_ptr          #将last_tail_ptr的地址存入k1寄存器中
	lw  $k1, 0($k1)                 #将last_tail_ptr的值存入k1寄存器中

	beq $k1, $k0, last              #比较tail_ptr-last_tail_ptr的值，如果相等，则退出循环

	li  $k0, 0x60020010             #将dma_size寄存器的地址加载到k0中
	lw  $k0, 0($k0)                 #将dma_size寄存器的值加载到k0中

	addu $k1, $k0, $k1              #将last_tail_ptr+dma_size，存入k1寄存器中
	la  $k0, last_tail_ptr          #加载last_tail_ptr的地址
	sw  $k1, 0($k0)

	la  $k0, dma_buf_stat           #加载dma_buf_stat的地址
	lw  $k1, 0($k0)                 #加载dma_buf_stat的值
	addiu $k1, $k1, -1              #将k1的值减1             #这里用addi反而会出错（变成+1），很奇怪！
	sw  $k1, 0($k0)                 #将k1的值移到dma_buf_stat中

	j   cycle                       #跳转回到循环开始

last:
	eret