---
title: 在windows下编译libssh2
date: 2017-9-24 16:33:32
tags: [ssh,openssl]
categories: SSH2
---
前两个星期的时候对一条悲伤的新闻印象比较深刻，Google Chrome宣布将FTP站点标记为不安全。由于FTP具有的致命的缺陷：密码和文件内容都使用明文传输。估计再苟延残喘几年，就快成互联网的化石了。目前FTP的替代协议用的最多的就是SFTP了。
STP(SSH File Transfer Protocol)是一款基于SSH协议的文件传输协议。SSH保证了其数据在传输的过程中安全不被窃听。大学的时候实现过一个简单的FTP的服务端程序，今天正好有空，打算学习一下SFTP。SFTP在服务端并没有单独的守护进程，和SSH都是使用的sshd。因此我打算在windows上编译一下libssh2的库(早期的ssh1存在一些安全性的漏洞)，看一下自带的DEMO程序 。libssh2在Github上只有200多个star，关于它怎么编译的中文内容不是很多，于是我记录下来编译的过程。<!--more-->
## libssh2依赖的组件
编译libssh2之前需要选择一个后端使用的密码库，根据[libssh2官网](https://www.libssh2.org/)介绍它，提供了四种选择OpenSSL, libgcrypt, mbedTLS or WinCNG (native since Windows Vista)，使用其中的任何一个都可以。这里我选用的是OpenSSL。OpenSSL在Github上拥有5000多个Star，文档相对来说详细很多，很容易编译。
另外一个依赖就是zlib了，当然libssh2也提供了关闭zlib的选项，后面会提到。但是网络带宽本身就是很宝贵的资源，传输的时候还是压缩一下比较合适。强烈不建议关闭这个选项。
这两个库在网上都能找到二进制的内容,openssl的安装包[http://slproweb.com/products/Win32OpenSSL.html](http://slproweb.com/products/Win32OpenSSL.html):
![openssl](http://bos.ilovecpp.com/build-libssh2/Win32OpenSSL.png)
zlib的库就更多了，即使不是程序员都能轻易找到。关于这个两个库的编译也比较简单，就不记录了。
## 编译libssh2
官方也提供了CMake，NMake的方式进行构建项目，这里我使用的是CMakeake，因为我对CMake相对熟悉一点。官方在[Github](https://github.com/libssh2/libssh2/blob/master/docs/INSTALL_CMAKE)上也对CMake Configure的一些选项进行了说明,其中最主要的有这几个选项：
```
 * `BUILD_SHARED_LIBS=OFF`

    Determines whether libssh2 is built as a static library or as a
    shared library (.dll/.so).  Can be `ON` or `OFF`.

 * `CRYPTO_BACKEND=`

    Chooses a specific cryptography library to use for cryptographic
    operations.  Can be `OpenSSL` (https://www.openssl.org),
    `Libgcrypt` (https://www.gnupg.org/), `WinCNG` (Windows Vista+),
    `mbedTLS` (https://tls.mbed.org/) or blank to use any library available.

    CMake will attempt to locate the libraries automatically.  See [2]
    for more information.

 * `ENABLE_ZLIB_COMPRESSION=OFF`

    Will use zlib (http://www.zlib.org) for payload compression.  Can
    be `ON` or `OFF`.
```
BUILD_SHARED_LIBS标记的是编译一个静态库还是动态库，由于我是用的是windows的环境，这里使用ON打开，CRYPTO_BACKEND指定的是后端使用的密码库，这里我选择的是OpenSSL，ENABLE_ZLIB_COMPRESSION选项标记了是否使用zlib进行压缩，使用ON打开即可。最后使用cmake的变量CMAKE_INSTALL_PREFIX指定要安装的目录。
到现在为止，执行cmake还不能成功Configure项目：
![cmake-error](http://bos.ilovecpp.com/build-libssh2/cmake-error.png)
主要是找不到zlib的头文件以及lib文件，而openssl的头文件和lib文件却被发现了（cmake中的脚本中方使用find_path，find_library两个函数找到的），手动提供他们的路径(`拷贝windows的路径的时候，要注意把路径中反斜杠改成斜杠/，使用反斜杠\一般都会报错Invalid character escape '\U'.比较难以察觉。`)即可，需要使用这两个变量：
```
ZLIB_LIBRARY //zlib.lib完整路径
ZLIB_INCLUDE_DIR  //.h文件所在的目录
```
现在将cmake Configure的命令修改为：
```
cmake -DENABLE_ZLIB_COMPRESSION=ON -DCRYPTO_BACKEND=OpenSSL -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_PREFIX=./dll -DZLIB_LIBRARY=C:/Users/eric/Desktop/code/zlib/zlib.lib -DZLIB_INCLUDE_DIR=C:/Users/eric/Desktop/code/zlib --build .
```
稍等半分钟，这时候已经能够生成.sln结尾的解决方案文件（我是用的是VS2015，如果采用的是其他的编译环境则不一定是这个）。执行`cmake --build . --target install` 或者用vs打开解决方案都能编译libssh2了。
![cmake-error](http://bos.ilovecpp.com/build-libssh2/success.png)
直接使用visual studio编译，全部生成成功。到此编译完成。
