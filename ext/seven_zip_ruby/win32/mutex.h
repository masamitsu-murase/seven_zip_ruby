#ifndef MUTEX_WIN32_H__
#define MUTEX_WIN32_H__

#include <winsock2.h>
#include <windows.h>


namespace SevenZip
{

class Mutex
{
  public:
    Mutex(const char *name = "No Name")
         : m_name(name)
    {
        InitializeCriticalSection(&m_mutex);
    }

    ~Mutex()
    {
        DeleteCriticalSection(&m_mutex);
    }

    void lock()
    {
        EnterCriticalSection(&m_mutex);
    }

    void unlock()
    {
        LeaveCriticalSection(&m_mutex);
    }

  private:
    CRITICAL_SECTION m_mutex;
    const char *m_name;
};

class MutexLocker
{
  public:
    MutexLocker(Mutex *mutex)
         : m_mutex(mutex)
    {
        m_mutex->lock();
    }

    ~MutexLocker()
    {
        m_mutex->unlock();
    }

  private:
    Mutex *m_mutex;
};

class ConditionVariable
{
  public:
    ConditionVariable()
         : m_waiters_count_mutex("waiters_count"),
           m_waiters_count(0)
    {
        m_signal_event = CreateEvent(NULL, FALSE, FALSE, NULL);
        m_broadcast_event = CreateEvent(NULL, TRUE, FALSE, NULL);
    }

    ~ConditionVariable()
    {
        CloseHandle(m_signal_event);
        CloseHandle(m_broadcast_event);
    }

    void wait(Mutex *mutex)
    {
        m_waiters_count_mutex.lock();
        m_waiters_count++;
        m_waiters_count_mutex.unlock();

        mutex->unlock();

        HANDLE events[] = { m_signal_event, m_broadcast_event };
        DWORD ret = WaitForMultipleObjects (2, events, FALSE, INFINITE);

        m_waiters_count_mutex.lock();
        m_waiters_count--;
        bool last = (ret == WAIT_OBJECT_0 + 1 && m_waiters_count == 0);
        m_waiters_count_mutex.unlock();


        if (last){
            ResetEvent(m_broadcast_event);
        }

        mutex->lock();
    }

    void signal()
    {
        m_waiters_count_mutex.lock();
        bool waiting = (m_waiters_count > 0);
        m_waiters_count_mutex.unlock();

        if (waiting){
            SetEvent(m_signal_event);
        }
    }

    void broadcast()
    {
        m_waiters_count_mutex.lock();
        bool waiting = (m_waiters_count > 0);
        m_waiters_count_mutex.unlock();

        if (waiting){
            SetEvent(m_broadcast_event);
        }
    }

  private:
    HANDLE m_signal_event;
    HANDLE m_broadcast_event;
    Mutex m_waiters_count_mutex;
    unsigned int m_waiters_count;
};

}

#endif
