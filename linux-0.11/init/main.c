/*
http://www.cnblogs.com/xuqiang/archive/2010/01/20/1953782.html
到了main.c，其实main.c中的大部分的内容是调用函数来实现初始化的工作，但是还是将它看完了。下面就是代码了。主要参考的是linux内核完全注释，在一些不太明白的地方，参考网上的介绍。废话少说。还有很长的路啊。努力啊O(∩_∩)O~。
*/

/*
 * main.c功能描述。
 */
//main.c 程序的主要功能是利用 setup.s 程序取得的系统参数设置系统的
// 的根文件设备号和一些全局变量。这些变量至两名了内存的开始地址
// 系统包含的内存容量和作为高速缓存区内存末端地址。如果还定义了
// 虚拟盘，则主存将会相应的减少。整个内存的镜像如下 :
//
// -------------------------------------------
// | kernel　| buffer | ramdisk | main memory |
// -------------------------------------------
//
// 高速缓存部分还要扣除显存和 rom bios 占用的部分。高速缓冲区主要
// 是磁盘等设备的临时存放数据的场所。主存的区域主要是由内存管理
// 模块 mm 通过分页机制进行内存的管理分配，以 4k 字节为一个页单位。
// 内核程序可以直接访问自由的高速缓冲区，但是对于页面的访问，则
// 需要通过 mm 模块才能实现将其分配到内存页面。
//
// 然后内核进行所有方面的硬件初始化工作。设置陷阱门，块设备，字符设备
// 和tty，包括人工创建的第一个任务task 0.待所有的设置工作完成时，开启
// 中断。在阅读这些初始化程序时最好跟着这些被调用函数深入看下去。
//
// 整个内核的初始化完成后，内核将执行权限切换到用户模式，即是 cpu 从
// 0 特权级切换到 3 特权级。然后系统第一次调用函数 fork，创建出第一个用于
// 运行的 init 子程序。
//
// 在该进程中系统将运行控制台程序。如果控制台环境监理成功，则在生成一
// 个子进程，用于运行 /bin/sh.
//
// 对于linux而言，所有的任务都是在用户模式下运行的。包括很多系统应用
// 程序，入Shell程序，网络子程序系统。

/*
 *  linux/init/main.c
 *
 *  (C) 1991  Linus Torvalds
 */

#define __LIBRARY__     // 在unistd.h中使用了如下的预处理命令，
                        // #ifdef __LIBRARY__，
                        // 所以这里包含这个定义。
#include <unistd.h>   
#include <time.h>       // 时间类型的头文件。其中最主要的是 tm 结构的定义。

/*
 * we need this inline - forking from kernel space will result
 * in NO COPY ON WRITE (!!!), until an execve is executed. This
 * is no problem, but for the stack. This is handled by not letting
 * main() use the stack at all after fork(). Thus, no function
 * calls - which means inline code for fork too, as otherwise we
 * would use the stack upon exit from 'fork()'.
 *
 * Actually only pause and fork are needed inline, so that there
 * won't be any messing with the stack from main(), but we define
 * some others too.
 */

/*
 * 我们需要下面这些内嵌语句 - 从内核空间创建进程(forking)将导致没有
 * 写时复制（COPY ON WRITE）!!! 直到一个执行execve 调用。这对堆栈可
 * 能带来问题。处理的方法是在fork()调用之后不让main()使用任何堆栈。
 *　因此就不能有函数调用 - 这意味着fork 也要使用内嵌的代码，否则我
 * 们在从fork()退出时就要使用堆栈了。实际上只有pause 和fork 需要使用
 * 内嵌方式，以保证从main()中不会弄乱堆栈，但是我们同时还定义了其它
 * 一些函数。
 *
 * 下面介绍linux对于堆栈使用，然后介绍对于上述注释的解释。
 * 1.开机初始化时（bootsect.s,setup.s）
 * 当bootsect代码被ROM BIOS引导加载到物理内存0x7c00处时，并没有设置
 * 堆栈段，程序也没有使用堆栈，直到bootsect被移动到0x9000:0处时，才把
 * 堆栈段寄存器SS设置为0x9000，堆栈指针esp寄存器设置为0xff00，所以堆
 * 栈堆栈在0x9000:0xff00处（boot/bootsect.s L61,62）setup.s也使用这个堆栈
 * 2.进入保护模式时候（head.s，L31）
 * 此时堆栈段被设置为内核数据段（0x10），堆栈指针esp设置成指向user_stack
 * 数组（sched.c L67～72）的顶端，保留了1页内存作为堆栈使用.
 * 3.初始化时（main.c）
 * 在执行move_to_user_mode()代码把控制权移交给任务0之前，系统一直使用
 * 上述堆栈，而在执行过move_to_user_mode()之后，main.c的代码被“切换”成
 * 任务0中执行。通过执行fork()系统调用，main.c中的init()将在任务1中执行，
 * 并使用任务1的堆栈，而main()本身则在被“切换”成为任务0后，仍热继续使
 * 用上述内核程序自己的堆栈作为任务0的用户态堆栈
 *
 * 上面的注释不是很清楚，现解释如下 : 
 * Linux在内核空间创建进程时不使用写时复制技术。main()在移动到用户模
 * 式（移到任务0）后执行内嵌方式的fork()和pause()，因此可保证不使用任
 * 务0的用户栈。在执行moveto_user_mode(),之后，本程序main()就以任务0
 * 的身份在运行了。而任务0是所有将创建子进程的父进程。当它创建一个子
 * 进程时（init进程），由于任务1代码属于内核空间，因此没有使用写时复制功能。
 * 此时任务0的用户栈就是任务1的用户栈，即它共同使用一个栈空间。因此
 * 希望在main.c运行,在任务0的环境下时不要有对堆栈的任何操作，以免弄
 * 乱堆栈。而在再次执行fork()并执行过execve()函数后，被加载程序已不
 * 属于内核空间，因此可以使用写时复制技术了.由上面的分析可知，使用
 * 内联函数时为了使init进程1不修改main.c进程0不修改堆栈空间。
 * 
 */
