参考资料 Linux内核完全注释.pdf
http://www.cnblogs.com/xuqiang/archive/2010/01/19/1953784.html

网上相关资料

! setup程序的主要作用是利用rom bios的中断来读取机器系统参数，并将这些数据保存在0x90000
! 开始的位置(覆盖掉了bootsect程序所在的位置)，所取得的参数被内核的相关程序使用。
! 注意在 bootsect 中已经将该模块和 system、模块加载到内存中。
! 然后setup程序将system模块从地址 0x10000-0x8fff (当时认为内核的最大值)
! 整块移动到内存的绝对址 0x00000 处。接下来加载中断描述符表寄存器 idtr 和全局描述符表 gdtr，
! 开启 a20 地址线，重新设置两个中断控制芯片，将硬件终端号重新设置，最后
! 设置 cpu 的控制寄存器 cr0，从而进入32位的保护模式，并且跳转到 system 模块
! 最前面的 head.s 程序处开始继续运行。
!
! 为了能让 head.s 在32位的保护模式下运行，本程序设置了中断描述符表 idt 
! 和全局描述符表 gdt ，并在 gdt 中设置了当前内核代码段的描述符和数据段的描述符。
! 在下面的 head.s 程序中会根据内核的需要重新设置这些描述符表。
!
! setup.s  (C) 1991 Linus Torvalds
!
! setup.s is responsible for getting the system data from the BIOS,
! and putting them into the appropriate places in system memory.
! both setup.s and system has been loaded by the bootblock.
!
! This code asks the bios for memory/disk/other parameters, and
! puts them in a "safe" place: 0x90000-0x901FF, ie where the
! boot-block used to be. It is then up to the protected mode
! system to read them from there before the area is overwritten
! for buffer-blocks.
!

! NOTE! These had better be the same as in bootsect.s!

INITSEG  = 0x9000 ! we move boot here - out of the way，原来的bootsect段
SYSSEG   = 0x1000 ! system loaded at 0x10000 (65536).system所在段
SETUPSEG = 0x9020 ! this is the current segment，本程序所在段

.globl begtext, begdata, begbss, endtext, enddata, endbss
.text
begtext:
.data
begdata:
.bss
begbss:
.text

entry start
start:

! ok, the read went well so we get current cursor position and save it for
! posterity.
! 整个读磁盘的过程都很顺利，现在将光标位置保存以备后用。

 ! 设置ds = 0x9000
 mov ax,#INITSEG  ! this is done in bootsect already, but...
 mov ds,ax

 !//////////////////////////////////////////////////////
 ! 调用系统中断 0x10 读取光标位置。下面是中断前的准备和调用中断。
 mov ah,#0x03     ! read cursor pos ah = 0x03
 xor bh,bh        ! bh = 页号
 int 0x10         ! save it in known place, con_init fetches
 !///////////////////////////////////////////////////////
 ! 将信息保存在 0x90000 处，控制台初始化时来读取。
 mov [0],dx       ! it from 0x90000.

! Get memory size (extended mem, kB)
! 得到拓展内存的大小，调用中断 0x15，同时将得到信息保存到 0x90002 处。
 mov ah,#0x88
 int 0x15
 mov [2],ax

! Get video-card data:
! 下面的代码用于取得的是当前的显卡的显示模式
! 调用中断 0x10，同时将信息存储。

 !//////////////////////////////////////////////////////
 mov ah,#0x0f
 int 0x10
 !//////////////////////////////////////////////////////
 ! 0x90004 中存放的是当前页
 ! 0x90006 显示模式
 ! 0x90007 字符列数
 mov [4],bx  ! bh = display page
 mov [6],ax  ! al = video mode, ah = window width
 !/////////////////////////////////////////////////////

! check for EGA/VGA and some config parameters
! 检查显示模式。并取得参数。其中 ega 和 vga 是显示器的两种模式。
! 利用中断 0x10 来实现读取信息，并将相关信息保存。
 !/////////////////////////////////////////////////
 mov ah,#0x12
 mov bl,#0x10
 int 0x10
 !////////////////////////////////////////////////
 mov [8],ax  ! ??
 mov [10],bx  ! 0x9000A -- 显存大小
              ! 0x9000B -- 显示状态，彩色还是单色
 mov [12],cx  ! 0x9000C -- 显卡的特征参数
 !///////////////////////////////////////////////
 
