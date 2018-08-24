---
title: seafile核心原理——部署和编译
date: 2018-6-25 23:40:35
tags: [linux,seafile,网络]
categories: seafile
---

Seafile是一款非常优秀的跨平台的国产开源企业云存储软件,Github上的仓库已经拥有了超过6000的star。由于工作的原因，学习了一段时间的seafile，这里将我的一些心得记录下来，但愿帮助后来者少走一点弯路。
Seafile功能强大，组件丰富，社区版本可以在其官网下载到，[https://www.seafile.com/download/](https://www.seafile.com/download/)。服务端同时支持Linux和Windows，文档也很详细，按照[https://manual-cn.seafile.com/](https://manual-cn.seafile.com/)部署起来并不复杂。
为了学习其原理，首先我们得拥有编译整个项目的能力，官方也提供了各种版本的编译文档：

> Client
> - [Linux](https://manual.seafile.com/build_seafile/linux.html)
> - [Max OS X](https://manual.seafile.com/build_seafile/osx.html)
> 
> Server
> - [Build Seafile server](https://manual.seafile.com/build_seafile/server.html)

但是并没有提供Windows版本客户端的编译方案。我根据官方提供的Linux客户端编译方案，写了一个Makefile可以同时编译出Linux和Windows两个平台的客户端。<!--more-->

## 组件依赖

Seafile功能复杂，依赖的组件自然也不会少，Linux版本的客户端大概需要的组件有：

- autoconf/automake/libtool
- libevent-dev ( 2.0 or later )
- libcurl4-openssl-dev (1.0.0 or later)
- libgtk2.0-dev ( 2.24 or later)
- uuid-dev
- intltool (0.40 or later)
- libsqlite3-dev (3.7 or later)
- valac (only needed if you build from git repo)
- libjansson-dev
- qtchooser
- qtbase5-dev
- libqt5webkit5-dev
- qttools5-dev
- qttools5-dev-tools
- valac
- cmake
- python-simplejson (for seaf-cli)
- libssl-dev

由于Windows下对开发不是很友好，缺少好用的包管理器，要把这些依赖装上也不是一件容易的事情。即使前方百计安装上了，要想做到一键编译，也是一件几乎不太可能的事情。写这篇文章的时候，我搜索了一下，果然有网友[用windows编译](https://blog.csdn.net/caokunchao/article/details/81233884)了，实在是太繁琐。没有做过的Windows开发的同学，可能对照着这篇博客，都没法顺利编译出客户端。

为了方便初学者，我想把Windows客户端的编译，拿在Linux上来做，并且只需要一个命令就能把所有的依赖、seafile组件统统编译好。

## 交叉编译概念

交叉编译就是在一个平台上生成另一个平台上的可执行代码的一项技术。这里有两个概念：

- host (宿主机) : 编译程序的平台
- target (目标机) ：运行程序的平台

我们需要寻找一款交叉编译器，它的host是linux，target是windows。MinGW就是一款符合要求的交叉编译器。通常大家都是在Windows下使用MinGW，今天我们要使用的是它的交叉编译的版本，具体可以点击[http://www.mingw.org/wiki/LinuxCrossMinGW](http://www.mingw.org/wiki/LinuxCrossMinGW)了解，这里不浪费篇幅了，如果有不懂的可以给我留言。

MinGW也是GNU的项目，基本上所有的GNU工具链都有对应的MinGW版本。MinGW交叉编译环境搭建也非常简单，常见的Linux上的包管理器yum、apt、dnf等都有提供MinGW rpm包。
比如我要在CentOS上搭建Qt的MinGW交叉编译环境，仅需要执行：

```shell
sudo yum install mingw32-qt5-qtbase-devel
```

然后对应的mingw32-qt5-qtbase-devel对应依赖，包括：

```shell
---> Package mingw32-qt5-qtbase.noarch 0:5.6.0-3.el7 will be installed
--> Processing Dependency: mingw32-qt5-qmake = 5.6.0-3.el7
--> Processing Dependency: mingw32-filesystem >= 95
--> Processing Dependency: mingw32(zlib1.dll)
--> Processing Dependency: mingw32(ws2_32.dll)
--> Processing Dependency: mingw32(winmm.dll)
--> Processing Dependency: mingw32(user32.dll)
--> Processing Dependency: mingw32(shell32.dll)
--> Processing Dependency: mingw32-pkg-config
--> Processing Dependency: mingw32(oleaut32.dll)
--> Processing Dependency: mingw32(ole32.dll)
--> Processing Dependency: mingw32(odbc32.dll)
--> Processing Dependency: mingw32(msvcrt.dll)
--> Processing Dependency: mingw32(mpr.dll)
--> Processing Dependency: mingw32(libstdc++-6.dll)
--> Processing Dependency: mingw32(libsqlite3-0.dll)
--> Processing Dependency: mingw32(libpq.dll)
--> Processing Dependency: mingw32(libpng16-16.dll)
--> Processing Dependency: mingw32(libpcre16-0.dll)
--> Processing Dependency: mingw32(libjpeg-62.dll)
--> Processing Dependency: mingw32(libharfbuzz-0.dll)
--> Processing Dependency: mingw32(libglesv2.dll)
--> Processing Dependency: mingw32(libgcc_s_sjlj-1.dll)

...
```

都会被安装上。默认的安装位置在`/usr/i686-w64-mingw32/sys-root/mingw/bin/`。此时用`i686-w64-mingw32-gcc`或者`i686-w64-mingw32-g++`编译c或c++的源文件就会得到PE格式的windows可执行文件。

举个例子：

```shell
[eric@localhost ~]$ cat 1.c
[eric@localhost ~]$ cat 1.c
#include <windows.h>

int main()
{
    MessageBox(0,"welcom to www.ilovecpp.com ","baixiangcpp",MB_OK);
}
[eric@localhost ~]$ i686-w64-mingw32-gcc 1.c -o hello.exe
[eric@localhost ~]$ ls
1.c  hello.exe

```

将hello.exe下载到windows上，双击执行即可弹出一个MessageBox：

![hello](http://oss.ilovecpp.com/blog/seafile-compile/hello.png)

如果运行时，提示缺少相关的Dll，可以去`/usr/i686-w64-mingw32/sys-root/mingw/bin/`下载到，放置到当前目录或者到环境变量PATH的目录里即可。


## 搭建交叉编译环境

现在我们就可以搭建一个交叉编译的环境了。我建议的Linux发型版本是[fedora 28](https://getfedora.org/)。因为fedora的版本更新比较快，每6个月就会有一个发行版本，因此包管理器[dnf](https://fedoraproject.org/wiki/DNF?rd=Dnf)里软件源版本会比较新。在[rpmfind](https://www.rpmfind.net)上得知，fedora 28 上边的mingw-qt版本已经是5.10了。

![hello](http://oss.ilovecpp.com/blog/seafile-compile/rpm.png)

安装完fedora之后，写一个shell脚本，先将所有的依赖装上,如果你没有使用fedora，将dnf替换成对应的包管理器即可。

```shell
echo "Install dependent library ..."

libs=(sed git mingw32-curl intltool vala libtool automake make cmake \
	mingw32-qt5-qtbase-devel mingw32-qt5-qttools-tools mingw32-pkg-config \
 	unzip libuuid-devel libcurl-devel openssl-devel qt5-qtbase-devel \
	make qt5-qttools-devel doxygen wget sqlite-devel mingw32-qt5-qttools \
	mingw32-qt5-qmake)

sudo dnf install ${libs[@]} -y
```

然后下载并解压，seafile客户端的源码，jansson和libevent也可以使用dnf安装，我为了调试的时候，能显示源码因此我选择了自己编译，如果你不想这样，将其添加到上班的`libs`数组中即可。为了不能科学上网同学的提高下载速度，我将6.2.4的源码放到了我的oss上：

```shell
echo "Download source code ..."

shopt -s expand_aliases

export version=6.2.4
alias wget='wget --content-disposition -nc'
wget http://oss.ilovecpp.com/cdn/libsearpc-3.1-latest.zip
wget http://oss.ilovecpp.com/cdn/seafile-${version}.zip
wget http://oss.ilovecpp.com/cdn/seafile-client-${version}.zip
wget http://oss.ilovecpp.com/cdn/jansson-2.11.tar.gz
wget http://oss.ilovecpp.com/cdn/libevent-2.1.8-stable.tar.gz

echo "Decompress source code ..."

unzip libsearpc-3.1-latest.zip
rm libsearpc-3.1-latest.zip

unzip seafile-${version}.zip
rm seafile-${version}.zip

unzip seafile-client-${version}.zip
rm seafile-client-${version}.zip

tar xf jansson-2.11.tar.gz
rm jansson-2.11.tar.gz

tar xf libevent-2.1.8-stable.tar.gz
rm libevent-2.1.8-stable.tar.gz
```

运行这个脚本，交叉编译的环境就算搞定了。install-seafile-env.sh在我的gist上：[https://gist.github.com/baixiangcpp/7e10afee74e25c0bc738ad2e8d1f3d4a](https://gist.github.com/baixiangcpp/7e10afee74e25c0bc738ad2e8d1f3d4a)。

## 交叉编译和Automake

libsearpc和seafile项目是通过autoconf和automake构建的，当需要交叉编译的时候，需要在configure的时候指定三个选项host,build,和target，[https://www.gnu.org/software/autoconf/manual/autoconf-2.65/autoconf.html](https://www.gnu.org/software/autoconf/manual/autoconf-2.65/autoconf.html):

> --build=build-type  
the type of system on which the package is being configured and compiled.  
--host=host-type  
the type of system on which the package runs. By default it is the same as the build machine. Specifying it enables the cross-compilation mode.  
--target=target-type  
the type of system for which any compiler tools in the package produce code (rarely needed).  

可见`--host`指定的交叉编译的模式。

而在seafile的configure.ac中有这么一段：

```shell
...

# check platform
AC_MSG_CHECKING(for WIN32)
if test "$build_os" = "mingw32" -o "$build_os" = "mingw64"; then
  bwin32=true
  AC_MSG_RESULT(compile in mingw)
else
  AC_MSG_RESULT(no)
fi

AM_CONDITIONAL([WIN32], [test "$bwin32" = "true"])
AM_CONDITIONAL([MACOS], [test "$bmac" = "true"])
AM_CONDITIONAL([LINUX], [test "$blinux" = "true"])

...
```

使用了`build_os`这个变量判断是否是WIN32，其实应该使用`host_os`(见上边的那个[链接](https://www.gnu.org/software/autoconf/manual/autoconf-2.65/autoconf.html)的，Getting the Canonical System Type一节)。因此编译之前我们需要将configure.ac中的`build_os`替换成`host_os`,使用sed命令如下:

```shell
sed -i 's/build_os/host_os/g' configure.ac;
```

## 交叉编译和CMAKE

seafile-client这个项目是基于Qt的，因此seafile团队使用了CMake来构建。CMakeLists.txt文件里并没有包含交叉编译时的一些环境变量，因此我额外添加了一个Toolchain-cross-linux.cmake来定义。

```cmake
SET(CMAKE_SYSTEM_NAME Windows)
ADD_DEFINITIONS(-DWIN32)
set(CMAKE_RC_COMPILER i686-w64-mingw32-windres)
set(CMAKE_C_COMPILER i686-w64-mingw32-gcc)
set(CMAKE_CXX_COMPILER i686-w64-mingw32-g++)
SET(CMAKE_FIND_ROOT_PATH /usr/i686-w64-mingw32/sys-root/mingw)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_VERBOSE_MAKEFILE ON)
```

cmake的时候加上-D指定这个文件即可。内容一目了然，不多赘述了。

## 文件名大小写

seafile 和 seafile-client里有的头文件名大小写没特别注意，导致在Linux上编译会找不到头文件。这里我同样使用sed命令全局替换了，例如：

```shell
sed -i 's/ShlObj.h/shlobj.h/g' src/ui/init-seafile-dialog.cpp;
```

## 几个环境变量

seafile这几个项目的依赖关系是这样的：seafile-client项目依赖seafile，seafile项目依赖libsearpc。举个例子，编译seafile的时候，要让编译器找到libsearpc产生的头文件和动态库。因此我定义了这样几个环境变量，帮助编译器发现他们(`注意Makefile中的条件判断是没有缩进的，我在这里吃了一点苦头:(，不要为了美化代码，将其缩进。` )：

```makefile
ifeq ($(HOST_OS),)
PREFIX = $(shell pwd)/build
export PATH = $(PREFIX)/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/bin
export PKG_CONFIG_PATH = $(PREFIX)/lib/pkgconfig
export C_INCLUDE_PATH = $(PREFIX)/include
export CPLUS_INCLUDE_PATH = $(PREFIX)/include
export PYTHON_DIR =  $(PREFIX)/python
else
HOST = i686-w64-mingw32
BUILD = x86_64-redhat-linux-gnu
TARGET = i686-w64-mingw32
PREFIX = $(shell pwd)/ms-build
OPTION = --host=$(HOST) --build=$(BUILD) --target=$(TARGET)
TOOLCHAIN = -DCMAKE_TOOLCHAIN_FILE=/home/eric/Toolchain-cross-linux.cmake
export PATH = $(PREFIX)/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/bin
export PKG_CONFIG = mingw32-pkg-config
export PKG_CONFIG_PATH = /usr/$(TARGET)/sys-root/mingw/lib/pkgconfig:$(PREFIX)/lib/pkgconfig
export C_INCLUDE_PATH = $(PREFIX)/include:/usr/$(TARGET)/sys-root/mingw/include
export CPLUS_INCLUDE_PATH = $(PREFIX)/include
export PYTHON_DIR =  $(PREFIX)/python
endif
```

其中`HOST_OS`是我在Makefile中定义的一个变量，用来标记是否是交叉编译。如果是交叉编译的时候就去MinGW的目录中去找相关的头文件或者动态库。

## one Makefile two platforms

现在我们就能通过一个Makefile编译出Linux和Windows两个目标平台的seafile客户端了。限于篇幅，完整的Makefile我还是选择贴到了gist上：[https://gist.github.com/baixiangcpp/201aa6f32b14ae89cf70acd143274b7d](https://gist.github.com/baixiangcpp/201aa6f32b14ae89cf70acd143274b7d)。

如果要编译Windows平台的客户端，就保留Makefile中的HOST_OS变量，编译后的可执行文件在ms-build文件夹中。相反如果要编译Linux桌面客户端，就把HOST_OS用'#'注释掉，编译后的可执行文件在build文件夹中。

```makefile
#HOST_OS = MINGW32
```

不出意外，现在就可以编译客户端了。命令如下：

```shell
./install.sh #仅需执行一回
make seafileclient
```

到此，seafile客户端项目所有组件都顺利编译通过了。

## 交叉编译与调试

如果需要调试交叉编译产生的Windows客户端，记得在编译的时候用`CFLAFGS`环境变量指定`-ggdb3`这个选项。在windows上安装上mingw-gdb工具，就可以像在Linux上一样的使用gdb调试客户端程序了。

![hello](http://oss.ilovecpp.com/blog/seafile-compile/gdb.png)

如果你编译遇到了问题，可以给我留言。enjoy!

## 后记
此外，我准备写一些关于seafile核心原理的博客，包含文件系统设计、增量传输技术、同步算法以及客户端的一些内容，欢迎讨论。