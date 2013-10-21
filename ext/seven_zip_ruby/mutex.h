#ifndef MUTEX_H__
#define MUTEX_H__

#ifdef _WIN32
#include "win32/mutex.h"
#else
#include "posix/mutex.h"
#endif

#endif
