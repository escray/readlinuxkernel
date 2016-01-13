/*
 *  linux/mm/memory.c
 *
 *  (C) 1991  Linus Torvalds
 */

/*
 * demand-loading started 01.12.91 - seems it is high on the list of
 * things wanted, and it should be easy to implement. - Linus
 */

/*
 * Ok, demand-loading was easy, shared pages a little bit tricker. Shared
 * pages started 02.12.91, seems to work. - Linus.
 *
 * Tested sharing by executing about 30 /bin/sh: under the old kernel it
 * would have taken more than the 6M I have free, but it worked well as
 * far as I could see.
 *
 * Also corrected some "invalidate()"s - I wasn't doing enough of them.
 */

#include <signal.h>

#include <asm/system.h>

#include <linux/sched.h>
#include <linux/head.h>
#include <linux/kernel.h>

// volatile 告诉编译器 gcc 该函数不会返回，这样可以让 gcc 产生更好一些的代码
// 使用 volatile 关键字，可以避免产生某些（未初始化变量）假警告信息
volatile void do_exit(long code);

// 显示内存已用完警告信息，并退出
static inline volatile void oom(void)
{
	printk("out of memory\n\r");
	// SIGSEGV = 11，表示“资源暂时不可用”
	do_exit(SIGSEGV);
}

// 刷新页变换高速缓存
// 为提高地址变换效率，CPU 将最近使用的页表数据放在芯片的高速缓存中
// 修改页表信息后，需刷新该缓存
// 重新加载页目录基址寄存器 cr3，刷新页变换高速缓存
// eax = 0 是页目录的基址
#define invalidate() \
__asm__("movl %%eax,%%cr3"::"a" (0)) 			// 重置 CR3 为 0

/* these are not to be changed without changing head.s etc */
// linux 0.11 内核默认支持的最大内存容量为 16 MB，可以修改这里的定义以适合更大内存
#define LOW_MEM 0x100000 										// 内核内存 1 MB
#define PAGING_MEMORY (15*1024*1024) 				// 分页内存 15 MB，主内存区最多 15 MB
#define PAGING_PAGES (PAGING_MEMORY>>12) 		// 乘以 4 KB = 15 MB 的页数
#define MAP_NR(addr) (((addr)-LOW_MEM)>>12)	// 指定地址映射为页号
#define USED 100														// 页面被占用标志

// 用于判断给定线性地址是否位于当前进程的代码段中，4095 = 0xfff
// ((addr) + 4095) & ~4095） 用于取得线性地址 addr 所在页面的末端地址

// addr+4095的作用是将位于 0~4095 产生一个进位。
// 例如, 2 + 4095 = 4097 = 0x1001 最左边的1就是产生的进位，
// 接着 (addr+4095) & ~4095 的作用就是把刚得到的结果的低 12 位置 0 。
// 这样一来 0x1001 就变成了 0x1000 这个就是 addr 所在页最后的地址 +1，
// 即是当前页面的下一个页面的开始地址。
// 假设一个代码段占据了 4 个页面大小的内存 addr 在这四个页面的话，
// (addr+4095）& ~4095 得到的将是 addr 所在页面的下一个页面的起始地址。
// 如果该结果小于 current->start_code + current->end_code 即代码段的结束地址，
// 那么则该地址在代码段内，否则在代码段外面。

#define CODE_SPACE(addr) ((((addr)+4095)&~4095) < \
current->start_code + current->end_code)

// 全局变量，存放实际物理内存的最高端地址
static long HIGH_MEMORY = 0;

// 从 from 处复制 1 页内存到 to 处
#define copy_page(from,to) \
__asm__("cld ; rep ; movsl"::"S" (from),"D" (to),"c" (1024):"cx","di","si")

// 系统通过 mem_map[] 对 1 MB 以上的内存分页进行管理
// 记录一个页面的使用次数
// 物理内存映射字节 map，1 字节代表 1 页内存
// 最多 15 MB 的内存空间
// 在 mem_init() 中，不能做主存页面的位置都设置为 100（USED）
static unsigned char mem_map [ PAGING_PAGES ] = {0,};

