---
title: 对知乎问题'listen(2)系统调用的backlog参数无效？'的一次实验
date: 2018-06-26 22:40:13
tags: [linux,network]
categories: network
---

原问题的地址:[listen(2)系统调用的backlog参数无效？](https://www.zhihu.com/question/57337887)。几个回答的争议也比较大。

关于这个参数man page是这么描述的：

> The backlog argument defines the maximum  length  to  which the queue of pending connections for sockfd may grow.  If a connection request arrives when  the  queue  is  full,  the client  may receive an error with an indication of ECONNREFUSED or, if the underlying protocol  supports  retransmission,  the request may be ignored so that a later reattempt      at connection succeeds.

要么是手册错了，要么就是提问者的测试的方式有问题。很可惜提问者已经把Github上测试的代码删除了，当我看到这个问题点进去的时候已经404了，无从分析了。于是我在我的服务器上展开了一次测试，我的系统版本是"4.16.3-301.fc28.x86_64"。另外本次实验listen(2)是用于TCP的，未测试作用于其他域的情况。<!--more-->

# listen 语义

listen将一个socket标记为被动(passive)。成功返回后这个socket就可以接受客户端的主动(active)连接了。然后可以对这个socket进行accept操作，当有客户端来连接时，accept会返回一个对等的socket与之进行通信。但是来自客户端的的连接是无法控制的，可能在accept之前，就有客户端发起了连接：

![listen](https://baixiangcpp.oss-cn-shanghai.aliyuncs.com/blog/listen-backlog/listen.png)

内核必须将这些请求维护起来，等后续到来的accept处理。backlog限制了这个维护连接队列的长度。如果队列里连接超过了backlog限制，那么客户端的connect()会阻塞，直到服务端accept成功，将连接从队列中清除。

# 用python写测试代码

python中socket.listen()的参数和C语言一样都包含backlog参数([https://docs.python.org/3/library/socket.html#socket.socket.listen](https://docs.python.org/3/library/socket.html#socket.socket.listen))，因此可以选用python作为测试语言。为了有足够的时间给客户端连接，我在listen和accpet之间，加了一分钟的睡眠:

```python
#listen.py
import socket
import time

s = socket.socket()
s.bind(("192.168.10.188",1234))
s.listen(5)
time.sleep(10)

while True:
    c = s.accept()
    s.close()
```

客户端也是python写的脚本,放在本地windows上跑:

```python
#client.py
import socket
for x in range(100):
    s = socket.socket()
    try:
        s.connect(("192.168.10.188",1234))
    except:
        pass

```

# 结果分析

在分析结果之前，先看connect()函数干了什么。connect()是客户端对服务端发起连接的函数，对于一个TCP socket 来讲，发起连接需要“3次握手”，也就是下图TCP状态转换图的右上方:

![connect](https://baixiangcpp.oss-cn-shanghai.aliyuncs.com/blog/listen-backlog/connect.png)

服务端运行listen.py后,backlog限制了只维护5条连接。此时在Windows上打开wireshark，再运行client.py抓到了这样的包:

![wireshark](https://baixiangcpp.oss-cn-shanghai.aliyuncs.com/blog/listen-backlog/wireshark.png)

前面成功建立了几次TCP连接，随后的SYN包一直在重传，也就是说服务端开始丢弃客户端来自客户端的SYN包。

可以通过wireshark统计在SYN包被重传之前成功建立了几次TCP，选中wirekshark筛选出的第一个SYN包，选择follow 选择tcp stream，然后可以看到:

![fllow](https://baixiangcpp.oss-cn-shanghai.aliyuncs.com/blog/listen-backlog/fllow.png)

再依次将filter中"tcp.stream eq 3"序号依次递增，直到出现:

![retran](https://baixiangcpp.oss-cn-shanghai.aliyuncs.com/blog/listen-backlog/timeout.png)

此时tcp.stream eq 9，也就是stream 3-8都是成功的TCP连接，也就是总共建立了6条TCP连接。

显然，backlog是发挥了作用的，但是队列的最大值不是backlog，而是backlog+1。将backlog调整为其他的值，重复试验，依然满足。

另外man page上还提到一句,当需要设置的backlog超过系统限制时，需要调整/proc/sys/net/core/somaxconn:

> If  the  backlog  argument  is greater than the value in /proc/sys/net/core/somaxconn, then it is silently truncated to that value; the default value in this file is 128.  In kernels before 2.4.25, this limit was a hard coded value, SOMAXCONN, with the value 128.

# 总结

网上得来终觉浅，绝知此事要躬行。对于网上的知识、观点如果违反了自己的认知，应当尽力自己求证，别急着否定自己，哪怕对方是行业的大V。