
#include <array>
#include <vector>
#include <cassert>
#include <string>
#include <cstddef>

#ifndef _WIN32
#include <dlfcn.h>
#endif

#include "seven_zip_archive.h"
#include "utils.h"
#include "util_common.h"

#define INTERN(const_str) rb_intern2(const_str, sizeof(const_str) - 1)

// For https://bugs.ruby-lang.org/issues/11962
#ifndef RARRAY_CONST_PTR
#define RARRAY_CONST_PTR(index_list) RARRAY_PTR(index_list)
#endif

////////////////////////////////////////////////////////////////
namespace SevenZip
{

using namespace RubyCppUtil;


typedef UINT32 (WINAPI * CreateObjectFunc)(
    const GUID *clsID,
    const GUID *interfaceID,
    void **outObject);

static CreateObjectFunc CreateObject;
static VALUE gSevenZipModule = Qnil;

#ifdef _WIN32
static HMODULE gSevenZipHandle;
#else
static void *gSevenZipHandle;
#endif

////////////////////////////////////////////////////////////////
ArchiveBase::RubyAction ArchiveBase::ACTION_END = [](){};

ArchiveBase::ArchiveBase()
     : m_action_tuple(nullptr),
       m_event_loop_running(false),
       m_self(Qnil)
{
    m_action_result.clear();
}

ArchiveBase::~ArchiveBase()
{
}

void ArchiveBase::setSelf(VALUE self)
{
    m_self = self;
}

VALUE ArchiveBase::self()
{
    return m_self;
}

void ArchiveBase::rubyEventLoop()
{
    m_action_mutex.lock();
    while(m_event_loop_running){
        m_action_mutex.unlock();

        RubyActionTuple end_tuple = std::make_pair(&ACTION_END, false);
        RubyActionTuple * volatile action_tuple = nullptr;

        bool success = runNativeFuncProtect([&](){
            MutexLocker locker(&m_action_mutex);
            while(!m_action_tuple){
                m_action_cond_var.wait(&m_action_mutex);
            }
            action_tuple = m_action_tuple;
        }, [&](){
            MutexLocker locker(&m_action_mutex);
            if (m_event_loop_running){
                m_action_tuple = &end_tuple;
                m_action_cond_var.broadcast();
            }
        });
        if (!success){
            MutexLocker locker(&m_action_mutex);
            action_tuple = &end_tuple;
        }

        RubyAction *action = action_tuple->first;
        bool event_loop_running = m_event_loop_running;
        if (action == &ACTION_END){
            action_tuple->second = true;
            event_loop_running = false;
        }else if (m_action_result.isError()){
            action_tuple->second = false;
        }else{
            int status = 0;
            rb_protect(runProtectedRubyAction, reinterpret_cast<VALUE>(action), &status);
            action_tuple->second = (status == 0);

            if (status && !m_action_result.isError()){
                m_action_result.status = status;
                m_action_result.exception = rb_gv_get("$!");
                event_loop_running = false;
            }
        }

        m_action_mutex.lock();
        m_event_loop_running = event_loop_running;
        // if (m_action_tuple && m_action_tuple != &end_tuple && m_action_tuple != action_tuple){
        //     // Someone overrode m_action_tuple.
        //     // It might be killEventLoopThread. Otherwise, it might a bug.
        //     // Therefore, terminate event loop for safety.
        //     m_event_loop_running = false;
        // }
        m_action_tuple = nullptr;
        m_action_cond_var.broadcast();
    }
    m_action_mutex.unlock();
}

VALUE ArchiveBase::runProtectedRubyAction(VALUE p)
{
    RubyAction *action = reinterpret_cast<RubyAction*>(p);
    (*action)();
    return Qnil;
}

VALUE ArchiveBase::staticRubyEventLoop(void *p)
{
    ArchiveBase *self = reinterpret_cast<ArchiveBase*>(p);
    VALUE gc_guard = self->self();
    RB_GC_GUARD(gc_guard);
    self->rubyEventLoop();
    return Qnil;
}

void ArchiveBase::startEventLoopThread()
{
    MutexLocker locker(&m_action_mutex);
    if (m_event_loop_running){
        return;
    }
    m_event_loop_running = true;
    RubyCppUtil::rb_thread_create(staticRubyEventLoop, this);
}

void ArchiveBase::cancelAction()
{
//    killEventLoopThread();
    setErrorState();
}

void ArchiveBase::killEventLoopThread()
{
    MutexLocker locker(&m_action_mutex);
    if (m_event_loop_running){
        static RubyActionTuple end_tuple;
        end_tuple = std::make_pair(&ACTION_END, false);
        m_action_tuple = &end_tuple;  // override.
        m_action_cond_var.broadcast();
    }
}

bool ArchiveBase::runRubyActionImpl(RubyAction *action)
{
    MutexLocker locker(&m_action_mutex);

    if (!action || !m_event_loop_running){
        return false;
    }

    RubyActionTuple tuple = std::make_pair(action, false);

    while(m_action_tuple && m_event_loop_running){
        m_action_cond_var.wait(&m_action_mutex);
    }
    if (!m_event_loop_running){
        return false;
    }

    m_action_tuple = &tuple;

    m_action_cond_var.broadcast();

    while(m_action_tuple == &tuple && m_event_loop_running){
        m_action_cond_var.wait(&m_action_mutex);
    }

    return (tuple.second && m_event_loop_running);
}

template<typename T>
bool ArchiveBase::runRubyAction(T t)
{
    RubyAction action = t;
    return runRubyActionImpl(&action);
}

void ArchiveBase::finishRubyAction()
{
    runRubyActionImpl(&ACTION_END);
}

void ArchiveBase::mark()
{
    rb_gc_mark(m_self);
    m_action_result.mark();
}

void ArchiveBase::prepareAction()
{
    m_action_result.clear();
}

void ArchiveBase::terminateEventLoopThread()
{
    runNativeFuncProtect([&](){
        finishRubyAction();
    }, [&](){
        // Nothing to do.
    });
}

////////////////////////////////////////////////////////////////
ArchiveReader::ArchiveReader(const GUID &format_guid)
     : m_rb_callback_proc(Qnil), m_rb_out_stream(Qnil),
       m_processing_index((UInt32)(Int32)-1), m_rb_in_stream(Qnil),
       m_format_guid(format_guid),
       m_password_specified(false),
       m_state(STATE_INITIAL)
{
    IInArchive *archive = 0;
    HRESULT ret = CreateObject(&m_format_guid, &IID_IInArchive, reinterpret_cast<void **>(&archive));
    if (ret != S_OK){
        m_state = STATE_ERROR;
        return;
    }

    m_in_archive.Attach(archive);
}

void ArchiveReader::setProcessingStream(VALUE stream, UInt32 index, Int32 askExtractMode)
{
    m_rb_out_stream = stream;
    m_processing_index = index;
    m_ask_extract_mode = askExtractMode;
}

void ArchiveReader::getProcessingStream(VALUE *stream, UInt32 *index, Int32 *askExtractMode)
{
    if (stream){
        *stream = m_rb_out_stream;
    }
    if (index){
        *index = m_processing_index;
    }
    if (askExtractMode){
        *askExtractMode = m_ask_extract_mode;
    }
}

void ArchiveReader::clearProcessingStream()
{
    setProcessingStream(Qnil, (UInt32)(Int32)-1, 0);
}

void ArchiveReader::setOperationResult(UInt32 index, Int32 result)
{
    if (index < m_test_result.size()){
        m_test_result[index] = result;
    }
}

VALUE ArchiveReader::open(VALUE in_stream, VALUE param)
{
    checkStateToBeginOperation(STATE_INITIAL);
    prepareAction();
    EventLoopThreadExecuter te(this);

    m_rb_in_stream = in_stream;
    m_rb_callback_proc = Qnil;
    m_rb_out_stream = Qnil;
    m_rb_entry_info_list.clear();

    VALUE password;
    runRubyFunction([&](){
        password = rb_hash_aref(param, ID2SYM(INTERN("password")));
    });
    if (NIL_P(password)){
//  Consistent handling of invalid or missing passwords
//  No data is returned, no exception is raised
//        m_password_specified = false;
        m_password_specified = true;
        m_password = std::string("");
    }else{
        m_password_specified = true;
        m_password = std::string(RSTRING_PTR(password), RSTRING_LEN(password));
    }

    HRESULT ret = E_FAIL;
    runNativeFunc([&](){
        ArchiveOpenCallback *callback;
        if (m_password_specified){
            callback = new ArchiveOpenCallback(this, m_password);
        }else{
            callback = new ArchiveOpenCallback(this);
        }

        CMyComPtr<IArchiveOpenCallback> callback_ptr(callback);

        InStream *stream = new InStream(m_rb_in_stream, this);
        m_in_stream = stream;
        ret = m_in_archive->Open(stream, 0, callback);
    });

    checkState(STATE_INITIAL, "Open error");
    if (ret != S_OK){
        if (m_password_specified){
            throw RubyCppUtil::RubyException("Invalid file format. open. or password is incorrect.");
        }else{
            throw RubyCppUtil::RubyException("Invalid file format. open.");
        }
    }

    m_state = STATE_OPENED;

    return Qnil;
}

VALUE ArchiveReader::close()
{
    if (m_state == STATE_CLOSED){
        return Qnil;
    }

    checkStateToBeginOperation(STATE_OPENED);
    prepareAction();
    EventLoopThreadExecuter te(this);

    runNativeFunc([&](){
        m_in_archive->Close();
    });
    std::vector<VALUE>().swap(m_rb_entry_info_list);

    checkState(STATE_OPENED, "Close error");
    m_state = STATE_CLOSED;

    return Qnil;
}

VALUE ArchiveReader::entryNum()
{
    checkStateToBeginOperation(STATE_OPENED);
    prepareAction();
    EventLoopThreadExecuter te(this);

    UInt32 num;
    runNativeFunc([&](){
        HRESULT ret = m_in_archive->GetNumberOfItems(&num);
        if (ret != S_OK){
            num = 0xFFFFFFFF;
        }
    });

    checkState(STATE_OPENED, "entryNum error");

    return ULONG2NUM(num);
}

VALUE ArchiveReader::getArchiveProperty()
{
    checkStateToBeginOperation(STATE_OPENED);
    prepareAction();
    EventLoopThreadExecuter te(this);

    struct PropIdVarTypePair
    {
        PROPID prop_id;
        VARTYPE vt;
    };
    PropIdVarTypePair list[] = {
        { kpidMethod, VT_BSTR },
        { kpidSolid, VT_BOOL },
        { kpidNumBlocks, VT_UI4 },
        { kpidHeadersSize, VT_UI8 },
        { kpidPhySize, VT_UI8 }
    };

    const unsigned int size = sizeof(list)/sizeof(list[0]);

    NWindows::NCOM::CPropVariant variant_list[size];
    runNativeFunc([&](){
        for (unsigned int i=0; i<size; i++){
            HRESULT ret = m_in_archive->GetArchiveProperty(list[i].prop_id, &variant_list[i]);
            if (ret != S_OK || variant_list[i].vt != list[i].vt){
                variant_list[i].Clear();
            }
        }
    });

    checkState(STATE_OPENED, "getArchiveProperty error");

    VALUE ret;
    VALUE value_list[size];
    runRubyFunction([&](){
        VALUE archive_info = rb_const_get(gSevenZipModule, INTERN("ArchiveInfo"));
        ID new_id = INTERN("new");
        for (unsigned int i=0; i<size; i++){
            value_list[i] = ConvertPropToValue(variant_list[i]);
        }
        ret = rb_funcall2(archive_info, new_id, size, value_list);
    });
    return ret;
}

VALUE ArchiveReader::getEntryInfo(VALUE index)
{
    checkStateToBeginOperation(STATE_OPENED);
    prepareAction();
    EventLoopThreadExecuter te(this);

    fillEntryInfo();

    checkState(STATE_OPENED, "getEntryInfo error");

    UInt32 idx;
    runRubyFunction([&](){
        idx = NUM2ULONG(index);
    });
    return entryInfo(idx);
}

VALUE ArchiveReader::entryInfo(UInt32 index)
{
    if (index >= m_rb_entry_info_list.size()){
        return Qnil;
    }

    return m_rb_entry_info_list[index];
}

VALUE ArchiveReader::getAllEntryInfo()
{
    checkStateToBeginOperation(STATE_OPENED);
    prepareAction();
    EventLoopThreadExecuter te(this);

    fillEntryInfo();

    checkState(STATE_OPENED, "getAllEntryInfo error");

    VALUE ret;
    runRubyFunction([&](){
        ret = rb_ary_new4(m_rb_entry_info_list.size(), &m_rb_entry_info_list[0]);
    });
    return ret;
}

VALUE ArchiveReader::setFileAttribute(VALUE path, VALUE attrib)
{
#ifdef _WIN32
    BSTR str = ConvertStringToBstr(RSTRING_PTR(path), RSTRING_LEN(path));
    BOOL ret = ::SetFileAttributesW(str, NUM2ULONG(attrib));
    SysFreeString(str);
    return (ret ? Qtrue : Qfalse);
#else
    // TODO
    return Qtrue;
#endif
}

VALUE ArchiveReader::extract(VALUE index, VALUE callback_proc)
{
    checkStateToBeginOperation(STATE_OPENED);
    prepareAction();
    EventLoopThreadExecuter te(this);

    m_rb_callback_proc = callback_proc;

    fillEntryInfo();

    UInt32 i;
    runRubyFunction([&](){
        i = NUM2ULONG(index);
    });
    HRESULT ret;
    runNativeFunc([&](){
        ArchiveExtractCallback *extract_callback = createArchiveExtractCallback();
        CMyComPtr<IArchiveExtractCallback> callback(extract_callback);
        ret = m_in_archive->Extract(&i, 1, 0, extract_callback);
    });

    m_rb_callback_proc = Qnil;

    checkState(STATE_OPENED, "extract error");
    if (ret != S_OK){
        throw RubyCppUtil::RubyException("Invalid file format. extract");
    }

    return Qnil;
}

VALUE ArchiveReader::extractFiles(VALUE index_list, VALUE callback_proc)
{
    checkStateToBeginOperation(STATE_OPENED);
    prepareAction();
    EventLoopThreadExecuter te(this);

    m_rb_callback_proc = callback_proc;

    fillEntryInfo();

    std::vector<UInt32> list(RARRAY_LEN(index_list));
    std::transform(RARRAY_CONST_PTR(index_list), RARRAY_CONST_PTR(index_list) + RARRAY_LEN(index_list),
                   list.begin(), [](VALUE num){ return NUM2ULONG(num); });

    HRESULT ret;
    runNativeFunc([&](){
        ArchiveExtractCallback *extract_callback = createArchiveExtractCallback();
        CMyComPtr<IArchiveExtractCallback> callback(extract_callback);
        ret = m_in_archive->Extract(&list[0], list.size(), 0, extract_callback);
    });

    m_rb_callback_proc = Qnil;

    checkState(STATE_OPENED, "extractFiles error");
    if (ret != S_OK){
        throw RubyCppUtil::RubyException("Invalid file format. extractFiles");
    }

    return Qnil;
}

VALUE ArchiveReader::extractAll(VALUE callback_proc)
{
    checkStateToBeginOperation(STATE_OPENED);
    prepareAction();
    EventLoopThreadExecuter te(this);

    m_rb_callback_proc = callback_proc;

    fillEntryInfo();

    HRESULT ret;
    runNativeFunc([&](){
        ArchiveExtractCallback *extract_callback = createArchiveExtractCallback();
        CMyComPtr<IArchiveExtractCallback> callback(extract_callback);
        ret = m_in_archive->Extract(0, (UInt32)(Int32)(-1), 0, extract_callback);
    });

    m_rb_callback_proc = Qnil;

    checkState(STATE_OPENED, "extractAll error");
    if (ret != S_OK){
        throw RubyCppUtil::RubyException("Invalid file format. extractAll");
    }

    return Qnil;
}

VALUE ArchiveReader::testAll(VALUE detail)
{
    checkStateToBeginOperation(STATE_OPENED);
    prepareAction();
    EventLoopThreadExecuter te(this);

    m_rb_callback_proc = Qnil;

    UInt32 num;
    HRESULT ret;
    runNativeFunc([&](){
        ret = m_in_archive->GetNumberOfItems(&num);
    });
    checkState(STATE_OPENED, "testAll error");
    if (ret != S_OK || m_state == STATE_ERROR){
        throw RubyCppUtil::RubyException("Cannot get number of items");
    }
    m_test_result.resize(num);
    std::fill(m_test_result.begin(), m_test_result.end(), NArchive::NExtract::NOperationResult::kOK);

    runNativeFunc([&](){
        ArchiveExtractCallback *extract_callback = createArchiveExtractCallback();
        CMyComPtr<IArchiveExtractCallback> callback(extract_callback);
        ret = m_in_archive->Extract(0, (UInt32)(Int32)(-1), 1, extract_callback);
    });

    checkState(STATE_OPENED, "testAll error");
    if (ret != S_OK){
        throw RubyCppUtil::RubyException("Archive corrupted.");
    }

    if (RTEST(detail)){
        VALUE ary;
        runRubyFunction([&](){
            using namespace NArchive::NExtract::NOperationResult;

            VALUE unsupportedMethod = ID2SYM(INTERN("UnsupportedMethod"));
            VALUE dataError = ID2SYM(INTERN("DataError"));
            VALUE crcError = ID2SYM(INTERN("CrcError"));

            ary = rb_ary_new2(num);
            for (unsigned int i=0; i<m_test_result.size(); i++){
                VALUE v;
                switch(m_test_result[i]){
                  case kOK:
                    v = Qtrue;
                    break;
                  case kUnsupportedMethod:
                    v = unsupportedMethod;
                    break;
                  case kDataError:
                    v = dataError;
                    break;
                  case kCRCError:
                    v = crcError;
                    break;
                  default:
                    v = Qnil;
                    break;
                }
                rb_ary_store(ary, (long)i, v);
            }
        });
        return ary;
    }else{
        using namespace NArchive::NExtract::NOperationResult;
        return (std::find_if(m_test_result.begin(), m_test_result.end(),
                             std::bind(std::not_equal_to<Int32>(), std::placeholders::_1, kOK))
                == m_test_result.end()) ? Qtrue : Qfalse;
    }
}

ArchiveExtractCallback *ArchiveReader::createArchiveExtractCallback()
{
    ArchiveExtractCallback *extract_callback;
    if (m_password_specified){
        extract_callback = new ArchiveExtractCallback(this, m_password);
    }else{
        extract_callback = new ArchiveExtractCallback(this);
    }
    return extract_callback;
}

void ArchiveReader::fillEntryInfo()
{
    if (!m_rb_entry_info_list.empty()){
        return;
    }

    struct PropIdVarTypePair
    {
        PROPID prop_id;
        VARTYPE vt;
    };
    PropIdVarTypePair list[] = {
        { kpidPath, VT_BSTR },
        { kpidMethod, VT_BSTR },
        { kpidIsDir, VT_BOOL },
        { kpidEncrypted, VT_BOOL },
        { kpidIsAnti, VT_BOOL },
        { kpidSize, VT_UI8 },
        { kpidPackSize, VT_UI8 },
        { kpidCTime, VT_FILETIME },
        { kpidATime, VT_FILETIME },
        { kpidMTime, VT_FILETIME },
        { kpidAttrib, VT_UI4 },
        { kpidCRC, VT_UI4 }
    };

    const unsigned int size = sizeof(list)/sizeof(list[0]);

    UInt32 num;
    HRESULT ret;
    runNativeFunc([&](){
        ret = m_in_archive->GetNumberOfItems(&num);
    });
    if (ret != S_OK || m_state == STATE_ERROR){
        throw RubyCppUtil::RubyException("Cannot get number of items");
    }

    std::vector< std::array< NWindows::NCOM::CPropVariant, size > > variant_list(num);

    runNativeFunc([&](){
        for (UInt32 idx=0; idx<num; idx++){
            for (unsigned int i=0; i<size; i++){
                HRESULT ret = m_in_archive->GetProperty(idx, list[i].prop_id, &variant_list[idx][i]);
                if (ret != S_OK || variant_list[idx][i].vt != list[i].vt){
                    variant_list[idx][i].Clear();
                }
            }
        }
    });
    if (m_state == STATE_ERROR){
        throw RubyCppUtil::RubyException("Cannot get property of items");
    }

    m_rb_entry_info_list.resize(variant_list.size(), Qnil);
    VALUE value_list[size + 1];
    runRubyFunction([&](){
        VALUE entry_info = rb_const_get(gSevenZipModule, INTERN("EntryInfo"));
        ID new_id = INTERN("new");
        for (UInt32 i=0; i<m_rb_entry_info_list.size(); i++){
            value_list[0] = ULONG2NUM(i);
            for (unsigned int j=0; j<size; j++){
                value_list[j+1] = ConvertPropToValue(variant_list[i][j]);
            }
            m_rb_entry_info_list[i] = rb_funcall2(entry_info, new_id, size + 1, value_list);
        }
    });
}

void ArchiveReader::mark()
{
    rb_gc_mark(m_rb_callback_proc);
    rb_gc_mark(m_rb_out_stream);
    rb_gc_mark(m_rb_in_stream);
    std::for_each(m_rb_entry_info_list.begin(), m_rb_entry_info_list.end(), [](VALUE i){ rb_gc_mark(i); });

    ArchiveBase::mark();
}

void ArchiveReader::checkStateToBeginOperation(ArchiveReaderState expected, const std::string &msg)
{
    if (m_state != expected){
        VALUE invalid_operation_exc = rb_const_get(gSevenZipModule, INTERN("InvalidOperation"));
        throw RubyCppUtil::RubyException(rb_exc_new(invalid_operation_exc, msg.c_str(), msg.size()));
    }
}

void ArchiveReader::checkState(ArchiveReaderState expected, const std::string &msg)
{
    if (m_action_result.isError()){
        m_state = STATE_ERROR;
        if (m_action_result.hasException()){
            VALUE exc = m_action_result.exception;
            m_action_result.clear();
            throw RubyCppUtil::RubyException(exc);
        }
    }

    if (m_state != expected){
        m_state = STATE_ERROR;

        VALUE invalid_operation_exc = rb_const_get(gSevenZipModule, INTERN("InvalidOperation"));
        throw RubyCppUtil::RubyException(rb_exc_new(invalid_operation_exc, msg.c_str(), msg.size()));
    }
}

void ArchiveReader::setErrorState()
{
    m_state = STATE_ERROR;
}

////////////////////////////////////////////////////////////////
ArchiveWriter::ArchiveWriter(const GUID &format_guid)
     : m_rb_callback_proc(Qnil),
       m_rb_in_stream(Qnil),
       m_processing_index((UInt32)(Int32)-1),
       m_rb_out_stream(Qnil),
       m_format_guid(format_guid),
       m_password_specified(false),
       m_state(STATE_INITIAL)
{
    IOutArchive *archive = 0;
    HRESULT ret = CreateObject(&m_format_guid, &IID_IOutArchive, reinterpret_cast<void **>(&archive));
    if (ret != S_OK){
        m_state = STATE_ERROR;
        return;
    }

    m_out_archive.Attach(archive);
}

VALUE ArchiveWriter::open(VALUE out_stream, VALUE param)
{
    checkStateToBeginOperation(STATE_INITIAL);
    prepareAction();

    m_rb_out_stream = out_stream;
    m_rb_callback_proc = Qnil;
    m_rb_in_stream = Qnil;
    std::vector<VALUE>().swap(m_rb_update_list);

    VALUE password;
    runRubyFunction([&](){
        password = rb_hash_aref(param, ID2SYM(INTERN("password")));
    });
    if (NIL_P(password)){
        m_password_specified = false;
    }else{
        m_password_specified = true;
        m_password = std::string(RSTRING_PTR(password), RSTRING_LEN(password));
    }

    checkState(STATE_INITIAL, "Open error");
    m_state = STATE_OPENED;

    return Qnil;
}

VALUE ArchiveWriter::addItem(VALUE item)
{
    checkStateToBeginOperation(STATE_OPENED);
    prepareAction();

    m_rb_update_list.push_back(item);

    checkState(STATE_OPENED, "addItem error");

    return Qnil;
}

VALUE ArchiveWriter::compress(VALUE callback_proc)
{
    if (m_state == STATE_COMPRESSED){
        return Qnil;
    }

    checkStateToBeginOperation(STATE_OPENED);
    prepareAction();
    EventLoopThreadExecuter te(this);

    m_rb_callback_proc = callback_proc;

    HRESULT opt_ret;
    HRESULT ret;
    runNativeFunc([&](){
        CMyComPtr<ISetProperties> set;
        m_out_archive->QueryInterface(IID_ISetProperties, (void **)&set);
        opt_ret = setOption(set);
        if (opt_ret != S_OK){
            return;
        }

        ArchiveUpdateCallback *callback;
        if (m_password_specified){
            callback = new ArchiveUpdateCallback(this, m_password);
        }else{
            callback = new ArchiveUpdateCallback(this);
        }

        CMyComPtr<IOutStream> out_stream(new OutStream(m_rb_out_stream, this));
        CMyComPtr<IArchiveUpdateCallback> callback_ptr(callback);
        ret = m_out_archive->UpdateItems(out_stream, m_rb_update_list.size(), callback_ptr);
    });

    m_rb_callback_proc = Qnil;

    if (opt_ret != S_OK){
        throw RubyCppUtil::RubyException(rb_exc_new2(rb_eArgError, "Invalid option"));
    }

    checkState(STATE_OPENED, "compress error");
    if (ret != S_OK){
        throw RubyCppUtil::RubyException("UpdateItems error");
    }

    m_state = STATE_COMPRESSED;

    return Qnil;
}

VALUE ArchiveWriter::close()
{
    if (m_state == STATE_CLOSED){
        return Qnil;
    }

    checkStateToBeginOperation(STATE_OPENED, STATE_COMPRESSED);
    prepareAction();

    std::vector<VALUE>().swap(m_rb_update_list);

    checkState(STATE_OPENED, STATE_COMPRESSED, "close error");
    m_state = STATE_CLOSED;

    return Qnil;
}

VALUE ArchiveWriter::getFileAttribute(VALUE path)
{
#ifdef _WIN32
    BSTR str = ConvertStringToBstr(RSTRING_PTR(path), RSTRING_LEN(path));
    DWORD attr = ::GetFileAttributesW(str);
    SysFreeString(str);
    return ULONG2NUM(attr);
#else
    // TODO
    return Qnil;
#endif
}

void ArchiveWriter::setProcessingStream(VALUE stream, UInt32 index)
{
    m_rb_in_stream = stream;
    m_processing_index = index;
}

void ArchiveWriter::getProcessingStream(VALUE *stream, UInt32 *index)
{
    if (stream){
        *stream = m_rb_in_stream;
    }
    if (index){
        *index = m_processing_index;
    }
}

void ArchiveWriter::clearProcessingStream()
{
    setProcessingStream(Qnil, (UInt32)(Int32)(-1));
}

bool ArchiveWriter::updateItemInfo(UInt32 index, bool *new_data, bool *new_properties, UInt32 *index_in_archive)
{
    bool ret = runRubyAction([&](){
        VALUE item = m_rb_update_list[index];
        if (new_data){
            *new_data = RTEST(rb_funcall(item, INTERN("new_data?"), 0));
        }
        if (new_properties){
            *new_properties = RTEST(rb_funcall(item, INTERN("new_properties?"), 0));
        }
        if (index_in_archive){
            VALUE idx = rb_funcall(item, INTERN("index_in_archive"), 0);
            *index_in_archive = (RTEST(idx) ? NUM2ULONG(idx) : (UInt32)(Int32)(-1));
        }
    });

    return ret;
}

void ArchiveWriter::mark()
{
    rb_gc_mark(m_rb_callback_proc);
    rb_gc_mark(m_rb_in_stream);
    rb_gc_mark(m_rb_out_stream);
    std::for_each(m_rb_update_list.begin(), m_rb_update_list.end(), [](VALUE i){ rb_gc_mark(i); });

    ArchiveBase::mark();
}

void ArchiveWriter::checkStateToBeginOperation(ArchiveWriterState expected, const std::string &msg)
{
    if (m_state != expected){
        VALUE invalid_operation_exc = rb_const_get(gSevenZipModule, INTERN("InvalidOperation"));
        throw RubyCppUtil::RubyException(rb_exc_new(invalid_operation_exc, msg.c_str(), msg.size()));
    }
}

void ArchiveWriter::checkStateToBeginOperation(ArchiveWriterState expected1, ArchiveWriterState expected2,
                                               const std::string &msg)
{
    if (m_state != expected1 && m_state != expected2){
        VALUE invalid_operation_exc = rb_const_get(gSevenZipModule, INTERN("InvalidOperation"));
        throw RubyCppUtil::RubyException(rb_exc_new(invalid_operation_exc, msg.c_str(), msg.size()));
    }
}

void ArchiveWriter::checkState(ArchiveWriterState expected, const std::string &msg)
{
    if (m_action_result.isError()){
        m_state = STATE_ERROR;
        if (m_action_result.hasException()){
            VALUE exc = m_action_result.exception;
            m_action_result.clear();
            throw RubyCppUtil::RubyException(exc);
        }
    }

    if (m_state != expected){
        m_state = STATE_ERROR;

        VALUE invalid_operation_exc = rb_const_get(gSevenZipModule, INTERN("InvalidOperation"));
        throw RubyCppUtil::RubyException(rb_exc_new(invalid_operation_exc, msg.c_str(), msg.size()));
    }
}

void ArchiveWriter::checkState(ArchiveWriterState expected1, ArchiveWriterState expected2,
                               const std::string &msg)
{
    if (m_action_result.isError()){
        m_state = STATE_ERROR;
        if (m_action_result.hasException()){
            VALUE exc = m_action_result.exception;
            m_action_result.clear();
            throw RubyCppUtil::RubyException(exc);
        }
    }

    if (m_state != expected1 && m_state != expected2){
        m_state = STATE_ERROR;

        VALUE invalid_operation_exc = rb_const_get(gSevenZipModule, INTERN("InvalidOperation"));
        throw RubyCppUtil::RubyException(rb_exc_new(invalid_operation_exc, msg.c_str(), msg.size()));
    }
}

void ArchiveWriter::setErrorState()
{
    m_state = STATE_ERROR;
}

////////////////////////////////////////////////////////////////
SevenZipReader::SevenZipReader()
     : ArchiveReader(CLSID_CFormat7z)
{
}

////////////////////////////////////////////////////////////////
SevenZipWriter::SevenZipWriter()
     : ArchiveWriter(CLSID_CFormat7z),
       m_method("LZMA"),
       m_level(5),
       m_solid(true),
       m_header_compression(true),
       m_header_encryption(false),
       m_multi_threading(true)
{
}

VALUE SevenZipWriter::setMethod(VALUE method)
{
    method = rb_check_string_type(method);
    if (NIL_P(method)){
        throw RubyCppUtil::RubyException(rb_exc_new2(rb_eArgError, "method should be String"));
    }

    method = rb_funcall(method, INTERN("upcase"), 0);
    std::string str(RSTRING_PTR(method), RSTRING_LEN(method));
    const char *supported[] = {
        "LZMA", "LZMA2", "PPMD", "BZIP2", "DEFLATE", "COPY"
    };
    if (std::find(supported, supported + sizeof(supported)/sizeof(supported[0]), str)
          == supported + sizeof(supported)/sizeof(supported[0])){
        throw RubyCppUtil::RubyException(rb_exc_new2(rb_eArgError, "Invalid method specified"));
    }

    if (str == "COPY"){
        m_level = 0;
    }

    m_method = str;
    return method;
}

VALUE SevenZipWriter::method()
{
    if (m_method != "PPMD"){
        return rb_str_new(m_method.c_str(), m_method.size());
    }else{
        return rb_str_new2("PPMd");
    }
}

VALUE SevenZipWriter::setLevel(VALUE level)
{
    level = rb_check_to_integer(level, "to_int");
    if (NIL_P(level)){
        throw RubyCppUtil::RubyException(rb_exc_new2(rb_eArgError, "level should be Integer"));
    }
    UInt32 l = NUM2ULONG(level);
    switch(l){
      case 0:
        m_method = "COPY";
        break;
      case 1: case 3: case 5: case 7: case 9:
        break;
      default:
        throw RubyCppUtil::RubyException(rb_exc_new2(rb_eArgError, "level should be 0, 1, 3, 5, 7 or 9"));
        break;
    }
    m_level = l;
    return level;
}

VALUE SevenZipWriter::level()
{
    return ULONG2NUM(m_level);
}

VALUE SevenZipWriter::setSolid(VALUE solid)
{
    m_solid = RTEST(solid);
    return solid;
}

VALUE SevenZipWriter::solid()
{
    return (m_solid ? Qtrue : Qfalse);
}

VALUE SevenZipWriter::setHeaderCompression(VALUE header_compression)
{
    m_header_compression = RTEST(header_compression);
    return header_compression;
}

VALUE SevenZipWriter::headerCompression()
{
    return (m_header_compression ? Qtrue : Qfalse);
}

VALUE SevenZipWriter::setHeaderEncryption(VALUE header_encryption)
{
    m_header_encryption = RTEST(header_encryption);
    return header_encryption;
}

VALUE SevenZipWriter::headerEncryption()
{
    return (m_header_encryption ? Qtrue : Qfalse);
}

VALUE SevenZipWriter::setMultiThreading(VALUE multi_threading)
{
    m_multi_threading = RTEST(multi_threading);
    return multi_threading;
}

VALUE SevenZipWriter::multiThreading()
{
    return (m_multi_threading ? Qtrue : Qfalse);
}

HRESULT SevenZipWriter::setOption(ISetProperties *set)
{
    NWindows::NCOM::CPropVariant prop[6];
    const wchar_t *name[6] = { L"0", L"x", L"s", L"hc", L"he", L"mt" };
    prop[0] = m_method.c_str();
    prop[1] = m_level;
    prop[2] = m_solid;
    prop[3] = m_header_compression;
    prop[4] = m_header_encryption;
    prop[5] = m_multi_threading;

    return set->SetProperties(name, prop, sizeof(name)/sizeof(name[0]));
}

////////////////////////////////////////////////////////////////
ArchiveOpenCallback::ArchiveOpenCallback(ArchiveReader *archive)
     : m_archive(archive), m_password_specified(false)
{
}

ArchiveOpenCallback::ArchiveOpenCallback(ArchiveReader *archive, const std::string &password)
     : m_archive(archive), m_password_specified(true), m_password(password)
{
}

STDMETHODIMP ArchiveOpenCallback::SetTotal(const UInt64 *files, const UInt64 *bytes)
{
    // This function is called periodically, so use this function as a check function of interrupt.
    if (m_archive->isErrorState()){
        return E_ABORT;
    }
    return S_OK;
}

STDMETHODIMP ArchiveOpenCallback::SetCompleted(const UInt64 *files, const UInt64 *bytes)
{
    // This function is called periodically, so use this function as a check function of interrupt.
    if (m_archive->isErrorState()){
        return E_ABORT;
    }
    return S_OK;
}

STDMETHODIMP ArchiveOpenCallback::CryptoGetTextPassword(BSTR *password)
{
    if (!m_password_specified){
        return E_ABORT;
    }

    if (password){
        *password = ConvertStringToBstr(m_password);
    }
    return S_OK;
}


////////////////////////////////////////////////////////////////
ArchiveExtractCallback::ArchiveExtractCallback(ArchiveReader *archive)
     : m_archive(archive), m_password_specified(false)
{
}

ArchiveExtractCallback::ArchiveExtractCallback(ArchiveReader *archive, const std::string &password)
     : m_archive(archive), m_password_specified(true), m_password(password)
{
}

STDMETHODIMP ArchiveExtractCallback::SetTotal(UInt64 size)
{
    // This function is called periodically, so use this function as a check function of interrupt.
    if (m_archive->isErrorState()){
        return E_ABORT;
    }
    return S_OK;
}

STDMETHODIMP ArchiveExtractCallback::SetCompleted(const UInt64 *completeValue)
{
    // This function is called periodically, so use this function as a check function of interrupt.
    if (m_archive->isErrorState()){
        return E_ABORT;
    }
    return S_OK;
}

STDMETHODIMP ArchiveExtractCallback::GetStream(UInt32 index, ISequentialOutStream **outStream,
                                               Int32 askExtractMode)
{
    switch(askExtractMode){
      case NArchive::NExtract::NAskMode::kExtract:
        break;
      case NArchive::NExtract::NAskMode::kTest:
        m_archive->setProcessingStream(Qnil, index, askExtractMode);
        return S_OK;
      default:
        return S_OK;
    }

    VALUE rb_stream;
    VALUE proc = m_archive->callbackProc();
    bool ret = m_archive->runRubyAction([&](){
        rb_stream = rb_funcall(proc, INTERN("call"), 2,
                               ID2SYM(INTERN("stream")), m_archive->entryInfo(index));
        m_archive->setProcessingStream(rb_stream, index, askExtractMode);
    });
    if (!ret){
        m_archive->clearProcessingStream();
        return E_FAIL;
    }

    OutStream *stream = new OutStream(rb_stream, m_archive);
    CMyComPtr<OutStream> ptr(stream);
    *outStream = ptr.Detach();

    return S_OK;
}

STDMETHODIMP ArchiveExtractCallback::PrepareOperation(Int32 askExtractMode)
{
    return S_OK;
}

STDMETHODIMP ArchiveExtractCallback::SetOperationResult(Int32 resultOperationResult)
{
    UInt32 index;
    VALUE stream;
    Int32 askExtractMode;
    m_archive->getProcessingStream(&stream, &index, &askExtractMode);

    switch(askExtractMode){
      case NArchive::NExtract::NAskMode::kExtract:
        break;
      case NArchive::NExtract::NAskMode::kTest:
        m_archive->clearProcessingStream();
        m_archive->setOperationResult(index, resultOperationResult);
        return S_OK;
      default:
        return S_OK;
    }

    if (!NIL_P(stream)){
        VALUE proc = m_archive->callbackProc();
        bool ret = m_archive->runRubyAction([&](){
            using namespace NArchive::NExtract::NOperationResult;

            VALUE arg_hash = rb_hash_new();
            rb_hash_aset(arg_hash, ID2SYM(INTERN("info")), m_archive->entryInfo(index));
            rb_hash_aset(arg_hash, ID2SYM(INTERN("stream")), stream);
            rb_hash_aset(arg_hash, ID2SYM(INTERN("success")), (resultOperationResult == kOK ? Qtrue : Qfalse));
            rb_funcall(proc, INTERN("call"), 2, ID2SYM(INTERN("result")), arg_hash);
        });
        if (!ret){
            m_archive->clearProcessingStream();
            return E_FAIL;
        }
    }
    m_archive->clearProcessingStream();

    return S_OK;
}

STDMETHODIMP ArchiveExtractCallback::CryptoGetTextPassword(BSTR *password)
{
    if (!m_password_specified){
        return E_ABORT;
    }

    if (password){
        *password = ConvertStringToBstr(m_password);
    }
    return S_OK;
}


////////////////////////////////////////////////////////////////
ArchiveUpdateCallback::ArchiveUpdateCallback(ArchiveWriter *archive)
     : m_archive(archive), m_password_specified(false)
{
}

ArchiveUpdateCallback::ArchiveUpdateCallback(ArchiveWriter *archive, const std::string &password)
     : m_archive(archive), m_password_specified(true), m_password(password)
{
}

STDMETHODIMP ArchiveUpdateCallback::SetTotal(UInt64 size)
{
    // This function is called periodically, so use this function as a check function of interrupt.
    if (m_archive->isErrorState()){
        return E_ABORT;
    }
    return S_OK;
}

STDMETHODIMP ArchiveUpdateCallback::SetCompleted(const UInt64 *completeValue)
{
    // This function is called periodically, so use this function as a check function of interrupt.
    if (m_archive->isErrorState()){
        return E_ABORT;
    }
    return S_OK;
}

STDMETHODIMP ArchiveUpdateCallback::EnumProperties(IEnumSTATPROPSTG **enumerator)
{
    return E_NOTIMPL;
}

STDMETHODIMP ArchiveUpdateCallback::GetUpdateItemInfo(UInt32 index, Int32 *newData,
                                                      Int32 *newProperties, UInt32 *indexInArchive)
{
    bool new_data = false;
    bool new_properties = false;
    UInt32 index_in_archive = (UInt32)(Int32)(-1);

    bool ret = m_archive->updateItemInfo(index, &new_data, &new_properties, &index_in_archive);
    if (!ret){
        return E_FAIL;
    }

    if (newData){
        *newData = static_cast<Int32>(new_data);
    }
    if (newProperties){
        *newProperties = static_cast<Int32>(new_properties);
    }
    if (indexInArchive){
        *indexInArchive = index_in_archive;
    }

    return S_OK;
}

STDMETHODIMP ArchiveUpdateCallback::GetProperty(UInt32 index, PROPID propID, PROPVARIANT *value)
{
    VALUE info = m_archive->itemInfo(index);

    bool ret = m_archive->runRubyAction([&](){
        switch(propID){
          case kpidIsAnti:
            ConvertValueToProp(rb_funcall(info, INTERN("anti?"), 0), VT_BOOL, value);
            break;
          case kpidPath:
            ConvertValueToProp(rb_funcall(info, INTERN("path"), 0), VT_BSTR, value);
            break;
          case kpidIsDir:
            ConvertValueToProp(rb_funcall(info, INTERN("directory?"), 0), VT_BOOL, value);
            break;
          case kpidSize:
            ConvertValueToProp(rb_funcall(info, INTERN("size"), 0), VT_UI8, value);
            break;
          case kpidAttrib:
            ConvertValueToProp(rb_funcall(info, INTERN("attrib"), 0), VT_UI4, value);
            break;
          case kpidCTime:
            ConvertValueToProp(rb_funcall(info, INTERN("ctime"), 0), VT_FILETIME, value);
            break;
          case kpidATime:
            ConvertValueToProp(rb_funcall(info, INTERN("atime"), 0), VT_FILETIME, value);
            break;
          case kpidMTime:
            ConvertValueToProp(rb_funcall(info, INTERN("mtime"), 0), VT_FILETIME, value);
            break;
          case kpidPosixAttrib:
            ConvertValueToProp(rb_funcall(info, INTERN("posix_attrib"), 0), VT_UI4, value);
            break;
          case kpidUser:
            {
                VALUE user = rb_funcall(info, INTERN("user"), 0);
                if (RTEST(user)){
                    ConvertValueToProp(user, VT_BSTR, value);
                }
            }
            break;
          case kpidGroup:
            {
                VALUE group = rb_funcall(info, INTERN("group"), 0);
                if (RTEST(group)){
                    ConvertValueToProp(group, VT_BSTR, value);
                }
            }
            break;
          default:
            rb_warning("Unknown propID");
            break;
        }
    });
    if (!ret){
        return E_FAIL;
    }

    return S_OK;
}

STDMETHODIMP ArchiveUpdateCallback::GetStream(UInt32 index, ISequentialInStream **inStream)
{
    VALUE rb_stream;
    std::string filepath;
    VALUE proc = m_archive->callbackProc();
    bool ret = m_archive->runRubyAction([&](){
        VALUE info = m_archive->itemInfo(index);
        VALUE ret_array = rb_funcall(proc, INTERN("call"), 2, ID2SYM(INTERN("stream")), info);
        if (NIL_P(ret_array)){
            rb_stream = Qnil;
            return;
        }

        // ret_array[0]: true:  filepath
        //               false: io
        if (RTEST(rb_ary_entry(ret_array, 0))){
            rb_stream = Qnil;
            VALUE path = rb_ary_entry(ret_array, 1);
            filepath = std::string(RSTRING_PTR(path), RSTRING_LEN(path));
        }else{
            rb_stream = rb_ary_entry(ret_array, 1);
        }

        m_archive->setProcessingStream(rb_stream, index);
    });
    if (!ret){
        m_archive->clearProcessingStream();
        return E_FAIL;
    }

    if (NIL_P(rb_stream) && !(filepath.empty())){
        FileInStream *stream = new FileInStream(filepath, m_archive);
        CMyComPtr<FileInStream> ptr(stream);
        *inStream = ptr.Detach();
    }else{
        InStream *stream = new InStream(rb_stream, m_archive);
        CMyComPtr<InStream> ptr(stream);
        *inStream = ptr.Detach();
    }

    return S_OK;
}

STDMETHODIMP ArchiveUpdateCallback::SetOperationResult(Int32 operationResult)
{
    UInt32 index;
    VALUE stream;
    m_archive->getProcessingStream(&stream, &index);

    if (!NIL_P(stream)){
        VALUE proc = m_archive->callbackProc();
        bool ret = m_archive->runRubyAction([&](){
            VALUE arg_hash = rb_hash_new();
            rb_hash_aset(arg_hash, ID2SYM(INTERN("info")), m_archive->itemInfo(index));
            rb_hash_aset(arg_hash, ID2SYM(INTERN("stream")), stream);
            rb_funcall(proc, INTERN("call"), 2, ID2SYM(INTERN("result")), arg_hash);
        });
        if (!ret){
            m_archive->clearProcessingStream();
            return E_FAIL;
        }
    }
    m_archive->clearProcessingStream();

    return S_OK;
}

STDMETHODIMP ArchiveUpdateCallback::CryptoGetTextPassword2(Int32 *passwordIsDefined, BSTR *password)
{
    if (m_password_specified){
        *passwordIsDefined = 1;
        *password = ConvertStringToBstr(m_password);
    }else{
        *passwordIsDefined = 0;
    }
    return S_OK;
}


////////////////////////////////////////////////////////////////
InStream::InStream(VALUE stream, ArchiveBase *archive)
     : m_stream(stream), m_archive(archive)
{
}

STDMETHODIMP InStream::Seek(Int64 offset, UInt32 seekOrigin, UInt64 *newPosition)
{
    bool ret = m_archive->runRubyAction([&](){
        VALUE whence;
        switch(seekOrigin){
          case 0:
            whence = rb_const_get(rb_cIO, INTERN("SEEK_SET"));
            break;
          case 1:
            whence = rb_const_get(rb_cIO, INTERN("SEEK_CUR"));
            break;
          case 2:
            whence = rb_const_get(rb_cIO, INTERN("SEEK_END"));
            break;
          default:
            return;
        }

        rb_funcall(m_stream, INTERN("seek"), 2, LL2NUM(offset), whence);
        if (newPosition){
            VALUE pos = rb_funcall(m_stream, INTERN("tell"), 0);
            *newPosition = NUM2ULONG(pos);
        }
    });
    if (!ret){
        return E_FAIL;
    }

    return S_OK;
}

STDMETHODIMP InStream::Read(void *data, UInt32 size, UInt32 *processedSize)
{
    bool ret = m_archive->runRubyAction([&](){
        VALUE str = rb_funcall(m_stream, INTERN("read"), 1, ULONG2NUM(size));
        if (!NIL_P(str) && data){
            memcpy(data, RSTRING_PTR(str), RSTRING_LEN(str));
        }

        if (processedSize){
            *processedSize = (NIL_P(str) ? 0 : RSTRING_LEN(str));
        }
    });
    if (!ret){
        if (processedSize){
            *processedSize = 0;
        }
        return E_FAIL;
    }

    return S_OK;
}

////////////////////////////////////////////////////////////////
FileInStream::FileInStream(const std::string  &filename, ArchiveBase *archive)
     : m_archive(archive)
#ifdef USE_WIN32_FILE_API
     , m_file_handle(INVALID_HANDLE_VALUE)
#else
     , m_file(filename.c_str(), std::ios::binary)
#endif
{
#ifdef USE_WIN32_FILE_API
    BSTR name = ConvertStringToBstr(filename);
    m_file_handle = CreateFileW(name, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING,
                                FILE_ATTRIBUTE_NORMAL, NULL);
    SysFreeString(name);
#else
    // Nothing to do
#endif
}

FileInStream::~FileInStream()
{
#ifdef USE_WIN32_FILE_API
    if (m_file_handle == INVALID_HANDLE_VALUE){
        return;
    }

    CloseHandle(m_file_handle);
    m_file_handle = INVALID_HANDLE_VALUE;
#else
    // Nothing to do
#endif
}

STDMETHODIMP FileInStream::Seek(Int64 offset, UInt32 seekOrigin, UInt64 *newPosition)
{
#ifdef USE_WIN32_FILE_API
    if (m_file_handle == INVALID_HANDLE_VALUE){
        return E_FAIL;
    }

    DWORD method;
    switch(seekOrigin){
      case 0:
        method = FILE_BEGIN;
        break;
      case 1:
        method = FILE_CURRENT;
        break;
      case 2:
        method = FILE_END;
        break;
      default:
        return E_FAIL;
    }

    DWORD low, high;
    low = (DWORD)(offset & 0xFFFFFFFFUL);
    high = (DWORD)((offset >> 32) & 0xFFFFFFFFUL);
    DWORD new_low = SetFilePointer(m_file_handle, (LONG)low, (PLONG)&high, method);

    if (newPosition){
        *newPosition = (((UInt64)high) << 32) + ((UInt64)new_low);
    }
    return S_OK;
#else
    if (!m_file.is_open()){
        return E_FAIL;
    }

    std::ios::seekdir method;
    switch(seekOrigin){
      case 0:
        method = std::ios::beg;
        break;
      case 1:
        method = std::ios::cur;
        break;
      case 2:
        method = std::ios::end;
        break;
      default:
        return E_FAIL;
    }

    std::streamoff sto = offset;
    m_file.seekg(sto, method);
    if (newPosition){
        *newPosition = m_file.tellg();
    }
    return S_OK;
#endif
}

STDMETHODIMP FileInStream::Read(void *data, UInt32 size, UInt32 *processedSize)
{
#ifdef USE_WIN32_FILE_API
    if (m_file_handle == INVALID_HANDLE_VALUE){
        return E_FAIL;
    }

    DWORD processed_size;
    BOOL ret = ReadFile(m_file_handle, data, size, &processed_size, NULL);
    if (!ret){
        return E_FAIL;
    }

    if (processedSize){
        *processedSize = processed_size;
    }

    return S_OK;
#else
    if (!m_file.is_open()){
        return E_FAIL;
    }

    m_file.read(reinterpret_cast<char*>(data), size);
    if (processedSize){
        *processedSize = m_file.gcount();
    }
    return S_OK;
#endif
}

////////////////////////////////////////////////////////////////
OutStream::OutStream(VALUE stream, ArchiveBase *archive)
     : m_stream(stream), m_archive(archive)
{
}

STDMETHODIMP OutStream::Write(const void *data, UInt32 size, UInt32 *processedSize)
{
    bool ret = m_archive->runRubyAction([&](){
        VALUE str = rb_str_new(reinterpret_cast<const char*>(data), size);
        VALUE len = rb_funcall(m_stream, INTERN("write"), 1, str);
        if (processedSize){
            if (NIL_P(len)){
                *processedSize = 0;
            }else{
                *processedSize = NUM2ULONG(len);
            }
        }
    });
    if (!ret){
        if (processedSize){
            *processedSize = 0;
        }
        // When killEventLoopThread is called in cancelAction
        // return S_OK even if error occurs.
        //
        // Detail:
        //  It seems that BZip2Encoder has a bug.
        //  If Write method returns E_FAIL, some Events are not set in that file
        //  because OutBuffer throws an exception in Encoder->WriteBytes.
        return E_FAIL;
    }

    return S_OK;
}

STDMETHODIMP OutStream::Seek(Int64 offset, UInt32 seekOrigin, UInt64 *newPosition)
{
    bool ret = m_archive->runRubyAction([&](){
        VALUE whence;
        switch(seekOrigin){
          case 0:
            whence = rb_const_get(rb_cIO, INTERN("SEEK_SET"));
            break;
          case 1:
            whence = rb_const_get(rb_cIO, INTERN("SEEK_CUR"));
            break;
          case 2:
            whence = rb_const_get(rb_cIO, INTERN("SEEK_END"));
            break;
          default:
            return;
        }

        rb_funcall(m_stream, INTERN("seek"), 2, LL2NUM(offset), whence);
        if (newPosition){
            VALUE pos = rb_funcall(m_stream, INTERN("tell"), 0);
            *newPosition = NUM2ULONG(pos);
        }
    });
    if (!ret){
        return E_FAIL;
    }

    return S_OK;
}

STDMETHODIMP OutStream::SetSize(UInt64 size)
{
    bool ret = m_archive->runRubyAction([&](){
        rb_funcall(m_stream, INTERN("truncate"), 1, ULL2NUM(size));
    });
    if (!ret){
        return E_FAIL;
    }

    return S_OK;
}

}