/*
 * Get physical address of first (actually last :-) free page, and mark it
 * used. If no free pages left, return 0.
 */
unsigned long get_free_page(void)
{
register unsigned long __res asm("ax");

__asm__("std ; repne ; scasb\n\t"
	"jne 1f\n\t"
	"movb $1,1(%%edi)\n\t"
	"sall $12,%%ecx\n\t"
	"addl %2,%%ecx\n\t"
	"movl %%ecx,%%edx\n\t"
	"movl $1024,%%ecx\n\t"
	"leal 4092(%%edx),%%edi\n\t"
	"rep ; stosl\n\t"
	"movl %%edx,%%eax\n"
	"1:"
	:"=a" (__res)
	:"0" (0),"i" (LOW_MEM),"c" (PAGING_PAGES),
	"D" (mem_map+PAGING_PAGES-1)
	:"di","cx","dx");
return __res;
}

/*
 * Free a page of memory at physical address 'addr'. Used by
 * 'free_page_tables()'
 */
void free_page(unsigned long addr)
{
	if (addr < LOW_MEM) return;
	if (addr >= HIGH_MEMORY)
		panic("trying to free nonexistent page");
	addr -= LOW_MEM;
	addr >>= 12;
	if (mem_map[addr]--) return;
	mem_map[addr]=0;
	panic("trying to free free page");
}

/*
 * This function frees a continuos block of page tables, as needed
 * by 'exit()'. As does copy_page_tables(), this handles only 4Mb blocks.
 */
int free_page_tables(unsigned long from,unsigned long size)
{
	unsigned long *pg_table;
	unsigned long * dir, nr;

	if (from & 0x3fffff)
		panic("free_page_tables called with wrong alignment");
	if (!from)
		panic("Trying to free up swapper memory space");
	size = (size + 0x3fffff) >> 22;
	dir = (unsigned long *) ((from>>20) & 0xffc); /* _pg_dir = 0 */
	for ( ; size-->0 ; dir++) {
		if (!(1 & *dir))
			continue;
		pg_table = (unsigned long *) (0xfffff000 & *dir);
		for (nr=0 ; nr<1024 ; nr++) {
			if (1 & *pg_table)
				free_page(0xfffff000 & *pg_table);
			*pg_table = 0;
			pg_table++;
		}
		free_page(0xfffff000 & *dir);
		*dir = 0;
	}
	invalidate();
	return 0;
}

/*
 *  Well, here is one of the most complicated functions in mm. It
 * copies a range of linerar addresses by copying only the pages.
 * Let's hope this is bug-free, 'cause this one I don't want to debug :-)
 *
 * Note! We don't copy just any chunks of memory - addresses have to
 * be divisible by 4Mb (one page-directory entry), as this makes the
 * function easier. It's used only by fork anyway.
 *
 * NOTE 2!! When from==0 we are copying kernel space for the first
 * fork(). Then we DONT want to copy a full page-directory entry, as
 * that would lead to some serious memory waste - we just copy the
 * first 160 pages - 640kB. Even that is more than we need, but it
 * doesn't take any more memory - we don't copy-on-write in the low
 * 1 Mb-range, so the pages can be shared with the kernel. Thus the
 * special case for nr=xxxx.
 */
 // 复制页目录表项和页表项
 // 复制指定线性地址和长度内存对应的页目录项和页表项，从而被复制的页目录和页表项对应的
 // 原物理内存页面被两套页表映射而共享使用。
 // 复制时，需申请新页面来存放新页表，原物理内存区被共享。
 // 此后，两个进程（父子进程）将共享内存区，直到有一个进程执行写操作时，内核才会为写操作进程
 // 分配新的内存页（写时复制）。
 // from, to: 线性地址
 // size: 需复制的内存大小，单位 byte
