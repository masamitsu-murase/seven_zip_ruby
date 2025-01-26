
#include "utils.h"

#define INTERN(const_str) rb_intern2(const_str, sizeof(const_str) - 1)

////////////////////////////////////////////////////////////////

// begin import CPP/Common/MyWindows.cpp

#ifndef _WIN32
static inline void *AllocateForBSTR(size_t cb) { return ::malloc(cb); }
static inline void FreeForBSTR(void *pv) { ::free(pv);}

#if 0
static UINT MyStringLen(const wchar_t *s)
{
    UINT i;
    for (i = 0; s[i] != '\0'; i++);
    return i;
}
#endif

BSTR SysAllocStringLen(const OLECHAR *psz, UINT len)
{
    len = sizeof(wchar_t) * len;

    // FIXED int realLen = len + sizeof(UINT) + 3;
    const int LEN_ADDON = sizeof(wchar_t) - 1;
    int realLen = len + sizeof(UINT) + sizeof(wchar_t) + LEN_ADDON;
    void *p = AllocateForBSTR(realLen);
    if (p == 0)
        return 0;
    *(UINT *)p = len;
    // "void *" instead of "BSTR" to avoid unaligned copy of "wchar_t" because of optimizer on Solaris
    void * bstr = (void *)((UINT *)p + 1);
    if (psz) memmove(bstr, psz, len); // psz does not always have "wchar_t" alignment.
    void *pb = (void *)(((Byte *)bstr) + len);
    memset(pb,0,sizeof(wchar_t) + LEN_ADDON);
    return (BSTR)bstr;
}

BSTR SysAllocStringByteLen(LPCSTR psz, UINT len)
{
    // FIXED int realLen = len + sizeof(UINT) + 3;
    const int LEN_ADDON = sizeof(wchar_t) - 1;
    int realLen = len + sizeof(UINT) + sizeof(wchar_t) + LEN_ADDON;
    void *p = AllocateForBSTR(realLen);
    if (p == 0)
        return 0;
    *(UINT *)p = len;
    // "void *" instead of "BSTR" to avoid unaligned copy of "wchar_t" because of optimizer on Solaris
    void * bstr = (void *)((UINT *)p + 1);
    if (psz) memmove(bstr, psz, len); // psz does not always have "wchar_t" alignment.
    void *pb = (void *)(((Byte *)bstr) + len);
    memset(pb,0,sizeof(wchar_t) + LEN_ADDON);
    return (BSTR)bstr;
}

BSTR SysAllocString(const OLECHAR *sz)
{
    if (sz == 0)
        return 0;
    UINT strLen = MyStringLen(sz);
    UINT len = (strLen + 1) * sizeof(OLECHAR);
    void *p = AllocateForBSTR(len + sizeof(UINT));
    if (p == 0)
        return 0;
    *(UINT *)p = strLen * sizeof(OLECHAR); // FIXED
    void * bstr = (void *)((UINT *)p + 1);
    memmove(bstr, sz, len); // sz does not always have "wchar_t" alignment.
    return (BSTR)bstr;
}

void SysFreeString(BSTR bstr)
{
    if (bstr != 0)
        FreeForBSTR((UINT *)bstr - 1);
}

UINT SysStringByteLen(BSTR bstr)
{
    if (bstr == 0)
        return 0;
    return *((UINT *)bstr - 1);
}

UINT SysStringLen(BSTR bstr)
{
    return SysStringByteLen(bstr) / sizeof(OLECHAR);
}

// end import CPP/Common/MyWindows.cpp

// begin import CPP/Common/UTFConvert.cpp

#ifdef _WIN32
#define _WCHART_IS_16BIT 1
#endif

/*
  _UTF8_START(n) - is a base value for start byte (head), if there are (n) additional bytes after start byte

  n : _UTF8_START(n) : Bits of code point

  0 : 0x80 :    : unused
  1 : 0xC0 : 11 :
  2 : 0xE0 : 16 : Basic Multilingual Plane
  3 : 0xF0 : 21 : Unicode space
  3 : 0xF8 : 26 :
  5 : 0xFC : 31 : UCS-4
  6 : 0xFE : 36 : We can use it, if we want to encode any 32-bit value
  7 : 0xFF :
*/

#define _UTF8_START(n) (0x100 - (1 << (7 - (n))))

#define _UTF8_HEAD_PARSE2(n) if (c < _UTF8_START((n) + 1)) { numBytes = (n); c -= _UTF8_START(n); }

