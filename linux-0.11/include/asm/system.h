#define move_to_user_mode() \
__asm__ ("movl %%esp,%%eax\n\t" \
	"pushl $0x17\n\t" \
	"pushl %%eax\n\t" \
	"pushfl\n\t" \
	"pushl $0x0f\n\t" \
	"pushl $1f\n\t" \
	"iret\n" \
	"1:\tmovl $0x17,%%eax\n\t" \
	"movw %%ax,%%ds\n\t" \
	"movw %%ax,%%es\n\t" \
	"movw %%ax,%%fs\n\t" \
	"movw %%ax,%%gs" \
	:::"ax")

#define sti() __asm__ ("sti"::)
#define cli() __asm__ ("cli"::)
#define nop() __asm__ ("nop"::)

#define iret() __asm__ ("iret"::)

#define _set_gate(gate_addr,type,dpl,addr) \
__asm__ ("movw %%dx,%%ax\n\t" \ // 将 edx 的低字复制给 eax 的低字
	"movw %0,%%dx\n\t" \					// %0 对应第二个冒号后的第 1 行的"i"
	"movl %%eax,%1\n\t" \					// %1 对应第二个冒号后的第 2 行的"o"
	"movl %%edx,%2" \							// %2 对应第二个冒号后面第 3 行的"d"
	: \														// 这个冒号后面是输出
																// 下面冒号后面是输入
	: "i" ((short) (0x8000+(dpl<<13)+(type<<8))), \	// 立即数
	"o" (*((char *) (gate_addr))), \				// 中断描述符前 4 个字节的地址
	"o" (*(4+(char *) (gate_addr))), \			// 中断描述符后 4 个字节的地址
	"d" ((char *) (addr)),"a" (0x00080000))	// "d"对应 edx，"a"对应 eax

#define set_intr_gate(n,addr) \
	_set_gate(&idt[n],14,0,addr)

#define set_trap_gate(n,addr) \
	_set_gate(&idt[n],15,0,addr)

#define set_system_gate(n,addr) \
	_set_gate(&idt[n],15,3,addr)

#define _set_seg_desc(gate_addr,type,dpl,base,limit) {\
	*(gate_addr) = ((base) & 0xff000000) | \
		(((base) & 0x00ff0000)>>16) | \
		((limit) & 0xf0000) | \
		((dpl)<<13) | \
		(0x00408000) | \
		((type)<<8); \
	*((gate_addr)+1) = (((base) & 0x0000ffff)<<16) | \
		((limit) & 0x0ffff); }

#define _set_tssldt_desc(n,addr,type) \
__asm__ ("movw $104,%1\n\t" \				// 将 104，即 110 1000 存入描述符的第1、2字节
	"movw %%ax,%2\n\t" \							// 将 tss 或 ldt 基地址的低 16 位
																		// 存入描述符的第 3，4 字节
	"rorl $16,%%eax\n\t" \						// 循环右移 16 位，即高、低字互换
	"movb %%al,%3\n\t" \							// 将互换完的第 1 字节
																		// 即地址的第 3 字节存入第 5 字节
	"movb $" type ",%4\n\t" \					// 将 0x89 或 0x82 存入第 6 字节
	"movb $0x00,%5\n\t" \							// 将 0x00 存入第 7 字节
	"movb %%ah,%6\n\t" \							// 将互换完的第 2 字节，
																		// 即地址的第 4 字节存入第 8 字节
	"rorl $16,%%eax" \								// 复原 eax
	::"a" (addr), "m" (*(n)), "m" (*(n+2)), "m" (*(n+4)), \
	 "m" (*(n+5)), "m" (*(n+6)), "m" (*(n+7)) \
	// “m” (*(n)) 是 gdt 的第 n 项描述符的地址开始的内存单元
	// "m" (*(n+2)) 是 gdt 的第 n 项描述符的地址向上第 3 字节开始的内存单元
	)

// n: gdt 的项值，addr: tss 或 ldt 的地址
// 0x89 对应 tss, 0x82 对应 ldt
#define set_tss_desc(n,addr) _set_tssldt_desc(((char *) (n)),addr,"0x89")
#define set_ldt_desc(n,addr) _set_tssldt_desc(((char *) (n)),addr,"0x82")