int copy_page_tables(unsigned long from,unsigned long to,long size)
{
	unsigned long * from_page_table;
	unsigned long * to_page_table;
	unsigned long this_page;
	unsigned long * from_dir, * to_dir;
	unsigned long nr;

	// 有效性检测
	// 0x3fffff = 4 MB，一个页表的管辖范围
	// from 和 to 的后 22 位必须都是 0，也就是 4 MB 的整数倍
	// 一个页表的 1024 项可以管理 4 MB内存
	// 一个页表对应 4 MB 连续的线性地址空间必须是从 0x000000 开始的 4 MB 的整数倍
  // 这样才能保证从一个页表的第一项开始复制，并且新页表最初的所有项都是有效的
	if ((from&0x3fffff) || (to&0x3fffff))
		panic("copy_page_tables called with wrong alignment");
	// 一个页目录项的管理范围是 4 MB，一项是 4 Byte，项的地址就是项数×4，
	// 也就是项管理的线性地址起始的 M 数
	// 比如，0 项的地址是 0，管理范围是 0 ~ 4 MB
	//      1 项的地址是 4，管理范围是 4 ~ 8 MB
	//      2 项的地址是 8，管理范围是 8 ~ 12 MB
	// 0xffc，(1111 1111 1100)，即 4 MB 以下部分清零的地址的 MB 数，也就是页目录项的地址
	from_dir = (unsigned long *) ((from>>20) & 0xffc); /* _pg_dir = 0 */
	to_dir = (unsigned long *) ((to>>20) & 0xffc);
	// 根据 size 计算要复制的内存块占用的页表数（目录项数）
	size = ((unsigned) (size+0x3fffff)) >> 22;				// 左移 22 位，即 4 MB 个数

	// 对每个页目录项依次申请 1 页内存来保存对应的页表，并且开始页表复制操作
	for( ; size-->0 ; from_dir++,to_dir++) {
		// 如果目的目录指定的页表已存在（P = 1），则内核报错并退出
		if (1 & *to_dir)
			panic("copy_page_tables: already exist");
		// 如果源目录项无效，即指定的页表不存在，则继续循环处理下一个页表项
		if (!(1 & *from_dir))
			continue;
		// *from_dir 是目录项中得地址，0xfffff000 是将低 12 位清零，高 20 位是页表的地址
		from_page_table = (unsigned long *) (0xfffff000 & *from_dir);
		if (!(to_page_table = (unsigned long *) get_free_page()))
			return -1;	/* Out of memory, see freeing */
		// 设置目的目录项信息，7 即 111，表示用户级，可读写，存在（User, R/W, Present）
		*to_dir = ((unsigned long) to_page_table) | 7;
		// 如果在内核空间，则仅需复制头 160 页对应的页表项，对应于开始 640 KB 物理内存
		// 0xA0，即 160，复制页表的项数
	  // 否则，就复制一个也表中所有的 1024 个页表项，可映射 4 MB 物理内存
		nr = (from==0)?0xA0:1024;
		for ( ; nr-- > 0 ; from_page_table++,to_page_table++) {
			// 复制父进程页表
			this_page = *from_page_table;
			// 若源页表未使用，则无需复制，继续处理下一项
			if (!(1 & this_page))
				continue;
			// 设置页表项属性，~2 是 101，代表用户、只读、存在
			// 让页表对应内存页面只读，然后将页表项复制到目录页表中
			this_page &= ~2;
			*to_page_table = this_page;

			// 如果该页表所指物理页面的地址在 1 MB 以上，则需要设置内存页面映射数组 mem_map[]
			// 计算页面号，以它为索引，在页面映射数组相应项中增加引用次数
			// 1 MB 以内的内核区不参与用户分页管理
			// mem_map[] 仅用于管理主内存区中的页面使用情况，
			// 对于内核移动到进程 0 中并且调用进程 1 时（运行init()），复制页面处于内核代码区，
			// 以下判断中的语句不会执行，进程 0 的页面可以随时读写
			// 只有当调用 fork() 的父进程代码处于主内存区之外（大于 1 MB）时才会执行，
			// 这种情况需要在进程调用 execve()，并装载执行了新程序代码才会出现
			if (this_page > LOW_MEM) {
				// 使源页表项所指内存页也为只读，因为现在有两个进程共用内存区了
				// 若其中一个进程需要进行写操作，则可以通过页异常写保护处理，为执行写操作的进程
				// 匹配 1 页新空闲页面，即写时复制（copy on write）
				*from_page_table = this_page;
				this_page -= LOW_MEM;
				this_page >>= 12;
				// 增加引用计数
				mem_map[this_page]++;
			}
		}
	}
	// 重置 CR3 为 0，刷新“页变换高速缓存”
	invalidate();
	return 0;
}

