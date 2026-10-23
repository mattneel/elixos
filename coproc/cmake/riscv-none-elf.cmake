# Cross toolchain for the coprocessor firmware: Alpine's bare-metal
# riscv-none-elf GCC with picolibc, for the K230 little core's C908 (rv64gc,
# no vector) in M-mode. medany: the image runs at 0x07000000 on the K230 and
# at 0x80000000 on QEMU virt, and picolibc's lp64d libraries are medany too.
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR riscv64)

set(CMAKE_C_COMPILER riscv-none-elf-gcc)
set(CMAKE_ASM_COMPILER riscv-none-elf-gcc)
set(CMAKE_AR riscv-none-elf-ar)
set(CMAKE_RANLIB riscv-none-elf-ranlib)
set(CMAKE_OBJCOPY riscv-none-elf-objcopy)
set(CMAKE_SIZE riscv-none-elf-size)
# libAtomVM's project() enables C++ by default; nothing here is C++ and
# Alpine's cross GCC ships no cc1plus, so the C++ compiler is declared, never
# identified or used.
set(CMAKE_CXX_COMPILER riscv-none-elf-gcc)
set(CMAKE_CXX_COMPILER_ID GNU)
set(CMAKE_CXX_COMPILER_VERSION 16.1.0)
set(CMAKE_CXX_COMPILER_FORCED TRUE)

set(COPROC_ARCH_FLAGS "-march=rv64imafdc_zicsr_zifencei -mabi=lp64d -mcmodel=medany --specs=picolibc.specs")
set(CMAKE_C_FLAGS_INIT "${COPROC_ARCH_FLAGS} -ffunction-sections -fdata-sections")
set(CMAKE_ASM_FLAGS_INIT "${COPROC_ARCH_FLAGS}")
# The C flags (with the specs) are on the link line already.
set(CMAKE_EXE_LINKER_FLAGS_INIT "-nostartfiles -Wl,--gc-sections")

# Feature probes compile only; nothing links without the firmware's own
# start code and linker script.
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
