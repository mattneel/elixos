/*
 * Host tests of the panel port (coproc/src/panel_k230.c) against the register
 * model (k230_mmio_mock.c). Built and run by coproc/test/panel_trace/run.sh:
 *
 *   panel_k230_test                          the unit tests below
 *   panel_k230_test trace <scenario> <file>  panel_k230_open()'s register
 *                                            trace, for the comparison with
 *                                            the vendor's (golden_main.c)
 *
 * Built twice: with COPROC_PANEL_K230=1 (the board) and =0 (QEMU virt, no
 * panel). Each test runs in its own process: the port keeps its state in
 * statics, as the firmware does across VM restarts. Link with -no-pie so the
 * status buffer's address fits the VO's 32-bit address registers, as on the
 * board, and the test can read the buffer back through it.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "k230_mmio_mock.h"
#include "panel_k230.h"

#define VO 0x90840000u
#define DSI 0x90850000u

static int failures;

#define CHECK(cond)                                                                                \
    do {                                                                                           \
        if (!(cond)) {                                                                             \
            fprintf(stderr, "%s:%d: %s: check failed: %s\n", __FILE__, __LINE__, __func__, #cond); \
            exit(1);                                                                               \
        }                                                                                          \
    } while (0)

#if COPROC_PANEL_K230

static size_t count(char kind, uint64_t addr)
{
    size_t n = 0;
    for (size_t i = 0; i < mock_event_count(); i++) {
        n += mock_events()[i].kind == kind && mock_events()[i].addr == addr;
    }
    return n;
}

/* The value of the last write to addr; the test fails if there is none. */
static uint32_t last_write(uint64_t addr)
{
    for (size_t i = mock_event_count(); i-- > 0;) {
        if (mock_events()[i].kind == MOCK_WRITE && mock_events()[i].addr == addr) {
            return mock_events()[i].value;
        }
    }
    fprintf(stderr, "no write to 0x%08llx\n", (unsigned long long) addr);
    exit(1);
}

static uint64_t total_delay_us(void)
{
    uint64_t us = 0;
    for (size_t i = 0; i < mock_event_count(); i++) {
        if (mock_events()[i].kind == MOCK_DELAY) {
            us += mock_events()[i].value;
        }
    }
    return us;
}

static void open_nominal(void)
{
    mock_reset(&mock_nominal);
    CHECK(panel_k230_open() == PANEL_K230_OK);
}

static void test_open_brings_up_and_scans_out_the_region(void)
{
    open_nominal();
    const struct mock_event *e = mock_events();
    /* The display power domain first (k230_logo.c 353). */
    CHECK(e[0].kind == MOCK_READ && e[0].addr == 0x9110303c);
    CHECK(e[1].kind == MOCK_WRITE && e[1].addr == 0x9110303c && (e[1].value & 0x20002) == 0x20002);
    CHECK(e[2].kind == MOCK_DELAY && e[2].value == 500);
    CHECK(e[3].kind == MOCK_READ && e[3].addr == 0x91103040);
    /* IO35 (bank 1, bit 3), IO22 and IO25 (bank 0) end as driven-high outputs. */
    CHECK((mock_peek(0x9140c004) & (1u << 3)) && (mock_peek(0x9140c000) & (1u << 3)));
    CHECK((mock_peek(0x9140b004) & (1u << 22)) && (mock_peek(0x9140b000) & (1u << 22)));
    CHECK((mock_peek(0x9140b004) & (1u << 25)) && (mock_peek(0x9140b000) & (1u << 25)));
    /* The reset pulse: IO22 data written high, low, high. */
    CHECK(count(MOCK_WRITE, 0x9140b000) == 4);
    /* OSD4: RGB565 from the region's pixels, 568 x 1232, stride 1136 / 8. */
    CHECK(last_write(VO + 0x880) == 0x02);
    CHECK(last_write(VO + 0x884) == (568u | (1232u << 16)));
    CHECK(last_write(VO + 0x888) == 0x08101000u && last_write(VO + 0x890) == 0x08101000u);
    CHECK(last_write(VO + 0x88c) == 0x08101000u && last_write(VO + 0x894) == 0x08101000u);
    CHECK(last_write(VO + 0x89c) == 142);
    CHECK(last_write(VO + 0x828) == (40u | (607u << 16)));
    CHECK(last_write(VO + 0x82c) == (16u | (1247u << 16)));
    CHECK((mock_peek(VO + 0x118) & (3u << 8)) == (1u << 8)); /* OSD4 on, OSD5 off */
    /* No scaler coefficients (VO + 0x8000 - 0x8fff). */
    for (size_t i = 0; i < mock_event_count(); i++) {
        CHECK(!(e[i].kind == MOCK_WRITE && e[i].addr >= VO + 0x8000 && e[i].addr < VO + 0x9000));
    }
    /* The DCS list, in order, then video mode and the clock lane last. */
    static const uint32_t headers[] = {
        0x0239, 0x0239, 0x0239, 0x0539, 0x0539, 0x0539, 0x0539,
        0x1205, 0x003515, 0xfe5115, 0x1105, 0x2905, 0x773a15,
    };
    size_t h = 0;
    for (size_t i = 0; i < mock_event_count(); i++) {
        if (e[i].kind == MOCK_WRITE && e[i].addr == DSI + 0x6c) {
            CHECK(h < sizeof headers / sizeof headers[0] && e[i].value == headers[h]);
            h++;
        }
    }
    CHECK(h == sizeof headers / sizeof headers[0]);
    CHECK(last_write(DSI + 0x34) == 0); /* video mode */
    const struct mock_event *end = &e[mock_event_count() - 1];
    CHECK(end->kind == MOCK_WRITE && end->addr == DSI + 0x94 && end->value == 1);
    /* About 0.93 s of waiting, most of it the reset pulse and sleep-out. */
    CHECK(total_delay_us() > 900000 && total_delay_us() < 1000000);
}