#ifdef _WIN32
#include "Shlwapi.h"
static HINSTANCE gDllInstance = NULL;

BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpReserved)
{
    // Perform actions based on the reason for calling.
    switch( fdwReason )
    {
        case DLL_PROCESS_ATTACH:
            gDllInstance = hinstDLL;
            break;
        case DLL_PROCESS_DETACH:
            gDllInstance = NULL;
            break;
    }
    return TRUE;
}
#endif

extern "C" void Init_seven_zip_archive(void)
{
    using namespace SevenZip;
    using namespace RubyCppUtil;

    VALUE mod = rb_define_module("SevenZipRuby");
    gSevenZipModule = mod;

    VALUE external_lib_dir = rb_const_get(mod, INTERN("EXTERNAL_LIB_DIR"));
    if (!RB_TYPE_P(external_lib_dir, RUBY_T_STRING)) {
        rb_warning("EXTERNAL_LIB_DIR should be String object.");
        return;
    }
    std::string external_lib_dir_str(RSTRING_PTR(external_lib_dir), RSTRING_LEN(external_lib_dir));

#ifdef _WIN32
    WCHAR modulePath[MAX_PATH];
    GetModuleFileNameW(gDllInstance, modulePath, _countof(modulePath));

    SetDllDirectory("");

    PathRemoveFileSpecW(modulePath);
    PathAppendW(modulePath, L"7z.dll");
    gSevenZipHandle = LoadLibraryW(modulePath);
    if (!gSevenZipHandle){
        PathRemoveFileSpecW(modulePath);
        PathAppendW(modulePath, L"7z64.dll");
        gSevenZipHandle = LoadLibraryW(modulePath);
    }
#else
    Dl_info dl_info;
    dladdr(reinterpret_cast<void*>(Init_seven_zip_archive), &dl_info);
    std::string dll_path = external_lib_dir_str + "/7z.so";
    gSevenZipHandle = dlopen(dll_path.c_str(), RTLD_NOW);
#endif
    if (!gSevenZipHandle){
        rb_warning("7z library is not found.");
        return;
    }

#ifdef _WIN32
    CreateObject = (CreateObjectFunc)GetProcAddress(gSevenZipHandle, "CreateObject");
#else
    CreateObject = (CreateObjectFunc)dlsym(gSevenZipHandle, "CreateObject");
#endif
    if (!CreateObject){
        rb_warning("CreateObject is not found.");
        return;
    }


    VALUE cls;

// arg_count is needed by MSVC 2010...
// MSVC 2010 seems not to be able to guess argument count of the function passed as a template parameter.
#define READER_FUNC(func, arg_count) wrappedFunction##arg_count<SevenZipReader, ArchiveReader, &ArchiveReader::func>

    cls = rb_define_wrapped_cpp_class_under<SevenZipReader>(mod, "SevenZipReader", rb_cObject);
    rb_define_method_ext(cls, "open_impl", READER_FUNC(open, 2));
    rb_define_method_ext(cls, "close_impl", READER_FUNC(close, 0));
    rb_define_method_ext(cls, "entry_num", READER_FUNC(entryNum, 0));
    rb_define_method_ext(cls, "extract_impl", READER_FUNC(extract, 2));
    rb_define_method_ext(cls, "extract_files_impl", READER_FUNC(extractFiles, 2));
    rb_define_method_ext(cls, "extract_all_impl", READER_FUNC(extractAll, 1));
    rb_define_method_ext(cls, "test_all_impl", READER_FUNC(testAll, 1));
    rb_define_method_ext(cls, "archive_property", READER_FUNC(getArchiveProperty, 0));
    rb_define_method_ext(cls, "entry", READER_FUNC(getEntryInfo, 1));
    rb_define_method_ext(cls, "entries", READER_FUNC(getAllEntryInfo, 0));
    rb_define_method_ext(cls, "set_file_attribute", READER_FUNC(setFileAttribute, 2));

#undef READER_FUNC


// arg_count is needed by MSVC 2010...
// MSVC 2010 seems not to be able to guess argument count of the function passed as a template parameter.
#define WRITER_FUNC(func, arg_count) wrappedFunction##arg_count<SevenZipWriter, ArchiveWriter, &ArchiveWriter::func>
#define WRITER_FUNC2(func, arg_count) wrappedFunction##arg_count<SevenZipWriter, &SevenZipWriter::func>

    cls = rb_define_wrapped_cpp_class_under<SevenZipWriter>(mod, "SevenZipWriter", rb_cObject);
    rb_define_method_ext(cls, "open_impl", WRITER_FUNC(open, 2));
    rb_define_method_ext(cls, "add_item", WRITER_FUNC(addItem, 1));
    rb_define_method_ext(cls, "compress_impl", WRITER_FUNC(compress, 1));
    rb_define_method_ext(cls, "close_impl", WRITER_FUNC(close, 0));
    rb_define_method_ext(cls, "get_file_attribute", WRITER_FUNC(getFileAttribute, 1));

    rb_define_method_ext(cls, "method=", WRITER_FUNC2(setMethod, 1));
    rb_define_method_ext(cls, "method", WRITER_FUNC2(method, 0));
    rb_define_method_ext(cls, "level=", WRITER_FUNC2(setLevel, 1));
    rb_define_method_ext(cls, "level", WRITER_FUNC2(level, 0));
    rb_define_method_ext(cls, "solid=", WRITER_FUNC2(setSolid, 1));
    rb_define_method_ext(cls, "solid", WRITER_FUNC2(solid, 0));
    rb_define_method_ext(cls, "solid?", WRITER_FUNC2(solid, 0));
    rb_define_method_ext(cls, "header_compression=", WRITER_FUNC2(setHeaderCompression, 1));
    rb_define_method_ext(cls, "header_compression", WRITER_FUNC2(headerCompression, 0));
    rb_define_method_ext(cls, "header_compression?", WRITER_FUNC2(headerCompression, 0));
    rb_define_method_ext(cls, "header_encryption=", WRITER_FUNC2(setHeaderEncryption, 1));
    rb_define_method_ext(cls, "header_encryption", WRITER_FUNC2(headerEncryption, 0));
    rb_define_method_ext(cls, "header_encryption?", WRITER_FUNC2(headerEncryption, 0));
    rb_define_method_ext(cls, "multi_threading=", WRITER_FUNC2(setMultiThreading, 1));
    rb_define_method_ext(cls, "multi_thread=", WRITER_FUNC2(setMultiThreading, 1));
    rb_define_method_ext(cls, "multi_threading", WRITER_FUNC2(multiThreading, 0));
    rb_define_method_ext(cls, "multi_threading?", WRITER_FUNC2(multiThreading, 0));
    rb_define_method_ext(cls, "multi_thread", WRITER_FUNC2(multiThreading, 0));
    rb_define_method_ext(cls, "multi_thread?", WRITER_FUNC2(multiThreading, 0));

#undef WRITER_FUNC2
#undef WRITER_FUNC

}
