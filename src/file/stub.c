/*
 * Copyright 2026 Leo Cheng
 * SPDX-License-Identifier: Apache-2.0
 *
 * The file calls a log sink cannot do without: open, write, close, rename,
 * remove, make a directory, list a directory, and the two numbers rotation
 * reads off a file. Everything that can fail returns an errno, which MoonBit
 * turns into the message the slot reports.
 */

#include <moonbit.h>

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#include <direct.h>
#include <fcntl.h>
#include <io.h>
#include <sys/stat.h>
#include <sys/types.h>
#else
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
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

static int mkdir_all(const wchar_t *path) {
  size_t len = wcslen(path);
  wchar_t *copy = (wchar_t *) malloc(sizeof(wchar_t) * (len + 1));
  if (copy == NULL) return ENOMEM;
  wcscpy(copy, path);
  for (size_t i = 3; i <= len; i++) {
    if (copy[i] == L'/' || copy[i] == L'\\' || copy[i] == 0) {
      wchar_t saved = copy[i];
      copy[i] = 0;
      if (_wmkdir(copy) != 0 && errno != EEXIST) {
        int code = errno;
        free(copy);
        return code;
      }
      copy[i] = saved;
    }
  }
  free(copy);
  return 0;
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

static int mkdir_all(const char *path) {
  size_t len = strlen(path);
  char *copy = (char *) malloc(len + 1);
  if (copy == NULL) return ENOMEM;
  memcpy(copy, path, len + 1);
  for (size_t i = 1; i <= len; i++) {
    if (copy[i] == '/' || copy[i] == 0) {
      char saved = copy[i];
      copy[i] = 0;
      if (mkdir(copy, 0777) != 0 && errno != EEXIST) {
        int code = errno;
        free(copy);
        return code;
      }
      copy[i] = saved;
    }
  }
  free(copy);
  return 0;
}

#endif

MOONBIT_FFI_EXPORT
int32_t moonlog_file_open(moonbit_bytes_t path, int32_t append, int32_t perms) {
#ifdef _WIN32
  wchar_t *p = wide_of(path);
  if (p == NULL) return -ENOMEM;
  /* `_wopen` shares nothing with a tool that wants to move the file, which is
   * exactly what an outside rotate does, so the handle comes from CreateFile
   * with delete sharing. FILE_APPEND_DATA makes every write land at the end
   * even when two processes write at once. */
  HANDLE handle = CreateFileW(
    p,
    append ? FILE_APPEND_DATA : GENERIC_WRITE,
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
    NULL,
    append ? OPEN_ALWAYS : CREATE_ALWAYS,
    FILE_ATTRIBUTE_NORMAL,
    NULL
  );
  free(p);
  if (handle == INVALID_HANDLE_VALUE) {
    DWORD code = GetLastError();
    switch (code) {
      case ERROR_FILE_NOT_FOUND:
      case ERROR_PATH_NOT_FOUND:
        return -ENOENT;
      case ERROR_ACCESS_DENIED:
      case ERROR_SHARING_VIOLATION:
      case ERROR_LOCK_VIOLATION:
        return -EACCES;
      case ERROR_DISK_FULL:
        return -ENOSPC;
      default:
        return -(int32_t)(code & 0x7fff);
    }
  }
  int fd = _open_osfhandle((intptr_t) handle, _O_WRONLY | _O_BINARY);
  if (fd < 0) {
    CloseHandle(handle);
    return -EIO;
  }
  return fd;
#else
  char *p = utf8_of(path);
  if (p == NULL) return -ENOMEM;
  int flags = O_WRONLY | O_CREAT | (append ? O_APPEND : O_TRUNC);
  int fd = open(p, flags, (mode_t) perms);
  int code = errno;
  free(p);
  return fd >= 0 ? fd : -code;
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonlog_file_write(int32_t fd, moonbit_bytes_t bytes) {
  int32_t len = Moonbit_array_length(bytes);
  int32_t done = 0;
  while (done < len) {
#ifdef _WIN32
    int32_t n = _write(fd, (const void *) (bytes + done), len - done);
#else
    ssize_t n = write(fd, (const void *) (bytes + done), (size_t) (len - done));
#endif
    if (n <= 0) {
      return n == 0 ? EIO : (int32_t) errno;
    }
    done += (int32_t) n;
  }
  return 0;
}

MOONBIT_FFI_EXPORT
void moonlog_file_close(int32_t fd) {
#ifdef _WIN32
  _close(fd);
#else
  close(fd);
#endif
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonlog_file_error(int32_t code) {
  const char *text = strerror((int) code);
  if (text == NULL) text = "unknown error";
  int32_t len = (int32_t) strlen(text);
  moonbit_bytes_t out = moonbit_make_bytes(len, 0);
  memcpy((void *) out, text, (size_t) len);
  return out;
}

MOONBIT_FFI_EXPORT
int32_t moonlog_file_rename(moonbit_bytes_t from, moonbit_bytes_t to) {
#ifdef _WIN32
  wchar_t *a = wide_of(from);
  wchar_t *b = wide_of(to);
  if (a == NULL || b == NULL) {
    free(a);
    free(b);
    return ENOMEM;
  }
  int code = 0;
  if (_wrename(a, b) != 0) {
    code = errno;
    /* Windows will not rename onto an existing name; a segment name is unique,
     * so a leftover there is stale. */
    if (code == EEXIST || code == EACCES) {
      _wremove(b);
      if (_wrename(a, b) != 0) code = errno;
      else code = 0;
    }
  }
  free(a);
  free(b);
  return code;
#else
  char *a = utf8_of(from);
  char *b = utf8_of(to);
  if (a == NULL || b == NULL) {
    free(a);
    free(b);
    return ENOMEM;
  }
  int code = 0;
  if (rename(a, b) != 0) code = errno;
  free(a);
  free(b);
  return code;
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonlog_file_remove(moonbit_bytes_t path) {
#ifdef _WIN32
  wchar_t *p = wide_of(path);
  if (p == NULL) return ENOMEM;
  int code = 0;
  if (_wremove(p) != 0) {
    code = errno;
    if (_wrmdir(p) == 0) code = 0;
  }
  free(p);
  return code;
#else
  char *p = utf8_of(path);
  if (p == NULL) return ENOMEM;
  int code = remove(p) != 0 ? errno : 0;
  free(p);
  return code;
#endif
}

MOONBIT_FFI_EXPORT
int32_t moonlog_file_mkdir(moonbit_bytes_t path) {
#ifdef _WIN32
  wchar_t *p = wide_of(path);
  if (p == NULL) return ENOMEM;
  int code = mkdir_all(p);
  free(p);
  return code;
#else
  char *p = utf8_of(path);
  if (p == NULL) return ENOMEM;
  int code = mkdir_all(p);
  free(p);
  return code;
#endif
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonlog_file_read(moonbit_bytes_t path) {
#ifdef _WIN32
  wchar_t *p = wide_of(path);
  if (p == NULL) return moonbit_make_bytes(0, 0);
  struct _stat64 info;
  if (_wstat64(p, &info) != 0 || info.st_size < 0) {
    free(p);
    return moonbit_make_bytes(0, 0);
  }
  int32_t size = (int32_t) info.st_size;
  moonbit_bytes_t out = moonbit_make_bytes(size, 0);
  FILE *f = _wfopen(p, L"rb");
  free(p);
  if (f == NULL) return moonbit_make_bytes(0, 0);
  size_t got = fread((void *) out, 1, (size_t) size, f);
  fclose(f);
  return got == (size_t) size ? out : moonbit_make_bytes(0, 0);
#else
  char *p = utf8_of(path);
  if (p == NULL) return moonbit_make_bytes(0, 0);
  struct stat info;
  if (stat(p, &info) != 0 || info.st_size < 0) {
    free(p);
    return moonbit_make_bytes(0, 0);
  }
  int32_t size = (int32_t) info.st_size;
  moonbit_bytes_t out = moonbit_make_bytes(size, 0);
  FILE *f = fopen(p, "rb");
  free(p);
  if (f == NULL) return moonbit_make_bytes(0, 0);
  size_t got = fread((void *) out, 1, (size_t) size, f);
  fclose(f);
  return got == (size_t) size ? out : moonbit_make_bytes(0, 0);
#endif
}

MOONBIT_FFI_EXPORT
int64_t moonlog_file_size(moonbit_bytes_t path) {
#ifdef _WIN32
  wchar_t *p = wide_of(path);
  if (p == NULL) return -1;
  struct _stat64 info;
  int64_t size = _wstat64(p, &info) == 0 ? (int64_t) info.st_size : -1;
  free(p);
  return size;
#else
  char *p = utf8_of(path);
  if (p == NULL) return -1;
  struct stat info;
  int64_t size = stat(p, &info) == 0 ? (int64_t) info.st_size : -1;
  free(p);
  return size;
#endif
}

MOONBIT_FFI_EXPORT
int64_t moonlog_file_mtime(moonbit_bytes_t path) {
#ifdef _WIN32
  wchar_t *p = wide_of(path);
  if (p == NULL) return -1;
  WIN32_FILE_ATTRIBUTE_DATA info;
  int64_t at = -1;
  if (GetFileAttributesExW(p, GetFileExInfoStandard, &info)) {
    ULARGE_INTEGER stamp;
    stamp.LowPart = info.ftLastWriteTime.dwLowDateTime;
    stamp.HighPart = info.ftLastWriteTime.dwHighDateTime;
    /* 100ns ticks since 1601, and the epoch is 11644473600 seconds later. */
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

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonlog_file_list(moonbit_bytes_t dir) {
  size_t cap = 1024, len = 0;
  char *names = (char *) malloc(cap);
  if (names == NULL) return moonbit_make_bytes(0, 0);
#ifdef _WIN32
  wchar_t *p = wide_of(dir);
  if (p == NULL) {
    free(names);
    return moonbit_make_bytes(0, 0);
  }
  wchar_t *pattern = (wchar_t *) malloc(sizeof(wchar_t) * (wcslen(p) + 3));
  if (pattern == NULL) {
    free(p);
    free(names);
    return moonbit_make_bytes(0, 0);
  }
  wcscpy(pattern, p);
  wcscat(pattern, L"\\*");
  WIN32_FIND_DATAW entry;
  HANDLE found = FindFirstFileW(pattern, &entry);
  if (found != INVALID_HANDLE_VALUE) {
    do {
      if (wcscmp(entry.cFileName, L".") == 0 ||
          wcscmp(entry.cFileName, L"..") == 0) {
        continue;
      }
      int need = WideCharToMultiByte(
        CP_UTF8, 0, entry.cFileName, -1, NULL, 0, NULL, NULL
      );
      if (need <= 1) continue;
      size_t room = (size_t) need - 1;
      if (len + room + 1 > cap) {
        cap = (len + room + 1) * 2;
        char *grown = (char *) realloc(names, cap);
        if (grown == NULL) break;
        names = grown;
      }
      WideCharToMultiByte(
        CP_UTF8, 0, entry.cFileName, -1, names + len, (int) room + 1, NULL, NULL
      );
      len += room;
      names[len++] = '\n';
    } while (FindNextFileW(found, &entry));
    FindClose(found);
  }
  free(pattern);
  free(p);
#else
  char *p = utf8_of(dir);
  if (p == NULL) {
    free(names);
    return moonbit_make_bytes(0, 0);
  }
  DIR *d = opendir(p);
  free(p);
  if (d == NULL) {
    free(names);
    return moonbit_make_bytes(0, 0);
  }
  struct dirent *entry;
  while ((entry = readdir(d)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }
    size_t room = strlen(entry->d_name);
    if (len + room + 1 > cap) {
      cap = (len + room + 1) * 2;
      char *grown = (char *) realloc(names, cap);
      if (grown == NULL) break;
      names = grown;
    }
    memcpy(names + len, entry->d_name, room);
    len += room;
    names[len++] = '\n';
  }
  closedir(d);
#endif
  moonbit_bytes_t out = moonbit_make_bytes((int32_t) len, 0);
  memcpy((void *) out, names, len);
  free(names);
  return out;
}