! Get hd0 data
! 获取第一个硬盘信息，赋值硬盘参数列表
 mov ax,#0x0000
 mov ds,ax
 !///////////////////////////////////////////////
 ! 利用中断向量 0x41 的值，也即是 hd0 参数列表的地址。
 ! 
 ! pc机上的中断向量表 : pc 机 bios 在初始化时会在物理内存
 ! 开始的一夜内存中存放中断向量表，每个中断向量表对应的
 ! 中断服务处理程序 isr 的地址使用 4 个字节来表示。但是某些
 ! 的中断向量却使用其他的值，这包括中断向量 0x41 和 0x46，
 ! 这两个中断向量的处理程序地址实际上就是硬盘参数表的位置。
 !
 ! 在CPU被加电的时候，最初的 1 M的内存，是由 BIOS 为我们安排
 ! 好了的，每一字节都有特殊的用处。

 lds si,[4*0x41]
 !////////////////////////////////////////////////
 mov ax,#INITSEG
 mov es,ax
 mov di,#0x0080
 mov cx,#0x10
 rep
 movsb

! Get hd1 data
! 取得hd1的参数列表，方法同上。
 mov ax,#0x0000
 mov ds,ax
 lds si,[4*0x46]
 mov ax,#INITSEG
 mov es,ax
 mov di,#0x0090
 mov cx,#0x10
 rep
 movsb

! Check that there IS a hd1 :-)
! 检查是否存在第二个硬盘，如果不存在，第二个硬盘表清 0. 利用 bios 的 int 0x13 来实现。

 mov ax,#0x01500
 mov dl,#0x81       ! 0x81指的是第2个硬盘
 int 0x13

 jc no_disk1
 cmp ah,#3  ! 是硬盘吗 ? 类型 = 3
 je is_disk1
no_disk1:
! 第二个硬盘不存在，则对第二个硬盘表清0
 mov ax,#INITSEG
 mov es,ax
 mov di,#0x0090      ! 0x90090 ---+--- 0x10
 mov cx,#0x10
 mov ax,#0x00
 rep
 stosb
is_disk1:

! now we want to move to protected mode ...
 cli                  ! no interrupts allowed !禁止中断

! first we move the system to it's rightful place
! 首先我们将system模块移动到正确的位置。下面程序代码是将system模块移动到 0x0000
! 位置，即把从 0x10000-0x8ffff 的内存数据 512 k，整体向内存低端移动了 0x10000 - 64k

 mov ax,#0x0000
 cld                  ! 'direction'=0, movs moves forward
do_move:
 mov es,ax            ! destination segment 
                      ! 目的地址初始为0x000 : 0x0
 add ax,#0x1000
 cmp ax,#0x9000       ! 移动完毕
 jz end_move
 mov ds,ax            ! source segment
                      ! 源地址 0x1000 : 0x0
 sub di,di
 sub si,si
 mov  cx,#0x8000      ! 移动64k
 rep
 movsw
 jmp do_move

! 现在已经将system模块加载到内存的0地址。

! then we load the segment descriptors
! lidt 指令用于加载中断描述符表 idt 寄存器。其中加载时只是加载的描述符表的线性基地址。
! 中断描述符表中的每一个表项指出发生中断时需要调用的代码信息。
!
! lgdt 指令用于加载中断描述符表idt。
! ldgt 指令用于加载全局描述符表gdt寄存器。
!
! 8086 处理器的保护模式和实时模式，采用实
! 时模式的寻址，没有虚拟内存空间,首先物理
! 内存的每个位置都是使用 20 位的地址来标识的。
! 寻址是通过使用 cs，ds，ss，es加上段的偏移量。
!
! 在保护模式下，cpu 通过选择子找到段描述符，来
! 寻址。包括全局段表，局部段表，中断表。
! 段选择子通过 ldgr 寄存器来找到全局段表，通过 idtr 找到中断表。
!
end_move:

! 加载中断描述符idt
 mov ax,#SETUPSEG     ! right, forgot this at first. didn't work :-)
 mov ds,ax
 lidt idt_48          ! load idt with 0,0，idt_48在下面定义。
 lgdt gdt_48          ! load gdt with whatever appropriate，
                      ! gdt_48在下面定义。

! that was painless, now we enable A20
! 以上的操作很简单，现在我们开启a20地址线。 
!
 ! 为了兼容使用开启a20管脚。可以不必追究。
 !///////////////////////////////////////////////
 call empty_8042
 mov al,#0xD1         ! command write
 out #0x64,al
 call empty_8042
 mov al,#0xDF         ! A20 on
 out #0x60,al
 call empty_8042
 !///////////////////////////////////////////////

