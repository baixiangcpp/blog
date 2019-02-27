---
title: 抽丝剥茧libevent——初识event
date: 2018-5-1 23:40:35
tags: [linux,libevent,网络]
categories: libevent
---

从这章起正式进入libevent的源码部分，libevent是事件驱动(event-driven)的网络库，事件是一切操作的基本单元，那么就从event说起。

首先event是一个不透明结构(opaque structure)，对于使用者来说，无需关心它的内部数据结构。所有对event的操作，都需要通过libevent提供的接口,不能自己私自操作其中的数据(不得不感慨一下，指针还是给了程序员太大的自由了)。这样做的好处主要有两个，[通用编程技法](http://www.ilovecpp.com/2018/04/20/lievent-trick/)一章已经提到过了：信息封装和二进制兼容。对于一个动态库来讲，这两个特性尤为重要。<!--more-->

# event概念

关于概念性的内容，libevent官方已经有了非常详细的英文文档说明:[http://www.wangafu.net/~nickm/libevent-book/](http://www.wangafu.net/~nickm/libevent-book/),已经有人这些文档翻译成了中文:[https://aceld.gitbooks.io/libevent/content/](https://aceld.gitbooks.io/libevent/content/)，方便对照着看。

珠玉在前，WHAT和HOW部分我就不再费笔墨赘述了。本系列博客主要是深入源码，探究WHY。

# struct event结构说明

首先来看struct event的定义,这和我们事先的[reactor一节中的事件](http://www.ilovecpp.com/2018/04/26/libevent-reactor/#事件)有神似之处，掌握了那个以后，很容易理解下文中的libevent事件。

```C
struct event {
    //事件对应的回调函数
    struct event_callback ev_evcallback;

    //用来管理超时事件最小堆的index
    union {
        TAILQ_ENTRY(event) ev_next_with_common_timeout;
        int min_heap_idx;
    } ev_timeout_pos;

    //对于I/O事件该值为文件描述符
    //对于超时事件该值为-1
    //对于信号事件该值为信号值
    evutil_socket_t ev_fd;

    //所属的event_base
    struct event_base *ev_base;

    //用来处理信号、I/O事件数据结构
    union {
        /* used for io events */
        struct {
            LIST_ENTRY (event) ev_io_next;
            struct timeval ev_timeout;
        } ev_io;

        /* used by signal events */
        struct {
            LIST_ENTRY (event) ev_signal_next;
            short ev_ncalls;
            /* Allows deletes in callback */
            short *ev_pncalls;
        } ev_signal;
    } ev_;

    //事件类型、标志可能的值是EV_TIMEOUT,EV_READ,EV_WRITE,EV_SIGNAL,EV_PERSIST...等
    short ev_events;

    //回调函数的返回值
    short ev_res;

    //事件的超时时间
    struct timeval ev_timeout;
};
```

# event的生命周期

前面提到的中文翻译的文档里，有一张图完美的诠释了event的生命周期，带箭头实线表示函数调用，实线矩形表示event的状态，虚线矩形表示用来检测事件状态的函数：

![event](https://baixiangcpp.oss-cn-shanghai.aliyuncs.com/blog/libevent-reactor/event.png)

下面就围绕这张图的上半部分，结合源码探究event的前半生。event的下半生将在[抽丝剥茧libevent——事件处理框架](http://www.ilovecpp.com/2018/06/29/libevent-event-base-analyze/)介绍。

# 初始化event

一个指针变量，可以通过event_new()函数，关联一个event。

```C
struct event* event_new(struct event_base *base, evutil_socket_t fd, short events, void (*cb)(evutil_socket_t, short, void *), void *arg)
{
    struct event *ev;
    ev = mm_malloc(sizeof(struct event));
    if (ev == NULL)
        return (NULL);
    if (event_assign(ev, base, fd, events, cb, arg) < 0) {
        mm_free(ev);
        return (NULL);
    }

    return (ev);
}
```

主要做了2个事情：分配内存、初始化结构。

首先通过mm_malloc先从堆上分配`struct event`的空间，为了监听这个事件，要保证这个事件一直在整个事件循环的过程中是存在的，因此只能从堆上分配。

分配内存后的event通过event_assign()根据参数对其各个字段初始化。

如果是要创建超时事件，fd和events的值分别设置为-1和0，libevent用一个宏来表示，超时事件的创建：

```C
#define evtimer_new(b, cb, arg) event_new((b), -1, 0, (cb), (arg))
```

此时新创建的event处于`non-pending`状态，event_assign()函数并未为其设置超时的时间，这个步骤会推迟到event被添加到reactor中的时候。跟着箭头向下，event_add()函数会将`non-pending`的event添加到reactor中，同时为其设置超时时间。

# 监听event

event_add()并不做实际的工作，而是获得锁之后，将任务交给event_add_nolock_函数来完成，关于libevent线程安全的内容暂且不说，后边单独开一篇来讨论。

event_add_nolock_()干的活儿非常多，为了深入理解这里也不会一一展开，同样也需要留到后边剖析(事件管理框架，超时时间管理)，这里仅仅摘出一条主线，省略其他干扰项：

```C
int event_add_nolock_(struct event *ev, const struct timeval *tv,
    int tv_is_absolute)
{
    ...

    if ((ev->ev_events & (EV_READ|EV_WRITE|EV_CLOSED|EV_SIGNAL)) &&
        !(ev->ev_flags & (EVLIST_INSERTED|EVLIST_ACTIVE|EVLIST_ACTIVE_LATER))) {
        if (ev->ev_events & (EV_READ|EV_WRITE|EV_CLOSED))
            res = evmap_io_add_(base, ev->ev_fd, ev);
        else if (ev->ev_events & EV_SIGNAL)
            res = evmap_signal_add_(base, (int)ev->ev_fd, ev);
        if (res != -1)
            event_queue_insert_inserted(base, ev);
        if (res == 1) {
            /* evmap says we need to notify the main thread. */
            notify = 1;
            res = 0;
        }
    }

    ...

    event_queue_insert_timeout(base, ev);

    ...
}
```

提前稍微"剧透"一下,libevent分别利用两个hashmap(暂不考虑windows平台)分别管理I/O事件和信号事件，利用最小堆管理超时事件。event变量正是通过event_add_nolock_()函数被调加到对应的数据结构上(分别是evmap_io_add_、evmap_signal_add_和event_queue_insert_timeout三个函数)。

至此，event的状态就变为了`pending`状态，可以通过event_pending()获取。事件循环开始工作后，event就处于被监听的状态了。

# 取消监听event

libevent同样提供了接口让我们取消监听event，和event_add()类似，event_del()也是讲任务交给event_del_nolock_()来完成。取消监听和监听是逆操作，这在代码里边也有体现,同样地，只摘出了主线:

```C
int event_del_nolock_(struct event *ev, int blocking)
{
    ...

    if (ev->ev_flags & EVLIST_TIMEOUT) {
        event_queue_remove_timeout(base, ev);
    }

    if (ev->ev_flags & EVLIST_ACTIVE)
        event_queue_remove_active(base, event_to_event_callback(ev));
    else if (ev->ev_flags & EVLIST_ACTIVE_LATER)
        event_queue_remove_active_later(base, event_to_event_callback(ev));

    if (ev->ev_flags & EVLIST_INSERTED) {
        event_queue_remove_inserted(base, ev);
        if (ev->ev_events & (EV_READ|EV_WRITE|EV_CLOSED))
            res = evmap_io_del_(base, ev->ev_fd, ev);
        else
            res = evmap_signal_del_(base, (int)ev->ev_fd, ev);
        if (res == 1) {
            /* evmap says we need to notify the main thread. */
            notify = 1;
            res = 0;
        }
    }

    ...
}

```

因为event的回调函数可能在其他线程正在运行着，为了线程安全，`blocking`参数是必要的。

event_del_nolock_()主要做的事情正和event_add_nolock_()相反，它把定时器从超时事件最小堆上移除，然后将其从信号或者I/O的hashmap上移除。额外地，还需要将就绪的回调函数从待处理的回调函数链表上摘除，也就是说如果这个event已经触发，顺利调用了event_del之后，它的回调函数不会被运行。

event的状态会从`pending`回到`non-pending`状态。

# 释放event

和event_new()对应，event_free()先取消监听event，然后释放其内存：

```C
void event_free(struct event *ev)
{
    event_del(ev);

    mm_free(ev);
}
```

虽然简单，但是却很重要，尤其不要忘记释放内存，造成内存泄漏。

# 一次性事件

对于只需要触发一次的事件，libevent2.1提供了一种方案————`event_once`，让使用者不需要手动管理event，并且也保证了事件被触发后，内存会被自动被释放。

原理并不复杂，先看一下它的结构,

```C
struct event_once {
    LIST_ENTRY(event_once) next_once;
    struct event ev;

    void (*cb)(evutil_socket_t, short, void *);
    void *arg;
};
```

并没有event_once_new()之类的函数用于创建event_once，要使用它要到一个新的函数event_base_once,它将event_new 和 event_add两个步骤合成了一个：

```C
int event_base_once(struct event_base *base, evutil_socket_t fd, short events, void (*callback)(evutil_socket_t, short, void *), void *arg, const struct timeval *tv)
{
    ...
    eonce->cb = callback;
    eonce->arg = arg;

    if ((events & (EV_TIMEOUT|EV_SIGNAL|EV_READ|EV_WRITE|EV_CLOSED)) == EV_TIMEOUT) {
        evtimer_assign(&eonce->ev, base, event_once_cb, eonce);

        if (tv == NULL || ! evutil_timerisset(tv)) {
            activate = 1;
        }
    } else if (events & (EV_READ|EV_WRITE|EV_CLOSED)) {
        events &= EV_READ|EV_WRITE|EV_CLOSED;
        event_assign(&eonce->ev, base, fd, events, event_once_cb, eonce);
    } else {
        mm_free(eonce);
        return (-1);
    }

    if (res == 0) {
        if (activate)
            event_active_nolock_(&eonce->ev, EV_TIMEOUT, 1);
        else
            res = event_add_nolock_(&eonce->ev, tv, 0);

        if (res != 0) {
            mm_free(eonce);
            return (res);
        } else {
            LIST_INSERT_HEAD(&base->once_events, eonce, next_once);
        }
    }

    return (0);
}
```

event_base_once的参数也和event_new一样，功能也是一样，不做额外的解释，主要看一下event_once里边的多出来的回调函数用来干了什么事情。

我们用event_once->cb和event->cb分别表示event_once和event里的回调函数。首先函数入口处直接把参数里的callback赋值给了event_once->cb，它用来负责实际的事件回调。然后调用event_assign新建一个event初始化event_once->event的同时，传入了一个`event_once_cb`回调函数。这个函数才是事件发生时会被回调的函数，也是一次性事件的秘密所在:

```C
static void event_once_cb(evutil_socket_t fd, short events, void *arg)
{
    struct event_once *eonce = arg;
    (*eonce->cb)(fd, events, eonce->arg);
    EVBASE_ACQUIRE_LOCK(eonce->ev.ev_base, th_base_lock);
    LIST_REMOVE(eonce, next_once);
    EVBASE_RELEASE_LOCK(eonce->ev.ev_base, th_base_lock);
    event_debug_unassign(&eonce->ev);
    mm_free(eonce);
}
```

event_once_cb这个函数被回调时，会马上调用event_once->cb,然后把他从一次性事件的链表里移除，最后释放掉整个event_once所分配的内存。

要是这个事件不触发，那么他的回调函数就不会被释放，event_once所占用的内存就得不到释放，我们无法获得它的指针对其free。一次性事件链表就是为了解决这个问题的，他是`event_base`里的一个结构

> LIST_HEAD(once_event_list, event_once) once_events;

所有的event_once在释放之前都会保留在这个链表里，除了event_once_cb触发时会被移除，在event_base被释放时，也会将所有once_events里的event_once逐个释放。

```C
static void event_base_free_(struct event_base *base, int run_finalizers)
{
    ...
    while (LIST_FIRST(&base->once_events)) {
        struct event_once *eonce = LIST_FIRST(&base->once_events);
        LIST_REMOVE(eonce, next_once);
        mm_free(eonce);
    }
    ...
}
```

# 总结

"空谈误国，实干兴邦"，写程序也是一样的道理，光看源码远远不够，要深切体会struct event还是多用。用的够多了，回头再看源码，才会有醍醐灌顶之感。