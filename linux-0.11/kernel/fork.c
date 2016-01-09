/*
 *  linux/kernel/fork.c
 *
 *  (C) 1991  Linus Torvalds
 */

/*
 *  'fork.c' contains the help-routines for the 'fork' system call
 * (see also system_call.s), and some misc functions ('verify_area').
 * Fork is rather simple, once you get the hang of it, but the memory
 * management can be a bitch. See 'mm/mm.c': 'copy_page_tables()'
 */
#include <errno.h>

#include <linux/sched.h>
#include <linux/kernel.h>
#include <asm/segment.h>
#include <asm/system.h>

extern void write_verify(unsigned long address);

long last_pid=0;

void verify_area(void * addr,int size)
{
	unsigned long start;

	start = (unsigned long) addr;
	size += start & 0xfff;
	start &= 0xfffff000;
	start += get_base(current->ldt[2]);
	while (size>0) {
		size -= 4096;
		write_verify(start);
		start += 4096;
	}
}
// 设置子进程的代码段、数据段，并且创建、复制子进程的第一个页表
// 复制内存页表
// nr 是新任务号
// p 是新任务的数据结构指针
// 该函数为新任务在线性地址空间中设置代码段和数据段基址、限长，并复制页表
// 由于 Linux 采用写时复制(copy on write)技术，
// 所以这里仅为新进程设置自己的目录表项和页表项，而没有实际为新进程分配物理内存页面。
// 此时新进程于其父进程共享所有内存页面
// 操作成功返回 0，否则返回出错号 ENOMEN(12)
int copy_mem(int nr,struct task_struct * p)
{
	unsigned long old_data_base,new_data_base,data_limit;
	unsigned long old_code_base,new_code_base,code_limit;

	// 取子进程的代码段限长和数据段限长（字节数）
	// 0x0f 代码段选择符，即 0 1111：代码段、LDT、3 特权级
	code_limit=get_limit(0x0f);
	// 0x17 数据段选择符，即 1 0111：数据段、LDT、3 特权级
	data_limit=get_limit(0x17);
	// 获取父进程（ 进程0 ）的代码段和数据段在线性空间中得基地址
	old_code_base = get_base(current->ldt[1]);
	old_data_base = get_base(current->ldt[2]);
	// Linux-0.11 内核还不支持代码和数据段分立，检查代码段和数据段基址是否相同，
	// 否则内核显示出错信息，并停止运行
	if (old_data_base != old_code_base)
		panic("We don't support separate I&D");
	if (data_limit < code_limit)
		panic("Bad data_limit");
	// 现在 nr 是 1，0x4000000 是 64 MB
	// 设置创建中的新进程在线性地址空间中得基地址等于（64 MB × nr(任务号) ）
	// 并用该值设置新进程局部描述符中段描述符的基地址
	new_data_base = new_code_base = nr * 0x4000000;
	p->start_code = new_code_base;
	// 设置子进程代码段基址
	set_base(p->ldt[1],new_code_base);
	// 设置子进程数据段基址 
	set_base(p->ldt[2],new_data_base);
	// 正常情况下 copy_page_tables() 返回 0，否则表示出错，则释放刚申请的页表项
	// 为进程 1 创建第一个页表，复制进程 0 的页表，设置进程 1 的页目录项
	if (copy_page_tables(old_data_base,new_data_base,data_limit)) {
		free_page_tables(new_data_base,data_limit);
		return -ENOMEM; 		// ENOMEM = 12
	}
	return 0;
}

/*
 *  Ok, this is the main fork-routine. It copies the system process
 * information (task[nr]) and sets up the necessary registers. It
 * also copies the data segment in it's entirety.
 */
 // 这些参数是 int 0X80, system_call, sys_fork 多次累计压栈的结果，顺序是完全一致的
