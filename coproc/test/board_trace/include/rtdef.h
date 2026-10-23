/*
 * Stand-in for RT-Thread's headers (rtdef.h, rtthread.h, touch.h,
 * lwp_user_mm.h, rtdbg.h) when LilyGO's GT9895 driver (gt9895.c) is
 * compiled on the build host (coproc/test/board_trace/golden_touch.c): the
 * types and calls it uses, nothing more. rt_i2c_transfer is the golden
 * harness's, talking to the GT9895 model.
 */
#ifndef BOARD_TRACE_RTDEF_H
#define BOARD_TRACE_RTDEF_H

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef uint8_t rt_uint8_t;
typedef uint16_t rt_uint16_t;
typedef uint32_t rt_uint32_t;
typedef size_t rt_size_t;
typedef long rt_err_t;
typedef void *rt_device_t;

#define RT_EOK 0
#define RT_ERROR 1
#define RT_EINVAL 10
#define RT_ENOSYS 6
#define RT_NULL NULL
#define RT_DEVICE_FLAG_RDWR 0x003

#define RT_I2C_WR 0x0000
#define RT_I2C_RD 0x0001

struct rt_i2c_bus_device {
    int unused;
};

struct rt_i2c_msg {
    rt_uint16_t addr;
    rt_uint16_t flags;
    rt_uint16_t len;
    rt_uint8_t *buf;
};

rt_size_t rt_i2c_transfer(struct rt_i2c_bus_device *bus, struct rt_i2c_msg msgs[], rt_uint32_t num);

#define RT_TOUCH_CTRL_GET_INFO 0
#define RT_TOUCH_TYPE_CAPACITANCE 2
#define RT_TOUCH_VENDOR_GT 1

struct rt_touch_info {
    rt_uint8_t type;
    rt_uint8_t vendor;
    rt_uint8_t point_num;
    int32_t range_x;
    int32_t range_y;
};

struct rt_touch_config {
    const char *dev_name;
    void *user_data;
};

struct rt_touch_device;

struct rt_touch_ops {
    rt_size_t (*touch_readpoint)(struct rt_touch_device *touch, void *buf, rt_size_t touch_num);
    rt_err_t (*touch_control)(struct rt_touch_device *touch, int cmd, void *arg);
};

struct rt_touch_device {
    struct rt_touch_info info;
    struct rt_touch_config config;
    const struct rt_touch_ops *ops;
};
typedef struct rt_touch_device *rt_touch_t;

struct rt_touch_data {
    rt_uint8_t event;
    rt_uint8_t track_id;
    rt_uint8_t width;
    rt_uint16_t x_coordinate;
    rt_uint16_t y_coordinate;
    rt_uint32_t timestamp;
};

#define rt_calloc calloc
#define rt_memcpy memcpy
#define rt_device_find(name) ((rt_device_t) NULL)
#define rt_device_open(dev, flags) (-1)
#define rt_hw_touch_register(touch, name, flag, data) (-1)
#define lwp_put_to_user(dst, src, size) memcpy((dst), (src), (size))
#define LOG_E(...) ((void) 0)
#define INIT_DEVICE_EXPORT(fn)

#endif
