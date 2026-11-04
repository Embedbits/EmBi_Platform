# CMake Build System

This repository provides the **CMake infrastructure** required to build STM32-based projects and other modules within the STM Template architecture.  
It is designed to be used as a **Git submodule** and separates complex build logic from project sources, ensuring consistency, versioning, and reusability across repositories.

---

## 🧩 Overview

The build system is divided into **two layers**:

1. **Project Layer**  
   Project root folder CMakeLists.txt represents project part for CMake build and provides a minimal entry point for CMake. 
   Its sole purpose is to invoke the centralized build logic:

   ```cmake
   include(${CMAKE_CURRENT_LIST_DIR}/CMake/Build.cmake)
   ```

2. **Platform Layer**  
   This script contains all major build definitions, functions, and configuration steps.  
   It manages:
   - Build options checks
   - Project initialization and target setup  
   - Toolchain detection and configuration  
   - Build type handling (Debug / Release / Test)  
   - Include path propagation  
   - Dependency and module registration  

This separation ensures that the root project remains clean and easy to maintain while the detailed logic is **versioned and shareable** as a standalone submodule.

---

## ⚙️ Placeholder Source Files

CMake requires at least one valid source file to generate a build system.  
For this reason, `Platform.c` and `Platform.h` are included as **empty placeholders** and version storage.  
They serve only as stubs during the initial configuration phase and are not compiled into the final firmware.

---

## 🧩 Integration as Submodule

This repository is meant to be added as a Git submodule:

```bash
git submodule add git@ssh.dev.azure.com:v3/Dlzen/STM_Template/CMake CMake
```

In the parent project, the main `CMakeLists.txt` should include:

```cmake
include("${CMAKE_SOURCE_DIR}/STM_Template/CMake/Build.cmake")
```

After initialization, the parent project can extend or override specific build steps via custom CMake scripts or options.

---

## 📜 Versioning

Because the build logic evolves independently from the application code, each version of this repository is **tagged** and can be referenced explicitly by parent repositories.  
This allows stable builds across multiple firmware generations and branches.

---

## 🧩 Future Extensions

Planned additions include:
- Integration test implementation
- CMake presets implementation

---

## 📁 Directory Layout

```
CMake/
 ├── Build.cmake                # Core build logic called from the root CMakeLists.txt
 ├── Platform.c                 # Placeholder source file required by CMake during project initialization
 ├── Platform.h                 # Placeholder header file (currently empty)
 ├── ArtifactsManager           # Artifactory management functionality
 |    ├── Artifacts.cmake       # Artifacts manager CMake script
 |    └── README.md             # Artifacts manager module description and usage informations
 ├── HelperTools                # Project initialization and support functionality
 |    ├── Scripts               # Location of CMake scripts
 |    ├── Templates             # Location of templates used by CMake scripts
 |    ├── Setup.bat             # Windows script to easier calling CMake scripts
 |    └── README.md             # Helper tools module description and usage informations 
 └── README.md                  # CMake module description and usage informations
```

---

## 🧱 Example Usage

Below is a minimal example of how to use this CMake Build System in a parent project.

### ProjectRootDir/CMakeLists.txt

