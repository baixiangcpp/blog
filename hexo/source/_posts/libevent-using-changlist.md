---
title: 抽丝剥茧libevent——使用changelist减少系统调用
date: 2018-5-10 00:20:15
tags: [linux,libevent,网络]
categories: libevent
---

本来准备将这节的内容直接写到[《抽丝剥茧libevent——初识event》](http://ilovecpp.com/2018/05/01/libevent-event-analyze/)一节，后边发现，越写越多，changlist好像并不是那么容易就可以描述清楚的，于是单开一节专门来讲changelist。

对事件的操作，到最后都会转换为对fd的操作————修改epoll兴趣列表。也就是说每一次event_add/event_del最终都会导致一次epoll_ctl系统调用,但是系统调用的开销很大([系统调用真正的效率瓶颈在哪里？](https://www.zhihu.com/question/32043825))。changelist正是一种能减少epoll_ctl调用的机制。<!--more-->


# changelist 基本原理

`changelist-internal.h`中有一段注释，解释了要使用changelist的原因:

> Sometimes applications will add and delete the same event more than once between calls to dispatch.  Processing these changes immediately is needless, and potentially expensive (especially if we're on a system that makes one syscall per changed event).
> Sometimes we can coalesce multiple changes on the same fd into a single syscall if we know about them in advance. For example, epoll can do an add and a delete at the same time, but only if we have found out about both of them before we tell epoll.
> Sometimes adding an event that we immediately delete can cause unintended consequences: in kqueue,this makes pending events get reported spuriously.

使用changelist后，对事件的修改不会立即作用到epoll上，而是把这些修改保存到一个list上，在作用到epoll之前，这些修改可以抵消，合并。比如说，对于同一个事件，先add再del，虽然什么也没做，如果不使用changelist就会多出2个不必要的系统调用。当然如果这种操作并不多的话，使用changelist反而多了额外的开销(相比系统调用，这种开销微不足道)，libevent将选择权交给了你。

# 使用changlist

要使用changelist机制，只要在创建event_base时，传入`EVENT_BASE_FLAG_EPOLL_USE_CHANGELIST`标志：

```C
struct event_config *cfg = event_config_new();
event_config_set_flag(cfg,EVENT_BASE_FLAG_EPOLL_USE_CHANGELIST);
struct event_base* base = event_base_new_with_config(cfg);
```

这里我写了两份代码，一个未使用chagelist，另一个未使用，都放在了Github上:[https://gist.github.com/baixiangcpp/f2d3feea38c81f50d02f33483587d2f2](https://gist.github.com/baixiangcpp/f2d3feea38c81f50d02f33483587d2f2)和[https://gist.github.com/baixiangcpp/ae836f31e618d002e6611ad0006c5c74](https://gist.github.com/baixiangcpp/ae836f31e618d002e6611ad0006c5c74)。用gdb分别单步调试,最终的函数栈大致是这样的:

```gdb
//不使用changelist
(gdb) bt
#0  0x00007ffff78bbcb0 in epoll_ctl () from /lib64/libc.so.6
#1  0x00007ffff7bad965 in epoll_apply_one_change (ch=ch@entry=0x7fffffffe29c, epollop=<optimized out>, base=<optimized out>) at epoll.c:290
#2  0x00007ffff7bae180 in epoll_nochangelist_add (base=<optimized out>, fd=<optimized out>, old=<optimized out>, events=<optimized out>,p=<optimized out>) at epoll.c:392
#3  0x00007ffff7ba6813 in evmap_io_add_ (base=base@entry=0x6022a0, fd=<optimized out>, ev=ev@entry=0x602710) at evmap.c:330
#4  0x00007ffff7ba1b9e in event_add_nolock_ (ev=ev@entry=0x602710, tv=tv@entry=0x0, tv_is_absolute=tv_is_absolute@entry=0) at event.c:2600
#5  0x00007ffff7ba200e in event_add (ev=0x602710, tv=0x0) at event.c:2445
#6  0x0000000000400991 in main () at helloworld.c:32

//使用changelist
(gdb) bt
#0  event_changelist_add_ (base=0x6022a0, fd=0, old=0, events=2, p=0x6028c0) at evmap.c:857
#1  0x00007ffff7ba5813 in evmap_io_add_ (base=base@entry=0x6022a0, fd=<optimized out>, ev=ev@entry=0x602710) at evmap.c:330
#2  0x00007ffff7ba0b9e in event_add_nolock_ (ev=ev@entry=0x602710, tv=tv@entry=0x0, tv_is_absolute=tv_is_absolute@entry=0) at event.c:2600
#3  0x00007ffff7ba100e in event_add (ev=0x602710, tv=0x0) at event.c:2445
#4  0x0000000000400a62 in main () at helloworld.c:35
```

事实上epoll_nochangelist_add和epoll_nochangelist_del就是对epoll_ctl(EPOLL_CTL_ADD/EPOLL_CTL_DEL)的封装。最终epoll_nochangelist_add会调用epoll_ctl,将事件对应的fd添加加到epoll的兴趣列表里。

使用changelist时，event_changelist_add_把changes加到了changlist里就直接返回了。那么是什么时候回调用epoll_ctl()的呢，给它下个断点:

```gdb
(gdb) bt
#0  0x00007ffff78adcb0 in epoll_ctl () from /lib64/libc.so.6
#1  0x00007ffff7ba7669 in epoll_apply_one_change (base=0x6022a0, epollop=0x602540, ch=0x6028d0) at epoll.c:290
#2  0x00007ffff7ba7a48 in epoll_apply_changes (base=0x6022a0) at epoll.c:367
#3  0x00007ffff7ba7caa in epoll_dispatch (base=0x6022a0, tv=0x0) at epoll.c:457
#4  0x00007ffff7b9663f in event_base_loop (base=0x6022a0, flags=0) at event.c:1947
#5  0x00007ffff7b95fd3 in event_base_dispatch (event_base=0x6022a0) at event.c:1772
#6  0x0000000000400a6e in main () at hello.c:36
```

也就是说，使用changelist时，先将修改保存到changelist上，到下一次event_base_dispatch()中再遍历链表，将修改作用到epoll上。

这个list正是减少系统调用的关键所在，它会将重复的change合并，将互斥的change抵消...

# 用changelist记录event change

先看struct event_changelist的定义:

```C
struct event_changelist {
    struct event_change *changes;
    int n_changes;
    int changes_size;
};

struct event_change {
    evutil_socket_t fd;
    short old_events;
    ev_uint8_t read_change;
    ev_uint8_t write_change;
    ev_uint8_t close_change;
};

/* If set, add the event. */
#define EV_CHANGE_ADD     0x01
/* If set, delete the event.  Exclusive with EV_CHANGE_ADD */
#define EV_CHANGE_DEL     0x02
/* If set, this event refers a signal, not an fd. */
#define EV_CHANGE_SIGNAL  EV_SIGNAL
/* Set for persistent events.  Currently not used. */
#define EV_CHANGE_PERSIST EV_PERSIST
/* Set for adding edge-triggered events. */
#define EV_CHANGE_ET      EV_ET

```

图示直观一点，黄色部分表示event_changelist，绿色部分表示event_change：

![event_changlist1](https://baixiangcpp.oss-cn-shanghai.aliyuncs.com/blog/libevent-changelist/event_changlist.png)

一个fd对应一个struct event_change结构，对该fd的操作，都将体现到对XXXX_change的位操作上。标志位定义，用图表示：

![bit](https://baixiangcpp.oss-cn-shanghai.aliyuncs.com/blog/libevent-changelist/bit.png)

比如要添加监听对一个fd的读事件(或者signal,其实也是读，[Effective epoll](http://www.ilovecpp.com/2019/01/20/effective-epoll/#用epoll处理signal)),只要将这个fd对应event_change的read_change字段的第一位设置为'EV_CHANGE_ADD'。同理要删除fd的读事件，将第二位置为'EV_CHANGE_DEL'即可。

在changelist-internal.h,定义了几个与changelist相关接口函数,先看event_changelist_add_：

```C
int event_changelist_add_(struct event_base *base, evutil_socket_t fd, short old, short events,void *p)
{
    struct event_changelist *changelist = &base->changelist;
    struct event_changelist_fdinfo *fdinfo = p;
    struct event_change *change;

    change = event_changelist_get_or_construct(changelist, fd, old, fdinfo);
    if (!change)
        return -1;

    if (events & (EV_READ|EV_SIGNAL)) {
        change->read_change = EV_CHANGE_ADD |
            (events & (EV_ET|EV_PERSIST|EV_SIGNAL));
    }
    if (events & EV_WRITE) {
        change->write_change = EV_CHANGE_ADD |
            (events & (EV_ET|EV_PERSIST|EV_SIGNAL));
    }
    if (events & EV_CLOSED) {
        change->close_change = EV_CHANGE_ADD |
            (events & (EV_ET|EV_PERSIST|EV_SIGNAL));
    }

    return (0);
}
```

event_changelist_get_or_construct()是根据fdinfo(存在struct evmap_io结构的尾部)选择该fd对应的event_change结构，如果之前还没创建该event_change，则创建一个。根据添加事件的类型，分别将read_change/write_change/close_change的第一位置为EV_CHANGE_ADD，并保留EV_ET、EV_PERSIST、EV_SIGNAL等标志位。

同理event_changelist_del_()用来标记对一个fd事件的删除，如果需要删除将对应event_change的read_change赋值为EV_CHANGE_DEL，其他标志也就没用了，不需要保留。如果对fd取消读事件，但是eventloop中根本没有监听它的读(通过判断old_events即可)，将read_change置为0。write_change/close_change同理。

# 将event_change作用到epoll上

在每一次epoll_wait()之前都会通过epoll_apply_changes遍历当前的changlist所有的event_change,然后通过epoll_apply_one_change再把事件添加到epoll_ctl上：

```C
static int epoll_apply_one_change(struct event_base *base,struct epollop *epollop, const struct event_change *ch)
{
    struct epoll_event epev;
    int op, events = 0;
    int idx;

    idx = EPOLL_OP_TABLE_INDEX(ch);
    op = epoll_op_table[idx].op;
    events = epoll_op_table[idx].events;

    if (!events) {
        EVUTIL_ASSERT(op == 0);
        return 0;
    }

    if ((ch->read_change|ch->write_change) & EV_CHANGE_ET)
        events |= EPOLLET;

    memset(&epev, 0, sizeof(epev));
    epev.data.fd = ch->fd;
    epev.events = events;
    if (epoll_ctl(epollop->epfd, op, ch->fd, &epev) == 0) {
        event_debug((PRINT_CHANGES(op, epev.events, ch, "okay")));
        return 0;
    }

    switch (op) {
    case EPOLL_CTL_MOD:
        if (errno == ENOENT) {
            if (epoll_ctl(epollop->epfd, EPOLL_CTL_ADD, ch->fd, &epev) == -1) {
                event_warn("Epoll MOD(%d) on %d retried as ADD; that failed too",
                    (int)epev.events, ch->fd);
                return -1;
            } else {
                event_debug(("Epoll MOD(%d) on %d retried as ADD; succeeded.",
                    (int)epev.events,
                    ch->fd));
                return 0;
            }
        }
        break;
    case EPOLL_CTL_ADD:
        if (errno == EEXIST) {
            if (epoll_ctl(epollop->epfd, EPOLL_CTL_MOD, ch->fd, &epev) == -1) {
                event_warn("Epoll ADD(%d) on %d retried as MOD; that failed too",
                    (int)epev.events, ch->fd);
                return -1;
            } else {
                event_debug(("Epoll ADD(%d) on %d retried as MOD; succeeded.",
                    (int)epev.events,
                    ch->fd));
                return 0;
            }
        }
        break;
    case EPOLL_CTL_DEL:
        if (errno == ENOENT || errno == EBADF || errno == EPERM) {
            event_debug(("Epoll DEL(%d) on fd %d gave %s: DEL was unnecessary.",
                (int)epev.events,
                ch->fd,
                strerror(errno)));
            return 0;
        }
        break;
    default:
        break;
    }

    event_warn(PRINT_CHANGES(op, epev.events, ch, "failed"));
    return -1;
}
```

EPOLL_OP_TABLE_INDEX()是一个宏运算，将event_change转换为一个正整数型，每一位分别表示:

```C
Bit 0: close change is add
Bit 1: close change is del
Bit 2: read change is add
Bit 3: read change is del
Bit 4: write change is add
Bit 5: write change is del
Bit 6: old events had EV_READ
Bit 7: old events had EV_WRITE
Bit 8: old events had EV_CLOSED
```

总共有2^9共512中组合，epoll_op_table数组是libevent使用python将这512个值分别对应的操作而自动创建的。每一种组合得出的值(EPOLL_OP_TABLE_INDEX())作为index，数组对应的值就是代表它对epoll的操作。举个例子：

![change](https://baixiangcpp.oss-cn-shanghai.aliyuncs.com/blog/libevent-event-mgr/change.png)

这个event_change通过EPOLL_OP_TABLE_INDEX()计算后得到69,然后选择epoll_op_table数组的70个值：

```
/* old=  r, write:  0, read:add, close:add */
{ EPOLLIN|EPOLLRDHUP, EPOLL_CTL_MOD },
```

正符合我们计算的值。然后接下来就会将对应的fd按这个操作，修改到epollfd上 。

然后这个过程可能会出错。举一例子，由于将对事件的修改是发生在两次dispatch之中的，可能前一次dispatch的时候，close掉了之前的fd，又重新打开了。EPOLL_CTL_MOD的操作会失败，将其改为EPOLL_CTL_ADD再试一遍。还有其他几种出错的情况可以参考注释。

# 总结

因为changelist机制对使用着来说是完全透明的，使用changelist也不会增加复杂度。这些大神们为了榨干计算机的性能，也是绞尽脑汁。




