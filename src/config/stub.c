/*
 * Copyright 2026 Leo Cheng
 * SPDX-License-Identifier: Apache-2.0
 *
 * Reading a configuration file, writing one back, and asking when it last
 * changed. Kept to three calls: a document is small, and a reload is not a
 * hot path.
 */

#include <moonbit.h>

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/stat.h>
#endif

#ifdef _WIN32

static wchar_t *wide_of(moonbit_bytes_t bytes) {
  int32_t len = Moonbit_array_length(bytes);
  int need = MultiByteToWideChar(CP_UTF8, 0, (const char *) bytes, len, NULL, 0);
  wchar_t *out = (wchar_t *) malloc(sizeof(wchar_t) * (need + 1));
  if (out == NULL) return NULL;
  MultiByteToWideChar(CP_UTF8, 0, (const char *) bytes, len, out, need);
  out[need] = 0;
  return out;
}

#else

static char *utf8_of(moonbit_bytes_t bytes) {
  int32_t len = Moonbit_array_length(bytes);
  char *out = (char *) malloc((size_t) len + 1);
  if (out == NULL) return NULL;
  memcpy(out, (const void *) bytes, (size_t) len);
  out[len] = 0;
  return out;
}

#endif

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonlog_config_read(moonbit_bytes_t path) {
#ifdef _WIN32
  wchar_t *p = wide_of(path);
  if (p == NULL) return moonbit_make_bytes(0, 0);
  FILE *f = _wfopen(p, L"rb");
  free(p);
#else
  char *p = utf8_of(path);
  if (p == NULL) return moonbit_make_bytes(0, 0);
  FILE *f = fopen(p, "rb");
  free(p);
#endif
  if (f == NULL) return moonbit_make_bytes(0, 0);
  size_t cap = 4096, len = 0;
  char *text = (char *) malloc(cap);
  if (text == NULL) {
    fclose(f);
    return moonbit_make_bytes(0, 0);
  }
  for (;;) {
    if (len + 4096 > cap) {
      cap = cap * 2;
      char *grown = (char *) realloc(text, cap);
      if (grown == NULL) {
        free(text);
        fclose(f);
        return moonbit_make_bytes(0, 0);
      }
      text = grown;
    }
    size_t got = fread(text + len, 1, 4096, f);
    len += got;
    if (got < 4096) break;
  }
  fclose(f);
  moonbit_bytes_t out = moonbit_make_bytes((int32_t) len, 0);
  memcpy((void *) out, text, len);
  free(text);
  return out;
}

MOONBIT_FFI_EXPORT
int32_t moonlog_config_write(moonbit_bytes_t path, moonbit_bytes_t text) {
  int32_t len = Moonbit_array_length(text);
#ifdef _WIN32
  wchar_t *p = wide_of(path);
  if (p == NULL) return ENOMEM;
  FILE *f = _wfopen(p, L"wb");
  free(p);
#else
  char *p = utf8_of(path);
  if (p == NULL) return ENOMEM;
  FILE *f = fopen(p, "wb");
  free(p);
#endif
  if (f == NULL) return errno == 0 ? EACCES : errno;
  size_t wrote = fwrite((const void *) text, 1, (size_t) len, f);
  int code = fclose(f) == 0 ? 0 : errno;
  if (wrote != (size_t) len && code == 0) code = EIO;
  return code;
}

MOONBIT_FFI_EXPORT
int64_t moonlog_config_mtime(moonbit_bytes_t path) {
#ifdef _WIN32
  wchar_t *p = wide_of(path);
  if (p == NULL) return -1;
  WIN32_FILE_ATTRIBUTE_DATA info;
  int64_t at = -1;
  if (GetFileAttributesExW(p, GetFileExInfoStandard, &info)) {
    ULARGE_INTEGER stamp;
    stamp.LowPart = info.ftLastWriteTime.dwLowDateTime;
    stamp.HighPart = info.ftLastWriteTime.dwHighDateTime;
    at = (int64_t) ((stamp.QuadPart - 116444736000000000ULL) * 100ULL);
  }
  free(p);
  return at;
#else
  char *p = utf8_of(path);
  if (p == NULL) return -1;
  struct stat info;
  if (stat(p, &info) != 0) {
    free(p);
    return -1;
  }
#if defined(__APPLE__)
  int64_t at =
    (int64_t) info.st_mtimespec.tv_sec * 1000000000LL + info.st_mtimespec.tv_nsec;
#else
  int64_t at =
    (int64_t) info.st_mtim.tv_sec * 1000000000LL + info.st_mtim.tv_nsec;
#endif
  free(p);
  return at;
#endif
}
