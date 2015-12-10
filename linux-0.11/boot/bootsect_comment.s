!时间  : 2010-1-14
!工作 : 阅读linux 0.11 源码中的bootsect.s
!http://www.cnblogs.com/xuqiang/archive/2010/01/19/1953785.html

!总体linux启动过程如下:
!
!当PC得电源打开之后，80x86结构的CPU将自动进入实时模式，并且从0xFFFF0开始自动执行程序代码，这个地址通常是
!ROM-BIOS的地址。PC机的BIOS将执行系统的检测，并且在物理地址的0处开始初始化中断向量。此后，它将可启动设备的第一
!扇区(512字节)读入内存的绝对地址0x7c00处，并且跳转到这个地方。启动设备通常是软盘或者是硬盘。这里的叙述是很简单
!的，但是这已经足够理解内核的初始化的工作过程。
!
!linux的0x9000由BIOS读入到内存的绝对地址0x7c00(31k)处，当它被
!执行时就会把自己移动到绝对地址0x90000处，并把启动设备中后2kb字节代码(boot/setup.s)读入到内存0x90200处，而内核的
!其他部分则被读入到从地址0x10000的开始处。在系统的加载期间显示信息?Loading...",然后将控制权传递给boot/setup.s中
!的代码.这是另一个实时模式汇编程序。
!
!系统启动部分识别主机的某些特性以及vga卡的类型。如果需要，它会要求用户为控制台选择显示模式。然后整个系统从地址
!0x10000移至0x0000处，进入保护模式病跳转至系统的余下部分。此时所有的32位运行方式的设置启动被完成:idt,gdt,ldt被
!加载，处理器和协处理器也确认，分页的工作也设置好了。最终将调用init/main.c中的main程序。上述的操作的源代码是在
!boot/head.s中的。这可能是整个内核中最有诀窍的代码了。注意如果在上述任何一步中出现了一步错误。计算机就会死锁。在
!操作系统还没有完全运转之前是处理不了错误的。
!
!
!bootsec.s文件说明如下:
!bootsec.s代码是磁盘的引导块程序，驻留在磁盘的第一扇区。在PC机加电rom bios自检之后，引导扇区由bios加载到内存0x7c00
!处，然后将自己移动到内存0x90000处。该程序的主要作用是首先将setup模块从磁盘加载到内存中，紧接着bootsect的后面位置
!(0x90200),然后利用bios中断0x13中断去磁盘参数表中当前引导盘的参数，然后在屏幕上显示"Loading system..."字符串。再者
!将system模块从磁盘上加载到内存0x10000开始的地方。随后确定根文件系统的设备号，如果没有指定，则根据所保存的引导盘的每
!类型和种类，并保存设备号与boot_dev,最后长跳转到 setup程序开始处0x90200执行setup程序。
!
!
!注释如下:
!
! SYS_SIZE is the number of clicks (16 bytes) to be loaded.
! 0x3000 is 0x30000 bytes = 196kB, more than enough for current
! versions of linux
!
SYSSIZE = 0x3000
!
!以下是这一段代码的翻译。
!
! bootsect.s
!bootsect.s被bios启动程序加载至0x7c00 31k处，并将自己移动到地址 0x90000 576 k 处，并跳转到那里。
!
!它然后利用bios中断将setup直接加载到自己后面 0x90200 576.5 k，并将system加载到地址 0x10000 处。
!
!注意 : 目前的内核系统最大的长度限制为 8*65536 = 512 k字节，即使是在将来这也应该没有问题的。我想让他保持简单明了，
!这样 512 k 的最大内核长度应该足够了，尤其是这里没有向minix中一样包含缓冲区高速缓冲。
!
!加载程序已经做的足够简单了，所以持续的独处错误将导致死循环。只能手工重启。只要可能，通过一次取出所有的扇区，加载的
!过程可以做的很快.
!
!
!
! bootsect.s  (C) 1991 Linus Torvalds
!
! bootsect.s is loaded at 0x7c00 by the bios-startup routines, and moves
! iself out of the way to address 0x90000, and jumps there.
!
! It then loads 'setup' directly after itself (0x90200) 256b, and the system
! at 0x10000, using BIOS interrupts. 
!
! NOTE! currently system is at most 8*65536 bytes long. This should be no
! problem, even in the future. I want to keep it simple. This 512 kB
! kernel size should be enough, especially as this doesn't contain the
! buffer cache as in minix
!
! The loader has been made as simple as possible, and continuos
! read errors will result in a unbreakable loop. Reboot by hand. It
! loads pretty fast by getting whole sectors at a time whenever possible.

