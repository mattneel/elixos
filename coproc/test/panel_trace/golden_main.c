/*
 * The golden trace: LilyGO's U-Boot RM69A10 logo bring-up, compiled from
 * the sha256-pinned vendor files against the register model, run exactly as
 * k230_display_logo() (k230_logo.c 282-356) runs it for
 * CONFIG_K230_BARE_DISP_LOGO_RM69A10, minus loading the logo picture:
 *
 *   golden <scenario> <trace-file>
 *
 * The scenarios are k230_mmio_mock.c's ("nominal", "dphy-timeout").
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#include "display_logo.h"
#include "k230_mmio_mock.h"

/* k230_logo.c 194-207: the framebuffer address display_logo.c asks for. */
#include "k230_logo_fb.inc"

void golden_power_on_display(void);

int main(int argc, char **argv)
{
    const struct mock_config *scenario = argc == 3 ? mock_scenario(argv[1]) : NULL;
    if (scenario == NULL) {
        fprintf(stderr, "usage: golden nominal|dphy-timeout <trace-file>\n");
        return 2;
    }
    mock_reset(scenario);

    k_connector_info info;
    /* k230_logo.c 317-334. */
#include "k230_logo_info.inc"

    golden_power_on_display(); /* k230_logo.c 353 */
    st7701_init(&info); /* k230_logo.c 354 */

    return mock_write_trace(argv[2]) == 0 ? 0 : 1;
}
