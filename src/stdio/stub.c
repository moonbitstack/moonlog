/*
 * Copyright 2026 Leo Cheng
 * SPDX-License-Identifier: Apache-2.0
 */

#include <moonbit.h>

#ifdef _WIN32
#include <io.h>
#else
#include <errno.h>
#include <unistd.h>
#endif

/* A console write either lands whole or reports the errno it stopped at. The
 * loop is here rather than in MoonBit because a partial write is not something
 * the caller can do anything about. */
MOONBIT_FFI_EXPORT
int32_t moonlog_stdio_write(int32_t fd, moonbit_bytes_t bytes) {
  int32_t len = Moonbit_array_length(bytes);
  int32_t done = 0;
  while (done < len) {
#ifdef _WIN32
    int32_t n = _write(fd, (const void *)(bytes + done), len - done);
#else
    ssize_t n = write(fd, (const void *)(bytes + done), (size_t)(len - done));
#endif
    if (n <= 0) {
#ifdef _WIN32
      return (int32_t) errno;
#else
      return n == 0 ? EIO : (int32_t) errno;
#endif
    }
    done += (int32_t) n;
  }
  return 0;
}

MOONBIT_FFI_EXPORT
int32_t moonlog_stdio_is_terminal(int32_t fd) {
#ifdef _WIN32
  return _isatty(fd) ? 1 : 0;
#else
  return isatty(fd) ? 1 : 0;
#endif
}