!六个全局标示符
.globl begtext, begdata, begbss, endtext, enddata, endbss
!文本段
.text
begtext:
!数据段
.data
begdata:
!堆栈段
.bss
begbss:

!文本段
.text
SETUPLEN = 4                    ! nr of setup-sectors setup 程序的扇区数(setup-sectors)值
BOOTSEG  = 0x07c0               ! original address of boot-sector bootsect的原始地址
INITSEG  = 0x9000               ! we move boot here - out of the way 将bootsect移动到这里
SETUPSEG = 0x9020               ! setup starts here setup程序开始地址
SYSSEG   = 0x1000               ! system loaded at 0x10000 (65536). 将system模块加载到的地址
ENDSEG   = SYSSEG + SYSSIZE     ! where to stop loading 停止加载的地址

! ROOT_DEV: 0x000 - same type of floppy as boot.
!  0x301 - first partition on first drive etc
ROOT_DEV = 0x306 !根文件系统设备是第二硬盘的第一个分区
   !0x300 -- /dev/hd0   
   !0x301 -- /dev/hd1
   !...
   !0x309 -- /dev/hd9

entry start 告知连接程序，程序充start标号开始。
start:
////////////////////////////////////////////////////////////////////////////////////////////////////////////
!下面的代码是将自身bootsect从目前位置0x07c0 31k移动到0x9000 576k处，然后跳转到本程序的下一条语句处。
 !
 !此时(在实时模式下)内存使用如下的分布 :
 !0      0x7c00(bootsect.s)
 !--------++++++++++---------------------------
 !ds = 0x7c00
 !         <-
 mov ax,#BOOTSEG 
 mov ds,ax

 !es = 0x9000
 mov ax,#INITSEG
 mov es,ax

 !移动计数的值 256
 !启动代码是 512 kb
 mov cx,#256

 !源地址 ds : si = 0x07co : 0x0000
 sub si,si
 !目的地址 es : di = 0x9000 : 0x0000
 sub di,di

 !重复执行直到 cx = 0。循环程序实现的另一种方法是利用串操作处理的重复指令 rep。rep 指令以 cx 为重复次数，
 !当指令被重复执行完一次，那么 cx 的值会自动减一。rep 指令和串操作指令 movs，stos 配合使用，它将这两条指令
 !重复执行 cx 次。
 rep
 !移动一个字
 !zr: 这个 movw 命令相当于是 mov ds, es
 movw

 !此时的内存使用情况如下 :
 !0         0x7c00            0x9000
 !----------+++++++++---------+++++++++---------
 !两个使用中的内存是相同的

 !在汇编中的段的使用
 !
 !间接跳转。这里 INITSEG 指出跳转到的地址。
 !其格式为：jmpi offset(标号), segment selector
 jmpi go, INITSEG -- 0x9000
//////////////////////////////////////////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////////////////////////////////
!在将自己成功移动之后，下面的几步是为下面加载setup程序做准备。
!
!在执行 jmpi 指令时，cs 段会被自动更新。
!需要注意的是 cs 寄存器在 call 或者是 jmp 指令时会自动更新。
!将 ds es ss 都设置成代码所在的段。
!zr: cs 的值为 0x0900
!zr: cs 代码段寄存器，ds 数据段寄存器，es 附加段寄存器，ss 栈基址寄存器
go: mov ax,cs
 mov ds,ax
 mov es,ax

! 将堆栈指针 sp 指向 0x9ff00 (0x9000 : 0xff00)
! put stack at 0x9ff00.
! ss 被成为堆栈段寄存器，用于存放堆栈段的基值.
 mov ss,ax

!代码段的移动，需要重新设置堆栈段的位置。sp 只要指向远大于 512 任意处都可以。
 mov sp,#0xFF00  ! arbitrary value >> 512
! load the setup-sectors directly after the bootblock.
! Note that 'es' is already set up.
!
!////////////////////////////////////////////////////////////////////////////////////////////////

!在 bootsect 程序块后紧随着加载 setup 模块。注意 es 已经设置好了。es 是指附加段寄存器。
!附加段寄存器是 es，它的作用是很大的.
!因为我们在处理数据的时候,往往需要用到两个数据段,特别是在字符串的处理方面,使用两个数据段简便了许多的操作.
!下面的这段代码的主要作用是使用int 0x13 把磁盘上的 setup 模块加载到内存中，
!位置在 bootsect.s (0x90000 + 512字节)之后，
!真个过程主要是操作寄存器 ax，bx，cx，dx 等四个寄存器。
!
!
!//////////////////////////////////////////////////////////////////////////////////////////////////
!设置 load_setup 标号，是为了执行 j load_setup 语句。