```cmake
################################################################################
# Author: Mr.Nobody
# file:  CMakeLists.txt
# brief: Project part CMake functionality. 
#
# User shall not change platform functionality, for project necessary 
# functionality can user implement in this file.     
#
# usage: Edit "VARIABLES"-section to suit project requirements.
#        For debug build:
#           cmake -S . -B Build_Debug -GNinja -DCMAKE_BUILD_TYPE=Debug -DTARGET_MCU=STM32WXXXyZ -DDOXYGEN_ENABLED=OFF
#           cmake --build Build_Debug
#        For release build:
#           cmake -S . -B Build_Release -GNinja -DCMAKE_BUILD_TYPE=Release -DTARGET_MCU=STM32WXXXyZ -DDOXYGEN_ENABLED=OFF
#           cmake --build Build_Release
################################################################################
#
# Necessary operators:
#
# CMAKE_BUILD_TYPE
#    - Debug
#    - Release
#    - UnitTest
#    - IntegrationTest
#
# TARGET_MCU
#    - STM32WXXXyZ
#      Where:
#       W - STM32 Family ID (single letter)
#       XXX - STM32 Family specification (three symbols)
#       y - Must stay unchanged
#       Z - Flash size identification ( A - 0K,6 - 32K, 8 - 64K, B - 128K ...)
#      Example: STM32G474xE
#
# Optional operators. If not specified default value will be used
#
# DOXYGEN_ENABLED
#    - OFF (default)
#    - ON
#
################################################################################

cmake_minimum_required(VERSION 3.25)

#=============================== Constant values ==============================#

set(BUILD_TYPE_ALLOWED_VALUES           "Debug"
                                        "Release"
                                        "UnitTest"
                                        "IntegrationTest")
                                        
# Doxygen is not available by default. If artifact is loaded, this macro will be set to ON
add_definitions(-DDOXYGEN_STATE=OFF)

#======================== Project configuration values ========================#
# Set project configuration values such as project name, type, CPU, FPU, runtime library, and compile commands export
set(PROJECT_NAME                        "Project_Template_${CMAKE_BUILD_TYPE}")
set(CMAKE_EXPORT_COMPILE_COMMANDS       ON)

# Setup compiler settings
set(CMAKE_C_STANDARD                    11)
set(CMAKE_C_STANDARD_REQUIRED           ON)
set(CMAKE_C_EXTENSIONS                  ON)

set(CMAKE_CXX_STANDARD                  17)
set(CMAKE_CXX_STANDARD_REQUIRED         ON)
set(CMAKE_CXX_EXTENSIONS                ON)

#=========================== DO NOT CHANGE THIS PART ==========================#
#============================ Artifacts preparation ===========================#

# Check, if artifact manager is used in project.
if(EXISTS ${CMAKE_SOURCE_DIR}/EmB_Platform/CMake/ArtifactsManager/Artifacts.cmake)
    # Run artifacts configuration before build.
    include(${CMAKE_SOURCE_DIR}/EmB_Platform/CMake/ArtifactsManager/Artifacts.cmake)
endif()

#========================== Build flags configuration =========================#
# Options of the project for the MCU builds (Debug, Release, IntegrationTest) - the platform adds its own flags
# (warnings, sections, system calls, link) in Build.cmake. The "UnitTest" build compiles for the host and does
# not take them.
if(NOT CMAKE_BUILD_TYPE STREQUAL "UnitTest")

    # Names of the flags (OPTIMIZATION_NONE, DISABLE_RTTI...) are used below
    include(${CMAKE_SOURCE_DIR}/EmBi_Platform/CMake/Flags.cmake)

    ## Optimization and debug information per build type - CMake adds CMAKE_<LANG>_FLAGS_<TYPE> after
    ## CMAKE_<LANG>_FLAGS (its own defaults would be "-g" and "-O3 -DNDEBUG")
    set(CMAKE_C_FLAGS_DEBUG             "${OPTIMIZATION_NONE} ${DEBUG_LEVEL_3}")
    set(CMAKE_C_FLAGS_RELEASE           "${OPTIMIZATION_FULL} ${DEBUG_LEVEL_0} -DNDEBUG")
    set(CMAKE_CXX_FLAGS_DEBUG           "${CMAKE_C_FLAGS_DEBUG}")
    set(CMAKE_CXX_FLAGS_RELEASE         "${CMAKE_C_FLAGS_RELEASE}")
    set(CMAKE_ASM_FLAGS_DEBUG           "${CMAKE_C_FLAGS_DEBUG}")
    set(CMAKE_ASM_FLAGS_RELEASE         "${CMAKE_C_FLAGS_RELEASE}")

    ## Assembler sources are preprocessed, dependency files are generated
    set(CMAKE_ASM_FLAGS                 "${CMAKE_ASM_FLAGS} ${ASSEMBLER_MODE} ${GENERATE_DEPENDENCY_FILE}")

    ## C++ without RTTI, exceptions and thread-safe initialization of statics
    set(CMAKE_CXX_FLAGS                 "${CMAKE_CXX_FLAGS} ${DISABLE_RTTI}")
    set(CMAKE_CXX_FLAGS                 "${CMAKE_CXX_FLAGS} ${DISABLE_EXCEPTIONS}")
    set(CMAKE_CXX_FLAGS                 "${CMAKE_CXX_FLAGS} ${DISABLE_THREADSAFE_STATICS}")

    ## Runtime library of C and C++ (newlib-nano)
    set(CMAKE_C_FLAGS                   "${CMAKE_C_FLAGS} ${LINKER_NANO}")
    set(CMAKE_CXX_FLAGS                 "${CMAKE_CXX_FLAGS} ${LINKER_NANO}")

else()
    # Host build of the unit tests - options of the host compiler are set by UnitTesting.cmake
endif()

#================================ MCU build ===================================#

# Core project settings
project(${PROJECT_NAME} 
        VERSION 0.1.0
        HOMEPAGE_URL "https://embedbits.com"
        LANGUAGES C CXX ASM)

# Include main CMake script
include("${CMAKE_SOURCE_DIR}/EmB_Platform/CMake/Build.cmake")

#========================= User specific commands =============================#

target_compile_definitions(${CMAKE_PROJECT_NAME}
    INTERFACE
    
    PRIVATE
    
    PUBLIC
)

# Link directories setup
target_link_directories(${CMAKE_PROJECT_NAME}
    INTERFACE
    
    PRIVATE
    
    PUBLIC
)

# Add sources to executable
target_sources(${CMAKE_PROJECT_NAME}
    INTERFACE
    
    PRIVATE
    
    PUBLIC
)

# Add include paths
target_include_directories(${CMAKE_PROJECT_NAME}
    INTERFACE
    
    PRIVATE
    
    PUBLIC
)

# Add project symbols (macros)
target_compile_definitions(${CMAKE_PROJECT_NAME}
    INTERFACE
    
    PRIVATE
    
    PUBLIC
)

# Add linked libraries
target_link_libraries(${CMAKE_PROJECT_NAME}
    INTERFACE
    
    PRIVATE
    
    PUBLIC
)

#==================== User specific pre-processing commands ===================#

#add_custom_command(
#    TARGET ${CMAKE_PROJECT_NAME}
#    PRE_BUILD
#    COMMAND
#) 

#=================== User specific post-processing commands ===================#

add_custom_command(
    TARGET ${CMAKE_PROJECT_NAME}
    POST_BUILD
    COMMENT "Total Size:"
    COMMAND ${CMAKE_SIZE} ARGS $<TARGET_FILE:${CMAKE_PROJECT_NAME}>
)

add_custom_command(
    TARGET ${CMAKE_PROJECT_NAME}
    POST_BUILD
    COMMENT "Generating .bin file."
    COMMAND ${CMAKE_OBJCOPY} -O binary $<TARGET_FILE:${CMAKE_PROJECT_NAME}> ${CMAKE_PROJECT_NAME}.bin 
)

add_custom_command(
    TARGET ${CMAKE_PROJECT_NAME} 
    POST_BUILD
    COMMENT "Generating .hex file."
    COMMAND ${CMAKE_OBJCOPY} -O ihex $<TARGET_FILE:${CMAKE_PROJECT_NAME}> ${CMAKE_PROJECT_NAME}.hex
)

```