/*
 * This function puts a page in memory at the wanted address.
 * It returns the physical address of the page gotten, 0 if
 * out of memory (either when trying to access page-table or
 * page.)
 */
unsigned long put_page(unsigned long page,unsigned long address)
{
	unsigned long tmp, *page_table;

/* NOTE !!! This uses the fact that _pg_dir=0 */

	if (page < LOW_MEM || page >= HIGH_MEMORY)
		printk("Trying to put page %p at %p\n",page,address);
	if (mem_map[(page-LOW_MEM)>>12] != 1)
		printk("mem_map disagrees with %p at %p\n",page,address);
	page_table = (unsigned long *) ((address>>20) & 0xffc);
	if ((*page_table)&1)
		page_table = (unsigned long *) (0xfffff000 & *page_table);
	else {
		if (!(tmp=get_free_page()))
			return 0;
		*page_table = tmp|7;
		page_table = (unsigned long *) tmp;
	}
	page_table[(address>>12) & 0x3ff] = page | 7;
/* no need for invalidate */
	return page;
}

void un_wp_page(unsigned long * table_entry)
{
	unsigned long old_page,new_page;

	old_page = 0xfffff000 & *table_entry;
	if (old_page >= LOW_MEM && mem_map[MAP_NR(old_page)]==1) {
		*table_entry |= 2;
		invalidate();
		return;
	}
	if (!(new_page=get_free_page()))
		oom();
	if (old_page >= LOW_MEM)
		mem_map[MAP_NR(old_page)]--;
	*table_entry = new_page | 7;
	invalidate();
	copy_page(old_page,new_page);
}	

/*
 * This routine handles present pages, when users try to write
 * to a shared page. It is done by copying the page to a new address
 * and decrementing the shared-page counter for the old page.
 *
 * If it's in code space we exit with a segment error.
 */
void do_wp_page(unsigned long error_code,unsigned long address)
{
#if 0
/* we cannot do this yet: the estdio library writes to code space */
/* stupid, stupid. I really want the libc.a from GNU */
	if (CODE_SPACE(address))
		do_exit(SIGSEGV);
#endif
	un_wp_page((unsigned long *)
		(((address>>10) & 0xffc) + (0xfffff000 &
		*((unsigned long *) ((address>>20) &0xffc)))));

}

void write_verify(unsigned long address)
{
	unsigned long page;

	if (!( (page = *((unsigned long *) ((address>>20) & 0xffc)) )&1))
		return;
	page &= 0xfffff000;
	page += ((address>>10) & 0xffc);
	if ((3 & *(unsigned long *) page) == 1)  /* non-writeable, present */
		un_wp_page((unsigned long *) page);
	return;
}

void get_empty_page(unsigned long address)
{
	unsigned long tmp;

	if (!(tmp=get_free_page()) || !put_page(tmp,address)) {
		free_page(tmp);		/* 0 is ok - ignored */
		oom();
	}
}

/*
 * try_to_share() checks the page at address "address" in the task "p",
 * to see if it exists, and if it is clean. If so, share it with the current
 * task.
 *
 * NOTE! This assumes we have checked that p != current, and that they
 * share the same executable.
 */
