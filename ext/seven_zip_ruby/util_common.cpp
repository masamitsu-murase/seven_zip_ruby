
#include <functional>

#include "util_common.h"

extern "C" VALUE rubyCppUtilFunctionForProtect(VALUE p)
{
    typedef std::function<void ()> func_type;
    func_type *func = reinterpret_cast<func_type*>(p);
    (*func)();
    return Qnil;
}

extern "C" void *rubyCppUtilFunction1(void *p)
{
    typedef std::function<void ()> func_type;
    func_type *func = reinterpret_cast<func_type*>(p);
    (*func)();
    return nullptr;
}

extern "C" void rubyCppUtilFunction2(void *p)
{
    typedef std::function<void ()> func_type;
    func_type *func = reinterpret_cast<func_type*>(p);
    (*func)();
}

