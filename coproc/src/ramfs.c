/*
 * Elixos coprocessor firmware: a flat RAM file system behind the POSIX calls
 * AtomVM's atomvm:posix_* NIFs make (open, read, write, close, fsync,
 * unlink, rename).
 *
 * The coprocessor runtime (os/src/elixos_coproc.erl) is the same code on the
 * Unix stand-in and here: it reads its cookie from a file, keeps its bundle
 * in a file and hands the drivers' state to the next VM in a file. The
 * payload seeds the files (payload.c); they live as long as the core runs,
 * so a deploy that ends the VM finds its bundle when main.c starts the next
 * one. Paths are plain names; there are no directories.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "hw.h"
#include "ramfs.h"

#define MAX_FILES 32
#define MAX_FDS 16
#define FIRST_FD 3

struct File
{
    char *name;
    uint8_t *data;
    size_t size;
    size_t capacity;
    unsigned opens;
    bool unlinked;
};

struct Fd
{
    struct File *file;
    size_t position;
    int flags;
};

static struct File files[MAX_FILES];
static struct Fd fds[MAX_FDS];

static struct File *lookup(const char *name)
{
    for (int i = 0; i < MAX_FILES; i++) {
        if (files[i].name && !files[i].unlinked && strcmp(files[i].name, name) == 0) {
            return &files[i];
        }
    }
    return NULL;
}

static void release(struct File *file)
{
    if (file->unlinked && file->opens == 0) {
        free(file->name);
        free(file->data);
        memset(file, 0, sizeof(*file));
    }
}

static struct File *create(const char *name)
{
    for (int i = 0; i < MAX_FILES; i++) {
        if (files[i].name == NULL) {
            files[i].name = strdup(name);
            if (files[i].name == NULL) {
                return NULL;
            }
            return &files[i];
        }
    }
    return NULL;
}

static bool reserve(struct File *file, size_t size)
{
    if (size <= file->capacity) {
        return true;
    }
    size_t capacity = file->capacity ? file->capacity : 256;
    while (capacity < size) {
        capacity *= 2;
    }
    uint8_t *data = realloc(file->data, capacity);
    if (data == NULL) {
        return false;
    }
    file->data = data;
    file->capacity = capacity;
    return true;
}

int ramfs_put(const char *name, const void *data, size_t size)
{
    struct File *file = lookup(name);
    if (file == NULL) {
        file = create(name);
    }
    if (file == NULL || !reserve(file, size)) {
        return -1;
    }
    memcpy(file->data, data, size);
    file->size = size;
    return 0;
}

static struct Fd *fd_of(int fd)
{
    if (fd < FIRST_FD || fd >= FIRST_FD + MAX_FDS || fds[fd - FIRST_FD].file == NULL) {
        return NULL;
    }
    return &fds[fd - FIRST_FD];
}

int open(const char *path, int flags, ...)
{
    struct File *file = lookup(path);
    if (file == NULL) {
        if (!(flags & O_CREAT)) {
            errno = ENOENT;
            return -1;
        }
        file = create(path);
        if (file == NULL) {
            errno = ENOSPC;
            return -1;
        }
    } else if ((flags & O_CREAT) && (flags & O_EXCL)) {
        errno = EEXIST;
        return -1;
    }
    for (int i = 0; i < MAX_FDS; i++) {
        if (fds[i].file == NULL) {
            if ((flags & O_TRUNC) && (flags & O_ACCMODE) != O_RDONLY) {
                file->size = 0;
            }
            fds[i].file = file;
            fds[i].position = (flags & O_APPEND) ? file->size : 0;
            fds[i].flags = flags;
            file->opens++;
            return FIRST_FD + i;
        }
    }
    errno = EMFILE;
    return -1;
}

int close(int fd)
{
    struct Fd *entry = fd_of(fd);
    if (entry == NULL) {
        errno = EBADF;
        return -1;
    }
    struct File *file = entry->file;
    entry->file = NULL;
    file->opens--;
    release(file);
    return 0;
}

ssize_t read(int fd, void *buf, size_t count)
{
    struct Fd *entry = fd_of(fd);
    if (entry == NULL || (entry->flags & O_ACCMODE) == O_WRONLY) {
        errno = EBADF;
        return -1;
    }
    struct File *file = entry->file;
    if (entry->position >= file->size) {
        return 0;
    }
    size_t n = file->size - entry->position;
    if (n > count) {
        n = count;
    }
    memcpy(buf, file->data + entry->position, n);
    entry->position += n;
    return (ssize_t) n;
}

ssize_t write(int fd, const void *buf, size_t count)
{
    if (fd == STDOUT_FILENO || fd == STDERR_FILENO) {
        hw_console_write(buf, count);
        return (ssize_t) count;
    }
    struct Fd *entry = fd_of(fd);
    if (entry == NULL || (entry->flags & O_ACCMODE) == O_RDONLY) {
        errno = EBADF;
        return -1;
    }
    struct File *file = entry->file;
    if (entry->flags & O_APPEND) {
        entry->position = file->size;
    }
    size_t end = entry->position + count;
    if (!reserve(file, end)) {
        errno = ENOSPC;
        return -1;
    }
    if (entry->position > file->size) {
        memset(file->data + file->size, 0, entry->position - file->size);
    }
    memcpy(file->data + entry->position, buf, count);
    entry->position = end;
    if (end > file->size) {
        file->size = end;
    }
    return (ssize_t) count;
}

off_t lseek(int fd, off_t offset, int whence)
{
    struct Fd *entry = fd_of(fd);
    if (entry == NULL) {
        errno = EBADF;
        return -1;
    }
    off_t base = whence == SEEK_SET ? 0 : whence == SEEK_CUR ? (off_t) entry->position : (off_t) entry->file->size;
    if (base + offset < 0) {
        errno = EINVAL;
        return -1;
    }
    entry->position = (size_t) (base + offset);
    return (off_t) entry->position;
}

int fsync(int fd)
{
    return fd_of(fd) ? 0 : (errno = EBADF, -1);
}

int unlink(const char *path)
{
    struct File *file = lookup(path);
    if (file == NULL) {
        errno = ENOENT;
        return -1;
    }
    file->unlinked = true;
    release(file);
    return 0;
}

int rename(const char *from, const char *to)
{
    struct File *file = lookup(from);
    if (file == NULL) {
        errno = ENOENT;
        return -1;
    }
    if (strcmp(from, to) == 0) {
        return 0;
    }
    char *name = strdup(to);
    if (name == NULL) {
        errno = ENOMEM;
        return -1;
    }
    struct File *replaced = lookup(to);
    if (replaced) {
        replaced->unlinked = true;
        release(replaced);
    }
    free(file->name);
    file->name = name;
    return 0;
}
