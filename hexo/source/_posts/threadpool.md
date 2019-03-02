---
title: 一个基于现代C++简单线程池的实现
date: 2018-11-15 16:33:32
tags: [c++,thread-safe]
categories: c++
---

无意间看到了上大学的时候用C++ + PThread API实现的了一个简单线程池：[https://github.com/baixiangcpp/TinxHttpd/blob/master/ThreadPool.h](https://github.com/baixiangcpp/TinxHttpd/blob/master/ThreadPool.h)。发现了几个问题：

1. 多线程对std::queue的操作都没有加锁，很明显的race condition
2. 虽然使用了C++11的特性 (std::function)，thread库没有使用，不统一。在linux上std::thread就是封装Pthread库，相比之下OO对象用起来还是舒服一点儿，免去了进一步封装的工作。
3. 接口设计不好,不容易复用。虽然名字叫task，其实只有一个fd，利用bind或者lambda表达式才更加合适。

首先要不是这段代码出现在我的Github上，我肯定不承认这段代码是我写的。今天花时间重新设计了一个基于C++11的线程池。<!--more-->

# 使用高级的同步数据结构

虽然使用[std::condition_variable](https://en.cppreference.com/w/cpp/thread/condition_variable)已经比使用pthread_cond_t要方便多了，但是我仍然不打算直接使用用它。在前面[当谈论线程安全时，我们在谈论什么](http://www.ilovecpp.com/2018/11/01/thread-safe/)一文中，我自己才总结了应尽量避免直接使用底层的同步原语，而是用高级的数据结构。我不能这么着急的打自己的脸。

java里的BlockingQueue正符合。他除了用来表示生产者消费者模型，还来实现任务队列。

# 封装一个BlockingQueue

Blocking的封装比较简单，只需要两种接口:put()和take()。我顺便提供了一个size():

```C++
class BlockingQueue
{
    using Task = std::function<void()>;

public:
    BlockingQueue() {}
    void put(const Task& task);
    void put(Task&& task);
    Task take();
    size_t size() const;

private:
    mutable std::mutex      mutex_;
    std::queue<Task>        queue_;
    std::condition_variable cond_;
};
```

构造函数不需要额外的干什么，成员变量都让他们默认构造就行了。size()也是只要在 mutex的保护下，直接返回std::queue中对应的函数。

scott meyers曾在《Effective Modern c++》里边说过：“Because you’re a C++ programmer, there’s an above-average chance you’re a performance freak. If you’re not, you’re still probably sympathetic to their point of view. (If you’re not at all interested in performance, shouldn’t you be in the Python room down the hall?)”。

作为一名C++程序员，我们应该时刻关注性能。

```C++
void BlockingQueue::put(const Task &task)
{
    std::lock_guard<std::mutex> lock(mutex_);
    queue_.emplace(task);
    cond_.notify_one();
}

void BlockingQueue::put(Task &&task)
{
    std::lock_guard<std::mutex> lock(mutex_);
    queue_.emplace(std::move(task));
    cond_.notify_one();
}

BlockingQueue::Task BlockingQueue::take()
{
    std::unique_lock<std::mutex> lock(mutex_);
    cond_.wait(lock, [this]() { return queue_.size() > 0; });
    Task task( std::move(queue_.front()));
    queue_.pop();
    return std::move(task);
}
```

BlockingQueue实现有2处可以提升性能的地方 ：

1. 使用move语义减少拷贝
2. 使用emplace代替put([std::queue<>::emplace](https://en.cppreference.com/w/cpp/container/queue/emplace))

put操作由于需要把mutex交给cond_解锁，因此使用了std::unique_lock<>而非std::lock_guard<>。

此外，自从有了lambda之后，STL中像条件变量wait()这样的函数多了好些个，[《正确封装条件变量不容易》](http://www.ilovecpp.com/2018/09/29/condition/) 可以参考这种封装方法。

# ThreadPool实现

有了BlockingQueue之后，实现ThreadPool逻辑就清晰多了。

```C++
class ThreadPool
{
public:
    ThreadPool(unsigned short num) ;
    ~ThreadPool();

    void put(const BlockingQueue::Task& task);
    void put(BlockingQueue::Task&& task);
private:
    void runInThread();

    std::vector<std::unique_ptr<std::thread>> threads_;
    BlockingQueue  bqueue_;
};
```

ThreadPool只有一个BlockingQueue成员，用来管理任务。put将task原封不动的交给BlockingQueue保存。

ThreadPool构造函数需要一个正整形的变量表示线程数，构造函数中将std::thread构造好。用std::vector<>保存线程的指针。当然，使用智能指针。

runInThread()是线程的入口函数，由于是成员函数，需要额外的传递一个this指针。这样才能访问到BlockingQueue。

```C++
ThreadPool::ThreadPool(int num)
{
    threads_.reserve(num);
    for (int i = 0; i < num; ++i)
    {
        std::unique_ptr<std::thread> ptr(new std::thread(std::bind(&ThreadPool::runInThread, this)));
        threads_.emplace_back(std::move(ptr));
    }
}

void ThreadPool::runInThread()
{
    while(true)
    {
        BlockingQueue::Task task(bqueue_.take());
        task();
    }
}

void ThreadPool::put(const BlockingQueue::Task& task)
{
    bqueue_.put(task);
}

void ThreadPool::put(BlockingQueue::Task&& task)
{
    bqueue_.put(task);
}
```

# 总结

这个线程池没有使用模板，而是直接使用了std::function<void()>，如果需要的话，很容易可以改写成模板实现。用现代C++的thread库代替Pthread，写出来的代码可阅读性更好，也省去了一些原始指针的操作。

这个版本暂时未提供ThreadPool::stop()操作，因此析构函数中也没有及时join结束的线程。这个功能留到日后改进。
