# The Elixos coprocessor firmware (M32): AtomVM on bare metal for the K230's
# little core, with lwIP over the §11 inter-core ring. See
# docs/notes/coproc-firmware.md; melange/coproc-firmware.yaml builds it.
#
#   cmake -S coproc -B build -G Ninja \
#     -DCMAKE_TOOLCHAIN_FILE=coproc/cmake/riscv-none-elf.cmake \
#     -DCOPROC_TARGET=k230|qemu-virt \
#     -DATOMVM_SRC=<AtomVM tree> -DLWIP_DIR=<lwIP tree> -DMBEDTLS_DIR=<Mbed TLS tree>
#
# Outputs: coproc-<target>.elf and the flat coproc-<target>.bin U-Boot loads.
cmake_minimum_required(VERSION 3.13)
project(ElixosCoproc C ASM)

set(ATOMVM_SRC "" CACHE PATH "AtomVM source tree (the pinned commit, patched)")
set(LWIP_DIR "" CACHE PATH "lwIP release tree")
set(MBEDTLS_DIR "" CACHE PATH "Mbed TLS release tree")
set(COPROC_TARGET "" CACHE STRING "k230 or qemu-virt")
foreach(required ATOMVM_SRC LWIP_DIR MBEDTLS_DIR COPROC_TARGET)
    if (NOT ${required})
        message(FATAL_ERROR "set ${required}")
    endif()
endforeach()

# ---- board parameters (src/board.h) ---------------------------------------
# Each is a build-time parameter (-DCOPROC_...=...) defaulting per target.
# The image region layout is the same on both targets; the ring is a separate
# shared region (on the K230 the board DT's no-map region at 0x08000000,
# outside the little core's 16 MiB). The K230 values are unverified on
# hardware (docs/notes/coproc-firmware.md, "Open on the board").
macro(coproc_default name value)
    if (NOT DEFINED ${name})
        set(${name} ${value})
    endif()
endmacro()
coproc_default(COPROC_REGION_SIZE 0x01000000)
coproc_default(COPROC_PAYLOAD_OFFSET 0x00400000)
coproc_default(COPROC_HEAP_OFFSET 0x00600000)
coproc_default(COPROC_STACK_SIZE 0x00040000)
coproc_default(COPROC_RING_SIZE 0x21000)
coproc_default(COPROC_FB_SIZE 0x180000)
if (COPROC_TARGET STREQUAL "k230")
    coproc_default(COPROC_BOARD "T-Display K230 little core")
    coproc_default(COPROC_LOAD_ADDR 0x07000000)
    coproc_default(COPROC_RING_ADDR 0x08000000)
    # The deck framebuffer (PROTOCOL §12), the board DT's `deck-fb` region.
    coproc_default(COPROC_FB_ADDR 0x08100000)
    # The RM69A10 panel on the VO/DSI block (src/panel_k230.c).
    coproc_default(COPROC_PANEL_K230 1)
    # GT9895 touch, SX1262 LoRa, the PMU's power key and power-off
    # (src/touch_k230.c, lora_k230.c, power_k230.c).
    coproc_default(COPROC_K230_DEVICES 1)
    coproc_default(COPROC_UART_BASE 0x91403000)
    coproc_default(COPROC_UART_SHIFT 2)
    coproc_default(COPROC_UART_WORD 1)
    # UART3: clock, divisor and pads programmed by src/uart_k230.c.
    coproc_default(COPROC_UART_K230 1)
    coproc_default(COPROC_MTIME_ADDR 0)
    coproc_default(COPROC_MTIMECMP_ADDR 0xF04004000)
    coproc_default(COPROC_TIMEBASE_HZ 27000000)
