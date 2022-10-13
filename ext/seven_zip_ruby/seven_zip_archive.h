#ifndef SEVEN_ZIP_ARCHIVE_H__
#define SEVEN_ZIP_ARCHIVE_H__

#include <iostream>
#include <fstream>
#include <cstdlib>
#include <cstring>
#include <list>
#include <map>
#include <utility>
#include <functional>

#ifdef _WIN32
#include <winsock2.h>
#include <windows.h>
#include <oleauto.h>
#include <initguid.h>
#else
#include <windows.h>
struct IEnumSTATPROPSTG;
#include <CPP/Common/MyWindows.h>
#include <CPP/Common/MyInitGuid.h>
#endif

#include "guid_defs.h"


#include <ruby.h>
#ifdef HAVE_RUBY_THREAD_H
#include <ruby/thread.h>
#endif

#include <CPP/Common/MyCom.h>
#include <CPP/Windows/PropVariant.h>
#include <CPP/7zip/Archive/IArchive.h>
#include <CPP/7zip/IPassword.h>


#include "mutex.h"
#include "util_common.h"


#ifdef NO_RB_THREAD_CALL_WITHOUT_GVL
inline VALUE rb_thread_call_without_gvl(void *(*func)(void *data), void *data1,
                                        rb_unblock_function_t *ubf, void *data2)
{
    typedef VALUE (*func_t)(void *);

    return rb_thread_blocking_region((func_t)func, data1, ubf, data2);
}
#endif

// For old compiler
#ifdef NO_NULLPTR
#define nullptr NULL
#endif

namespace SevenZip
{

class ArchiveExtractCallback;

////////////////////////////////////////////////////////////////
class ArchiveBase
{
  public:
    typedef std::function<void ()> RubyAction;

    typedef std::pair<RubyAction*, bool> RubyActionTuple;

    struct RubyActionResult
    {
        int status;
        VALUE exception;

        RubyActionResult()
             : status(0), exception(Qnil)
        {
        }

        void clear()
        {
            status = 0;
            exception = Qnil;
        }

        bool isError()
        {
            return status != 0;
        }

        bool hasException()
        {
            return exception != Qnil;
        }

        void mark()
        {
            rb_gc_mark(exception);
        }
    };

  protected:
    class EventLoopThreadExecuter
    {
      public:
        EventLoopThreadExecuter(ArchiveBase *self)
             : m_self(self)
        {
            m_self->startEventLoopThread();
        }

        ~EventLoopThreadExecuter()
        {
            m_self->terminateEventLoopThread();
        }

      private:
        ArchiveBase *m_self;
    };


  public:
    ArchiveBase();
    ~ArchiveBase();
    void setSelf(VALUE self);
    VALUE self();
    void rubyEventLoop();
    static VALUE staticRubyEventLoop(void *p);
    template<typename T> bool runRubyAction(T t);
    static VALUE runProtectedRubyAction(VALUE p);

  protected:
    void mark();
    void prepareAction();

    template<typename T>
      void runNativeFunc(T func);
    template<typename T, typename U>
      bool runNativeFuncProtect(T func, U cancel);

  private:
    void startEventLoopThread();
    void terminateEventLoopThread();
    void killEventLoopThread();
    void finishRubyAction();
    bool runRubyActionImpl(RubyAction *action);
    void cancelAction();
    virtual void setErrorState() = 0;


  private:
    static RubyAction ACTION_END;

  private:
    RubyActionTuple * volatile m_action_tuple;
    Mutex m_action_mutex;
    ConditionVariable m_action_cond_var;
    volatile bool m_event_loop_running;
    VALUE m_self;

