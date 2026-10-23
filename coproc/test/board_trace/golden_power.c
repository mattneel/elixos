/*
 * The power golden trace: LilyGO's Linux power-key driver's register code
 * (LT-BSP 0064-input-k230-pmu-pwrkey.patch lines 90-583, pinned in
 * vendor.lock; run.sh extracts them as pmu_pwrkey.inc) compiled on the
 * build host against the register model and the PMU model, run as Linux
 * would run it: probe (hw_init), the interrupt handler with nothing
 * pending, a key press, the handler, a release, the handler, power-off.
 *
 *   golden_power <trace-file>
 *
 * The trace is the register model's (every PMU access and delay).
 */
#include <stdio.h>

#include "k230_mmio_mock.h"
#include "pmu_linux.h"
#include "pmu_model.h"

#include "pmu_pwrkey.inc"

static int reports[4];
static int reported;

void golden_report_key(int pressed)
{
    if (reported < 4) {
        reports[reported] = pressed;
    }
    reported++;
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: golden_power <trace-file>\n");
        return 2;
    }
    mock_reset(&mock_nominal);
    pmu_model_attach();

    struct k230_pmu_pwrkey pwrkey = { 0 };
    pwrkey.base = (void *) (uintptr_t) 0x91000000u;
    pwrkey.pwr_base = (void *) (uintptr_t) 0x91103000u;
    k230_pmu_pwrkey_hw_init(&pwrkey);
    irqreturn_t idle = k230_pmu_pwrkey_irq(175, &pwrkey);
    pmu_model_key(1);
    (void) k230_pmu_pwrkey_irq(175, &pwrkey);
    pmu_model_key(0);
    (void) k230_pmu_pwrkey_irq(175, &pwrkey);
    struct sys_off_data off = { .cb_data = &pwrkey };
    (void) k230_pmu_pwrkey_power_off(&off);

    printf("golden power: idle %s, reports %d (%d %d), supply %s\n", idle == IRQ_NONE ? "none" : "handled",
           reported, reports[0], reports[1], pmu_model_cut() ? "cut" : "on");
    if (idle != IRQ_NONE || reported != 2 || reports[0] != 1 || reports[1] != 0 || !pmu_model_cut()) {
        fprintf(stderr, "golden power: the vendor code behaved differently\n");
        return 1;
    }
    return mock_write_trace(argv[1]) == 0 ? 0 : 1;
}