#define _UTF8_HEAD_PARSE \
         _UTF8_HEAD_PARSE2(1) \
    else _UTF8_HEAD_PARSE2(2) \
    else _UTF8_HEAD_PARSE2(3) \
    else _UTF8_HEAD_PARSE2(4) \
    else _UTF8_HEAD_PARSE2(5) \

    // else _UTF8_HEAD_PARSE2(6)

#define _ERROR_UTF8 \
  { if (dest) dest[destPos] = (wchar_t)0xFFFD; destPos++; ok = false; continue; }

static bool Utf8_To_Utf16(wchar_t *dest, size_t *destLen, const char *src, const char *srcLim) throw()
{
  size_t destPos = 0;
  bool ok = true;

  for (;;)
  {
    Byte c;
    if (src == srcLim)
    {
      *destLen = destPos;
      return ok;
    }
    c = *src++;

    if (c < 0x80)
    {
      if (dest)
        dest[destPos] = (wchar_t)c;
      destPos++;
      continue;
    }
    if (c < 0xC0)
      _ERROR_UTF8

    unsigned numBytes;
    _UTF8_HEAD_PARSE
    else
      _ERROR_UTF8

    UInt32 val = c;

    do
    {
      Byte c2;
      if (src == srcLim)
        break;
      c2 = *src;
      if (c2 < 0x80 || c2 >= 0xC0)
        break;
      src++;
      val <<= 6;
      val |= (c2 - 0x80);
    }
    while (--numBytes);

    if (numBytes != 0)
      _ERROR_UTF8

    if (val < 0x10000)
    {
      if (dest)
        dest[destPos] = (wchar_t)val;
      destPos++;
    }
    else
    {
      val -= 0x10000;
      if (val >= 0x100000)
        _ERROR_UTF8
      if (dest)
      {
        dest[destPos + 0] = (wchar_t)(0xD800 + (val >> 10));
        dest[destPos + 1] = (wchar_t)(0xDC00 + (val & 0x3FF));
      }
      destPos += 2;
    }
  }
}

#define _UTF8_RANGE(n) (((UInt32)1) << ((n) * 5 + 6))

#define _UTF8_HEAD(n, val) ((char)(_UTF8_START(n) + (val >> (6 * (n)))))
#define _UTF8_CHAR(n, val) ((char)(0x80 + (((val) >> (6 * (n))) & 0x3F)))

static size_t Utf16_To_Utf8_Calc(const wchar_t *src, const wchar_t *srcLim)
{
  size_t size = srcLim - src;
  for (;;)
  {
    if (src == srcLim)
      return size;

    UInt32 val = *src++;

    if (val < 0x80)
      continue;

    if (val < _UTF8_RANGE(1))
    {
      size++;
      continue;
    }

    if (val >= 0xD800 && val < 0xDC00 && src != srcLim)
    {
      UInt32 c2 = *src;
      if (c2 >= 0xDC00 && c2 < 0xE000)
      {
        src++;
        size += 2;
        continue;
      }
    }

    #ifdef _WCHART_IS_16BIT

    size += 2;

    #else

         if (val < _UTF8_RANGE(2)) size += 2;
    else if (val < _UTF8_RANGE(3)) size += 3;
    else if (val < _UTF8_RANGE(4)) size += 4;
    else if (val < _UTF8_RANGE(5)) size += 5;
    else                           size += 6;

    #endif
  }
}

static char *Utf16_To_Utf8(char *dest, const wchar_t *src, const wchar_t *srcLim)
{
  for (;;)
  {
    if (src == srcLim)
      return dest;

    UInt32 val = *src++;

    if (val < 0x80)
    {
      *dest++ = (char)val;
      continue;
    }

    if (val < _UTF8_RANGE(1))
    {
      dest[0] = _UTF8_HEAD(1, val);
      dest[1] = _UTF8_CHAR(0, val);
      dest += 2;
      continue;
    }

    if (val >= 0xD800 && val < 0xDC00 && src != srcLim)
    {
      UInt32 c2 = *src;
      if (c2 >= 0xDC00 && c2 < 0xE000)
      {
        src++;
        val = (((val - 0xD800) << 10) | (c2 - 0xDC00)) + 0x10000;
        dest[0] = _UTF8_HEAD(3, val);
        dest[1] = _UTF8_CHAR(2, val);
        dest[2] = _UTF8_CHAR(1, val);
        dest[3] = _UTF8_CHAR(0, val);
        dest += 4;
        continue;
      }
    }

    #ifndef _WCHART_IS_16BIT
    if (val < _UTF8_RANGE(2))
    #endif
    {
      dest[0] = _UTF8_HEAD(2, val);
      dest[1] = _UTF8_CHAR(1, val);
      dest[2] = _UTF8_CHAR(0, val);
      dest += 3;
      continue;
    }

    #ifndef _WCHART_IS_16BIT

    UInt32 b;
    unsigned numBits;
         if (val < _UTF8_RANGE(3)) { numBits = 6 * 3; b = _UTF8_HEAD(3, val); }
    else if (val < _UTF8_RANGE(4)) { numBits = 6 * 4; b = _UTF8_HEAD(4, val); }
    else if (val < _UTF8_RANGE(5)) { numBits = 6 * 5; b = _UTF8_HEAD(5, val); }
    else                           { numBits = 6 * 6; b = _UTF8_START(6); }

    *dest++ = (Byte)b;

    do
    {
      numBits -= 6;
      *dest++ = (char)(0x80 + ((val >> numBits) & 0x3F));
    }
    while (numBits != 0);

    #endif
  }
}

