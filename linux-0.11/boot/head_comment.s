
aq DMASCWQSZ  CCQ 1`WD`WF http://www.cnblogs.com/xuqiang/archive/2010/02/16/1953757.html
#
# 这段代码被连接到system模块的最前面，这也是它为什么称之为 head.s 的原因。
# 从这里开始内核完全运行在保护模式下。head.s采用的是 at&t 格式的
# 汇编。注意的是代码中的赋值方向是从左到右。
# 
# 这段程序实际上是出于内存的绝对地址 0 开始处。首先是加载各个数据段寄存器。
# 重新设置全局描述符表 gdt --> 检测 a20 地址线是否真的开启，没有开启，loop
# 掉了 --> 检测 pc 是否含有数学协处理器 --> 设置管理内存分页的处理机制 -->
# 将页目录放置在内存地址 0 开始处。所以这段程序将被覆盖掉。 --> 最后利用 ret
# 指令弹出预先压入的/init/main.c程序的入口地址，去运行 main.c 程序。
#
/*
 *  linux/boot/head.s
 *
 *  (C) 1991  Linus Torvalds
 */
/*
 *  head.s contains the 32-bit startup code.
 *
 * NOTE!!! Startup happens at absolute address 0x00000000, which is also where
 * the page directory will exist. The startup code will be overwritten by
 * the page directory.
 */
.text
.globl _idt,_gdt,_pg_dir,_tmp_floppy_area
_pg_dir:  #页目录将会存放在这里
startup_32:
#############################################
# 设置段寄存器
# 再次注意，现在程序已经运行在32模式，因此这里
# 的 0x10 并不是把地址 0x10 装入各个段寄存器，它现在
# 是全局段描述符表的偏移量。这里的 0x10 正好指向
# 在setup.s中设置的数据段的描述符。
#
# 下面代码的含义是，置 ds，es，fs，gs 中的选择符
# 为 setup.s 中构造的数据段，并将堆栈放置在数据段
# _stack_start数组内，然后使用新的中断描述符表
# 和全局描述符表，新的全局段描述符表中初始化内
# 容和 setup.s 中完全相同。
#
movl $0x10,%eax
mov %ax,%ds
mov %ax,%es
mov %ax,%fs
mov %ax,%gs

#############################################
# 加载堆栈指针寄指令
# long user_stack [ PAGE_SIZE>>2 ] ;
#
# struct {
# long * a;
# short b;
# } stack_start = { & user_stack [PAGE_SIZE>>2] , 0x10 };
# from kernel/sched.c
#############################################

lss _stack_start,%esp   # 设置系统堆栈段
                        # _stack_start -> ss:esp
                        # zr: 低 16 位传递给 esp, 高 32 位传递给 ss
call setup_idt
call setup_gdt

############################################
# 因为修改了gdt，需要重新加载所有的段寄存器。
############################################

movl $0x10,%eax     # reload all the segment registers
mov %ax,%ds         # after changing gdt. CS was already
mov %ax,%es         # reloaded in 'setup_gdt'
mov %ax,%fs
mov %ax,%gs
lss _stack_start,%esp

############################################
# 下面检测是否开启a20地址线采用的方法是向0x000000
# 处写入一个数值，然后看内存地址0x100000处是否也是
# 这个数值。如果一直相同的话，loop死掉。
############################################

xorl %eax,%eax
1:  incl %eax       # check that A20 really IS enabled
movl %eax,0x000000  # loop forever if it isn't
cmpl %eax,0x100000
je 1b

/*
 * NOTE! 486 should set bit 16, to check for write-protect in supervisor
 * mode. Then it would be unnecessary with the "verify_area()"-calls.
 * 486 users probably want to set the NE (#5) bit also, so as to use
 * int 16 for math errors.
 */
 ###########################################
 # 检查数学协处理器是否存在。采用的方法是先假设协处理器存在，
 # 执行一个协处理器指令，出错，表明不存在协处理器。
 ############################################

movl %cr0,%eax        # check math chip
andl $0x80000011,%eax # Save PG,PE,ET