  protected:
    RubyActionResult m_action_result;
};

template<typename T>
void ArchiveBase::runNativeFunc(T func)
{
    typedef std::function<void ()> func_type;

    func_type functor = func;
    func_type cancel = [&](){ cancelAction(); };

    func_type protected_func = [&](){
        rb_thread_call_without_gvl(rubyCppUtilFunction1, reinterpret_cast<void*>(&functor),
                                   rubyCppUtilFunction2, reinterpret_cast<void*>(&cancel));
    };

    int state = 0;
    rb_protect(rubyCppUtilFunctionForProtect, reinterpret_cast<VALUE>(&protected_func), &state);
    if (state){
        throw RubyCppUtil::RubyException(std::string("Interrupted"));
    }
}

template<typename T, typename U>
bool ArchiveBase::runNativeFuncProtect(T func, U cancel)
{
    typedef std::function<void ()> func_type;

    func_type functor1 = func;
    func_type functor2 = cancel;

    func_type protected_func = [&](){
        rb_thread_call_without_gvl(rubyCppUtilFunction1, reinterpret_cast<void*>(&functor1),
                                   rubyCppUtilFunction2, reinterpret_cast<void*>(&functor2));
    };

    int state = 0;
    rb_protect(rubyCppUtilFunctionForProtect, reinterpret_cast<VALUE>(&protected_func), &state);
    return (state == 0);
}

class ArchiveReader : public ArchiveBase
{
  private:
    enum ArchiveReaderState
    {
        STATE_INITIAL,
        STATE_OPENED,
        STATE_CLOSED,
        STATE_ERROR
    };


  public:
    ArchiveReader(const GUID &format_guid);
    void setProcessingStream(VALUE stream, UInt32 index, Int32 askExtractMode);
    void getProcessingStream(VALUE *stream, UInt32 *index, Int32 *askExtractMode);
    void clearProcessingStream();
    void setOperationResult(UInt32 index, Int32 result);
    VALUE callbackProc()
    {
        return m_rb_callback_proc;
    }
    void mark();
    void checkStateToBeginOperation(ArchiveReaderState expected, const std::string &msg = "Invalid operation");
    void checkState(ArchiveReaderState expected, const std::string &msg);
    bool isErrorState()
    {
        return m_state == STATE_ERROR;
    }

    // Called from Ruby script.
    VALUE open(VALUE in_stream, VALUE param);
    VALUE close();
    VALUE entryNum();
    VALUE getArchiveProperty();
    VALUE getEntryInfo(VALUE index);
    VALUE getAllEntryInfo();
    VALUE extract(VALUE index, VALUE callback_proc);
    VALUE extractFiles(VALUE index_list, VALUE callback_proc);
    VALUE extractAll(VALUE callback_proc);
    VALUE testAll(VALUE callback_proc);
    VALUE setFileAttribute(VALUE path, VALUE attrib);

    VALUE entryInfo(UInt32 index);

  protected:
    virtual void setErrorState();

  private:
    ArchiveExtractCallback *createArchiveExtractCallback();
    void fillEntryInfo();

  private:
    VALUE m_rb_callback_proc;
    VALUE m_rb_out_stream;
    UInt32 m_processing_index;
    VALUE m_rb_in_stream;
    std::vector<VALUE> m_rb_entry_info_list;

    Int32 m_ask_extract_mode;
    std::vector<Int32> m_test_result;

    const GUID &m_format_guid;

    CMyComPtr<IInArchive> m_in_archive;
    CMyComPtr<IInStream> m_in_stream;

    bool m_password_specified;
    std::string m_password;

    ArchiveReaderState m_state;
};

class ArchiveWriter : public ArchiveBase
{
  private:
    enum ArchiveWriterState
    {
        STATE_INITIAL,
        STATE_OPENED,
        STATE_COMPRESSED,
        STATE_CLOSED,
        STATE_ERROR
    };


  public:
    ArchiveWriter(const GUID &format_guid);
    void mark();
    VALUE callbackProc()
    {
        return m_rb_callback_proc;
    }
    void setProcessingStream(VALUE stream, UInt32 index);
    void getProcessingStream(VALUE *stream, UInt32 *index);
    void clearProcessingStream();
    bool updateItemInfo(UInt32 index, bool *new_data, bool *new_properties, UInt32 *index_in_archive);
    VALUE itemInfo(UInt32 index)
    {
        return m_rb_update_list[index];
    }
    void checkStateToBeginOperation(ArchiveWriterState expected,
                                    const std::string &msg = "Invalid operation");
    void checkStateToBeginOperation(ArchiveWriterState expected1, ArchiveWriterState expected2,
                                    const std::string &msg = "Invalid operation");
    void checkState(ArchiveWriterState expected, const std::string &msg);
    void checkState(ArchiveWriterState expected1, ArchiveWriterState expected2,
                    const std::string &msg);
    bool isErrorState()
    {
        return m_state == STATE_ERROR;
    }

