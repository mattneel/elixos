/*
 * Host test double for coproc/src/k230_mmio.h (k230_mmio_mock.h).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "k230_mmio_mock.h"

#define PHY_STATUS 0x908500b0u
#define PHY_TST_CTRL1 0x908500b8u
#define DISP_LPI_STATE 0x91103040u

const struct mock_config mock_nominal = { .phy_ready_after = 3, .fsm_done_after = 3, .power_fails = 0 };
static const struct mock_config mock_dphy_timeout = { .phy_ready_after = -1, .fsm_done_after = -1, .power_fails = 0 };

const struct mock_config *mock_scenario(const char *name)
{
    if (strcmp(name, "nominal") == 0) {
        return &mock_nominal;
    }
    if (strcmp(name, "dphy-timeout") == 0) {
        return &mock_dphy_timeout;
    }
    return NULL;
}

#define SLOTS 4096
#define DEVICES 16

static struct {
    struct mock_config config;
    uint64_t addr[SLOTS];
    uint32_t value[SLOTS];
    unsigned char used[SLOTS];
    long phy_status_reads;
    long tst_ctrl1_reads;
    struct mock_event *events;
    size_t count;
    size_t capacity;
    struct mock_device devices[DEVICES];
    size_t device_count;
    uint64_t now_us;
} mock;

void mock_attach(const struct mock_device *device)
{
    if (mock.device_count == DEVICES) {
        fprintf(stderr, "k230_mmio_mock: too many devices\n");
        exit(2);
    }
    mock.devices[mock.device_count++] = *device;
}

static const struct mock_device *device_at(uint64_t addr)
{
    for (size_t i = 0; i < mock.device_count; i++) {
        if (addr >= mock.devices[i].base && addr - mock.devices[i].base < mock.devices[i].size) {
            return &mock.devices[i];
        }
    }
    return NULL;
}

uint64_t mock_now_us(void)
{
    return mock.now_us;
}

void mock_reset(const struct mock_config *config)
{
    free(mock.events);
    memset(&mock, 0, sizeof mock);
    mock.config = *config;
}

void mock_clear_events(void)
{
    mock.count = 0;
}

static void record(char kind, uint64_t addr, uint32_t value)
{
    if (mock.count == mock.capacity) {
        mock.capacity = mock.capacity ? 2 * mock.capacity : 4096;
        mock.events = realloc(mock.events, mock.capacity * sizeof *mock.events);
        if (mock.events == NULL) {
            fprintf(stderr, "k230_mmio_mock: out of memory\n");
            exit(2);
        }
    }
    mock.events[mock.count++] = (struct mock_event) { .kind = kind, .addr = addr, .value = value };
}

static size_t slot(uint64_t addr)
{
    size_t i = (size_t) ((addr >> 2) * 2654435761u) % SLOTS;
    while (mock.used[i] && mock.addr[i] != addr) {
        i = (i + 1) % SLOTS;
    }
    if (!mock.used[i]) {
        mock.used[i] = 1;
        mock.addr[i] = addr;
        /* Reset value: a pattern, so masks that drop bits show in the trace. */
        mock.value[i] = (uint32_t) (addr * 0x9e3779b1u) ^ 0x5a3cc3a5u;
    }
    return i;
}

static int ready(long reads, long after)
{
    return after >= 0 && reads >= after;
}

uint32_t mock_peek(uint64_t addr)
{
    return mock.value[slot(addr)];
}

void k230_mmio_write32(uintptr_t addr, uint32_t value)
{
    if (addr & 3) {
        fprintf(stderr, "k230_mmio_mock: unaligned write to 0x%08llx\n", (unsigned long long) addr);
        exit(2);
    }
    mock.value[slot(addr)] = value;
    record(MOCK_WRITE, addr, value);
    const struct mock_device *device = device_at(addr);
    if (device != NULL && device->write != NULL) {
        device->write(device->ctx, addr - device->base, value);
    }
}

uint32_t k230_mmio_read32(uintptr_t addr)
{
    if (addr & 3) {
        fprintf(stderr, "k230_mmio_mock: unaligned read of 0x%08llx\n", (unsigned long long) addr);
        exit(2);
    }
    uint32_t value = mock.value[slot(addr)];
    if (addr == PHY_STATUS) {
        value = ready(++mock.phy_status_reads, mock.config.phy_ready_after) ? 0x1fbd : 0x1f00;
    } else if (addr == PHY_TST_CTRL1) {
        value = ready(++mock.tst_ctrl1_reads, mock.config.fsm_done_after) ? 0x580 : 0x500;
    } else if (addr == DISP_LPI_STATE) {
        value = mock.config.power_fails ? (value & ~2u) : (value | 2u);
    }
    const struct mock_device *device = device_at(addr);
    if (device != NULL && device->read != NULL) {
        value = device->read(device->ctx, addr - device->base, value);
    }
    record(MOCK_READ, addr, value);
    return value;
}

void k230_delay_us(uint32_t us)
{
    mock.now_us += us;
    record(MOCK_DELAY, 0, us);
}

void mock_poke(uint64_t addr, uint32_t value)
{
    mock.value[slot(addr)] = value;
}

size_t mock_event_count(void)
{
    return mock.count;
}

const struct mock_event *mock_events(void)
{
    return mock.events;
}

int mock_write_trace(const char *path)
{
    FILE *out = fopen(path, "w");
    if (out == NULL) {
        perror(path);
        return -1;
    }
    for (size_t i = 0; i < mock.count; i++) {
        const struct mock_event *e = &mock.events[i];
        if (e->kind == MOCK_DELAY) {
            fprintf(out, "D %u\n", (unsigned) e->value);
        } else {
            fprintf(out, "%c 0x%08llx 0x%08x\n", e->kind, (unsigned long long) e->addr, (unsigned) e->value);
        }
    }
    return fclose(out);
}