static inline _syscall0(int,fork)
static inline _syscall0(int,pause)
static inline _syscall1(int,setup,void *,BIOS)
static inline _syscall0(int,sync)   // int sync ()系统调用。

#include <linux/tty.h>   
// tty 头文件，定义了有关tty_io，串行通信方面的参数、常数。
// 所谓“串行通信“是指外设和计算机间使用一根数据信号线,
// 数据在一根数据信号线上按位进行传输，每一位数据都占据一个固定的时间长度。
#include <linux/sched.h>  
// 调度程序头文件，定义了任务结构task_struct、第1 个初始任务   
// 的数据。还有一些以宏的形式定义的有关描述符参数设置和获取的
// 嵌入式汇编函数程序。
#include <linux/head.h>   
// head 头文件，定义了段描述符的简单结构，和几个选择符常量。
#include <asm/system.h>   
// 系统头文件。以宏的形式定义了许多有关设置或修改
// 描述符/中断门等的嵌入式汇编子程序。
#include <asm/io.h>    
// io 头文件。以宏的嵌入汇编程序形式定义对io 端口操作的函数。
#include <stddef.h>    
// 标准定义头文件。定义了NULL, offsetof(TYPE, MEMBER)。
#include <stdarg.h>    
// 标准参数头文件。以宏的形式定义变量参数列表。主要说明了-个
// 类型(va_list)和三个宏(va_start, va_arg 和va_end)，vsprintf
// vprintf、vfprintf。
#include <unistd.h>    
#include <fcntl.h>    
// 文件控制头文件。用于文件及其描述符的操作控制常数符号的定义。
#include <sys/types.h>   
// 类型头文件。定义了基本的系统数据类型

#include <linux/fs.h>   
// 文件系统头文件。定义文件表结构（file,buffer_head,m_inode 等）

static char printbuf[1024];

extern int  vsprintf();
extern void init(void);
extern void blk_dev_init(void);                   // 块设备初始化。
extern void chr_dev_init(void);                   // 字符设备初始化。
extern void hd_init(void);                        // 硬盘初始化程序。
extern void floppy_init(void);                    // 软盘初始化程序。
extern void mem_init(long start, long end);       // 内存管理程序初始化。
extern long rd_init(long mem_start, int length);  // 虚拟盘初始化
extern long kernel_mktime(struct tm * tm);        // 建立内核时间
extern long startup_time;                         // 内核启动时间（开机时间）（秒）.

/*
 * This is set up by the setup-routine at boot-time
 */
/* 
 * 以下这些数据是由setup.s 程序在引导时间设置的. 
 */  
#define EXT_MEM_K     (*(unsigned short *)    0x90002)  // 1m以后的拓展内存大小。
#define DRIVE_INFO    (*(struct drive_info *) 0x90080)  // 硬盘参数表基址。
#define ORIG_ROOT_DEV (*(unsigned short *)    0x901FC)  // 根文件系统所在设备号。

/*
 * Yeah, yeah, it's ugly, but I cannot find how to do this correctly
 * and this seems to work. I anybody has more info on the real-time
 * clock I'd be interested. Most of this was trial and error, and some
 * bios-listing reading. Urghh.
 */

#define CMOS_READ(addr) ({ \    // 这段宏读取cmos实时时钟信息。
outb_p(0x80|addr,0x70); \       // 0x70是写端口号，0x80|addr 是要读取的CMOS 内存地址
inb_p(0x71); \                  // 0x71 是读端口号。
})