/* "orl $0x10020,%eax" here for 486 might be good */
orl $2,%eax           # set MP
movl %eax,%cr0
call check_x87
jmp after_page_tables

/*
 * We depend on ET to be correct. This checks for 287/387.
 */

check_x87:
  fninit
  fstsw %ax
  cmpb $0,%al
  je 1f             /* no coprocessor: have to set bits */
  movl %cr0,%eax
  xorl $6,%eax      /* reset MP, set EM */
  movl %eax,%cr0
  ret
.align 2
1:  .byte 0xDB,0xE4 /* fsetpm for 287, ignored by 387 */
  ret

####################################################
/*
 *  setup_idt
 *
 *  sets up a idt with 256 entries pointing to
 *  ignore_int, interrupt gates. It then loads
 *  idt. Everything that wants to install itself
 *  in the idt-table may do so themselves. Interrupts
 *  are enabled elsewhere, when we can be relatively
 *  sure everything is ok. This routine will be over-
 *  written by the page tables.
 */
/*
 * 将中断描述符表idt设置成具有256项，并且都指向邋ignore_int
 * 中断门。然后加载中断描述符寄存器lidt。真正使用的中断门
 * 以后再安装。当我们认为其他地方认为一切正常时，在开启中断。
 * 这个 routine 会被页表覆盖掉。
 *
 * 中断描述表中的项8个字节。它的 0-1，6-7 字节是偏移量，2-3 字节
 * 是选择符，4-5 是一些标志。
 *
 */
setup_idt:
  lea ignore_int,%edx       # ignore_int 的有效地址移动到 edx
  movl $0x00080000,%eax     # 8 应该被看成 1000, 用来初始化 IDT
  movw %dx,%ax              /* selector = 0x0008 = cs */
  movw $0x8E00,%dx          /* interrupt gate - dpl=0, present */
  lea _idt,%edi             # 将_idt的值加载到edi。
  mov $256,%ecx             # 下面跳转使用跳转使用。dec %ecx
rp_sidt:
  movl %eax,(%edi)          # 在上面将 movl $0x00080000,%eax
                            # 设置为 $0x00080000
  movl %edx,4(%edi)         # 在上面已经设置了edx的值
  addl $8,%edi
  dec %ecx
  jne rp_sidt
  lidt idt_descr            # 加载idt，其中idt_descr在下面定义。
  ret

/*
 *  setup_gdt
 *
 *  This routines sets up a new gdt and loads it.
 *  Only two entries are currently built, the same
 *  ones that were built in init.s. The routine
 *  is VERY complicated at two whole lines, so this
 *  rather long comment is certainly needed :-).
 *  This routine will beoverwritten by the page tables.
 */
 #
 # 这个子程序设置全局描述表gdt，并加载。
 #

setup_gdt:
  lgdt gdt_descr    # 加载全局描述符表寄存器。
  ret

/*
 * I put the kernel page tables right after the page directory,
 * using 4 of them to span 16 Mb of physical memory. People with
 * more than 16MB will have to expand this.
 */
 #
 # Linus将内核的内存页表直接放置在页目录之后，使用4个表来寻址
 # 16mb的物理内存。
 # 
 # 每个表项的格式是，0-11 一些标志位，12-31 表示一页内存的物理起始地址。

.org 0x1000 # 从0x1000处开始是第1页表。
pg0:
.org 0x2000
pg1:
.org 0x3000
pg2:
.org 0x4000
pg3:
.org 0x5000 # 下面定义的内存数据块从偏移量0x5000处开始。
/*
 * tmp_floppy_area is used by the floppy-driver when DMA cannot
 * reach to a buffer-block. It needs to be aligned, so that it isn't
 * on a 64kB border.
 */