// end import CPP/Common/UTFConvert.cpp

// begin import CPP/Common/MyWindows.cpp

HRESULT VariantClear(VARIANTARG *prop)
{
    if (prop->vt == VT_BSTR)
        SysFreeString(prop->bstrVal);
    prop->vt = VT_EMPTY;
    return S_OK;
}

HRESULT VariantCopy(VARIANTARG *dest, VARIANTARG *src)
{
    HRESULT res = ::VariantClear(dest);
    if (res != S_OK)
        return res;
    if (src->vt == VT_BSTR)
    {
        dest->bstrVal = SysAllocStringByteLen((LPCSTR)src->bstrVal,
                                              SysStringByteLen(src->bstrVal));
        if (dest->bstrVal == 0)
            return E_OUTOFMEMORY;
        dest->vt = VT_BSTR;
    }
    else
        *dest = *src;
    return S_OK;
}
#endif

// end import CPP/Common/MyWindows.cpp

////////////////////////////////////////////////////////////////

// begin import CPP/Windows/PropVariant.cpp

namespace NWindows {
namespace NCOM {

// From PropVariant.cpp

CPropVariant::CPropVariant(const PROPVARIANT &varSrc)
{
  vt = VT_EMPTY;
  InternalCopy(&varSrc);
}

CPropVariant::CPropVariant(const CPropVariant &varSrc)
{
  vt = VT_EMPTY;
  InternalCopy(&varSrc);
}

CPropVariant::CPropVariant(BSTR bstrSrc)
{
  vt = VT_EMPTY;
  *this = bstrSrc;
}

CPropVariant::CPropVariant(LPCOLESTR lpszSrc)
{
  vt = VT_EMPTY;
  *this = lpszSrc;
}

CPropVariant& CPropVariant::operator=(const CPropVariant &varSrc)
{
  InternalCopy(&varSrc);
  return *this;
}
CPropVariant& CPropVariant::operator=(const PROPVARIANT &varSrc)
{
  InternalCopy(&varSrc);
  return *this;
}

CPropVariant& CPropVariant::operator=(BSTR bstrSrc)
{
  *this = (LPCOLESTR)bstrSrc;
  return *this;
}

static const char *kMemException = "out of memory";

CPropVariant& CPropVariant::operator=(LPCOLESTR lpszSrc)
{
  InternalClear();
  vt = VT_BSTR;
  wReserved1 = 0;
  bstrVal = ::SysAllocString(lpszSrc);
  if (bstrVal == NULL && lpszSrc != NULL)
  {
    throw kMemException;
    // vt = VT_ERROR;
    // scode = E_OUTOFMEMORY;
  }
  return *this;
}


CPropVariant& CPropVariant::operator=(const char *s)
{
  InternalClear();
  vt = VT_BSTR;
  wReserved1 = 0;
  UINT len = (UINT)strlen(s);
  bstrVal = ::SysAllocStringByteLen(0, (UINT)len * sizeof(OLECHAR));
  if (bstrVal == NULL)
  {
    throw kMemException;
    // vt = VT_ERROR;
    // scode = E_OUTOFMEMORY;
  }
  else
  {
    for (UINT i = 0; i <= len; i++)
      bstrVal[i] = s[i];
  }
  return *this;
}

CPropVariant& CPropVariant::operator=(bool bSrc) throw()
{
  if (vt != VT_BOOL)
  {
    InternalClear();
    vt = VT_BOOL;
  }
  boolVal = bSrc ? VARIANT_TRUE : VARIANT_FALSE;
  return *this;
}

#define SET_PROP_FUNC(type, id, dest) \
  CPropVariant& CPropVariant::operator=(type value) throw() \
  { if (vt != id) { InternalClear(); vt = id; } \
    dest = value; return *this; }

SET_PROP_FUNC(Byte, VT_UI1, bVal)
// SET_PROP_FUNC(Int16, VT_I2, iVal)
SET_PROP_FUNC(Int32, VT_I4, lVal)
SET_PROP_FUNC(UInt32, VT_UI4, ulVal)
SET_PROP_FUNC(UInt64, VT_UI8, uhVal.QuadPart)
SET_PROP_FUNC(Int64, VT_I8, hVal.QuadPart)
SET_PROP_FUNC(const FILETIME &, VT_FILETIME, filetime)

static HRESULT MyPropVariantClear(PROPVARIANT *prop)
{
  switch(prop->vt)
  {
    case VT_EMPTY:
    case VT_UI1:
    case VT_I1:
    case VT_I2:
    case VT_UI2:
    case VT_BOOL:
    case VT_I4:
    case VT_UI4:
    case VT_R4:
    case VT_INT:
    case VT_UINT:
    case VT_ERROR:
    case VT_FILETIME:
    case VT_UI8:
    case VT_R8:
    case VT_CY:
    case VT_DATE:
      prop->vt = VT_EMPTY;
      prop->wReserved1 = 0;
      prop->wReserved2 = 0;
      prop->wReserved3 = 0;
      prop->uhVal.QuadPart = 0;
      return S_OK;
  }
  return ::VariantClear((VARIANTARG *)prop);
  // return ::PropVariantClear(prop);
  // PropVariantClear can clear VT_BLOB.
}

HRESULT CPropVariant::Clear() throw()
{
  if (vt == VT_EMPTY)
    return S_OK;
  return MyPropVariantClear(this);
}

HRESULT CPropVariant::Copy(const PROPVARIANT* pSrc) throw()
{
  ::VariantClear((tagVARIANT *)this);
  switch(pSrc->vt)
  {
    case VT_UI1:
    case VT_I1:
    case VT_I2:
    case VT_UI2:
    case VT_BOOL:
    case VT_I4:
    case VT_UI4:
    case VT_R4:
    case VT_INT:
    case VT_UINT:
    case VT_ERROR:
    case VT_FILETIME:
    case VT_UI8:
    case VT_R8:
    case VT_CY:
    case VT_DATE:
      memmove((PROPVARIANT*)this, pSrc, sizeof(PROPVARIANT));
      return S_OK;
  }
  return ::VariantCopy((tagVARIANT *)this, (tagVARIANT *)const_cast<PROPVARIANT *>(pSrc));
}


HRESULT CPropVariant::Attach(PROPVARIANT *pSrc) throw()
{
  HRESULT hr = Clear();
  if (FAILED(hr))
    return hr;
  memcpy(this, pSrc, sizeof(PROPVARIANT));
  pSrc->vt = VT_EMPTY;
  return S_OK;
}

HRESULT CPropVariant::Detach(PROPVARIANT *pDest) throw()
{
  if (pDest->vt != VT_EMPTY)
  {
    HRESULT hr = MyPropVariantClear(pDest);
    if (FAILED(hr))
      return hr;
  }
  memcpy(pDest, this, sizeof(PROPVARIANT));
  vt = VT_EMPTY;
  return S_OK;
}

HRESULT CPropVariant::InternalClear() throw()
{
  if (vt == VT_EMPTY)
    return S_OK;
  HRESULT hr = Clear();
  if (FAILED(hr))
  {
    vt = VT_ERROR;
    scode = hr;
  }
  return hr;
}

void CPropVariant::InternalCopy(const PROPVARIANT *pSrc)
{
  HRESULT hr = Copy(pSrc);
  if (FAILED(hr))
  {
    if (hr == E_OUTOFMEMORY)
      throw kMemException;
    vt = VT_ERROR;
    scode = hr;
  }
}

}
}