load_setup:

 mov dx,#0x0000             ! drive 0, head 0 
 mov cx,#0x0002             ! sector 2, track 0
 mov bx,#0x0200             ! address = 512, in INITSEG
 mov ax,#0x0200+SETUPLEN    ! service 2, nr of sectors
 int 0x13                   ! read it 调用中断信号，开始读取。

 ! 进位操作标示符 cf = 0 表示操作成功。
 jnc ok_load_setup          ! ok - continue·如果成功就跳转到下面的 ok_load_setup
                            ! 否则执行下面的代码，复位磁盘再次执行这段代码
 mov dx,#0x0000
 mov ax,#0x0000             ! reset the diskette 磁盘复位
 int 0x13                   ! ld86中就有j这条指令，等价于jmp。这条语句的含义是 : 
                            ! 跳转回去继续执行,如果总是失败系统，将总执行这段代码
 j load_setup

!//////////////////////////////////////////////////////////////////////////////////////////////////

!时间 : 2010-1-15
!工作量  : 继续阅读linux 0.11 源码
!时间 : 2010-1-17
!工作量 : 继续阅读linux源码。
!
!如果上面讲setup模块顺利读入到内存中，那么执行下面的ok_load_setup代码。
!

ok_load_setup:

! Get disk drive parameters, specifically nr of sectors/track
! 取得磁盘驱动器的参数，特别是没道的扇区数量。
! 取得磁盘的参数使用的是int 0x13中断来实现，其调用格式如下 :
! ah = 0x08 dl = 启动器号
! 返回信息如下 :
! 如果出错的话cf置位，并且ah = 状态码
! ah = 0， al = 0, bl = 驱动器类型(at/ps2)
! ch = 最大磁盘号的低 8 位， cl = 每磁盘的最大扇区数(位 0-5)，最大磁道号高 2 位(位 6-7)
! dh = 最大磁道数 dl = 驱动器数量
! es : di = 软驱磁盘参数表
!
! 调用中断0x13
 mov dl,#0x00       ! 清空dl，以获得驱动器号
 mov ax,#0x0800     ! AH=8 is get drive parameters
 int 0x13
 
 mov ch,#0x00
 ///////////////////////////////////////////////////////////
 !先讲一下寄存器的默认组合问题，比如指令 mov [si], ax 表示将ax中的内容存入 ds:si 指向的内存单元，也就是说在寄存器间
 !接寻址的情况下,以 si 间接寻址时总是默认以 ds 为相应的段地址寄存器。同样 di 是以 es 为默认的段地址寄存器。
 
 !第二个要了解的是“段超越”的问题，就是在某些时候你不想使用默认的段地址寄存器，那
 !么你可以强制指定一个段地址寄存器（当然这种强制是在允许的情况下，建议看一下汇编
 !教材上的说明），同上例 mov [si],ax 表示存入 ds:si 中，但如果你想存入 cs 指向的段中可
 !以这样 mov cs:[si],ax，这样就强制指定将 ax 中的内容存入 cs:si 的内存单元。
 
 !第三个要明白的是 seg cs 这样的语句只影响到它下一条指令，比如在 linux 启动代码中的一段：
      !seg cs
      !mov sectors,ax
      !mov ax,#INITSEG
 !要说明两点：
     !第一，seg cs 只影响到 mov sectors,ax 而不影响 mov ax,#INITSEG
     !第二，如果以 Masm 语法写, seg cs 和 mov sectors,ax 两句合起来等
        !  价于mov cs:[sectors],ax，这里使用了间接寻址方式。
        !  重复一下前面的解释，mov [sectors],ax 表示将ax中的内容
        !  存入 ds:sectors 内存单元，而 mov cs:[sectors], ax 强制以
        !  cs 作为段地址寄存器，因此是将 ax 的内容存入 cs:sectors 内存
        !  单元，一般来说 cs 与 ds 的值是不同的，如果 cs 和 ds 的值一样，
        !  那两条指令的运行结果会是一样的。（编译后的指令后者比前
        !  者一般长一个字节，多了一个前缀。）
     !结论，seg cs 只是表明紧跟它的下一条语句将使用段超越，因为在编
        !  译后的代码中可以清楚的看出段超越本质上就是加了一个字节
        !  的指令前缀，因此 as86 把它单独作为一条指令来写也是合理的。
        !
        !mov cs:[sectors],ax
 !
 !下面的代码在linux 2.6.x的内核中可能改变。没有查证。网上有关于其的讨论，认为其中含有错误。
 
 seg cs
 mov sectors,cx         !sectors在下面定义，保存每个磁道扇区数
 
 ///////////////////////////////////////////////////////////
 
 mov ax,#INITSEG
 mov es,ax              !INITSEG = 0x90000 恢复 es 值

