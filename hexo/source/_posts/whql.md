---
title: win10驱动通过微软whql认证经验
date: 2018-3-16 19:33:32
tags: [whql,驱动，windows]
categories: 杂谈
---
## whql认证是什么
whql(Windows Hardware Quality Labs)认证是微软针对第三方的驱动程序进行的一系列测试，旨在确保驱动程序的兼容性。windows 10 1607以后版本的操作系统版本安装的驱动程序都需要先通过whql认证。

## 注册公司开发者账号
在注册微软开发者账号前，首先确保先拥有一个EV代码签名的证书。这个证书需要向微软授信的机构购买。
网上的介绍都是去https://sysdev.microsoft.com 注册开发者，并进行HLK测试，实际上现在最新的开发者中心已经是这里了:[https://developer.microsoft.com/](https://developer.microsoft.com/)。注册过程不再赘述。<!--more-->

注册完账号后，微软会对账户信息进行审核，审核的方式是微软会在网页上提供一个bin文件，需要我们下载下来对其添加EV代码的数字签名，上传给微软验证。只有数字证书里边的公司名与我们注册的开发者账号能够对应得上的话，才能注册成功使用账号。

## 准备测试设备
至少需要两个系统（**必须为英文操作系统**）：

- **测试服务器** 一个windows server版本的系统，推荐使用windows server 2012 ,可以是虚拟机。（需要注意的是远程会话的时候可能读不到UKEY里的EV数字证书，需要直接接显示器操作，我因为证书找不到的问题浪费了不少的时间）。
- **测试系统** 需要windows 10 版本的操作系统，不能是任何的虚拟机，必须是`物理机`。并且安装好要测试的驱动程序（1607以后的windows 10 可以打开测试模式安装驱动）。

另外这两个系统需要加入在一个内网并且加入同一个工作组。如果不在同一网段的话，可能安装完HLK client后连接不上HLk server。当时我的环境是公司的两个子网(192.168.1.*,192.168.2.*)虽然互通，但是就是连不上server端。加入了同一网段后，如果未把测试服务器和测试系统加入同一工作组，则会导致HLK测试的时候找不到测试的项。

## 安装测试服务器
 Windows Hardware Lab Kit (Windows HLK) 是一套进行whql认证的测试框架。HLK套件仅用于windows 10，如果要测试windows 10 之前的操作系统，需要使用HCK套件(Hardware Certification Kit)。
HCK安装包的下载地址:[https://docs.microsoft.com/en-us/windows-hardware/test/hlk/windows-hardware-lab-kit](https://docs.microsoft.com/en-us/windows-hardware/test/hlk/windows-hardware-lab-kit)。安装完选择Controller + Studio 一路点击Next即可完成测试服务器的安装：

![setup](http://bos.ilovecpp.com/whql/setup.jpg)

## 安装测试系统
测试系统的安装不需要额外的去下载安装包了，应该从安装完成的服务端获取。地址为：
> \\\\\<ControllerName>\HLKInstall\Client\Setup.cmd

例如我们的服务器地址是192.168.2.239：
![setup](http://bos.ilovecpp.com/whql/clientsetup.jpg)

双击setup.cmd，即可出现安装界面： 

![setup](http://bos.ilovecpp.com/whql/clientsetup2.jpg) 

也是一路点击next即可完成安装。

安装完HLK client之后，去服务端打开HLK studio，便可以在默认连接池中找到我们刚刚成功安装的HLK client

![setup](http://bos.ilovecpp.com/whql/pool.jpg) 

HLK的测试环境到此搭建完成。

## 开始测试
首先需要新建一个计算机池（HLK控制器会把测试的任务，分配到你选择的计算机池里边），然后将默认的计算机池中的计算机拖动至我们新建的计算机池中，然后右键计算机池中的计算机，可以改变其状态，当计算机的状态为Ready状态的时候，即表示当前的计算机可以开始测试任务了。

配置好计算机池后，我们就可以新建测试项目了：

![setup](http://bos.ilovecpp.com/whql/start.jpg) 

新建完成后选择项目，然后点击Selection，到这里可以选择测项，由于我们的驱动程序是一个文件系统，选择下图红圈中的Software device，选到对应的驱动程序，打上勾即可：

![setup](http://bos.ilovecpp.com/whql/selection.jpg) 

下面切换到Tests选项，下图是测项旁边可能会出现的几种标志的意思，比如有个人形的logo代表测试的时候需要交互：

![setup](http://bos.ilovecpp.com/whql/state.png) 

给全部的测项打上勾，点击Run Selected，此时测试就开始了。

![setup](http://bos.ilovecpp.com/whql/test.png) 

测试的过程中测试系统会重启，等重启完成后，如果驱动程序需要手动启动的话，就先启动我们的驱动程序，驱动程序启动后就不需要再操作测试系统了，等待测试完成即可。当测试结果出现错误的时候，首先确保测试系统为英文操作系统。

## 测试结果打包
如果一切顺利的话，所有的测项都通过了，就可以对测试的结果打包，提交给微软审核了。打包需要的几个材料分别是：

![setup](http://bos.ilovecpp.com/whql/hlkx.jpg) 

蓝色的项目中不需要我们手动添加了，我们需要提供EV代码签过名的驱动程序以及对应的inf文件，还有对应的pdb符号文件。点击Create Package ，

![setup](http://bos.ilovecpp.com/whql/package.jpg)

这时候会弹出一个签名的提示，根据情况选择2或3即可，未签名的hlkx文件是无法提交给微软审核的。等待打包完成会生成一个hlkx文件，这个就是需要提交给微软审核测试包了，具体过程不赘述了，非常简单。通常耐心等待20分钟即可完成审核，获得微软的数字签名（所谓的微软徽标认证）。