---

## 🔗 Project Linker Script

By default the firmware is linked with the linker script generated by `Bsp/Linker` for the selected MCU
(`TARGET_MCU`). A project can replace it with its own script by the cache variable `USER_LINKER_SCRIPT`:

| Value | Linker script of the build |
|---|---|
| empty (default) | script generated by `Bsp/Linker` (`<build>/Linker.ld`) |
| `<path>.in` | configured by `configure_file(@ONLY)` into `<build>/UserLinkerScript/<name without .in>` - the values of `Bsp/Linker` for the MCU are available (`@RAM_SIZE@`, `@FLASH_SIZE@`, `@USER_DATA_SIZE@`, ... see `Bsp/Linker/Linker.cmake` of the family) |
| `<path>` (any other) | used as it is |

- A relative path is taken from the project root folder (`CMAKE_SOURCE_DIR`). A script which does not exist stops
  the configuration.
- The selected script is printed during the configuration (`Linker script: ...`).
- The script is used for all MCU builds: `Debug`, `Release` and the integration test firmware (`IntegrationTest`).
  The `UnitTest` build compiles for the host and does not use it.
- The firmware is linked again when the script changes.

The variable is set in the project root `CMakeLists.txt` before `Build.cmake` is included (section
"Project configuration values"):

```cmake
set(USER_LINKER_SCRIPT                  "Application/Linker/Linker.ld.in")
```

or on the command line / in the `cacheVariables` of a preset:

```bash
cmake --preset STM32H563xI_Debug -DUSER_LINKER_SCRIPT=Application/Linker/Linker.ld.in
```

A value set in `CMakeLists.txt` takes precedence over the value of the command line.

A copy of `Bsp/Linker/Linker.ld.in` of the family is the recommended start - it already holds everything listed
below, the project extends it (e.g. own memory regions `SRAM1` ... `SRAMn` and sections placed into them).

### Requirements of the platform code

The script has to keep the entry point, symbols, sections and memory regions below. A missing symbol ends with an
`undefined reference` error of the link. A missing rule for an input section is **not** reported - the linker
places such a section as an orphan section anywhere (e.g. a RAM vector table without the alignment of VTOR).

