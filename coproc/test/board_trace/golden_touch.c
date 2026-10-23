/*
 * The touch golden trace: LilyGO's RT-Smart GT9895 driver (LT-RT
 * drivers/extdrv/touch/gt9895.c, pinned in vendor.lock) compiled on the
 * build host against the GT9895 model, its I2C messages delivered to the
 * model as RT-Thread's DesignWare driver sends them (drv_i2c.c 1070-1107: a
 * repeated start between messages, a stop after the last). One report with
 * one finger is read the way the RT-Thread touch framework reads it
 * (touch.c 125-140: touch_readpoint for one point).
 *
 *   golden_touch <log-file>
 *
 * The log is the model's I2C transfers; stdout gets the point the vendor
 * code decoded. With range_x/range_y set to the driver's own resolution
 * (1024 x 2400) its scaling is the identity, so it prints the controller's
 * raw coordinates.
 */
#include <stdio.h>

#include "gt9895_model.h"

/* The defconfig's values (configs/k230_canmv_v3p0_defconfig 242-243). */
#define TOUCH_GT9895_I2C_DEV "i2c3"
#define TOUCH_GT9895_I2C_ADDR 0x5d

#include "gt9895.c"

rt_size_t rt_i2c_transfer(struct rt_i2c_bus_device *bus, struct rt_i2c_msg msgs[], rt_uint32_t num)
{
    (void) bus;
    const struct i2c_target *gt = gt9895_model_target();
    for (rt_uint32_t m = 0; m < num; m++) {
        int read = msgs[m].flags & RT_I2C_RD;
        if (msgs[m].addr != gt->addr || !gt->start(gt->ctx, read)) {
            return m;
        }
        for (rt_uint16_t i = 0; i < msgs[m].len; i++) {
            if (read) {
                msgs[m].buf[i] = gt->read(gt->ctx);
            } else {
                gt->write(gt->ctx, msgs[m].buf[i]);
            }
        }
    }
    gt->stop(gt->ctx);
    return num;
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: golden_touch <log-file>\n");
        return 2;
    }
    gt9895_model_init();
    gt9895_model_force_on();
    struct gt9895_point point = { .id = 0, .type = 0, .x = 530, .y = 1200, .w = 20 };
    gt9895_model_report(&point, 1);

    struct rt_touch_device touch = { 0 };
    touch.info.point_num = 10; /* gt9895.c 195 */
    touch.info.range_x = TOUCH_RESOLUTION_X;
    touch.info.range_y = TOUCH_RESOLUTION_Y;
    touch.config.user_data = &gt9895_dev0;
    struct rt_touch_data data[1];
    rt_size_t got = gt9895_read_point(&touch, data, sizeof data);
    printf("golden touch: %zu point(s), id %u x %u y %u\n", got / sizeof data[0], data[0].track_id,
           data[0].x_coordinate, data[0].y_coordinate);
    if (got != sizeof data || data[0].x_coordinate != 530 || data[0].y_coordinate != 1200) {
        fprintf(stderr, "golden touch: the vendor code decoded something else\n");
        return 1;
    }
    return gt9895_model_write_log(argv[1]) == 0 ? 0 : 1;
}
