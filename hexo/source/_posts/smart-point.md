---
title: 都9102年了,你居然还在使用原始指针
date: 2019-1-29 19:43:35
tags: [linux,c++,thread-safety]
categories: c++
---

原始指针(raw pointer，为了表述方便，下面提到的‘指针’均指原始指针)是C/C++最强大的工具，它威力无穷，但是稍有不慎，就有引发各种内存问题。智能指针来势汹汹，它利用RAII特性对指针的封装，帮助程序员自动管理内存。其目的是用来代替指针。重载了操作符(operator*,operator->和operator[])，用起来和指针没多大区别。同时也规避了许多指针带来的陷阱，大大减少了程序员犯错的机会。本篇博客我将列举原始指针之罪以及一些不得不使用智能指针的理由。

本文的智能指针([https://en.cppreference.com/book/intro/smart_pointers](https://en.cppreference.com/book/intro/smart_pointers))是指C++11以来的`std::unique_ptr`、`std::shared_ptr`和`std::weak_ptr`,不包括半吊子的`std::auto_ptr`，它谈不上智能二字。<!--more-->

# 原始指针七宗罪

1. 不能通过一个指针判断指向的是单个对象还是一个数组。
2. 当你使用完指针的时候，你不知道应不应该将它释放(delete)。
3. 使用指针时，当你确定要释放一处内存，你不知道如何释放(除了delete之外)。智能指针可以在构造的时候指定custom deleter。
4. 当你确定使用delete释放内存的时候，又不知道使用delete还是delete[]，一旦用错，就是未定义的错误。
5. 你无法确定一个指针是不是空悬指针(dangle)。
6. 忘记释放内存会造成内存泄漏(memory leak)。
7. 重复释放内存会造成重复释放(double delete)。

# 智能指针

初次之外，你还有其他理由不得不使用智能指针。

# 当多线程遇上析构函数

单线程程序中，对象析构是一件很轻松的事情。但是当它遇上多线程时，头疼问题来了，如何保证一个对象正在析构(或者析构以后)，其他的线程不会使用它呢？

```C++
class Foo
{
public:
    Foo ()  :fd_(open_file()) { }

    ~Foo()
    {
        close(fd_);
        fd_ = 0;
    }

    void write()
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if(fd_)
            write(fd_);
    }

    void read()
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if(fd_)
            std::cout << read(fd) << std::endl;
    }

private:
    int fd_;
    std::mutex mutex_;
};

Foo* foo = new Foo;
```

Foo是一个文件读写的class。为了线程安全，read()和write()操作用mutex保护了起来。有两个线程拥有Foo的对象foo，他们分别对foo保存的资源进行读写操作，在mutex的保护下，它们相安无事。一旦要释放foo对象的时候，如果其中一个线程`delete foo`，fd_未被保护，如果另外的线程正在read()/write()，程序会发生未定义的错误。给析构函数加锁依然不是办法:

```C++
~Foo()
{
    std::lock_guard<std::mutex> lock(mutex_);
    close(fd_);
    fd_ = 0;
}
```

此时fd_是被保护了，但是却会引发新的问题：当其中一个线程阻塞在mutex_上的时候，另外一个线程释放了foo,析构函数被调用时，fd_被关闭，但是成员变量mutex_也会随之被销毁。此时，前一个线程阻塞在一个销毁的mutex上，程序依然会出现未定义的错误。对析构函数加不加锁都是悲剧。那如何确保一个线程析构的时候，另一个线程没有使用这个对象呢？

办法是有的————使用智能指针就能轻松解决这个问题。只需要将`Foo* foo = new Foo;`改为`std::shared_ptr<Foo> foo = std::make_shared(Foo);`。工作线程里不需要显式delete，当引用计数(reference count)归0时,foo对象会被自动析构。

# 借助智能指针实现Copy-On-Write

# 总结

现在C++ 不应当出现delete。