elseif (COPROC_TARGET STREQUAL "qemu-virt")
    coproc_default(COPROC_BOARD "QEMU virt")
    coproc_default(COPROC_LOAD_ADDR 0x80000000)
    # Right after the 16 MiB image region, as on the K230.
    coproc_default(COPROC_RING_ADDR 0x81000000)
    # As on the K230: 1 MiB after the ring.
    coproc_default(COPROC_FB_ADDR 0x81100000)
    # No display block: panel_open/0 answers {error, no_panel}.
    coproc_default(COPROC_PANEL_K230 0)
    # No board devices: their NIFs answer {error, no_device}.
    coproc_default(COPROC_K230_DEVICES 0)
    coproc_default(COPROC_UART_BASE 0x10000000)
    coproc_default(COPROC_UART_SHIFT 0)
    coproc_default(COPROC_UART_WORD 0)
    coproc_default(COPROC_UART_K230 0)
    coproc_default(COPROC_MTIME_ADDR 0)
    coproc_default(COPROC_MTIMECMP_ADDR 0x2004000)
    coproc_default(COPROC_TIMEBASE_HZ 10000000)
else()
    message(FATAL_ERROR "COPROC_TARGET must be k230 or qemu-virt, not '${COPROC_TARGET}'")
endif()

set(COPROC_DEFINITIONS
    COPROC_LOAD_ADDR=${COPROC_LOAD_ADDR}
    COPROC_PAYLOAD_OFFSET=${COPROC_PAYLOAD_OFFSET}
    COPROC_HEAP_OFFSET=${COPROC_HEAP_OFFSET}
    COPROC_REGION_SIZE=${COPROC_REGION_SIZE}
    COPROC_RING_ADDR=${COPROC_RING_ADDR}
    COPROC_RING_SIZE=${COPROC_RING_SIZE}
    COPROC_FB_ADDR=${COPROC_FB_ADDR}
    COPROC_FB_SIZE=${COPROC_FB_SIZE}
    COPROC_PANEL_K230=${COPROC_PANEL_K230}
    COPROC_K230_DEVICES=${COPROC_K230_DEVICES}
    COPROC_UART_BASE=${COPROC_UART_BASE}
    COPROC_UART_SHIFT=${COPROC_UART_SHIFT}
    COPROC_UART_WORD=${COPROC_UART_WORD}
    COPROC_UART_K230=${COPROC_UART_K230}
    COPROC_MTIME_ADDR=${COPROC_MTIME_ADDR}
    COPROC_MTIMECMP_ADDR=${COPROC_MTIMECMP_ADDR}
    COPROC_TIMEBASE_HZ=${COPROC_TIMEBASE_HZ}
    "COPROC_BOARD=\"${COPROC_BOARD}\""
)

# ---- AtomVM ---------------------------------------------------------------
list(APPEND CMAKE_MODULE_PATH "${ATOMVM_SRC}/CMakeModules")
set(AVM_DISABLE_SMP ON CACHE BOOL "" FORCE)
set(AVM_DISABLE_TASK_DRIVER ON CACHE BOOL "" FORCE)
set(AVM_DISABLE_JIT ON CACHE BOOL "" FORCE)
set(AVM_CREATE_STACKTRACES ON CACHE BOOL "" FORCE)
# As the Unix stand-in (melange/atomvm.yaml): erpc exits with its result.
set(AVM_PRINT_PROCESS_CRASH_DUMPS OFF CACHE BOOL "" FORCE)
set(AVM_SYSTEM_ARCHITECTURE_STRING "riscv64-elixos-coproc")

# What libc and the firmware provide. The POSIX file calls are the RAM file
# system (src/ramfs.c); there are no BSD sockets (OTP socket runs on lwIP),
# directories, processes or clocks to set.
foreach(available OPEN CLOSE UNLINK RENAME FSYNC LSEEK)
    set(HAVE_${available} 1 CACHE INTERNAL "" FORCE)
endforeach()
foreach(missing MKFIFO EXECVE KILL OPENDIR CLOSEDIR READDIR CLOSEFROM GETCWD CLOCK_SETTIME SETTIMEOFDAY
        SOCKET SELECT PREAD PWRITE FTRUNCATE STAT FSTAT MKDIR RMDIR TCGETATTR SCHED_YIELD
        POSIX_SPAWN_CLOEXEC_DEFAULT)
    set(HAVE_${missing} "" CACHE INTERNAL "" FORCE)
endforeach()