! well, that went ok, I hope. Now we have to reprogram the interrupts :-(
! we put them right after the intel-reserved hardware interrupts, at
! int 0x20-0x2F. There they won't mess up anything. Sadly IBM really
! messed this up with the original PC, and they haven't been able to
! rectify it afterwards. Thus the bios puts interrupts at 0x08-0x0f,
! which is used for the internal hardware interrupts as well. We just
! have to reprogram the 8259's, and it isn't fun.
! 
! 下面的代码是给中断编程，我们将他放在处于intel保留的硬件中断后面，在
! int 0x20 -- 0x2f，在哪里它们不会引起中断。
! 
! 下面是8259芯片的简介 : 8259芯片是一种可编程控制芯片。每片可以管理8
! 个中断源。通过多片的级联方式，能构成最多管理64个中断向量的系统。在
! pc/at系列的兼容机中，使用了两个8259a芯片，共可管理15级中断向量。主
! 8259a芯片的端口基址是0x20，从芯片是0xa0.
!
 !/////////////////////////////////////////////////////////
 ! 0x11 表示初始化命令开始，是 icw1 命令字，表示边沿触发，多片
 ! 8259 级联,最后要发送 icw4 命令字。8259a 的编程就是根据应用
 ! 程序需要将初始化字 icw1 -- icw4 和操作命令字 ocw1 -- ocw3
 ! 分别写入初始化命令寄存器组和操作命令寄存器组。 
 !
 mov al,#0x11       ! initialization sequence
 out #0x20,al       ! send it to 8259A-1
 !/////////////////////////////////////////////////////////
 !/////////////////////////////////////////////////////////
 ! 使用如下的.word 0x00eb,0x00eb 来祈祷延迟的作用。下面是相
 ! 关解释 : 0x00eb 是直接跳转指令操作码，带一个字节的相对地址
 ! 偏移量。0x00eb 表示跳转值是 0 的一条指令，因此还是直接执行
 ! 下一条指令。在 as86 中没有表示的助记符，所以 linus 直接使用了
 ! 机器码来表示这种指令。
 .word 0x00eb,0x00eb  ! jmp $+2, jmp $+2
 !/////////////////////////////////////////////////////////

 !//////////////////////////////////////////////////////////
 ! 进行8259a芯片编程。一次发送icw2，3，4
 out #0xA0,al  ! and to 8259A-2
 .word 0x00eb,0x00eb
 mov al,#0x20  ! start of hardware int's (0x20)
 out #0x21,al
 .word 0x00eb,0x00eb
 mov al,#0x28  ! start of hardware int's 2 (0x28)
 out #0xA1,al
 .word 0x00eb,0x00eb
 mov al,#0x04  ! 8259-1 is master
 out #0x21,al
 .word 0x00eb,0x00eb
 mov al,#0x02  ! 8259-2 is slave
 out #0xA1,al
 .word 0x00eb,0x00eb
 mov al,#0x01  ! 8086 mode for both
 out #0x21,al
 .word 0x00eb,0x00eb
 out #0xA1,al
 .word 0x00eb,0x00eb
 !/////////////////////////////////////////////////////////
 mov al,#0xFF  ! mask off all interrupts for now
     ! 屏蔽所有的主芯片的中断请求。
 out #0x21,al
 .word 0x00eb,0x00eb
 out #0xA1,al  ! 屏蔽芯片所有的中断请求。

! well, that certainly wasn't fun :-(. Hopefully it works, and we don't
! need no steenking BIOS anyway (except for the initial loading :-).
! The BIOS-routine wants lots of unnecessary data, and it's less
! "interesting" anyway. This is how REAL programmers do it.
!
! Well, now's the time to actually move into protected mode. To make
! things as simple as possible, we do no register set-up or anything,
! we let the gnu-compiled 32-bit programs do that. We just jump to
! absolute address 0x00000, in 32-bit protected mode.

 !////////////////////////////////////////////////
 ! 加载cr0
 mov ax,#0x0001     ! protected mode (PE) bit
 lmsw ax            ! This is it!
 ! cpu处于保护模式。
 !////////////////////////////////////////////////
 
 jmpi 0,8           ! jmp offset 0 of segment 8 (cs)
                    ! 跳转到cs段8，偏移量0
 ! 我们已经将system模块移动到 0x00000 处，所以这里的偏移地址
 ! 是 0.这里的段值的 8 已经是保护模式下的段选择符了，用于选择
 ! 描述符表和描述符表项以及所要求的特权级。
 ! 段选择符长度为16位；0-1 位表示请求的特权级；Linus只
 ! 只使用了2级:0级系统级和3级用户级。第2位用于选择是全局描
 ! 述符表还是局部描述符表。3-15 位是描述表项的索引，指出是第
 ! 几项描述符。
 ! 8 -- 0000，0000，0000，1000，表示请求的特权级是 0--系统级，
 ! 使用全局描述符表第1项，该代码指出代码的基地址是 0，因此这
 ! 里的跳转指令就回去执行system中的代码。
 !

! This routine checks that the keyboard command queue is empty
! No timeout is used - if this hangs there is something wrong with
! the machine, and we probably couldn't proceed anyway.
!
! 下面的代码检查键盘命令队列是否为空。
! 只有当输入缓冲区为空时才可以对其进行写的操作。
!
empty_8042:
 .word 0x00eb,0x00eb  ! 延迟
 in al,#0x64          ! 8042 status port
 test al,#2           ! is input buffer full? 
                      ! 输入缓冲区满 ?
 jnz empty_8042       ! yes - loop
 ret

!////////////////////////////////////////////////////////////////
! 数据描述
! 
! (1)Linux的任务： 
! ---定义GDT表 
! ---定义LDT表 
! ---初始化的时候执行LGDT指令，将GDT表的基地址装入到GDTR中 
! ---进程初始化的时候执行LLDT指令，将LLDT表的基地址装入到LDTR中 
!
! (2)CPU的任务 
! ---用GDTR寄存器保存GDT表的基地址 
! ---用LDTR寄存器保存当前进程的LDT表的基地址 
! ---需要访问内存的时候，利用LDTR(或者GDTR,多数情况下是前者)找到相应的表，再根据提供的内存地址的某些部分找到相应的表项，然后再对表项的内容继续操作，得到最终的物理地址。所有这些操作都是在一条指令的指令周期里面完成的。

! gdt -- 描述符表的主要作用是将应用程序的逻辑地址转换为线性地址。

gdt:

 !/////////////////////////////////////////////////////
 .word 0,0,0,0  ! dummy，第一个描述符，不可用，
    ! 主要适用于保护。
 !/////////////////////////////////////////////////////

 !///////////////////////////////////////////////////////
 ! 系统代码段描述符。加载代码段时，使用这个偏移量。段描述符
 ! 一共64位。描述如下 : 
 ! 0  -- 15 limit字段决定段的长度
 ! 16 -- 39 56 -- 63 段的首字节的线性地址
 ! 40 -- 43 描述段的类型和存取权限
 ! 44       系统标志；如果被清0，则是系统端。
 ! 45 -- 46 dpl 描述符的特权级；用于限制这个段的存取。它表示
 !          为访问这个段而要求的cpu的最小优先级。
 ! 47 -- 1
 ! 48 -- 51
 ! 52       被linux忽略。
 ! 53 -- 0
 ! 54 -- d/s 
 ! 55 -- g 力度标志
 ! 
 .word 0x07FF  ! 8Mb - limit=2047 (2048*4096= 8 Mb)
 .word 0x0000  ! base address=0
 .word 0x9A00  ! code read/exec
 .word 0x00C0  ! granularity=4096, 386
 !
 ! 从高地址到低地址为 00c0 9a00 0000 07ff
 ! 那么断脊地址就是 00 00 0000
 ! 偏移量是 07ff
 ! 描述符为 07ff
 !
 !///////////////////////////////////////////////////////

 !///////////////////////////////////////////////////////
 ! 系统数据段描述符。当加载数据段寄存器时使用的是这个偏移量。
 .word 0x07FF  ! 8Mb - limit=2047 (2048*4096=8Mb)
 .word 0x0000  ! base address=0
 .word 0x9200  ! data read/write
 .word 0x00C0  ! granularity=4096, 386
 !//////////////////////////////////////////////////////

idt_48:
 .word 0              ! idt limit=0
 .word 0,0            ! idt base=0L

gdt_48:
 .word 0x800          ! gdt limit=2048, 256 GDT entries
 .word 512+gdt,0x9    ! gdt base = 0X9xxxx

!/////////////////////////////////////////////////////////////////

.text
endtext:
.data
enddata:
.bss
endbss: