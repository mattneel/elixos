/*
 * Test model of the K230 PMU (pmu_model.h).
 */
#include <string.h>

#include "k230_mmio_mock.h"
#include "pmu_model.h"

#define PMU 0x91000000u
#define PWR_ISO 0x91103158u
#define INT_DETECT_EN 0x4cu
#define INT_DETECT_TYP 0x50u
#define INT_DETECT_CLR 0x54u
#define SYSCTRL 0x78u
#define OUT_EVENT_CTRL 0xa4u
#define INT_STATE 0xacu

static struct {
    uint32_t pending;
    uint32_t out;
    int cut;
} pmu;

static void write_reg(void *ctx, uint64_t offset, uint32_t value)
{
    (void) ctx;
    if (offset == INT_DETECT_CLR) {
        if (value & 0x040u) pmu.pending &= ~(1u << 9);
        if (value & 0x080u) pmu.pending &= ~(1u << 10);
        if (value & 0x200u) pmu.pending &= ~(1u << 11);
        if (value & 0x100u) pmu.pending &= ~(1u << 0);
    } else if (offset == SYSCTRL) {
        if ((pmu.out & 1u) && !(value & 1u) && (mock_peek(PMU + OUT_EVENT_CTRL) & (1u << 4))) {
            pmu.cut = 1;
        }
        pmu.out = value;
    }
}

static uint32_t read_reg(void *ctx, uint64_t offset, uint32_t stored)
{
    (void) ctx;
    return offset == INT_STATE ? pmu.pending : stored;
}

void pmu_model_attach(void)
{
    memset(&pmu, 0, sizeof pmu);
    pmu.out = 3;
    mock_poke(PMU + SYSCTRL, 3);
    mock_poke(PWR_ISO, 1u << 5);
    struct mock_device device = { .base = PMU, .size = 0xc00, .read = read_reg, .write = write_reg, .ctx = NULL };
    mock_attach(&device);
}

void pmu_model_key(int pressed)
{
    uint32_t type = (mock_peek(PMU + INT_DETECT_TYP) >> 16) & 7u;
    if ((mock_peek(PMU + INT_DETECT_EN) & (1u << 9)) && type == (pressed ? 1u : 3u)) {
        pmu.pending |= 1u << 9;
    }
}

int pmu_model_cut(void)
{
    return pmu.cut;
}
