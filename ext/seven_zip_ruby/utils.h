#ifndef UTILS_H__
#define UTILS_H__

#include <string>

#ifdef _WIN32
#include <winsock2.h>
#include <windows.h>
#include <oleauto.h>
#else
#include <windows.h>
#endif

#include <ruby.h>

#include <CPP/Common/Common.h>
#include <CPP/Windows/PropVariant.h>

VALUE ConvertBstrToString(const BSTR &bstr);
BSTR ConvertStringToBstr(const std::string &str);
BSTR ConvertStringToBstr(const char *str, int length);
VALUE ConvertFiletimeToTime(const FILETIME &filetime);
VALUE ConvertPropToValue(const PROPVARIANT &prop);
void ConvertValueToProp(VALUE value, VARTYPE type, PROPVARIANT *prop);

#endif