static void test_open_runs_once(void)
{
    open_nominal();
    mock_clear_events();
    CHECK(panel_k230_open() == PANEL_K230_OK);
    CHECK(mock_event_count() == 0);
}

static void test_power_domain_failure_stops_before_the_panel(void)
{
    struct mock_config config = mock_nominal;
    config.power_fails = 1;
    mock_reset(&config);
    CHECK(panel_k230_open() == PANEL_K230_POWER_TIMEOUT);
    CHECK(mock_event_count() == 4);
    mock_clear_events();
    CHECK(panel_k230_open() == PANEL_K230_POWER_TIMEOUT);
    CHECK(mock_event_count() == 0);
    static uint8_t band[PANEL_K230_STATUS_BYTES];
    CHECK(panel_k230_status(band, sizeof band) == PANEL_K230_NOT_OPEN);
    CHECK(mock_event_count() == 0);
}

static void test_dphy_timeout_runs_the_vendor_sequence_then_fails(void)
{
    mock_reset(mock_scenario("dphy-timeout"));
    CHECK(panel_k230_open() == PANEL_K230_DPHY_TIMEOUT);
    /* PHY1's state machine: the first read, then 1000 polls 20 ms apart. */
    CHECK(count(MOCK_READ, DSI + 0xb8) == 1000);
    /* Each lane wait: 100001 reads, one more for the message; one final read. */
    CHECK(count(MOCK_READ, DSI + 0xb0) == 2 * 100002 + 1);
    /* The rest still ran: the DSI host ends in video mode. */
    const struct mock_event *end = &mock_events()[mock_event_count() - 1];
    CHECK(end->kind == MOCK_WRITE && end->addr == DSI + 0x94 && end->value == 1);
    static uint8_t band[PANEL_K230_STATUS_BYTES];
    CHECK(panel_k230_status(band, sizeof band) == PANEL_K230_NOT_OPEN);
}