_tmp_floppy_area: # 用作dma缓冲区，_tmp_floppy_area内存供
# 软驱驱动程序使用。
.fill 1024,1,0  # 供保留1024项，每项一个字节，填充0.
#
# 下面这几个入栈操作pushl永固为调用/init/main.c程序和返回做准备。
# 前面三个入栈操作不知道作什么用的。也许是linus用于在调试时能够
# 看清机器码用的。
# pushl $L6入栈操作是模拟调用main.c程序时，首先将返回地址入栈操作。
# 所以如果main.c程序真正退出时，就会返回这里标号l6处继续执行下去。
# 即形成死循环。
# pushl $_main将main程序的地址压入堆栈，这样在设置分页处理结束之后，
# 执行ret指令返回指令时就会将main.c程序的地址弹出堆栈，并去执行main.c
# 程序去了。
#

after_page_tables:

# 这些是调用main程序的参数。

  pushl $0          # These are the parameters to main :-)
  pushl $0
  pushl $0
  pushl $L6         # return address for main, if it decides to.
  pushl $_main      # _main是编译程序对main的内部表示方法。
  jmp setup_paging
  L6:
  jmp L6            # main should never return here, but
                    # just in case, we know what happens.

/* This is the default interrupt "handler" :-) */
# 下面是默认的中断向量句柄。
int_msg:
.asciz "Unknown interrupt\n\r"
.align 2
ignore_int:
  pushl %eax
  pushl %ecx
  pushl %edx
  push %ds
  push %es
  push %fs
  movl $0x10,%eax     # 设置段选择符
  mov %ax,%ds
  mov %ax,%es
  mov %ax,%fs
  pushl $int_msg      # 把调用printk函数的参数的指针入栈。
  call _printk        # 调用printk函数。该函数在/kernel/printk.c
                      # _printk是printk编译后模块内部的表示方法。
  popl %eax
  pop %fs
  pop %es
  pop %ds
  popl %edx
  popl %ecx
  popl %eax
  iret                # 中断返回，吧中断调用是压入栈的 cpu 标志寄存器的值夜弹出。

/*
 * Setup_paging
 *
 * This routine sets up paging by setting the page bit
 * in cr0. The page tables are set up, identity-mapping
 * the first 16MB. The pager assumes that no illegal
 * addresses are produced (ie >4Mb on a 4Mb machine).
 *
 * NOTE! Although all physical memory should be identity
 * mapped by this routine, only the kernel page functions
 * use the >1Mb addresses directly. All "normal" functions
 * use just the lower 1Mb, or the local data space, which
 * will be mapped to some other place - mm keeps track of
 * that.
 *
 * For those with more memory than 16 Mb - tough luck. I've
 * not got it, why should you :-) The source is here. Change
 * it. (Seriously - it shouldn't be too difficult. Mostly
 * change some constants etc. I left it at 16Mb, as my machine
 * even cannot be extended past that (ok, but it was cheap :-)
 * I've tried to show which constants to change by having
 * some kind of marker at them (search for "16Mb"), but I
 * won't guarantee that's all :-( )
 */
 # 这个子程序通过设置控制寄存器cr0的标志来开启cpu对内存的分页处理
 # ，并设置各个页表内容。
 #
 #

.align 2  # 按4字节方式对其内存地址边界。
setup_paging:       # 首先对5页清0
  movl $1024*5,%ecx /* 5 pages - pg_dir+4 page tables */
  xorl %eax,%eax
  xorl %edi,%edi    /* pg_dir is at 0x000 */
  cld
  rep
  #stosl等指令表示将一段内存（源）中的数据复制到另一段内存（目标）中去。
  stosl

##############################################################
# 下面四句设置页目录项，我们共有4个页表，所以只需要设置4项。
# 页目录的结构与页表中的项的结构是相同的，4个字节为1项。
# $pg0 + 7表示 0x00001007，是页目录表的第一项。
# 则第一页表所在的地址 0x00001007 & 0xfffff000 = 0x1000
# 第一页的属性标志是 0x00001007 & 0x00000fff = 0x07，表示
# 该页存在，用户可以读写。
# 以下几行中的 7 应看成二进制的 111，是页属性，
# 代表 u/s, r/w, present
# 111 代表：用户 u，读写 rw，存在 p
# 000 代表：内核 s，只读 r ，不存在 
##############################################################

  movl $pg0+7,_pg_dir     /* set present bit/user r/w */
  movl $pg1+7,_pg_dir+4   /*  --------- " " --------- */
  movl $pg2+7,_pg_dir+8   /*  --------- " " --------- */
  movl $pg3+7,_pg_dir+12  /*  --------- " " --------- */

