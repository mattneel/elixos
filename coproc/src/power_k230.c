/*
 * Elixos coprocessor firmware: the K230 PMU's power key and power-off
 * (power_k230.h).
 *
 * The register sequence is LilyGO's Linux power-key driver's (LT-BSP =
 * Xinyuan-LilyGO/T-Display-K230 @ 0ad78192,
 * k230_bsp/overlay/buildroot-overlay/linux/0064-input-k230-pmu-pwrkey.patch,
 * GPL-2.0, used as a specification; its header says it mirrors an RT-Thread
 * driver that is not in LilyGO's published RT-Smart tree):
 *   90-150    registers and values: PMU at 0x91000000, PMU isolation in
 *             PWR + 0x158 bit 5, long-press 96000 and debounce 256 ticks of
 *             32768 Hz
 *   186-199   the PMU's isolation removed before any access
 *   293-327   the runtime configuration: no event drives OUT0/OUT1, the key's
 *             edge event (bit 9) routed and detected, rising edge first
 *   474-532   probe: OUT0/OUT1 follow the software register and the
 *             interrupt logic, OUT1's register bit set; long press and
 *             debounce times; pending key events cleared
 *   405-472   on the key's event: the status masked by its routing, cleared,
 *             press on a rising-edge event (then wait for falling), release
 *             on a falling one (then wait for rising)
 *   534-583   power-off: only an INT0 long press may raise OUT0/OUT1 again,
 *             PMU_STATUS = SOC_NORMAL_PD, the software register 3 then 0
 *             (OUT0 and OUT1 dropped), 1 s for the supply to go
 * The PMU's interrupt line (PLIC 175) is never enabled here: the event
 * register is polled (as LilyGO's launcher polls it, LT-BSP
 * k230_launcher/k230_phone_ui/src/ui_hardware.c 9250-9420).
 * coproc/test/board_trace/ compiles the patch's functions against the
 * register model and checks that this file's register trace is the same.
 */
#include "board.h"
#include "k230_mmio.h"
#include "power_k230.h"

#if !defined(COPROC_K230_DEVICES)
#error "COPROC_K230_DEVICES is a build parameter (coproc/CMakeLists.txt)"
#endif

#if COPROC_K230_DEVICES

#define PMU_BASE 0x91000000u
#define PWR_BASE 0x91103000u

#define PMU_STATUS 0x3cu
#define PMU_INT0_TO_CTL 0x40u
#define PMU_INT1_TO_CTL 0x44u
#define PMU_INT0_TO_CPU 0x48u
#define PMU_INT_DETECT_EN 0x4cu
#define PMU_INT_DETECT_TYP 0x50u
#define PMU_INT_DETECT_CLR 0x54u
#define PMU_INT0_LONG_PRESS_TRIGGER_VAL 0x58u
#define PMU_INT0_LEVEL_DEBOUNCE_VAL 0x64u
#define PMU_SYSCTRL 0x78u
#define PMU_OUT_EVENT_CTRL 0xa4u
#define PMU_OUT_LOGIC_CTRL 0xa8u
#define PMU_INT_STATE 0xacu
#define PWR_PMU_ISO_CTRL 0x158u

#define SYSCTRL_CTRL_0 (1u << 0)
#define SYSCTRL_CTRL_1 (1u << 1)
#define OUT_EVENT_CTRL_0_INT_LOGIC (1u << 2)
#define OUT_EVENT_CTRL_0_INT8 (1u << 3)
#define OUT_EVENT_CTRL_0_SW_REG (1u << 4)
#define OUT_LOGIC_CTRL_1_LOGIC_AND (1u << 0)
#define OUT_LOGIC_CTRL_1_INT_LOGIC (1u << 1)
#define OUT_LOGIC_CTRL_1_INT8 (1u << 2)
#define OUT_LOGIC_CTRL_1_SW_REG (1u << 3)
#define ISO_ACCESS (1u << 5)
#define CPU_IRQ_MASK 0x0fffu
#define DET_SOURCE_MASK 0x1fffu
#define IRQ_KEY_LONG (1u << 11)
#define IRQ_KEY_SHORT (1u << 10)
#define IRQ_KEY_EDGE (1u << 9)
#define IRQ_KEY_SHUTDOWN (1u << 0)
#define IRQ_KEY_MASK (IRQ_KEY_LONG | IRQ_KEY_SHORT | IRQ_KEY_EDGE | IRQ_KEY_SHUTDOWN)
#define DET_KEY_LONG (1u << 11)
#define DET_KEY_EDGE (1u << 9)
#define CLR_KEY_LONG 0x200u
#define CLR_KEY_SHUTDOWN 0x100u
#define CLR_KEY_SHORT 0x080u
#define CLR_KEY_EDGE 0x040u
#define CLR_KEY_ALL (CLR_KEY_LONG | CLR_KEY_SHUTDOWN | CLR_KEY_SHORT | CLR_KEY_EDGE)
#define TRIGGER_MASK 0x7u
#define TRIGGER_EDGE 0x1u
#define TRIGGER_FALLING 0x2u
#define KEY_EDGE_OFFSET 16u
#define LONG_PRESS_TICKS 96000u
#define DEBOUNCE_TICKS 256u
#define STATUS_NORMAL_PD 2u