! Print some inane message 在显示一些信息("Loading system...\n"回车换行。共24个字符)
 !//////////////////////////////////////////////////
 !读取光标位置
 mov ah,#0x03           ! read cursor pos
 xor bh,bh              ! bh = 0，使用 xor 指令将 bh 清 0，但是速度比赋值快
 int 0x10
 !//////////////////////////////////////////////////

 !//////////////////////////////////////////////////
 !利用int 0x10来实现将移动光标，并写字符创
 mov cx,#24         ! 共24个字符
 mov bx,#0x0007     ! page 0, attribute 7 (normal)
 mov bp,#msg1       ! msgl下面定义,指向要显示的字符串
 mov ax,#0x1301     ! write string, move cursor
 int 0x10           ! 写字符串并且移动光标
 !//////////////////////////////////////////////////

! ok, we've written the message, now
! we want to load the system (at 0x10000)
! 现在开始将system模块加载到内存0x10000(64k)处。
 !/////////////////////////////////////////////////
 mov ax,#SYSSEG
 mov es,ax          ! segment of 0x010000，现在es就是存放system的段地址
 !/////////////////////////////////////////////////

 !//////////////////////////////////////////////////
 ! 调用邋read_it来实现读取磁盘上的system模块，其中es为输入参数。
 call read_it
 !//////////////////////////////////////////////////
 !关闭驱动器马达，这样就知道驱动器的状态了。
 call kill_motor
 !/////////////////////////////////////////////////
 
! After that we check which root-device to use. If the device is
! defined (!= 0), nothing is done and the given device is used.
! Otherwise, either /dev/PS0 (2,28) or /dev/at0 (2,8), depending
! on the number of sectors that the BIOS reports currently.
! 此后，我们检查使用哪个根文件系统设备。如果已经指定了设备，就直接使用给定的设备，
! 否则就需要根据bios的报告的每磁道扇区数来确定到底是使用/dev/ps0还是/dev/at0
 ! 上面一行中的两个设备文件的含义 :
 ! 在 linux 中软驱的主设备号是 2，次设备号 = type * 4 + nr,其中 nr 为 0-3 分别
 ! 对应软驱的 abcd；type 是软驱的类型(2->1.2 m 7->1.44 m等)。因为 7*4+0=28，所
 ! 以 /dev/ps0 指的是 1.44 m a驱动器，起设备号是 0x021c，同理/dev/at0(2,8)指的是 1.2  
 ! m a的驱动器，其设备号是 0x0208

 seg cs
 mov ax,root_dev  ! 根设备号
 !////////////////////////////////////////////////////
 ! 使用cmp和jne指令来实现条件转移。在汇编语句中的跳转指令分为有条件跳转和
 ! 无条件跳转,jne可解释为如下:jump not equal
 ! 
 cmp ax,#0
 jne root_defined
 !////////////////////////////////////////////////////
 
 seg cs
 mov bx,sectors     ! 取上面保存的sectors。如果 sectors=15，则说明是
                    ! 1.2 mb的驱动器；如果 sectors=18，则说明是 1.44 mb
                    ! 软驱。因为是可引导的驱动器，所以肯定是a驱。
     
 !////////////////////////////////////////////////////
 ! 如果跳转到root_defined，则使用ax作为参数来传递。
 mov ax,#0x0208     ! /dev/ps0 - 1.2 Mb
 cmp bx,#15         ! 判断每磁道扇区数是否是 15
 je root_defined    ! 如果等于，则ax中就是引导驱动器的设备号
 !///////////////////////////////////////////////////

 !//////////////////////////////////////////////////////
 ! 如果跳转到root_defined，使用ax来作为参数传递。
 mov ax,#0x021c     ! /dev/PS0 - 1.44 Mb
 !/////////////////////////////////////////////////////
 ! 使用cmp和je指令来实现，助记符 je 的含义是 jump equal
 cmp bx,#18
 je root_defined
 !/////////////////////////////////////////////////////

