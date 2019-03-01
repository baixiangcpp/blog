---
title: 为什么DHCP要基于UDP协议？
date: 2018-03-01 20:10:33
tags: [network,network]
categories: network
---

如果你是因为看到这个标题而点进来的话，那么可能会让你失望了，因为我还没找到答案。

网上看到一个问题:"使用DHCP获取IP的时候，在事先没有ip的情况下，客户机是怎么和DHCP服务器通信的呢?"第一反应DHCP是链路层的协议，在链路层广播。

![arp](https://baixiangcpp.oss-cn-shanghai.aliyuncs.com/blog/dhcp/arp.png)

如上图，ARP协议就是通过链路层的广播获取目标的MAC地址。要是DHCP也在链路层广播，也说得通:当电脑加入一个新的局域网时，首先通过链路层广播请求获取一个新的ip，DHCP服务器的网卡收到广播，分配ip池中的一个可用ip，通过广播包里的MAC地址将IP下发。似乎也说得通。<!--more-->

理想很丰满，现实很骨感。查了资料才知道DHCP其实是基于UDP的。那么问题还是没有解决，UDP协议在IP层之上。网络通信可以有下层没有上层，不可能有上层而没有下层。IP头中是包含源IP地址的:

![ip](https://baixiangcpp.oss-cn-shanghai.aliyuncs.com/blog/dhcp/ip.png)

要是电脑预先没有IP地址，那么UDP广播包是怎么发出去的呢？还是抓包一探究竟吧。

用wireshark抓DHCP包需要用到两个命令：

```powershell
ipconfig /release
ipconfig /renew
```

release用来释放网卡连接，renew表示重新连接。禁用/启用网卡的方式是无法抓到DHCP的，网卡被禁用的瞬间，wireshark就会停止对该网卡的抓包，直到被重新启用才能重新开始抓包。wireshark的filter无法直接填DHCP(bug?)，但是因为DHCP服务的端口是确定的，通过"udp.port == 67" filrer 也可以筛选出DHCP包。按照这个步骤，成功抓到了DHCP包:

![dhcp](https://baixiangcpp.oss-cn-shanghai.aliyuncs.com/blog/dhcp/dhcp.png)

总共5个包，第一个是释放连接，也就是`ipconfig /release`操作。后面4个包正是DHCP获取IP的流程。为了表述简单，下面将获取IP的机器称为客户端，DHCP服务器简称为服务端。

编号180的包，可以看到源IP地址填的是"0.0.0.0",这正是我们开篇的答案。"0.0.0.0"是一个不可路由(non-routable )的地址。目的IP是"255.255.255.255"同一网段的所有网卡都会收到这个DHCP Discover请求。

编号181的包，是服务端发出来的，它已经收到了客户端发给它的Discover请求，于是通过DHCP Offer下发给它一个IP，目的IP填的就是下发的IP。当服务端这个网络包到达链路层的时候，并不需要通过ARP协议获取客户端的MAC地址(当然，通过ARP也获取不到,这个包发出来的时候，客户端并不知道这个是分配给自己的IP),它们之前在DHCP Discover的时候通信过了，MAC地址已经被它记了下来。

![request](https://baixiangcpp.oss-cn-shanghai.aliyuncs.com/blog/dhcp/request.png)

这是编号182的包的内容，虽然它现在已经有了自己的IP了，可以直接和服务端通信并签约。但是这依旧是一个广播包。因为同网段可能有多个DHCP服务器，客户机通过广播通知所有的DHCP服务器它已经接受了一个租约。包里有它的IP地址，还有与他签约的DHCP服务器的IP等，具体参考上面的插图。当其他DHCP服务器收到了该消息后，它们会收回所有可能已提供给客户的IP地址。然后它们把刚才保留的客户机的IP地址放回到IP池中。

编号183的包是签约的DHCP服务器发给客户端的，表示签约成功，现在可以使用新的IP了。

Offer和ACK是直接发给客户机还是广播，取决于客户端Discover包标志位的设置，比如我换了一台电脑实验，就抓到了这样的包：

![broadcast](https://baixiangcpp.oss-cn-shanghai.aliyuncs.com/blog/dhcp/broadcast.png)

这台机子的Discover设置了Broadcast的标志为1(包366)，随后Offer包就变成了广播包(包372)。

基于以上对DHCP的理解，我以为这些Discover，Offer...等操作，在技术上完全可以到链路层来实现。从而也避免了对"0.0.0.0"地址的使用。RARP协议也是在二层获取三层的IP地址，所以我认为这样设计也不是基于网络模型考虑的。

除此之外,我想不出是基于怎样的考虑。
