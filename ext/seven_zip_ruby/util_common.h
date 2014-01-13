#ifndef UTIL_COMMON_H__
#define UTIL_COMMON_H__

#include <algorithm>
#include <functional>
#include <utility>
#include <string>
#include <iostream>

#include <ruby.h>

extern "C" VALUE rubyCppUtilFunctionForProtect(VALUE p);
extern "C" void *rubyCppUtilFunction1(void *p);
extern "C" void rubyCppUtilFunction2(void *p);

namespace RubyCppUtil
{

class RubyException
{
  public:
    RubyException(VALUE exc)
         : m_exc(exc)
    {
    }

    RubyException(const std::string &str)
         : m_exc(rb_exc_new(rb_eStandardError, str.c_str(), str.size()))
    {
    }

    VALUE exception()
    {
        return m_exc;
    }

  private:
    VALUE m_exc;
};


template<typename T>
void runRubyFunction(T func)
{
    std::function<void ()> function = func;
    int state = 0;
    rb_protect(rubyCppUtilFunctionForProtect, reinterpret_cast<VALUE>(&function), &state);

    if (state){
        VALUE exception = rb_gv_get("$!");
        if (!NIL_P(exception)){
            throw RubyException(exception);
        }
        throw RubyException(std::string("Unknown exception"));
    }
}


template<typename T, VALUE (T::*func)()>
VALUE wrappedFunction0(VALUE self)
{
    T *p;
    Data_Get_Struct(self, T, p);

    VALUE exc = Qnil;
    try{
        return (p->*func)();
    }catch(RubyException &e){
        exc = e.exception();
    }catch(...){
    }

    if (NIL_P(exc)){
        rb_raise(rb_eStandardError, "Unknown exception");
    }else{
        rb_exc_raise(exc);
    }

    return Qnil;
}

template<typename T, typename U, VALUE (U::*func)()>
VALUE wrappedFunction0(VALUE self)
{
    T *p;
    Data_Get_Struct(self, T, p);
    U *u = p;

    VALUE exc = Qnil;
    try{
        return (u->*func)();
    }catch(RubyException &e){
        exc = e.exception();
    }catch(...){
    }

    if (NIL_P(exc)){
        rb_raise(rb_eStandardError, "Unknown exception");
    }else{
        rb_exc_raise(exc);
    }

    return Qnil;
}

template<typename T, VALUE (T::*func)(VALUE)>
VALUE wrappedFunction1(VALUE self, VALUE a1)
{
    T *p;
    Data_Get_Struct(self, T, p);

    VALUE exc = Qnil;
    try{
        return (p->*func)(a1);
    }catch(RubyException &e){
        exc = e.exception();
    }catch(...){
    }

    if (NIL_P(exc)){
        rb_raise(rb_eStandardError, "Unknown exception");
    }else{
        rb_exc_raise(exc);
    }

    return Qnil;
}

template<typename T, typename U, VALUE (U::*func)(VALUE)>
VALUE wrappedFunction1(VALUE self, VALUE a1)
{
    T *p;
    Data_Get_Struct(self, T, p);
    U *u = p;

    VALUE exc = Qnil;
    try{
        return (u->*func)(a1);
    }catch(RubyException &e){
        exc = e.exception();
    }catch(...){
    }

    if (NIL_P(exc)){
        rb_raise(rb_eStandardError, "Unknown exception");
    }else{
        rb_exc_raise(exc);
    }

    return Qnil;
}

template<typename T, VALUE (T::*func)(VALUE, VALUE)>
VALUE wrappedFunction2(VALUE self, VALUE a1, VALUE a2)
{
    T *p;
    Data_Get_Struct(self, T, p);

    VALUE exc = Qnil;
    try{
        return (p->*func)(a1, a2);
    }catch(RubyException &e){
        exc = e.exception();
    }catch(...){
    }

    if (NIL_P(exc)){
        rb_raise(rb_eStandardError, "Unknown exception");
    }else{
        rb_exc_raise(exc);
    }

    return Qnil;
}

template<typename T, typename U, VALUE (U::*func)(VALUE, VALUE)>
VALUE wrappedFunction2(VALUE self, VALUE a1, VALUE a2)
{
    T *p;
    Data_Get_Struct(self, T, p);
    U *u = p;

    VALUE exc = Qnil;
    try{
        return (u->*func)(a1, a2);
    }catch(RubyException &e){
        exc = e.exception();
    }catch(...){
    }

    if (NIL_P(exc)){
        rb_raise(rb_eStandardError, "Unknown exception");
    }else{
        rb_exc_raise(exc);
    }

    return Qnil;
}

template<typename T, VALUE (T::*func)(VALUE, VALUE, VALUE)>
VALUE wrappedFunction3(VALUE self, VALUE a1, VALUE a2, VALUE a3)
{
    T *p;
    Data_Get_Struct(self, T, p);

    VALUE exc = Qnil;
    try{
        return (p->*func)(a1, a2, a3);
    }catch(RubyException &e){
        exc = e.exception();
    }catch(...){
    }

    if (NIL_P(exc)){
        rb_raise(rb_eStandardError, "Unknown exception");
    }else{
        rb_exc_raise(exc);
    }

    return Qnil;
}

template<typename T, typename U, VALUE (U::*func)(VALUE, VALUE, VALUE)>
VALUE wrappedFunction3(VALUE self, VALUE a1, VALUE a2, VALUE a3)
{
    T *p;
    Data_Get_Struct(self, T, p);
    U *u = p;

    VALUE exc = Qnil;
    try{
        return (u->*func)(a1, a2, a3);
    }catch(RubyException &e){
        exc = e.exception();
    }catch(...){
    }

    if (NIL_P(exc)){
        rb_raise(rb_eStandardError, "Unknown exception");
    }else{
        rb_exc_raise(exc);
    }

    return Qnil;
}

template<typename T, VALUE (T::*func)(VALUE, VALUE, VALUE, VALUE)>
VALUE wrappedFunction4(VALUE self, VALUE a1, VALUE a2, VALUE a3, VALUE a4)
{
    T *p;
    Data_Get_Struct(self, T, p);

    VALUE exc = Qnil;
    try{
        return (p->*func)(a1, a2, a3, a4);
    }catch(RubyException &e){
        exc = e.exception();
    }catch(...){
    }

    if (NIL_P(exc)){
        rb_raise(rb_eStandardError, "Unknown exception");
    }else{
        rb_exc_raise(exc);
    }

    return Qnil;
}

template<typename T, typename U, VALUE (U::*func)(VALUE, VALUE, VALUE, VALUE)>
VALUE wrappedFunction4(VALUE self, VALUE a1, VALUE a2, VALUE a3, VALUE a4)
{
    T *p;
    Data_Get_Struct(self, T, p);
    U *u = p;

    VALUE exc = Qnil;
    try{
        return (u->*func)(a1, a2, a3, a4);
    }catch(RubyException &e){
        exc = e.exception();
    }catch(...){
    }

    if (NIL_P(exc)){
        rb_raise(rb_eStandardError, "Unknown exception");
    }else{
        rb_exc_raise(exc);
    }

    return Qnil;
}

template<typename T, VALUE (T::*func)(VALUE, VALUE, VALUE, VALUE, VALUE)>
VALUE wrappedFunction5(VALUE self, VALUE a1, VALUE a2, VALUE a3, VALUE a4, VALUE a5)
{
    T *p;
    Data_Get_Struct(self, T, p);

    VALUE exc = Qnil;
    try{
        return (p->*func)(a1, a2, a3, a4, a5);
    }catch(RubyException &e){
        exc = e.exception();
    }catch(...){
    }

    if (NIL_P(exc)){
        rb_raise(rb_eStandardError, "Unknown exception");
    }else{
        rb_exc_raise(exc);
    }

    return Qnil;
}

template<typename T, typename U, VALUE (U::*func)(VALUE, VALUE, VALUE, VALUE, VALUE)>
VALUE wrappedFunction5(VALUE self, VALUE a1, VALUE a2, VALUE a3, VALUE a4, VALUE a5)
{
    T *p;
    Data_Get_Struct(self, T, p);
    U *u = p;

    VALUE exc = Qnil;
    try{
        return (u->*func)(a1, a2, a3, a4, a5);
    }catch(RubyException &e){
        exc = e.exception();
    }catch(...){
    }

    if (NIL_P(exc)){
        rb_raise(rb_eStandardError, "Unknown exception");
    }else{
        rb_exc_raise(exc);
    }

    return Qnil;
}


////////////////////////////////////////////////////////////////
const unsigned char INIT_MEMORY_VALUE = 0xFF;

template<typename T>
bool isValidStruct(const T *p)
{
    const unsigned char *begin = reinterpret_cast<const unsigned char*>(p);
    const unsigned char *end = begin + sizeof(T);
    const unsigned char *pos = std::find_if(begin, end, std::bind(std::not_equal_to<unsigned char>(),
                                                                  std::placeholders::_1,
                                                                  INIT_MEMORY_VALUE));

    return (pos != end);
}

template<typename T>
void wrapMark(T *p)
{
    if (!isValidStruct(p)){
        return;
    }
    p->mark();
}

template<typename T>
void wrapFree(T *p)
{
    if (isValidStruct(p)){
        p->~T();
    }
    ruby_xfree(p);
}

template<typename T>
VALUE wrapAlloc(VALUE cls)
{
    T *p = (T *)ruby_xmalloc(sizeof(T));
    std::fill_n(reinterpret_cast<unsigned char*>(p), sizeof(T), INIT_MEMORY_VALUE);

    void (*mark)(T *);
    mark = wrapMark<T>;
    void (*free)(T *);
    free = wrapFree<T>;

    return Data_Wrap_Struct(cls, mark, free, p);
}

template<typename T>
VALUE wrapInitialize(VALUE self)
{
    T *p;
    Data_Get_Struct(self, T, p);
    std::fill_n(reinterpret_cast<unsigned char*>(p), sizeof(T), ~INIT_MEMORY_VALUE);
    new(p) T();
    p->setSelf(self);

    return Qnil;
}

////////////////////////////////////////////////////////////////
template<typename T>
VALUE rb_define_wrapped_cpp_class(const char *name, VALUE super)
{
    // When this function is compiled on Linux, the following code force to instanciate
    // wrapAlloc and wrapInitialize.
    VALUE (*alloc)(VALUE);
    alloc = wrapAlloc<T>;
    VALUE (*init)(VALUE);
    init = wrapInitialize<T>;

    VALUE cls = rb_define_class(name, super);
    rb_define_alloc_func(cls, alloc);
    rb_define_private_method(cls, "initialize", RUBY_METHOD_FUNC(init), 0);
    return cls;
}

template<typename T>
VALUE rb_define_wrapped_cpp_class_under(VALUE outer, const char *name, VALUE super)
{
    // When this function is compiled on Linux, the following code force to instanciate
    // wrapAlloc and wrapInitialize.
    VALUE (*alloc)(VALUE);
    alloc = wrapAlloc<T>;
    VALUE (*init)(VALUE);
    init = wrapInitialize<T>;

    VALUE cls = rb_define_class_under(outer, name, super);
    rb_define_alloc_func(cls, alloc);
    rb_define_private_method(cls, "initialize", RUBY_METHOD_FUNC(init), 0);
    return cls;
}

inline void rb_define_method_ext(VALUE cls, const char *name, VALUE (*func)(VALUE))
{
    rb_define_method(cls, name, RUBY_METHOD_FUNC(func), 0);
}

inline void rb_define_method_ext(VALUE cls, const char *name, VALUE (*func)(VALUE, VALUE))
{
    rb_define_method(cls, name, RUBY_METHOD_FUNC(func), 1);
}

inline void rb_define_method_ext(VALUE cls, const char *name, VALUE (*func)(VALUE, VALUE, VALUE))
{
    rb_define_method(cls, name, RUBY_METHOD_FUNC(func), 2);
}

inline void rb_define_method_ext(VALUE cls, const char *name, VALUE (*func)(VALUE, VALUE, VALUE, VALUE))
{
    rb_define_method(cls, name, RUBY_METHOD_FUNC(func), 3);
}

inline void rb_define_method_ext(VALUE cls, const char *name, VALUE (*func)(VALUE, VALUE, VALUE, VALUE, VALUE))
{
    rb_define_method(cls, name, RUBY_METHOD_FUNC(func), 4);
}

inline void rb_define_method_ext(VALUE cls, const char *name, VALUE (*func)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))
{
    rb_define_method(cls, name, RUBY_METHOD_FUNC(func), 5);
}


}

#endif