#########################################################
# 下面的代码段填写4个页表中所有的项内容。
#
# 每项的内容是，当前项所映射的物理内存地址 + 该页的标志。
##########################################################

  movl $pg3+4092,%edi     # edi -> 最后一页的最后一项
  movl $0xfff007,%eax     /*  16Mb - 4096 + 7 (r/w user,p) */
  std                     # 方向置位，edi自减。
1:  stosl                 /* fill pages backwards - more efficient :-) */
  subl $0x1000,%eax       # 每填好一项，地址自减。
  jge 1b                  # 如果小于0，则表示全部填好。

  # 设置也目录基址寄存器cr3的值，指向页目录表。

  xorl %eax,%eax          /* pg_dir is at 0x0000 */
                          # 页目录在0x0000处
  movl %eax,%cr3          /* cr3 - page directory start */
                          # 设置启动分页处理功能。
  movl %cr0,%eax
  orl $0x80000000,%eax
  movl %eax,%cr0          /* set paging (PG) bit */

#########################################################
# 在改变分页处理标志之后，要求使用转移指令来刷新予取指令队列，
# 这里使用的是指令ret。该返回指令的另一个作用是将堆栈中的main
# 程序的返回地址弹出，并开始运行/init/main.c程序。
#
# 呵呵，启动程序终于完了。
##########################################################

  ret                     /* this also flushes prefetch-queue */


.align 2            # 按4字节方式对齐内存边界地址
.word 0
idt_descr:
.word 256*8-1       # idt contains 256 entries
.long _idt
.align 2
.word 0

gdt_descr:
  .word 256*8-1     # so does gdt (not that that's any
  .long _gdt        # magic number, but it works for me :^)

.align 3
_idt: .fill 256,8,0 # idt is uninitialized

###############################################################
#
# 全局描述符表，前四项分别为空项，代码段描述符，数据段描述符
# 系统段描述符。其中系统段描述符在linux中没有起到作用。后面还预留
# 了252项用于创建任务的ldt和tss
#

_gdt: .quad 0x0000000000000000  /* NULL descriptor */
  .quad 0x00c09a0000000fff      /* 16Mb */
  .quad 0x00c0920000000fff      /* 16Mb */
  .quad 0x0000000000000000      /* TEMPORARY - don't use */
  .fill 252,8,0                 /* space for LDT's and TSS's etc */

################################################################
# head.s程序执行结束之后，已经正式的完成了内存页目录和页表的设置，
# 并重新设置了内核实际使用的中断描述符表idt和全局描述符表gdt。另外
# 还给软盘的驱动程序开辟了1kb的字节缓冲区。此时的system模块在内存中
# 的详细映像如下 :
#
# 1-----------------------------1
# 1       .........             1
# 1-----------------------------1
# 1      lib 模块代码             1
# 1-----------------------------1
# 1      mm模块代码               1
# 1-----------------------------1
# 1      kernel模块代码           1
# 1-----------------------------1
# 1        main.c程序            1
# 1-----------------------------1
# 1           gdt               1
# 1-----------------------------1
# 1           idt               1
# 1-----------------------------1
# 1        head.s部分代码         1
# 1-----------------------------1
# 1        软盘缓冲区 1k          1
# 1-----------------------------1
# 1        内存页表 pg3           1
# 1-----------------------------1
# 1         pg2                 1
# 1-----------------------------1
# 1         pg1                 1
# 1-----------------------------1
# 1         pg0                 1
# 1-----------------------------1
# 1         内存页目录表          1
# 1-----------------------------1
# 参考《linux内核完全注释》和网上相关文章