static int try_to_share(unsigned long address, struct task_struct * p)
{
	unsigned long from;
	unsigned long to;
	unsigned long from_page;
	unsigned long to_page;
	unsigned long phys_addr;

	from_page = to_page = ((address>>20) & 0xffc);
	from_page += ((p->start_code>>20) & 0xffc);
	to_page += ((current->start_code>>20) & 0xffc);
/* is there a page-directory at from? */
	from = *(unsigned long *) from_page;
	if (!(from & 1))
		return 0;
	from &= 0xfffff000;
	from_page = from + ((address>>10) & 0xffc);
	phys_addr = *(unsigned long *) from_page;
/* is the page clean and present? */
	if ((phys_addr & 0x41) != 0x01)
		return 0;
	phys_addr &= 0xfffff000;
	if (phys_addr >= HIGH_MEMORY || phys_addr < LOW_MEM)
		return 0;
	to = *(unsigned long *) to_page;
	if (!(to & 1))
		if (to = get_free_page())
			*(unsigned long *) to_page = to | 7;
		else
			oom();
	to &= 0xfffff000;
	to_page = to + ((address>>10) & 0xffc);
	if (1 & *(unsigned long *) to_page)
		panic("try_to_share: to_page already exists");
/* share them: write-protect */
	*(unsigned long *) from_page &= ~2;
	*(unsigned long *) to_page = *(unsigned long *) from_page;
	invalidate();
	phys_addr -= LOW_MEM;
	phys_addr >>= 12;
	mem_map[phys_addr]++;
	return 1;
}

/*
 * share_page() tries to find a process that could share a page with
 * the current one. Address is the address of the wanted page relative
 * to the current data space.
 *
 * We first check if it is at all feasible by checking executable->i_count.
 * It should be >1 if there are other tasks sharing this inode.
 */
static int share_page(unsigned long address)
{
	struct task_struct ** p;

	if (!current->executable)
		return 0;
	if (current->executable->i_count < 2)
		return 0;
	for (p = &LAST_TASK ; p > &FIRST_TASK ; --p) {
		if (!*p)
			continue;
		if (current == *p)
			continue;
		if ((*p)->executable != current->executable)
			continue;
		if (try_to_share(address,*p))
			return 1;
	}
	return 0;
}

void do_no_page(unsigned long error_code,unsigned long address)
{
	int nr[4];
	unsigned long tmp;
	unsigned long page;
	int block,i;

	address &= 0xfffff000;
	tmp = address - current->start_code;
	if (!current->executable || tmp >= current->end_data) {
		get_empty_page(address);
		return;
	}
	if (share_page(tmp))
		return;
	if (!(page = get_free_page()))
		oom();
/* remember that 1 block is used for header */
	block = 1 + tmp/BLOCK_SIZE;
	for (i=0 ; i<4 ; block++,i++)
		nr[i] = bmap(current->executable,block);
	bread_page(page,current->executable->i_dev,nr);
	i = tmp + 4096 - current->end_data;
	tmp = page + 4096;
	while (i-- > 0) {
		tmp--;
		*(char *)tmp = 0;
	}
	if (put_page(page,address))
		return;
	free_page(page);
	oom();
}

void mem_init(long start_mem, long end_mem)
{
	int i;

	HIGH_MEMORY = end_mem;
	// 将所有内存页面使用计数均设为 USED (100，被使用)
	for (i=0 ; i<PAGING_PAGES ; i++)
		mem_map[i] = USED;
	i = MAP_NR(start_mem); 	// start_mem 为 6 MB (虚拟盘之后)
	end_mem -= start_mem;
	end_mem >>= 12;					// 16 MB 的页数
	// 将主内存中所有的页面计数全部清零
	// 系统以后只把使用计数为 0 的页面视为空闲页面
	while (end_mem-->0)
		mem_map[i++]=0;
}

void calc_mem(void)
{
	int i,j,k,free=0;
	long * pg_tbl;

	for(i=0 ; i<PAGING_PAGES ; i++)
		if (!mem_map[i]) free++;
	printk("%d pages free (of %d)\n\r",free,PAGING_PAGES);
	for(i=2 ; i<1024 ; i++) {
		if (1&pg_dir[i]) {
			pg_tbl=(long *) (0xfffff000 & pg_dir[i]);
			for(j=k=0 ; j<1024 ; j++)
				if (pg_tbl[j]&1)
					k++;
			printk("Pg-dir[%d] uses %d pages\n",i,k);
		}
	}
}