int copy_process(int nr,long ebp,long edi,long esi,long gs,long none,
		long ebx,long ecx,long edx,
		long fs,long es,long ds,
		long eip,long cs,long eflags,long esp,long ss)
{
	struct task_struct *p;
	int i;
	struct file *f;

	// 在 16 MB 内存的最高端获取一页
	// 强制类型转换的意思是将这个页用作 task_union
	p = (struct task_struct *) get_free_page();
	if (!p)
		return -EAGAIN;
	task[nr] = p;		// nr = 1
	// current 指向当前进程的 task_struct 指针，当前进程是进程 0
	// 指针类型，只复制 task_struct，并未将 4 KB 都复制，即进程 0 的内核栈未复制
	*p = *current;	/* NOTE! this doesn't copy the supervisor stack */
	// 只有内核代码中明确表示将该进程设置为就绪状态才能被唤醒
	p->state = TASK_UNINTERRUPTIBLE;
	// 开始子进程的个性化设置
	p->pid = last_pid;
	p->father = current->pid;
	p->counter = p->priority;
	p->signal = 0;
	p->alarm = 0;
	p->leader = 0;		/* process leadership doesn't inherit */
	p->utime = p->stime = 0;
	p->cutime = p->cstime = 0;
	p->start_time = jiffies;
	// start to set the TSS of subprocess
	p->tss.back_link = 0;
	// esp0 is the reference to kernel stack
	p->tss.esp0 = PAGE_SIZE + (long) p;
	// 0X10， （10000），0 特权级，GDT，数据段
	p->tss.ss0 = 0x10;
	// 参数的 EIP，是 int 0X80 压栈的，指向 if (__res >= 0)
	p->tss.eip = eip;
	p->tss.eflags = eflags;
	// 决定 main() 函数中 if(!fork()) 后面的分支走向
	p->tss.eax = 0;
	p->tss.ecx = ecx;
	p->tss.edx = edx;
	p->tss.ebx = ebx;
	p->tss.esp = esp;
	p->tss.ebp = ebp;
	p->tss.esi = esi;
	p->tss.edi = edi;
	p->tss.es = es & 0xffff;
	p->tss.cs = cs & 0xffff;
	p->tss.ss = ss & 0xffff;
	p->tss.ds = ds & 0xffff;
	p->tss.fs = fs & 0xffff;
	p->tss.gs = gs & 0xffff;
	// 挂接子进程的 LDT
	p->tss.ldt = _LDT(nr);
	p->tss.trace_bitmap = 0x80000000;
	if (last_task_used_math == current)
		__asm__("clts ; fnsave %0"::"m" (p->tss.i387));
	// 设置子进程的代码段、数据段，并且创建、复制子进程的第一个页表
	if (copy_mem(nr,p)) {
		task[nr] = NULL;
		free_page((long) p);
		return -EAGAIN;
	}
	// 将父进程相关文件引用系数加 1，表示父子进程共享文件
	for (i=0; i<NR_OPEN;i++)
		if (f=p->filp[i])
			f->f_count++;

	if (current->pwd)
		current->pwd->i_count++;
	if (current->root)
		current->root->i_count++;
	if (current->executable)
		current->executable->i_count++;
	set_tss_desc(gdt+(nr<<1)+FIRST_TSS_ENTRY,&(p->tss));
	set_ldt_desc(gdt+(nr<<1)+FIRST_LDT_ENTRY,&(p->ldt));
	p->state = TASK_RUNNING;	/* do this last, just in case */
	return last_pid;
}

// find an available slot for creating new process
// NR_task = 64
// global field last_pid store the process counter from system start
// and can be the new process number
int find_empty_process(void)
{
	int i;

	repeat:
		// if ++last_pic overflowed, then last_pid = 1
		if ((++last_pid)<0) last_pid=1;
		// now, last_pid = 1, then find valid last_pid
		for(i=0 ; i<NR_TASKS ; i++)
			if (task[i] && task[i]->pid == last_pid) goto repeat;
	// return first available i
	for(i=1 ; i<NR_TASKS ; i++)
		if (!task[i])
			return i;
	return -EAGAIN;			//EAGAIN = 11
}