// end import CPP/Windows/PropVariant.cpp

VALUE ConvertBstrToString(const BSTR &bstr)
{
    const int char_count = SysStringLen(bstr);
#ifdef _WIN32
    const int len = WideCharToMultiByte(CP_UTF8, 0, bstr, char_count, NULL, 0, NULL, NULL);
    VALUE str = rb_str_new(NULL, len);

    WideCharToMultiByte(CP_UTF8, 0, bstr, char_count, RSTRING_PTR(str), len, NULL, NULL);
#else
   size_t len = Utf16_To_Utf8_Calc(bstr, bstr + char_count);
    VALUE str = rb_str_new(NULL, len);
    Utf16_To_Utf8(RSTRING_PTR(str), bstr, bstr + char_count);
#endif
    return str;
}

BSTR ConvertStringToBstr(const std::string &str)
{
#ifdef _WIN32
    const int len = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), str.length(), NULL, 0);
    BSTR ret = SysAllocStringLen(NULL, len);
    MultiByteToWideChar(CP_UTF8, 0, str.c_str(), str.length(), ret, len);
    return ret;
#else
    size_t len = 0;
    Utf8_To_Utf16(NULL, &len, str.c_str(), str.c_str() + str.length());
    BSTR ret = SysAllocStringLen(NULL, len);
    Utf8_To_Utf16(ret, &len, str.c_str(), str.c_str() + str.length());
    return ret;