// 将BCD 码转换成数字.
// 二进制转十进制
#define BCD_TO_BIN(val) ((val)=((val)&15) + ((val)>>4)*10)   

//----------------------------------------------------------
//        time_init
//----------------------------------------------------------
// 读取cmos中的信息，初始化全局变量startup_time
static void time_init(void)    
{
 struct tm time;

 do {
  time.tm_sec = CMOS_READ(0);   // 当前时间的秒值
  time.tm_min = CMOS_READ(2);
  time.tm_hour = CMOS_READ(4);
  time.tm_mday = CMOS_READ(7);
  time.tm_mon = CMOS_READ(8);
  time.tm_year = CMOS_READ(9);
 } while (time.tm_sec != CMOS_READ(0));

 BCD_TO_BIN(time.tm_sec);
 BCD_TO_BIN(time.tm_min);
 BCD_TO_BIN(time.tm_hour);
 BCD_TO_BIN(time.tm_mday);
 BCD_TO_BIN(time.tm_mon);
 BCD_TO_BIN(time.tm_year);
 time.tm_mon--;                         // months since January - [0,11]
 startup_time = kernel_mktime(&time);   // 开机时间，从 1970-01-01 00:00 开始计算
}

static long memory_end          = 0;    // 机器具有的内存（字节数）
static long buffer_memory_end   = 0;    // 高速缓冲区末端地址
static long main_memory_start   = 0;    // 主内存（将用于分页）开始的位置

struct drive_info { char dummy[32]; } drive_info;   // 用于存放硬盘信息

//---------------------------------------------------------------------------
//      main
//-------------------------------------------------------------------------
void main(void)   /* This really IS void, no error here. */
{                 /* The startup routine assumes (well, ...) this */
/*
 * Interrupts are still disabled. Do necessary setups, then
 * enable them
 */
// 此时中断仍然是关着，在必要的设置完成之后，打开中断。
  // 下面这段代码用于保存
  // 根设备号 -- ROOT_DEV； 
  // 高速缓存末端地址 -- buffer_memory_end   
  // 机器内存数 -- memory_end；
  // 主内存开始地址 -- main_memory_start
  
  // 根据 bootsect 中写入机器系统数据的信息设置根设备为软盘的信息，设置为根设备
  ROOT_DEV = ORIG_ROOT_DEV;  
  drive_info = DRIVE_INFO;              
 
  memory_end = (1<<20) + (EXT_MEM_K<<10); // 内存大小=1Mb 字节+扩展内存(k)*1024 字节
  memory_end &= 0xfffff000;               // 忽略不到4Kb（1 页）的内存数
                                          // 按页的倍数取整，
                                          // 忽略内存末端不足一页的部分
  
  if (memory_end > 16*1024*1024)          // 如果内存超过16Mb，则按16Mb 计
    memory_end = 16*1024*1024;
  
  if (memory_end > 12*1024*1024)          // 如果内存>12Mb，则设置缓冲区末端=4Mb
    buffer_memory_end = 4*1024*1024;
  else if (memory_end > 6*1024*1024)      // 否则如果内存>6Mb，则设置缓冲区末端=2Mb
    buffer_memory_end = 2*1024*1024;
  else                                    // 否则则设置缓冲区末端=1Mb
    buffer_memory_end = 1*1024*1024;
  
  main_memory_start = buffer_memory_end;  // 主内存(用于分页使用)起始位置=缓冲区末端
                                          // 缓冲区之后就是主内存
  
  // 如果 makefile 文件中设置了 “虚拟盘使用标志”
  // 操作系统从缓冲区末端开辟 2 MB 内存空间做为虚拟盘
  // 主内存起始位置后移 2 MB 至虚拟盘的末端
  #ifdef RAMDISK
  main_memory_start += rd_init(main_memory_start, RAMDISK*1024);
  // kernel/ramdisk.c
  #endif

  // mm/memory.c
  mem_init(main_memory_start,memory_end);
  // 陷阱门（硬件中断向量）初始化
  // trap_init()函数将中断、异常处理的服务程序与IDT进行挂接，
  // 逐步重建中断服务体系，支持内核、进程在主机中的运算
  // kernel/traps.c
  trap_init();
  // 块设备初始化 
  // kernel/blk_dev/blk.h        
  blk_dev_init();        
  // 字符设备初始化
  // 空函数
  // kernel/chr_dev/tty_io.c
  chr_dev_init();        
  // tty 初始化
  tty_init();         
  // 设置开机启动时间,startup_time
  time_init();        
  // 调度程序初始化 
  sched_init();        
  // 缓冲管理初始化，建内存链表等.
  buffer_init(buffer_memory_end);    
  // 硬盘初始化
  hd_init();         
  // 软盘初始化
  floppy_init();        
  // 设置完成，开启中断。
  sti();          
  // 移到用户模式
  // 模仿中断返回动作，实现进程 0 的特权级从 0 转变为 3
  move_to_user_mode();      

  if (!fork()) {  /* we count on this going ok */
    init();
  }
/*
 *   NOTE!!   For any other task 'pause()' would mean we have to get a
 * signal to awaken, but task0 is the sole exception (see 'schedule()')
 * as task 0 gets activated at every idle moment (when no other tasks
 * can run). For task0 'pause()' just means we go check if some other
 * task can run, and if not we return here.
 */

/*
 * 注意!! 对于任何其它的任务，'pause()'将意味着我们必须等待收到一个信号才会返 
 * 回就绪运行态，但任务0（task0）是唯一的意外情况（参见'schedule()'），因为任务0 在 
 * 任何空闲时间里都会被激活（当没有其它任务在运行时），因此对于任务0'pause()'仅意味着 
 * 我们返回来查看是否有其它任务可以运行，如果没有的话我们就回到这里，一直循环执行'pause()'。 
 */  
 for(;;) pause();
}