add_subdirectory(${ATOMVM_SRC}/src/libAtomVM libAtomVM)

# ---- Mbed TLS (crypto only) -------------------------------------------------
set(ENABLE_PROGRAMS OFF CACHE BOOL "" FORCE)
set(ENABLE_TESTING OFF CACHE BOOL "" FORCE)
set(GEN_FILES OFF CACHE BOOL "" FORCE)
set(MBEDTLS_FATAL_WARNINGS OFF CACHE BOOL "" FORCE)
set(USE_STATIC_MBEDTLS_LIBRARY ON CACHE BOOL "" FORCE)
set(USE_SHARED_MBEDTLS_LIBRARY OFF CACHE BOOL "" FORCE)
add_subdirectory(${MBEDTLS_DIR} mbedtls EXCLUDE_FROM_ALL)
set(COPROC_MBEDTLS_CONFIG "MBEDTLS_USER_CONFIG_FILE=\"${CMAKE_CURRENT_SOURCE_DIR}/src/mbedtls_coproc_config.h\"")
target_compile_definitions(mbedcrypto PRIVATE ${COPROC_MBEDTLS_CONFIG})

# ---- lwIP -------------------------------------------------------------------
include(${LWIP_DIR}/src/Filelists.cmake)
add_library(lwip STATIC ${lwipcore_SRCS} ${lwipcore4_SRCS})
target_include_directories(lwip PUBLIC ${LWIP_DIR}/src/include ${CMAKE_CURRENT_SOURCE_DIR}/src)

# ---- the firmware -----------------------------------------------------------
set(COPROC_ELF coproc-${COPROC_TARGET}.elf)
set(COPROC_BIN coproc-${COPROC_TARGET}.bin)
configure_file(src/coproc.ld.in ${CMAKE_CURRENT_BINARY_DIR}/coproc.ld @ONLY)

add_executable(${COPROC_ELF}
    src/start.S
    src/hw.c
    src/k230_i2c.c
    src/k230_io.c
    src/k230_mmio.c
    src/k230_spi.c
    src/lora_k230.c
    src/main.c
    src/net.c
    src/otp_net_lwip_raw.c
    src/otp_socket_platform.c
    src/panel_k230.c
    src/payload.c
    src/platform_nifs.c
    src/power_k230.c
    src/ramfs.c
    src/ring.c
    src/sys.c
    src/touch_k230.c
    src/uart_k230.c
    ${ATOMVM_SRC}/src/libAtomVM/inet.c
    ${ATOMVM_SRC}/src/libAtomVM/otp_crypto.c
    ${ATOMVM_SRC}/src/libAtomVM/otp_socket.c
    ${ATOMVM_SRC}/src/libAtomVM/portnifloader.c
)
# OTP_SOCKET_LWIP_NODELAY (melange/atomvm-baremetal/0001): TCP without Nagle,
# as OTP runs distribution; the firmware's TCP is distribution and epmd.
target_compile_definitions(${COPROC_ELF} PRIVATE ${COPROC_DEFINITIONS} HAVE_LWIP_RAW=1 ATOMVM_HAS_MBEDTLS
    OTP_SOCKET_LWIP_NODELAY ${COPROC_MBEDTLS_CONFIG})
target_include_directories(${COPROC_ELF} PRIVATE src ${ATOMVM_SRC}/src/libAtomVM)
target_compile_options(${COPROC_ELF} PRIVATE -Wall -Wextra)
target_link_libraries(${COPROC_ELF} PRIVATE libAtomVM lwip mbedcrypto)
target_link_options(${COPROC_ELF} PRIVATE -T${CMAKE_CURRENT_BINARY_DIR}/coproc.ld
    -Wl,-Map=${CMAKE_CURRENT_BINARY_DIR}/coproc-${COPROC_TARGET}.map)
set_target_properties(${COPROC_ELF} PROPERTIES LINK_DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/coproc.ld)

add_custom_command(TARGET ${COPROC_ELF} POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O binary ${COPROC_ELF} ${COPROC_BIN}
    COMMAND ${CMAKE_SIZE} -A ${COPROC_ELF}
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})