////////////////////////////////////////////////////////
undef_root:         ! 未定义跟设备号，死循环 - 死机
 jmp undef_root
////////////////////////////////////////////////////////

////////////////////////////////////////////////////////
root_defined:
 seg cs
 mov root_dev,ax    ! ax = 0x0208,将检查的设备号保存。
///////////////////////////////////////////////////////

! after that (everyting loaded), we jump to
! the setup-routine loaded directly after
! the bootblock:
! 到此，所有的程序都加在完毕，我们就跳转到被加载在 bootsect 后面的 setup 程序去。 

 jmpi 0,SETUPSEG  ! 跳转到0x9020 : 0000(setup.s的开始处)。
     ! 本程序到此结束。呵呵终于结束了。

! 下面是两个子程序。
! This routine loads the system at address 0x10000, making sure
! no 64kB boundaries are crossed. We try to load it as fast as
! possible, loading whole tracks whenever we can.
!
! in: es - starting address segment (normally 0x1000)
!
! 该子程序将系统模块加载到内存地址0x10000处，并确定没有跨越64kb内存边界，我们试图尽快的
! 进行加载，只要可能，就每次加载整条磁道的数据。
! 输入es : -- 开始内存地址段值 (通常是0x1000)
!
sread: .word 1+SETUPLEN ! sectors read of current track
    ! 定义变量sread，表示当前磁道中以读的扇区数。开始时已经读
    ! 进1扇区的引导扇区,bootsect和setup程序所占的扇区数SETUPLEN.
    !
head: .word 0       ! current head，当前磁头号。
track: .word 0      ! current track，当前磁道号。

read_it:

! 测试输入的段值。必须位于内存地址64kb边界处，否则进入死循环。清bx寄存器，用于表示当前段内
! 存放数据的开始位置。
!
! es = 0x1000
 mov ax,es
 !//////////////////////////////////////////////
 ! test指令，实现将原操作数用于和目的操作数按位"与"运算，但是结果并不放在目的地址。
 ! test指令会影响到 ZF 的标志位。如果"与"的结果为 0，那么 zf = 1。
 test ax,#0x0fff
 !/////////////////////////////////////////////
 
die: jne die        ! es must be at 64kB boundary
                    ! es 的值必须是位于64k地址的边界，否则进入死循环。
 xor bx,bx          ! bx is starting address within segment
                    ! bx 是段内偏移地址。
rp_read:

! 判断是否已经全部读入数据。比较当前所读段是否就是系统数据的末端所处的段(endseg),
!如果不是，跳转到下面的ok1_read标号处继续读取数据。否则退出子程序返回。
!
!
 mov ax,es
 cmp ax,#ENDSEG     ! have we loaded all yet?
 jb ok1_read
 ret
 
ok1_read:
! 计算和验证当前的磁道需要读取的扇区数，放在ax寄存器中。
! 根据当前磁道还未读取的扇区数以及段内数据字节的开始偏
! 移量，计算如果全部读取这些未读扇区，所读总字节数是否
! 会超过64kb段长度限制。若会超过，则根据此次最多能读入
! 的字节数(64kb - 段内偏移量)，反算出此次需要读取的扇区数。
!
 seg cs
 mov ax,sectors     ! 取出每个磁道扇区数
 sub ax,sread       ! 减去当前磁道中已经读取的扇区数
 mov cx,ax          ! cx = ax = 当前磁道未读的扇区数
 shl cx,#9          ! cx = cx * 512
 add cx,bx          ! cx = cx + 段内当前的偏移量 
                    !  = 此次读操作后，段内共读入的字节数。
                    ! cf 是进位标志，就是说当执行一个加法或减
                    ! 法时，最高位产生进位或借位时，cf 就为 1，否则为 0．
                    ! add 它的功能是将源操作数与目标操作数相加，
                    ! 结果保存在目标操作数中，并根据结果置标志位．
                    ! 例如：
                    ! mov dl，12h 将 12h 放到数据寄存器低 8 位中，即 dl
                    ! add dl，34h 将 34h 和 12h 相加，结果保存在 dl 中，运行后 dl 为 46h
                    ! 他们相加后最高位没有进位，所以 cf ＝ 0，它们是这样相加的
                    ! 12h 对应的二进制　　　０００１００１０
                    ! 34h 对应的二进制　＋　００１１０１００
                    !         　　　　　　　－－－－－－－－－－
                    !　　　　　　　　       ０１０００１１０
                    ! 最高位是第 8 位，0 + 0 没有进位，所以 cf ＝ 0

 jnc ok2_read       ! 如果没有超过64kb字节，则跳转到ok2_read
                    ! 进位时转移 jnc, cf = 0 时跳转。
 je ok2_read 
 xor ax,ax          ! 若加上此次将读磁道上所未读扇区时会超过64kb
 sub ax,bx          ! 那么计算此时最多能读入的字节数64kb - 段内读偏移量
 shr ax,#9          ! 再转换成需要读取的扇区数。
 
