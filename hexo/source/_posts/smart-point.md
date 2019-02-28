---
title: 都9102年了,你居然还没用上智能指针
date: 2019-1-29 19:43:35
tags: [linux,c++,thread-safety]
categories: c++
---

原始指针(raw pointer，为了表述方便，下面提到的‘指针’均指原始指针)是C/C++最强大的工具，它威力无穷，但是稍有不慎，就有引发各种内存问题。智能指针来势汹汹，它利用RAII特性对指针的封装，帮助程序员自动管理内存。其目的是用来代替指针。重载了操作符(operator*,operator->和operator[])，用起来和指针没多大区别。同时也规避了许多指针带来的陷阱，大大减少了程序员犯错的机会。本篇博客我将列举原始指针之罪以及一些不得不使用智能指针的理由。

本文的智能指针([https://en.cppreference.com/book/intro/smart_pointers](https://en.cppreference.com/book/intro/smart_pointers))是指C++11以来的`std::unique_ptr`、`std::shared_ptr`和`std::weak_ptr`,不包括半吊子的`std::auto_ptr`，它谈不上智能二字(不支持移动语义，不能存储在容器中)。<!--more-->

# 原始指针七宗罪

C/C++程序员恐怕没有没吃过指针亏的，先列举它主要的罪状：

1. 不能通过一个指针判断指向的是单个对象还是一个数组。
2. 当你使用完指针的时候，你不知道应不应该将它释放(delete)。
3. 使用指针时，当你确定要释放一处内存，你不知道如何释放(除了delete之外)。智能指针可以在构造的时候指定custom deleter。
4. 当你确定使用delete释放内存的时候，又不知道使用delete还是delete[]，一旦用错，就是未定义的错误。
5. 你无法确定一个指针是不是空悬指针(dangle)。
6. 忘记释放内存会造成内存泄漏(memory leak)。
7. 重复释放内存会造成重复释放(double delete)。

一些内存错误，通常不是必现的，偶尔出现一次内存错误，排查起来也不容易。正确使用智能指针，能很好的杜绝程序里出这些问题。为了保全头发，还是趁早的放弃原始指针。

# 智能指针

C++11带来了3种智能指针:

> std::unique_ptr : unique_ptr is a smart pointer that owns and manages another object through a pointer and disposes of that object when the unique_ptr goes out of scope.

unique_ptr和被指向的对象表示一种独自占有的关系，因此拷贝一个unique_ptr是不允许的，是"move-only"的。智能通过转移语义将一个unique_ptr的值初始化另外的unique_ptr(源指针将会被置为nullptr)。auto_ptr在表现上很像一个unique_ptr，但是由于当时没有move语义，因此成为了鸡肋。unique_ptr基本上是没有额外的性能消耗的，和使用raw pointer基本一致，应优先考虑。

> std::shared_ptr : shared_ptr is a smart pointer that retains shared ownership of an object through a pointer. Several shared_ptr objects may own the same object. 

shared_ptr可以和其他的shared_ptr共同管理同一个对象。通过引用计数表示共有几个shared_ptr管理着当前的对象。当最后一个拥有对象的shared_ptr被析构时(或者被reset())，该对象才会被delete。shared_ptr是有一点性能损失的：1.需要一个额外的字段表示引用计数 2.引用计数需要动态分配 3.引用计数的Increment 和 decrement操作被实现时原子操作。

> std::weak_ptr ：weak_ptr is a smart pointer that holds a non-owning ("weak") reference to an object that is managed by std::shared_ptr. It must be converted to std::shared_ptr in order to access the referenced object.

weak_ptr不控制对象的生命周期。通常配合shared_ptr使用，可以将shared_ptr的赋值给weak_ptr，而并不会改变引用计数的值，如果shared_ptr存在可以通过lock()成员函数将其提升为一个shared_ptr，否则当所有shared_ptr被析构后，提升会失败，返回false。

初始化智能指针时，最好不要使用到原始指针，充当中间变量。可以直接在构造函数中直接调用new。可能会导致不必要的问题：如果原始指针ptr，先后被用来构造两个shared_ptr，因为它们不知道彼此的存在，ptr会被delete两次。

推荐的做法是使用make_unique()/make_shared()构造智能指针，但是make_unique()直到C++14才姗姗来迟，原因是在C++11中被忘掉了。[Why does C++11 have `make_shared` but not `make_unique` ](https://stackoverflow.com/questions/12580432/why-does-c11-have-make-shared-but-not-make-unique)还提供了一个简易的make_unique()实现：

```C++
template<typename T, typename ...Args>
std::unique_ptr<T> make_unique( Args&& ...args )
{
    return std::unique_ptr<T>( new T( std::forward<Args>(args)... ) );
}
```

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

# 用shared_ptr 实现Copy-On-Write

陈硕的《Linux多线程服务端编程》介绍了一种利用shared_ptr实现为Copy-on-Write(准确的来说是Copy-On-Race)从而避免死锁的方式。主要原理是：

1. shared_ptr的引用计数用来标记当前有几个read/write端。
2. 对于read端，将shared_ptr使用一个栈上的变量保存，此时引用计数加1。

```C++

void read()
{
    std::shared_ptr<Foo> ptr;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        ptr = gptr_; //引用计数增加1
    }

    // 使用ptr访问资源
    // 因为ptr占有1个引用计数，可以安全访问，不会被析构

}

```

3. 对于write端，如果当前的引用计数为1，可以安全的修改对象。
4. 对于write端，如果当前的引用计数大于1，需要将之前的对象重新复制一份赋值给shared_ptr。

```C++

void write()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if(!gptr_.unique())
    {
        gptr_.reset(new XXX(*gptr_));
    }

    // 此时可以保证gptr_引用计数为1
    // 修改gptr_的资源
}

```

此外，以上代码中的mutex_是用来保护shared_ptr的([为什么多线程读写 shared_ptr 要加锁？](https://blog.csdn.net/solstice/article/details/8547547))。

# 总结

在 C++ 1x 之前，"记得"delete，不是最佳实践。使用智能指针才是减少内存问题的最佳途径。但是智能指针的好处远不仅于此，确保线程安全，实现Copy-On-Write都有它一席之地。