static int opened;
static int pressed;

static uint32_t pmu(uintptr_t reg)
{
    return k230_mmio_read32(PMU_BASE + reg);
}

static void set_pmu(uintptr_t reg, uint32_t value)
{
    k230_mmio_write32(PMU_BASE + reg, value);
}

static void ensure_access(void)
{
    uint32_t value = k230_mmio_read32(PWR_BASE + PWR_PMU_ISO_CTRL);
    if (value & ISO_ACCESS) {
        k230_mmio_write32(PWR_BASE + PWR_PMU_ISO_CTRL, value & ~ISO_ACCESS);
    }
}

static void set_edge(int falling)
{
    uint32_t value = pmu(PMU_INT_DETECT_TYP) & ~(TRIGGER_MASK << KEY_EDGE_OFFSET);
    value |= (falling ? (TRIGGER_EDGE | TRIGGER_FALLING) : TRIGGER_EDGE) << KEY_EDGE_OFFSET;
    set_pmu(PMU_INT_DETECT_TYP, value);
}

static uint32_t clear_mask(uint32_t status)
{
    uint32_t clear = 0;
    if (status & IRQ_KEY_LONG) {
        clear |= CLR_KEY_LONG;
    }
    if (status & IRQ_KEY_SHORT) {
        clear |= CLR_KEY_SHORT;
    }
    if (status & IRQ_KEY_EDGE) {
        clear |= CLR_KEY_EDGE;
    }
    if (status & IRQ_KEY_SHUTDOWN) {
        clear |= CLR_KEY_SHUTDOWN;
    }
    return clear;
}

/* k230_pmu_pwrkey_config_runtime (293-327). */
static void config_runtime(int clear_pending)
{
    ensure_access();
    set_pmu(PMU_INT0_TO_CTL, pmu(PMU_INT0_TO_CTL) & ~CPU_IRQ_MASK);
    set_pmu(PMU_INT1_TO_CTL, pmu(PMU_INT1_TO_CTL) & ~CPU_IRQ_MASK);
    set_pmu(PMU_INT0_TO_CPU, (pmu(PMU_INT0_TO_CPU) & ~CPU_IRQ_MASK) | IRQ_KEY_EDGE);
    set_pmu(PMU_INT_DETECT_EN, (pmu(PMU_INT_DETECT_EN) & ~DET_SOURCE_MASK) | DET_KEY_EDGE);
    set_edge(pressed);
    if (clear_pending) {
        uint32_t clear = clear_mask(IRQ_KEY_MASK);
        if (clear) {
            set_pmu(PMU_INT_DETECT_CLR, clear);
        }
    }
}