ok2_read:
 call read_track
 mov cx,ax          ! cx = 该次操作已读取的扇区数
 add ax,sread       ! 当前磁道上已经读取的扇区数。
 
 seg cs
 cmp ax,sectors     ! 如果当前磁道上还有扇区未读，则跳转到ok3_read
 jne ok3_read
 
 !读该磁道的下一个磁头面上的数据。如果已经完成，则去读下一个磁道。
 mov ax,#1
 sub ax,head        ! 判断当前的磁头号
 
 jne ok4_read       ! 如果是 0 磁头，则再去读 1 磁头面上的数据。
 inc track          ! 否则去读取下一个磁道。
 
ok4_read:
 mov head,ax        ! 保存当前磁道已读扇区数
 xor ax,ax          ! 清空前磁道已读扇区数
 
ok3_read:
 mov sread,ax       ! 保存当前磁道已读扇区数。
 shl cx,#9          ! 上次已读扇区数 * 512 字节
 add bx,cx          ! 调整当前段内数据开始位置
 
 jnc rp_read        ! 如果小于64kb边界值，则跳转到邋 rp_read 处，继续

 ! 读取数据。否则调整当前段，为下一个段数据做准备。
 ///////////////////////////////////////////////////
 ! 将段基址调整为指向下一个 64 kb 段内存。
 mov ax,es
 add ax,#0x1000
 mov es,ax
 ///////////////////////////////////////////////////
 xor bx,bx          ! 清段内数据开始偏移量
 //////////////////////////////////////////////////

 jmp rp_read

read_track:
! 读取当前磁道上制定开始的扇区和需要读取的扇区数的数据到es:bx处。
! al - 需要读取的扇区数
! es : bx - 缓冲区的位置
!
 !/////////////////////////////////////////////////
 ! 信息保护
 push ax
 push bx
 push cx
 push dx
 !/////////////////////////////////////////////////

 !////////////////////////////////////////////////
 ! 调用中断前的准备工作
 mov dx,track       ! 当前的磁道号
 mov cx,sread       ! 去当前磁道上已读的扇区数
 inc cx             ! cl = 开始读扇区
 mov ch,dl          ! ch = 当前磁道号
 mov dx,head
 mov dh,dl
 mov dl,#0
 and dx,#0x0100
 mov ah,#2
 int 0x13
 !//////////////////////////////////////////////////
 
 jc bad_rt          ! 如果出错的话，跳转到bad_rt
                    ! 否则执行下面的代码，回复现场
 pop dx
 pop cx
 pop bx
 pop ax
 ret
! 执行驱动器的复位操作，在跳转到read_track处重试

bad_rt: mov ax,#0
 mov dx,#0
 int 0x13

 ! 回复现场
 pop dx
 pop cx
 pop bx
 pop ax

 ! 重新再读
 jmp read_track

/*
 * This procedure turns off the floppy drive motor, so
 * that we enter the kernel in a known state, and
 * don't have to worry about it later.
 */
 ! 这个子程序关闭软驱的马达，这样我们进入内核之后它处于已知的状态，所以以后也就
 ! 无需担心了。

kill_motor:
 push dx
 mov dx,#0x3f2      ! 软驱控制卡的驱动端口，只写
 mov al,#0          ! 关闭马达
 outb               ! 将al中的内容传输到dx指定的端口上去
 pop dx
 ret

sectors:            ! 存放的是当前启动软盘每磁道的扇区数
 .word 0

msg1:
 .byte 13,10
 .ascii "Loading system ..."
 .byte 13,10,13,10

.org 508            ! 标示下面的语句从地址508开始，所以邋root_dev
                    ! 在启动扇区的第508开始的2个字节中。
root_dev:           ! 这里存放的是根文件系统所在的设备号，
                    ! 在init/main.c中会使用。
 .word ROOT_DEV
boot_flag:          ! 硬盘的有效标示
 .word 0xAA55

.text
endtext:
.data
enddata:
.bss
endbss: