/*
 * Stand-in for the Linux kernel API that LilyGO's power-key driver
 * (0064-input-k230-pmu-pwrkey.patch, lines 90-583 of the patch extracted by
 * run.sh) uses, for compiling its register code on the build host
 * (golden_power.c): register accesses go to the register model, locks and
 * work queues do nothing, key reports are recorded.
 */
#ifndef BOARD_TRACE_PMU_LINUX_H
#define BOARD_TRACE_PMU_LINUX_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "k230_mmio.h"

typedef uint32_t u32;
typedef int spinlock_t;
typedef enum { IRQ_NONE = 0, IRQ_HANDLED = 1 } irqreturn_t;

#define __iomem
#define BIT(n) (1u << (n))
#define readl(addr) k230_mmio_read32((uintptr_t) (addr))
#define writel(value, addr) k230_mmio_write32((uintptr_t) (addr), (uint32_t) (value))
#define mdelay(ms) k230_delay_us((uint32_t) (ms) * 1000u)

struct device {
    int unused;
};
struct input_dev {
    int unused;
};
struct work_struct {
    int unused;
};
struct delayed_work {
    struct work_struct work;
};
struct sys_off_data {
    void *cb_data;
};

#define container_of(ptr, type, member) ((type *) ((char *) (ptr) - offsetof(type, member)))
#define to_delayed_work(w) container_of(w, struct delayed_work, work)
#define spin_lock_irqsave(lock, flags) ((void) (lock), (flags) = 0)
#define spin_unlock_irqrestore(lock, flags) ((void) (lock), (void) (flags))
#define cancel_delayed_work(w) ((void) (w), false)
#define mod_delayed_work(wq, w, delay) ((void) (wq), (void) (w), (void) (delay), true)
#define msecs_to_jiffies(ms) ((unsigned long) (ms))
#define system_wq NULL
#define orderly_poweroff(force) ((void) (force))
#define dev_info(dev, ...) ((void) (dev))
#define dev_warn(dev, ...) ((void) (dev))
#define dev_emerg(dev, ...) ((void) (dev))
#define input_sync(input) ((void) (input))
#define NOTIFY_DONE 0

/* The key reports, in order (golden_power.c). */
void golden_report_key(int pressed);
#define input_report_key(input, code, value) ((void) (input), (void) (code), golden_report_key(value))

#endif
