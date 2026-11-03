# CMake toolchain file for bare-metal RISC-V.
# Use:  cmake -B build -DCMAKE_TOOLCHAIN_FILE=cmake/riscv64-unknown-elf.cmake
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR riscv)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(CMAKE_C_COMPILER   riscv64-unknown-elf-gcc)
set(CMAKE_CXX_COMPILER riscv64-unknown-elf-g++)
set(CMAKE_ASM_COMPILER riscv64-unknown-elf-gcc)
set(CMAKE_OBJCOPY      riscv64-unknown-elf-objcopy)
set(CMAKE_SIZE         riscv64-unknown-elf-size)

# Set arch flags in your project, e.g. for a 32-bit core with picolibc:
#   -march=rv32imac -mabi=ilp32 --specs=picolibc.specs

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