#endif
}

BSTR ConvertStringToBstr(const char *str, int length)
{
    return ConvertStringToBstr(std::string(str, length));
}

VALUE ConvertFiletimeToTime(const FILETIME &filetime)
{
    UInt64 time = filetime.dwLowDateTime + ((UInt64)(filetime.dwHighDateTime) << 32);  // 100ns
    time -= (UInt64)((1970-1601)*365.2425) * 24 * 60 * 60 * 1000 * 1000 * 10;

    return rb_time_nano_new(time / (1000*1000*10), (time % (1000*1000*10)) * 100);
}

void ConvertTimeToFiletime(VALUE time, FILETIME *filetime)
{
    VALUE t = rb_funcall(time, INTERN("to_i"), 0);
    VALUE nsec = rb_funcall(time, INTERN("nsec"), 0);
    UInt64 value = NUM2ULL(t) * 10000000 + NUM2ULL(nsec) / 100 + 116444736000000000ULL;
    filetime->dwLowDateTime = (UInt32)value;
    filetime->dwHighDateTime = (UInt32)(value >> 32);
}

VALUE ConvertPropToValue(const PROPVARIANT &prop)
{
    switch(prop.vt){
      case VT_EMPTY:
      case VT_NULL:
        return Qnil;
      case VT_I2:
        return LONG2NUM(prop.iVal);
      case VT_I4:
        return LONG2NUM(prop.lVal);
      // case VT_R4:
      // case VT_R8:
      // case VT_CY:
      // case VT_DATE:
      case VT_BSTR:
        return ConvertBstrToString(prop.bstrVal);
      // case VT_DISPATCH:
      // case VT_ERROR:
      case VT_BOOL:
        return (prop.boolVal ? Qtrue : Qfalse);
      // case VT_VARIANT:
      // case VT_UNKNOWN:
      // case VT_DECIMAL:
      case VT_I1:
        return LONG2NUM(prop.cVal);
      case VT_UI1:
        return ULONG2NUM(prop.bVal);
      case VT_UI2:
        return ULONG2NUM(prop.uiVal);
      case VT_UI4:
        return ULONG2NUM(prop.ulVal);
      case VT_I8:
        return LL2NUM(prop.hVal.QuadPart);
      case VT_UI8:
        return ULL2NUM(prop.uhVal.QuadPart);
      // case VT_INT:
      // case VT_UINT:
      // case VT_VOID:
      // case VT_HRESULT:
      case VT_FILETIME:
        return ConvertFiletimeToTime(prop.filetime);
      default:
        rb_warning("ConvertPropToValue: Not supported prop id: %d", prop.vt);
        break;
    }
    return Qnil;
}

void ConvertValueToProp(VALUE value, VARTYPE type, PROPVARIANT *prop)
{
    NWindows::NCOM::MyPropVariantClear(prop);

    prop->vt = type;
    switch(type){
      case VT_BOOL:
        prop->boolVal = RTEST(value);
        break;
      case VT_BSTR:
        prop->bstrVal = ConvertStringToBstr(RSTRING_PTR(value), RSTRING_LEN(value));
        break;
      case VT_UI4:
        prop->ulVal = NUM2ULONG(value);
        break;
      case VT_UI8:
        prop->uhVal.QuadPart = NUM2ULL(value);
        break;
      case VT_FILETIME:
        ConvertTimeToFiletime(value, &prop->filetime);
        break;
      default:
        rb_warning("Unknown VARTYPE %d", type);
        break;
    }
}