//----------------------------------------------------------------------------
//     printf
//----------------------------------------------------------------------------
static int printf(const char *fmt, ...)   // 使用变长参数，调用write系统调用。
{
 va_list args;
 int i;

 va_start(args, fmt);
 write(1,printbuf,i=vsprintf(printbuf, fmt, args));
 va_end(args);
 return i;
}

static char * argv_rc[] = { "/bin/sh", NULL };  // 调用执行程序时参数的字符串数组
static char * envp_rc[] = { "HOME=/", NULL };  // 调用执行程序时的环境字符串数组

static char * argv[] = { "-/bin/sh",NULL };   // 同上
static char * envp[] = { "HOME=/usr/root", NULL };

//------------------------------------------------------------------------------
//      init
//------------------------------------------------------------------------------
void init(void)
{
 int pid,i;

 setup((void *) &drive_info);   // 读取硬盘信息
 (void) open("/dev/tty0",O_RDWR,0);  // 用读写访问方式打开设备“/dev/tty0“
 (void) dup(0);       // 复制句柄，产生句柄1 号 -- stdout 标准输出设备
 (void) dup(0);       // 复制句柄，产生句柄2 号 -- stderr 标准出错输出设备

 // 输出一些信息
 printf("%d buffers = %d bytes buffer space\n\r",NR_BUFFERS,
  NR_BUFFERS*BLOCK_SIZE);
 printf("Free mem: %d bytes\n\r",memory_end-main_memory_start);

 /*
  * 下面的代码打开/etc/rc，然后执行/bin/sh。但是这里开辟了
  * ；两个线程。
  */
 if (!(pid=fork())) {
  close(0);
  if (open("/etc/rc",O_RDONLY,0))
   _exit(1);
  execve("/bin/sh",argv_rc,envp_rc);
  _exit(2);
 }
 if (pid>0)
  while (pid != wait(&i))
   /* nothing */;
 
 /*
  * 如果执行到这里，说明刚创建的子进程的执行已停止或终止了。
  * 下面循环中首先再创建一个子进程.如果出错，则显示“初始化
  * 程序创建子进程失败”的信息并继续执行。对于所创建的子进
  * 程关闭所有以前还遗留的句柄(stdin, stdout, stderr)，新创
  * 建一个会话并设置进程组号，然后重新打开/dev/tty0 作为stdin，
  * 并复制成stdout 和stderr。再次执行系统解释程序/bin/sh。但
  * 这次执行所选用的参数和环境数组另选了一套。然后父进程再次
  * 运行wait()等待。如果子进程又停止了执行，则在标准输出上显
  * 示出错信息“子进程pid 停止了运行，返回码是i”，然后继续重
  * 试下去…，形成“大”死循环
  *
  */
 while (1) {
  if ((pid=fork())<0) {
   printf("Fork failed in init\r\n");
   continue;
  }
  if (!pid) {
   close(0);
   close(1);
   close(2);
   setsid();
   (void) open("/dev/tty0",O_RDWR,0);
   (void) dup(0);
   (void) dup(0);
   _exit(execve("/bin/sh",argv,envp));
  }
  while (1)
   if (pid == wait(&i))
    break;
  printf("\n\rchild %d died with code %04x\n\r",pid,i);
  sync();
 }
 _exit(0); /* NOTE! _exit, not exit() */
}

/*
 * 至此linux启动已经完成。有上面的代码分析可知，根文件系统只要即可实现。
 */