| Used by | Required in the linker script |
|---|---|
| Startup (`Bsp/Startup`) | entry `StartUp_Handler`; `_sidata`, `_sdata`, `_edata` (`.data` copied from FLASH); `_sbss`, `_ebss` (`.bss` cleared); `__preinit_array_start` / `_end`, `__init_array_start` / `_end`, `__fini_array_start` / `_end` |
| Stack | `_estack` - initial stack pointer (top of the stack) |
| Nvic | section `.isr_vector` at the start of the FLASH (vector table of the boot); section `._irqVectorTable_RAM` in RAM (NOLOAD) aligned for VTOR - power of two not lower than 4 x count of the vectors (1024 on STM32H5); `_ram_end` |
| Gpdma (families with GPDMA) | `_flash_start`, `_flash_end`, `_ram_start`, `_ram_end` and `_ram4_start`, `_ram4_end` (STM32U5) or `_ram_d2_start`, `_ram_d2_end` (STM32H7R/S) - memories accessible by the DMA |
| RamCfg integration test | `_ram_start`, `_irqVectorTable_RAM_End`, `_estack` |
| Integration testing | section `.noinit` in RAM (NOLOAD) - result mailbox, kept over reset |
| Coverage (`INTEGRATION_TEST_COVERAGE`) | memory regions `FLASH` and `RAM`, output sections `.rodata` and `.bss` (`ItCore/IntegrationTesting_GcovInfo.ld` is inserted after `.rodata`, `ItCore/IntegrationTesting_GcovCounters.ld` before `.bss`) |

---

## 🔒 Option Bytes

Every option byte of the MCU is a variable of the project `CMakeLists.txt` - `OPTION_BYTE_<name>`, empty: the value
of the chip is kept (`OptionBytes/OptionBytes.cmake`):

```cmake
# BOR_LEV (BOR Level): These bits reflects the power level that generates a system reset. ... - 0x0: reset level is
#   set to VBOR0, 0x1: reset level is set to VBOR1, 0x2: reset level is set to VBOR2, 0x3: reset level is set to VBOR3
set(OPTION_BYTE_BOR_LEV                 "0x2")
```

- The section `Option bytes` of the file (before `DO NOT CHANGE THIS PART`) lists the option bytes of the MCUs of the
  project - the vendor data `optionBytes` of `Bsp/Ral/RalPresets.json` (STM32CubeProgrammer database, generated by
  `ral-presets.sh` of Bsp_Linker). The BSP configuration, the BSP update and the VSCode project initialization add the
  new option bytes with an empty value and keep the set values.
- A cmake parameter `-DOPTION_BYTE_<name>=<value>` overrides the value of the file (it stays in the cache of the build
  folder, `-UOPTION_BYTE_<name>` removes it).
- The configuration of an MCU build checks the set values (hexadecimal `0x...` or decimal, at most the bits of the
  option byte) and prints them (`Option bytes: BOR_LEV=0x2, ...`); an option byte of another MCU of the project is
  reported and not written. The project of a core of a multi-core MCU (`TARGET_CORE`) gets an empty `BCM7` / `BCM4`
  (boot of the core) from `TARGET_CORES`.
- The values are stored in the non-allocated ELF section `.option_bytes` of the firmware and of the integration test
  firmwares (text `EMBI_OPTION_BYTES 1`, `MCU <preset>`, `DEVICE_ID <id>`, `<name> <value>` per line, generated
  assembler source with the flag `R` - kept by `--gc-sections`); the loaded content and the segments of the firmware
  are not changed, a firmware without set option bytes has no section (unchanged firmware).
- Every value can be set - also the irreversible ones (RDP level 2, ...); the flash of the platform writes them as
  configured.

The flash of the platform writes the option bytes of the firmware (`OptionBytes/OptionBytes_Flash.cmake`) - the task
*EmBi: Flash* after the download, the integration tests after the download (also on an IT agent - the script is a
part of the test package), the debug configurations of an MCU (step *EmBi: Option bytes \<MCU\>_Debug* of the
preLaunchTask) and of a picked board of this machine: the section is read from the ELF file by CMake, the device
variant of the chip is found by the register checks of the section (a register written by a check gets its value
back), only the option bytes which differ from the chip are written by the write procedure of the family (unlock,
program registers, start, busy, launch or lock), the MCU is reset and the values are read back. A chip with the values
is not written and not reset. The projects of the cores of a multi-core MCU have to set the same option bytes - the
task Flash and the debug configurations compare the firmware with the firmware of the other cores built in the same
build folder of their project (no firmware of the other core - not compared). The task Flash and the debugging of a
board of an IT agent write them by its agent tools (`embi-agent option-bytes` with `OptionBytes_Flash.cmake` of this
platform); agent tools older than the platform - warning, the option bytes are not written.

---

## 🛠️ Requirements

- **CMake ≥ 3.25**

---

## 📜 License
This project is licensed under the
Creative Commons Attribution–NonCommercial 4.0 International (CC BY-NC 4.0).
