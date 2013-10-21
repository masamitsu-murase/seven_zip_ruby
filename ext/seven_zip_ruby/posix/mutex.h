#ifndef MUTEX_POSIX_H__
#define MUTEX_POSIX_H__

#include <pthread.h>

namespace SevenZip
{

class ConditionVariable;

class Mutex
{
    friend class ConditionVariable;

  public:
    Mutex(const char *name = "No Name")
         : m_name(name)
    {
        pthread_mutex_init(&m_mutex, NULL);
    }

    ~Mutex()
    {
        pthread_mutex_destroy(&m_mutex);
    }

    void lock()
    {
        pthread_mutex_lock(&m_mutex);
    }

    void unlock()
    {
        pthread_mutex_unlock(&m_mutex);
    }

  private:
    pthread_mutex_t m_mutex;
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
    {
        pthread_cond_init(&m_cond_var, NULL);
    }

    ~ConditionVariable()
    {
        pthread_cond_destroy(&m_cond_var);
    }

    void wait(Mutex *mutex)
    {
        pthread_cond_wait(&m_cond_var, &(mutex->m_mutex));
    }

    void signal()
    {
        pthread_cond_signal(&m_cond_var);
    }

    void broadcast()
    {
        pthread_cond_broadcast(&m_cond_var);
    }

  private:
    pthread_cond_t m_cond_var;
};

}

#endif