    // Called from Ruby script.
    VALUE open(VALUE out_stream, VALUE param);
    VALUE addItem(VALUE item);
    VALUE compress(VALUE callback_proc);
    VALUE close();
    VALUE getFileAttribute(VALUE path);

  protected:
    virtual HRESULT setOption(ISetProperties *set) = 0;
    virtual void setErrorState();

  private:
    VALUE m_rb_callback_proc;
    VALUE m_rb_in_stream;
    UInt32 m_processing_index;
    VALUE m_rb_out_stream;
    std::vector<VALUE> m_rb_update_list;

    const GUID &m_format_guid;

    CMyComPtr<IOutArchive> m_out_archive;
    CMyComPtr<IInStream> m_in_stream;

    bool m_password_specified;
    std::string m_password;

    ArchiveWriterState m_state;
};

////////////////////////////////////////////////////////////////
class SevenZipReader : public ArchiveReader
{
  public:
    SevenZipReader();
};

////////////////////////////////////////////////////////////////
class SevenZipWriter : public ArchiveWriter
{
  public:
    SevenZipWriter();
    virtual HRESULT setOption(ISetProperties *set);

    VALUE setMethod(VALUE method);
    VALUE method();
    VALUE setLevel(VALUE level);
    VALUE level();
    VALUE setSolid(VALUE solid);
    VALUE solid();
    VALUE setHeaderCompression(VALUE header_compression);
    VALUE headerCompression();
    VALUE setHeaderEncryption(VALUE header_encryption);
    VALUE headerEncryption();
    VALUE setMultiThreading(VALUE multi_threading);
    VALUE multiThreading();

  private:
    std::string m_method;
    UInt32 m_level;
    bool m_solid;
    bool m_header_compression;
    bool m_header_encryption;
    bool m_multi_threading;
};

////////////////////////////////////////////////////////////////
class ArchiveOpenCallback : public IArchiveOpenCallback, public ICryptoGetTextPassword,
                            public CMyUnknownImp
{
  public:
    ArchiveOpenCallback(ArchiveReader *archive);
    ArchiveOpenCallback(ArchiveReader *archive, const std::string &password);
    virtual ~ArchiveOpenCallback() {}

    MY_UNKNOWN_IMP2(IArchiveOpenCallback, ICryptoGetTextPassword)

    // IArchiveOpenCallback
    STDMETHOD(SetTotal)(const UInt64 *files, const UInt64 *bytes);
    STDMETHOD(SetCompleted)(const UInt64 *files, const UInt64 *bytes);

    // ICryptoGetTextPassword
    STDMETHOD(CryptoGetTextPassword)(BSTR *password);

  protected:
    ArchiveReader *m_archive;

    bool m_password_specified;
    std::string m_password;
};

class ArchiveExtractCallback : public IArchiveExtractCallback, public ICryptoGetTextPassword,
                               public CMyUnknownImp
{
  public:
    ArchiveExtractCallback(ArchiveReader *archive);
    ArchiveExtractCallback(ArchiveReader *archive, const std::string &password);
    virtual ~ArchiveExtractCallback() {}

    MY_UNKNOWN_IMP2(IArchiveExtractCallback, ICryptoGetTextPassword)

    // IProgress
    STDMETHOD(SetTotal)(UInt64 size);
    STDMETHOD(SetCompleted)(const UInt64 *completeValue);

    // IArchiveExtractCallback
    STDMETHOD(GetStream)(UInt32 index, ISequentialOutStream **outStream, Int32 askExtractMode);
    STDMETHOD(PrepareOperation)(Int32 askExtractMode);
    STDMETHOD(SetOperationResult)(Int32 resultOperationResult);

    // ICryptoGetTextPassword
    STDMETHOD(CryptoGetTextPassword)(BSTR *password);

  private:
    ArchiveReader *m_archive;

    bool m_password_specified;
    const std::string m_password;
};

class ArchiveUpdateCallback : public IArchiveUpdateCallback, public ICryptoGetTextPassword2,
                              public CMyUnknownImp
{
  public:
    ArchiveUpdateCallback(ArchiveWriter *archive);
    ArchiveUpdateCallback(ArchiveWriter *archive, const std::string &password);
    virtual ~ArchiveUpdateCallback() {}

    MY_UNKNOWN_IMP2(IArchiveUpdateCallback, ICryptoGetTextPassword2)

    // IProgress
    STDMETHOD(SetTotal)(UInt64 size);
    STDMETHOD(SetCompleted)(const UInt64 *completeValue);

    // IUpdateCallback
    STDMETHOD(EnumProperties)(IEnumSTATPROPSTG **enumerator);
    STDMETHOD(GetUpdateItemInfo)(UInt32 index, Int32 *newData,
                                 Int32 *newProperties, UInt32 *indexInArchive);
    STDMETHOD(GetProperty)(UInt32 index, PROPID propID, PROPVARIANT *value);
    STDMETHOD(GetStream)(UInt32 index, ISequentialInStream **inStream);
    STDMETHOD(SetOperationResult)(Int32 operationResult);

    // ICryptoGetTextPassword2
    STDMETHOD(CryptoGetTextPassword2)(Int32 *passwordIsDefined, BSTR *password);

  private:
    ArchiveWriter *m_archive;

    bool m_password_specified;
    std::string m_password;
};


class InStream : public IInStream, public CMyUnknownImp
{
  public:
    InStream(VALUE stream, ArchiveBase *archive);
    virtual ~InStream() {}