static void test_status_band_is_osd5_over_rows_0_to_27(void)
{
    open_nominal();
    static uint8_t band[PANEL_K230_STATUS_BYTES];
    for (size_t i = 0; i < sizeof band; i++) {
        band[i] = (uint8_t) (i * 7 + 3);
    }
    mock_clear_events();
    CHECK(panel_k230_status(band, sizeof band) == PANEL_K230_OK);
    CHECK(last_write(VO + 0x8b0) == 0x02);
    CHECK(last_write(VO + 0x8b4) == (568u | (28u << 16)));
    CHECK(last_write(VO + 0x830) == (40u | (607u << 16)));
    CHECK(last_write(VO + 0x834) == (16u | (43u << 16)));
    CHECK(last_write(VO + 0x8cc) == 142);
    uint32_t addr = last_write(VO + 0x8b8);
    CHECK(addr != 0 && addr % 64 == 0);
    CHECK(last_write(VO + 0x8bc) == addr && last_write(VO + 0x8c0) == addr && last_write(VO + 0x8c4) == addr);
    /* The layer shows a copy: changing the caller's buffer changes nothing. */
    CHECK(memcmp((const void *) (uintptr_t) addr, band, sizeof band) == 0);
    band[0] ^= 0xff;
    CHECK(memcmp((const void *) (uintptr_t) addr, band, sizeof band) != 0);
    CHECK((mock_peek(VO + 0x118) & (3u << 8)) == (3u << 8));
    const struct mock_event *end = &mock_events()[mock_event_count() - 1];
    CHECK(end->kind == MOCK_WRITE && end->addr == VO + 0x04 && end->value == 0x11);
    CHECK(total_delay_us() == 0);

    /* Removing it turns OSD5 off and leaves the framebuffer layer on. */
    mock_clear_events();
    CHECK(panel_k230_status(NULL, 0) == PANEL_K230_OK);
    CHECK(mock_event_count() == 3);
    const struct mock_event *e = mock_events();
    CHECK(e[0].kind == MOCK_READ && e[0].addr == VO + 0x118);
    CHECK(e[1].kind == MOCK_WRITE && e[1].addr == VO + 0x118 && e[1].value == (e[0].value & ~(1u << 9)));
    CHECK(e[1].value & (1u << 8));
    CHECK(e[2].kind == MOCK_WRITE && e[2].addr == VO + 0x04 && e[2].value == 0x11);
}

static void test_status_rejects_anything_but_one_band(void)
{
    open_nominal();
    static uint8_t band[PANEL_K230_STATUS_BYTES + 2];
    mock_clear_events();
    CHECK(panel_k230_status(band, PANEL_K230_STATUS_BYTES - 2) == PANEL_K230_BADARG);
    CHECK(panel_k230_status(band, PANEL_K230_STATUS_BYTES + 2) == PANEL_K230_BADARG);
    CHECK(panel_k230_status(NULL, PANEL_K230_STATUS_BYTES) == PANEL_K230_BADARG);
    CHECK(mock_event_count() == 0);
}

#else

static void test_no_panel_build_touches_nothing(void)
{
    mock_reset(&mock_nominal);
    CHECK(panel_k230_open() == PANEL_K230_NO_PANEL);
    CHECK(panel_k230_open() == PANEL_K230_NO_PANEL);
    static uint8_t band[PANEL_K230_STATUS_BYTES];
    CHECK(panel_k230_status(band, sizeof band) == PANEL_K230_NOT_OPEN);
    CHECK(mock_event_count() == 0);
}

#endif

static void test_status_before_open(void)
{
    mock_reset(&mock_nominal);
    static uint8_t band[PANEL_K230_STATUS_BYTES];
    CHECK(panel_k230_status(band, sizeof band) == PANEL_K230_NOT_OPEN);
    CHECK(panel_k230_status(NULL, 0) == PANEL_K230_NOT_OPEN);
    CHECK(mock_event_count() == 0);
}

static void run(const char *name, void (*test)(void))
{
    fflush(stdout);
    pid_t pid = fork();
    if (pid == 0) {
        test();
        exit(0);
    }
    int status = 0;
    if (pid < 0 || waitpid(pid, &status, 0) != pid || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        printf("FAIL %s\n", name);
        failures++;
    } else {
        printf("ok   %s\n", name);
    }
}

#define RUN(test) run(#test, test)

int main(int argc, char **argv)
{
    if (argc == 4 && strcmp(argv[1], "trace") == 0) {
        const struct mock_config *scenario = mock_scenario(argv[2]);
        if (scenario == NULL) {
            fprintf(stderr, "unknown scenario %s\n", argv[2]);
            return 2;
        }
        mock_reset(scenario);
        (void) panel_k230_open();
        return mock_write_trace(argv[3]) == 0 ? 0 : 1;
    }
    if (argc != 1) {
        fprintf(stderr, "usage: panel_k230_test [trace nominal|dphy-timeout <file>]\n");
        return 2;
    }
#if COPROC_PANEL_K230
    RUN(test_open_brings_up_and_scans_out_the_region);
    RUN(test_open_runs_once);
    RUN(test_power_domain_failure_stops_before_the_panel);
    RUN(test_dphy_timeout_runs_the_vendor_sequence_then_fails);
    RUN(test_status_band_is_osd5_over_rows_0_to_27);
    RUN(test_status_rejects_anything_but_one_band);
#else
    RUN(test_no_panel_build_touches_nothing);
#endif
    RUN(test_status_before_open);
    printf("panel_k230_test (COPROC_PANEL_K230=%d): %s\n", COPROC_PANEL_K230, failures ? "FAILED" : "passed");
    return failures ? 1 : 0;
}
