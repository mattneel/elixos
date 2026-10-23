/*
 * Elixos coprocessor firmware: the RAM file system (ramfs.c).
 */
#ifndef COPROC_RAMFS_H
#define COPROC_RAMFS_H

#include <stddef.h>

/* Creates or replaces a file with a copy of `data`; 0 or -1. */
int ramfs_put(const char *name, const void *data, size_t size);

#endif
