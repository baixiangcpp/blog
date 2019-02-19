---
title: 抽丝剥茧libevent——前言
date: 2018-4-14 23:40:35
tags: [linux,libevent,网络]
categories: libevent
---

网上已经流传了各种版本的libevent源码剖析了，今天再开这个系列的剖析，似乎有点凑热闹的意思了。为了对得起标题里的"抽丝剥茧"，我打算深入libevent的每一处细节，从最根本处分析libevent是如何工作的。

由于libevent是跨平台的网络库，后端的IO复用模型会因所在平台的不同而有所差异，但是原理大致相当，我选择的是最常用的linux平台。

目前心里边有一个大纲：先从libevent通用的一些编程技法讲起，如果是第一次阅读开源项目，难免会对一些常见的C语言编程技巧感到陌生（例如C语言里实现多态）。然后升入介绍epoll的用法 ，再通过实现一个Echo服务器介绍Reactor设计模式，到这里差不多能够明白libevent工作流是怎么回事了，这之后再从libevent的数据结构(struct event,struct event_base)剖析过来，一点点深入细节，抽丝剥茧。最后是libevent的高级功能以及应用。<!--more-->章节安排大概如下：

+ 前言
+ libevent的通用编程技法
+ epoll接口介绍
+ Reactor设计模式
+ event数据结构
+ event_base结构
+ libevent事件循环
+ 统一事件源
+ EventBuffer
+ 线程安全
+ 应用

内容看似比较多，其实已经是非常精简了。libevent是性能、稳定性都非常出色的网络库，即使多花一点时间研究它，也是一件非常值得的事情，最好能够深入学习其中每一行的代码，体会其中每一处细节的精妙。

# 关于libevent

关于libevent的介绍，在这里就不浪费笔墨了。[http://libevent.org/](http://libevent.org/)写的很详细。此外libevent各版本的特性变化的可以参阅[https://raw.githubusercontent.com/libevent/libevent/patches-2.0/whatsnew-2.0.txt](https://raw.githubusercontent.com/libevent/libevent/patches-2.0/whatsnew-2.0.txt)和[https://raw.githubusercontent.com/libevent/libevent/master/whatsnew-2.1.txt](https://raw.githubusercontent.com/libevent/libevent/master/whatsnew-2.1.txt)。

# 安装libevent

2.1.8版本的libevent源码地址可以在[https://github.com/libevent/libevent/releases/download/release-2.1.8-stable/libevent-2.1.8-stable.tar.gz](https://github.com/libevent/libevent/releases/download/release-2.1.8-stable/libevent-2.1.8-stable.tar.gz)获取到。

编译安装也比较容易，直接依次执行下面3条命令即可:

```bash
./configure
make -j 8
sudo make install
```

如需编译debug版本，仅需要在configure的时候加上CFLAGS:

> $ CFLAGS=-DUSE_DEBUG ./configure [...]

要检测libevent是否正确安装，可以使用源码包里边的helloworld程序进行测试，路径是/libevent-2.1.8-stable/sample/hello-world，运行后另开一个终端，netcat一下本机的9995端口，如果能收到hello world消息，则表示libevent已经安装完成:

```bash
[eric@localhost ~]$ nc 127.0.0.1 9995
Hello, World!
```

# 使用libevent

libevent的一些结构体、函数申明，基本都包含event.h头文件里边了，源码里边包含需要带上它所处的目录event2: `#include <event2/event.h>`,另外编译的时候别忘了加上`-levent`链接libevent的动态库。
这里我写了一个基于标准输入的echo程序:

```C
#include <event2/event.h>
#define BUF_SIZE 1024

void onError(const char *reason)
{
    perror(reason);
    exit(EXIT_FAILURE);
}

void read_cb(int fd,short events,void* arg)
{
    char buf[BUF_SIZE] = {0};
    int ret = read(fd,buf,sizeof(buf)-1);
    if(ret < 0 )
        onError("read()");
    buf[ret] = 0;
    printf("What you type is : %s \n",buf);
}

int main()
{
    struct event_base* base = event_base_new();
    if(!base)
        onError("event_base_new()");
    struct event* ev = event_new(base,STDIN_FILENO,EV_READ | EV_PERSIST ,read_cb,NULL);
    if(!ev)
        onError("event_new()");

    event_add(ev,NULL);
    event_base_dispatch(base);

    event_free(ev);
    event_base_free(base);
}
```

功能很简单，在终端上运行后，每次输入一串字符，都原样回显出来（read_cb函数的功能）。

```bash
[eric@localhost demo]$ gcc demo.c -o main -levent
[eric@localhost demo]$ ./main
hello libevent
What you type is : hello libevent

i'am baixiangcpp
What you type is : i'am baixiangcpp
```

这段程序的功能现在我们已经知道了，至于每一行是如何运作的，暂且不提，后边再来剖析。观察到这样一个现象，我们的代码里其实是没有主动地调用`read_cb`函数，但是每次往标准输入里键入一行字符串后，read_cb函数总是能够得到执行。你并没有看错，其实，read_cb函数有一个专业术语叫做"回调函数"(callback)，和普通函数不同的是，这里我们不需要主动掉用它，在必要的时候它也能得到执行。在某些天生就是事件驱动编程的语言(比如JavaScript)来说，回调函数是一个很基础的概念，但是对于接触C语言不久的同学来说，可能就是一个比较新鲜的玩意儿了。如果不是太理解回调函数的概念，可以戳这里[https://www.zhihu.com/question/19801131](https://www.zhihu.com/question/19801131)花十分钟了解一下先。

我们的这个demo里，第25行代码的意思，就是将read_cb函数注册到libevent上，它告诉libevent:在`STDIN_FILENO`上如果发生了读事件，你帮我调用read_cb函数，这个过程我们称之为回调。值得一提的是，这里的`STDIN_FILENO`可以替换为任何的文件、设备、Socket，甚至是信号值,当然这是后话了。

这里仅仅简单的演示一下libevent如何使用。至于read_cb这个函数，是如何被libevent在正确的时机回调的呢？其实整个libevent本身就是一个Reactor。后面的章节会详细介绍Reactor设计模式。