int power_k230_open(void)
{
    /* k230_pmu_pwrkey_hw_init (496-532) with init_output_state (474-494). */
    ensure_access();
    uint32_t value = pmu(PMU_OUT_EVENT_CTRL);
    value |= OUT_EVENT_CTRL_0_INT_LOGIC | OUT_EVENT_CTRL_0_SW_REG;
    value &= ~OUT_EVENT_CTRL_0_INT8;
    set_pmu(PMU_OUT_EVENT_CTRL, value);
    value = pmu(PMU_OUT_LOGIC_CTRL);
    value |= OUT_LOGIC_CTRL_1_INT_LOGIC | OUT_LOGIC_CTRL_1_SW_REG;
    value &= ~OUT_LOGIC_CTRL_1_INT8;
    value &= ~OUT_LOGIC_CTRL_1_LOGIC_AND;
    set_pmu(PMU_OUT_LOGIC_CTRL, value);
    set_pmu(PMU_SYSCTRL, pmu(PMU_SYSCTRL) | SYSCTRL_CTRL_1);

    set_pmu(PMU_INT0_LONG_PRESS_TRIGGER_VAL, LONG_PRESS_TICKS);
    set_pmu(PMU_INT0_LEVEL_DEBOUNCE_VAL, DEBOUNCE_TICKS);
    set_pmu(PMU_INT0_TO_CTL, pmu(PMU_INT0_TO_CTL) & ~IRQ_KEY_MASK);
    set_pmu(PMU_INT1_TO_CTL, pmu(PMU_INT1_TO_CTL) & ~IRQ_KEY_MASK);
    set_pmu(PMU_INT0_TO_CPU, (pmu(PMU_INT0_TO_CPU) & ~IRQ_KEY_MASK) | IRQ_KEY_EDGE);
    set_pmu(PMU_INT_DETECT_EN, (pmu(PMU_INT_DETECT_EN) & ~DET_SOURCE_MASK) | DET_KEY_EDGE);
    set_pmu(PMU_INT_DETECT_CLR, CLR_KEY_ALL);
    pressed = 0;
    config_runtime(0);
    opened = 1;
    return POWER_K230_OK;
}

/* k230_pmu_pwrkey_irq (405-472) and _report (329-338). */
int power_k230_poll(enum power_k230_key *key)
{
    if (!opened) {
        return POWER_K230_NOT_OPEN;
    }
    uint32_t raw = pmu(PMU_INT_STATE);
    uint32_t route = pmu(PMU_INT0_TO_CPU) & CPU_IRQ_MASK;
    uint32_t status = raw & route & IRQ_KEY_MASK;
    if (!status) {
        return 0;
    }
    uint32_t clear = clear_mask(status);
    if (clear) {
        set_pmu(PMU_INT_DETECT_CLR, clear);
    }
    if (!(status & IRQ_KEY_EDGE)) {
        config_runtime(1);
        return 0;
    }
    uint32_t mode = (pmu(PMU_INT_DETECT_TYP) >> KEY_EDGE_OFFSET) & TRIGGER_MASK;
    int now;
    if (mode == TRIGGER_EDGE) {
        now = 1;
        set_edge(1);
    } else if (mode == (TRIGGER_EDGE | TRIGGER_FALLING)) {
        now = 0;
        set_edge(0);
    } else {
        now = !pressed;
        set_edge(now);
    }
    if (now == pressed) {
        return 0;
    }
    pressed = now;
    *key = now ? POWER_K230_PRESSED : POWER_K230_RELEASED;
    return 1;
}

/* k230_pmu_pwrkey_power_off (555-583) with prepare_wakeup_sources
 * (534-553). */
int power_k230_off(void)
{
    ensure_access();
    set_pmu(PMU_INT0_TO_CTL, (pmu(PMU_INT0_TO_CTL) & ~CPU_IRQ_MASK) | IRQ_KEY_LONG);
    set_pmu(PMU_INT1_TO_CTL, (pmu(PMU_INT1_TO_CTL) & ~CPU_IRQ_MASK) | IRQ_KEY_LONG);
    set_pmu(PMU_INT_DETECT_EN, (pmu(PMU_INT_DETECT_EN) & ~DET_SOURCE_MASK) | DET_KEY_LONG);
    set_pmu(PMU_STATUS, STATUS_NORMAL_PD);
    set_pmu(PMU_SYSCTRL, SYSCTRL_CTRL_1 | SYSCTRL_CTRL_0);
    set_pmu(PMU_INT_DETECT_CLR, CLR_KEY_ALL);
    set_pmu(PMU_SYSCTRL, 0);
    k230_delay_us(1000000);
    return POWER_K230_STILL_ON;
}

#else

int power_k230_open(void)
{
    return POWER_K230_NO_DEVICE;
}

int power_k230_poll(enum power_k230_key *key)
{
    (void) key;
    return POWER_K230_NO_DEVICE;
}

int power_k230_off(void)
{
    return POWER_K230_NO_DEVICE;
}

#endif