    MY_UNKNOWN_IMP1(IInStream)

    STDMETHOD(Seek)(Int64 offset, UInt32 seekOrigin, UInt64 *newPosition);
    STDMETHOD(Read)(void *data, UInt32 size, UInt32 *processedSize);

  private:
    VALUE m_stream;
    ArchiveBase *m_archive;
};

class FileInStream : public IInStream, public CMyUnknownImp
{
  public:
    FileInStream(const std::string &filename, ArchiveBase *archive);
    virtual ~FileInStream();

    MY_UNKNOWN_IMP1(IInStream)

    STDMETHOD(Seek)(Int64 offset, UInt32 seekOrigin, UInt64 *newPosition);
    STDMETHOD(Read)(void *data, UInt32 size, UInt32 *processedSize);

  private:
    ArchiveBase *m_archive;
#ifdef USE_WIN32_FILE_API
    HANDLE m_file_handle;
#else
    std::ifstream m_file;
#endif
};


class OutStream : public IOutStream, public CMyUnknownImp
{
  public:
    OutStream(VALUE stream, ArchiveBase *archive);
    virtual ~OutStream() {}

    MY_UNKNOWN_IMP1(IOutStream)

    STDMETHOD(Write)(const void *data, UInt32 size, UInt32 *processedSize);

    STDMETHOD(Seek)(Int64 offset, UInt32 seekOrigin, UInt64 *newPosition);
    STDMETHOD(SetSize)(UInt64 size);

  private:
    VALUE m_stream;
    ArchiveBase *m_archive;
};

// Not implemented yet.
class FileOutStream : public IOutStream, public CMyUnknownImp
{
  public:
    FileOutStream(const std::string &filename, ArchiveBase *archive);
    virtual ~FileOutStream() {}

    MY_UNKNOWN_IMP1(IOutStream)

    STDMETHOD(Write)(const void *data, UInt32 size, UInt32 *processedSize);

    STDMETHOD(Seek)(Int64 offset, UInt32 seekOrigin, UInt64 *newPosition);
    STDMETHOD(SetSize)(UInt64 size);

  private:
    const std::string m_filename;
    ArchiveBase *m_archive;
};


////////////////////////////////////////////////////////////////


}

#endif
