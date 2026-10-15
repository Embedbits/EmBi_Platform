################################################################################
# Author: Mr.Nobody
# file:  IntegrationTesting.cmake
# brief: Integration testing on target (boards) - Unity on MCU, results read
#        by debug probe (probe-rs).
#
# Included by Build.cmake when CMAKE_BUILD_TYPE is "IntegrationTest". Modules
# are built for MCU exactly as in firmware build, every registered test creates
# own firmware "IT_<NAME>.elf": test set sources + Unity + ItCore + generated
# runner + libraries listed by the test set.
#
# The framework (ItCore) is independent of MCU, BSP, MCAL and CPU architecture.
# Every test set is independent - it implements the target interface
# (ItCore/IntegrationTesting_Target.h) in its own source: entry point of the
# firmware calling IntegrationTesting_Run(), initialization (ItTarget_Init),
# fault handlers and system reset (ItTarget_SystemReset). Test sets are created
# from the template by Setup scripts (HelperTools/Test_Handler).
#
# Every test case runs after system reset of the MCU (one test case per boot).
# Unity output is stored in RAM mailbox (section .noinit, kept over reset), host
# script IntegrationTesting_Run.cmake selects the probe, checks the MCU, flashes
# the firmware by probe-rs, waits for the end of the tests and reads the output
# over the debug port. No peripheral (USART, pins) is used for results. Faults
# and blocked test cases are reported as failures and the execution continues
# by the next test. The host knows no MCU, board or probe vendor - all target
# data are parameters (or the boards file of the project).
#
# Required tools (parameter or environment variable):
#   UNITY_ROOT            - Unity root folder (src/unity.c), artifact "unity"
#   PROBE_RS_EXECUTABLE   - probe-rs, artifact "probe-rs" (probe search, MCU
#                           check, download, mailbox access, reset)
#
# Optional parameters:
#   INTEGRATION_TEST_BOARD        - Board name = MCU (eg. STM32H503xB), compile definition
#                                   IT_BOARD_<name> selects board dependent pins in tests.
#                                   Parameters of the board are taken from the boards file.
#   INTEGRATION_TEST_BOARDS_FILE  - Boards file (default Build/IntegrationTestBoards.json -
#                                   connected boards written by IntegrationTesting_Detect.cmake
#                                   from the optional IntegrationTestBoards.json of the project):
#                                   preset, probes and parameters (below) of every board, used
#                                   for parameters which are not set.
#   INTEGRATION_TEST_PROBE        - Probes of the board - probe-rs selectors (VID:PID[:SN])
#                                   or serial numbers (list). Empty: probes of the board in the
#                                   boards file, all connected probes without it.
#                                   Environment variable INTEGRATION_TEST_PROBE_SN selects
#                                   the probe when the tests are executed (more equal boards).
#   INTEGRATION_TEST_PROBE_RS_CHIP - probe-rs chip name (default: TARGET_MCU if probe-rs
#                                   knows it)
#   INTEGRATION_TEST_MCU_PRESETS_FILE - Ral presets with MCU identification (default
#                                   Bsp/Ral/RalPresets.json) - ID and flash size registers of
#                                   TARGET_MCU, used for the parameters below which are not set.
#   INTEGRATION_TEST_ID_ADDRESS   - Address of the ID register of the MCU.
#   INTEGRATION_TEST_ID_MASK      - Mask of the ID bits (default 0xFFFFFFFF)
#   INTEGRATION_TEST_ID_VALUE     - Expected ID - the host checks the MCU of the board before
#                                   download and selects the probe of matching MCU when more
#                                   probes are connected. Empty address: MCU is not checked.
#   INTEGRATION_TEST_FLASH_SIZE_ADDRESS - Address of the 16-bit flash size register [KB]
#   INTEGRATION_TEST_FLASH_SIZE_KB - Expected flash size - checked together with the ID.
#   INTEGRATION_TEST_OUTPUT_SIZE  - Size of output buffer in bytes (default 4096)
#   INTEGRATION_TEST_TIMEOUT      - Default timeout of test firmware execution [s]
#   INTEGRATION_TEST_CASE_TIMEOUT - Default timeout of one test case [s], blocked test
#                                   case is aborted by host (reset of MCU)
#   INTEGRATION_TEST_OPTIMIZATION - Optimization option of the test firmware (default -O0).
#                                   Devices with small flash (STM32H7R / STM32H7S: 64 KB) use
#                                   -Os, the firmware of bigger test sets does not fit at -O0.
#   INTEGRATION_TEST_RUN_KNOWN_DEFECTS - Execute tests marked by IT_KNOWN_DEFECT
#   INTEGRATION_TEST_COVERAGE     - OFF (default) / ON: code coverage (gcov) of the tested modules
#                                   (Coverage/Coverage.cmake, ItCore/IntegrationTesting_Coverage.h).
#                                   The libraries under test (COVERAGE_LIBS of the test set,
#                                   default <NAME>_Lib) are compiled with the gcov instrumentation,
#                                   the firmware serializes the counters after the last test case,
#                                   "<NAME>.Run" reads them and converts them to .gcda files of the
#                                   build folder. Targets:
#                                     IntegrationTest_Coverage        report (HTML, Cobertura XML, JSON)
#                                     IntegrationTest_CoverageSummary table of the last report
#                                     IntegrationTest_CoverageMerge   converts the stored data again
#                                     IntegrationTest_CoverageReset   deletes the counters of earlier runs
#                                   Needs the artifact "gcovr" and the gcov and gcov-tool of the compiler.
#   INTEGRATION_TEST_COVERAGE_CTEST_REPORT - ON (default) / OFF: with the coverage ctest creates the
#                                   report and prints the table of the coverage after the last test
#                                   (CTestCustom.cmake of the build folder); scripts which create the
#                                   report themselves switch it OFF
#   INTEGRATION_TEST_COVERAGE_SIZE - Size of the buffer of the coverage data in RAM of the firmware
#                                   [B] (default 49152: the data are about 1.4 times the counters of the
#                                   instrumented code, up to 33 kB for the biggest test sets of
#                                   STM32F722xE; a device with a small RAM needs a smaller value and
#                                   fewer instrumented libraries - the counters take RAM too)
#   INTEGRATION_TEST_COVERAGE_ROOT - Root of the sources in the coverage report (default: source
#                                   folder of the project)
#   INTEGRATION_TEST_COVERAGE_MIN_LINES - Required line coverage in percent, the report fails below
#                                   it (default 0 = not checked)
#
# Registration in module CMakeLists.txt (same principle as unit tests):
#   if(INTEGRATION_TESTING_AVAILABLE STREQUAL "ON")
#       IntegrationTesting_AddPath("${CMAKE_CURRENT_SOURCE_DIR}/Tests/IntegrationTests")
#   endif()
#
# Test definition (<Module>/Tests/IntegrationTests/CMakeLists.txt):
#   IntegrationTesting_Add_Test(
#       NAME          Gpio                  # Test name (CTest prefix, IT_Gpio.elf)
#       TEST_SOURCE   ItTest_Gpio.c         # Unity test file
#       SOURCES       ItTarget_Gpio.c       # Target interface + other test sources
#       INCLUDE_DIRS  ...                   # Include paths
#       DEFINITIONS   ...                   # Compile definitions
#       LINK_LIBS     StartUp_Lib Gpio_Lib  # All libraries of the firmware (startup,
#                                           # module under test, ...)
#       TIMEOUT       30                    # Execution timeout of all test cases [s]
#       CASE_TIMEOUT  5                     # Timeout of one test case [s]
#       COVERAGE_LIBS Gpio_Lib              # Libraries under test for INTEGRATION_TEST_COVERAGE
#                                           # (default <NAME>_Lib)
#   )
#   CTest: "<NAME>.Run" executes the firmware (fixture), every
#   "void It_...( void )" function is registered as "<NAME>.<function>".
################################################################################

include_guard(GLOBAL)

#=============================== Constant values ==============================#

set(INTEGRATION_TESTING_DIR             "${CMAKE_CURRENT_LIST_DIR}")

set(INTEGRATION_TEST_BOARD              ""
    CACHE STRING                        "Board used for integration tests - MCU name (eg. STM32H503xB)")

set(INTEGRATION_TEST_BOARDS_FILE        "${CMAKE_SOURCE_DIR}/Build/IntegrationTestBoards.json"
    CACHE FILEPATH                      "Connected boards (IntegrationTesting_Detect.cmake) - preset, probes and parameters of every board")

set(INTEGRATION_TEST_MCU_PRESETS_FILE   "${CMAKE_SOURCE_DIR}/Bsp/Ral/RalPresets.json"
    CACHE FILEPATH                      "Ral presets with MCU identification (ID and flash size registers)")

set(INTEGRATION_TEST_PROBE              ""
    CACHE STRING                        "Probes of the board - probe-rs selectors VID:PID[:SN] or serial numbers (empty = all)")

set(INTEGRATION_TEST_PROBE_RS_CHIP      ""
    CACHE STRING                        "probe-rs chip name of the MCU (empty = TARGET_MCU if probe-rs knows it)")

set(INTEGRATION_TEST_ID_ADDRESS         ""
    CACHE STRING                        "Address of the MCU ID register (empty = MCU is not checked)")

set(INTEGRATION_TEST_ID_MASK            ""
    CACHE STRING                        "Mask of the MCU ID bits (empty = 0xFFFFFFFF)")

set(INTEGRATION_TEST_ID_VALUE           ""
    CACHE STRING                        "Expected MCU ID (after mask)")

set(INTEGRATION_TEST_FLASH_SIZE_ADDRESS ""
    CACHE STRING                        "Address of the 16-bit flash size register [KB] (empty = flash size is not checked)")

set(INTEGRATION_TEST_FLASH_SIZE_KB      ""
    CACHE STRING                        "Expected flash size of the MCU [KB]")

set(INTEGRATION_TEST_OUTPUT_SIZE        "4096"
    CACHE STRING                        "Size of Unity output buffer in RAM [B]")

set(INTEGRATION_TEST_TIMEOUT            "60"
    CACHE STRING                        "Default timeout of integration test firmware execution [s]")

set(INTEGRATION_TEST_CASE_TIMEOUT       "10"
    CACHE STRING                        "Default timeout of one integration test case [s]")

option(INTEGRATION_TEST_RUN_KNOWN_DEFECTS "Execute tests of known defects (IT_KNOWN_DEFECT) instead of ignoring them" OFF)

option(INTEGRATION_TEST_COVERAGE        "Code coverage (gcov) of the tested modules" OFF)

option(INTEGRATION_TEST_COVERAGE_CTEST_REPORT "ctest prints the table of the coverage after the tests (with INTEGRATION_TEST_COVERAGE)" ON)

set(INTEGRATION_TEST_COVERAGE_SIZE      "49152"
    CACHE STRING                        "Size of the buffer of the coverage data in RAM of the firmware [B]")

set(INTEGRATION_TEST_COVERAGE_ROOT      "${CMAKE_SOURCE_DIR}"
    CACHE PATH                          "Root of the sources in the coverage report")

set(INTEGRATION_TEST_COVERAGE_MIN_LINES "0"
    CACHE STRING                        "Required line coverage in percent (0 = not checked)")

set(INTEGRATION_TEST_OPTIMIZATION       "${OPTIMIZATION_NONE}"
    CACHE STRING                        "Optimization option of the test firmware (-O0 default, -Og / -Os for devices with small flash)")

# Build type specific flags (as CMAKE_C_FLAGS_DEBUG) - test firmware is debuggable
set(CMAKE_C_FLAGS_INTEGRATIONTEST       "${INTEGRATION_TEST_OPTIMIZATION} ${DEBUG_LEVEL_3}")
set(CMAKE_ASM_FLAGS_INTEGRATIONTEST     "${DEBUG_LEVEL_3}")

#============================= Tools localization =============================#

if(NOT UNITY_ROOT AND DEFINED ENV{UNITY_ROOT})
    set(UNITY_ROOT "$ENV{UNITY_ROOT}")
endif()

if(NOT UNITY_ROOT OR NOT EXISTS "${UNITY_ROOT}/src/unity.c")
    message(FATAL_ERROR "UNITY_ROOT is not set or does not contain src/unity.c ('${UNITY_ROOT}'). "
                        "Add the artifact 'unity' to ArtifactsConfig.txt or pass -DUNITY_ROOT=<path>.")
endif()

set(UNITY_ROOT "${UNITY_ROOT}" CACHE PATH "Unity root folder" FORCE)

# probe-rs comes from the artifact (PROBE_RS_EXECUTABLE is exported by the artifact
# initialization) or from the parameter - probe-rs installed in the system (PATH)
# is not searched.
if(NOT PROBE_RS_EXECUTABLE)
    message(WARNING "probe-rs not found. Test firmware is built, but tests cannot be executed. "
                    "Add the artifact 'probe-rs' or pass -DPROBE_RS_EXECUTABLE=<path>.")
endif()

# gcovr of the coverage report (artifact "gcovr")
if(INTEGRATION_TEST_COVERAGE)
    include("${INTEGRATION_TESTING_DIR}/../Coverage/Coverage.cmake")
    Coverage_Provide_Gcovr(INTEGRATION_TEST_COVERAGE)
endif()

#============================ Board parameters ================================#

# Parameters of the board from the boards file - used for parameters which are
# not set (command line, preset and cache have priority):
#   { "boards": { "<INTEGRATION_TEST_BOARD>": { "preset": "<configure preset>",
#                 "probes": [ "<VID:PID:SN>", ... ],
#                 "cacheVariables": { "INTEGRATION_TEST_...": "<value>", ... } } } }
if(INTEGRATION_TEST_BOARD AND EXISTS "${INTEGRATION_TEST_BOARDS_FILE}")

    file(READ "${INTEGRATION_TEST_BOARDS_FILE}" IT_BOARDS_CONTENT)

    string(JSON IT_BOARD_CONFIG ERROR_VARIABLE IT_BOARD_ERROR GET "${IT_BOARDS_CONTENT}" boards ${INTEGRATION_TEST_BOARD})

    if(IT_BOARD_ERROR)
        message(STATUS "Board ${INTEGRATION_TEST_BOARD} is not defined in ${INTEGRATION_TEST_BOARDS_FILE}.")
    else()
        string(JSON IT_PROBES_CNT ERROR_VARIABLE IT_PROBES_ERROR LENGTH "${IT_BOARD_CONFIG}" probes)

        if(NOT INTEGRATION_TEST_PROBE AND NOT IT_PROBES_ERROR AND IT_PROBES_CNT GREATER 0)
            math(EXPR IT_PROBES_LAST "${IT_PROBES_CNT} - 1")

            foreach(IT_PROBE_IDX RANGE ${IT_PROBES_LAST})
                string(JSON IT_BOARD_PROBE GET "${IT_BOARD_CONFIG}" probes ${IT_PROBE_IDX})
                list(APPEND INTEGRATION_TEST_PROBE "${IT_BOARD_PROBE}")
            endforeach()
        endif()

        string(JSON IT_VARS_CNT ERROR_VARIABLE IT_VARS_ERROR LENGTH "${IT_BOARD_CONFIG}" cacheVariables)

        if(NOT IT_VARS_ERROR AND IT_VARS_CNT GREATER 0)
            math(EXPR IT_VARS_LAST "${IT_VARS_CNT} - 1")

            foreach(IT_VAR_IDX RANGE ${IT_VARS_LAST})
                string(JSON IT_VAR_NAME  MEMBER "${IT_BOARD_CONFIG}" cacheVariables ${IT_VAR_IDX})
                string(JSON IT_VAR_VALUE GET    "${IT_BOARD_CONFIG}" cacheVariables ${IT_VAR_NAME})

                if("${${IT_VAR_NAME}}" STREQUAL "")
                    set(${IT_VAR_NAME} "${IT_VAR_VALUE}")
                endif()
            endforeach()
        endif()
    endif()

endif()

# MCU identification of the target MCU preset (TARGET_MCU_FULL_NAME, eg.
# STM32F407xG) from the Ral presets (vendor data "identification",
# IntegrationTesting_Probe.cmake) - used for parameters which are not set
set(IT_IDENTIFICATION_DEVICE "")

if(TARGET_MCU_FULL_NAME)

    include("${INTEGRATION_TESTING_DIR}/IntegrationTesting_Probe.cmake")

    IntegrationTesting_ReadMcuIdentification(IT_IDENTIFIED_MCUS "${INTEGRATION_TEST_MCU_PRESETS_FILE}")

    if("${TARGET_MCU_FULL_NAME}" IN_LIST IT_IDENTIFIED_MCUS)
        set(IT_MCU "${TARGET_MCU_FULL_NAME}")
        set(IT_IDENTIFICATION_DEVICE "${IT_MCU_${IT_MCU}_DEVICE}")

        if(NOT INTEGRATION_TEST_ID_ADDRESS)
            set(INTEGRATION_TEST_ID_ADDRESS "${IT_MCU_${IT_MCU}_ID_ADDRESS}")
            set(INTEGRATION_TEST_ID_MASK    "${IT_MCU_${IT_MCU}_ID_MASK}")
            set(INTEGRATION_TEST_ID_VALUE   "${IT_MCU_${IT_MCU}_ID_VALUE}")
        endif()

        if(NOT INTEGRATION_TEST_FLASH_SIZE_ADDRESS)
            set(INTEGRATION_TEST_FLASH_SIZE_ADDRESS "${IT_MCU_${IT_MCU}_FLASH_SIZE_ADDRESS}")
            set(INTEGRATION_TEST_FLASH_SIZE_KB      "${IT_MCU_${IT_MCU}_FLASH_SIZE_KB}")
        endif()
    else()
        message(STATUS "No MCU identification of ${TARGET_MCU_FULL_NAME} in ${INTEGRATION_TEST_MCU_PRESETS_FILE}.")
    endif()

endif()

# probe-rs chip - device of the MCU identification or TARGET_MCU, the first one
# probe-rs knows ("probe-rs chip info"); naming of MCUs is not interpreted (the
# board defines its chip otherwise)
if(NOT INTEGRATION_TEST_PROBE_RS_CHIP AND PROBE_RS_EXECUTABLE)

    foreach(IT_CHIP_CANDIDATE IN ITEMS "${IT_IDENTIFICATION_DEVICE}" "${TARGET_MCU_FULL_NAME}")

        if(NOT IT_CHIP_CANDIDATE)
            continue()
        endif()

        execute_process(COMMAND "${PROBE_RS_EXECUTABLE}" chip info "${IT_CHIP_CANDIDATE}"
                        RESULT_VARIABLE IT_CHIP_RESULT
                        OUTPUT_QUIET
                        ERROR_QUIET)

        if(IT_CHIP_RESULT EQUAL 0)
            set(INTEGRATION_TEST_PROBE_RS_CHIP "${IT_CHIP_CANDIDATE}")
            break()
        endif()

    endforeach()

    if(NOT INTEGRATION_TEST_PROBE_RS_CHIP)
        message(STATUS "probe-rs does not know chip '${TARGET_MCU_FULL_NAME}' (TARGET_MCU) - tests cannot be "
                       "executed until INTEGRATION_TEST_PROBE_RS_CHIP is set (boards file or parameter).")
    endif()

endif()

if(NOT INTEGRATION_TEST_ID_MASK)
    set(INTEGRATION_TEST_ID_MASK "0xFFFFFFFF")
endif()

if(INTEGRATION_TEST_FLASH_SIZE_ADDRESS AND "${INTEGRATION_TEST_FLASH_SIZE_KB}" STREQUAL "")
    message(FATAL_ERROR "INTEGRATION_TEST_FLASH_SIZE_ADDRESS is set, but INTEGRATION_TEST_FLASH_SIZE_KB is not.")
endif()

if(INTEGRATION_TEST_ID_ADDRESS AND "${INTEGRATION_TEST_ID_VALUE}" STREQUAL "")
    message(FATAL_ERROR "INTEGRATION_TEST_ID_ADDRESS is set, but INTEGRATION_TEST_ID_VALUE is not.")
endif()

if(NOT INTEGRATION_TEST_ID_ADDRESS)
    message(STATUS "INTEGRATION_TEST_ID_ADDRESS is not set - MCU on the board is not checked.")
endif()

# Host configuration - parameters of IntegrationTesting_Run.cmake (CTest) and
# IntegrationTesting_AllBoards.cmake
set(INTEGRATION_TEST_HOST_CONFIG        "${CMAKE_BINARY_DIR}/IntegrationTesting_Host.cmake")

file(CONFIGURE OUTPUT "${INTEGRATION_TEST_HOST_CONFIG}" CONTENT
"# Generated by IntegrationTesting.cmake - host configuration of integration tests
set(IT_PROBE_RS   [==[${PROBE_RS_EXECUTABLE}]==])
set(IT_CHIP       [==[${INTEGRATION_TEST_PROBE_RS_CHIP}]==])
set(IT_PROBE      [==[${INTEGRATION_TEST_PROBE}]==])
set(IT_ID_ADDRESS [==[${INTEGRATION_TEST_ID_ADDRESS}]==])
set(IT_ID_MASK    [==[${INTEGRATION_TEST_ID_MASK}]==])
set(IT_ID_VALUE   [==[${INTEGRATION_TEST_ID_VALUE}]==])
set(IT_FLASH_SIZE_ADDRESS [==[${INTEGRATION_TEST_FLASH_SIZE_ADDRESS}]==])
set(IT_FLASH_SIZE_KB      [==[${INTEGRATION_TEST_FLASH_SIZE_KB}]==])
")

message(STATUS "Unity:                ${UNITY_ROOT}")
message(STATUS "probe-rs:             ${PROBE_RS_EXECUTABLE}")
message(STATUS "Board:                ${INTEGRATION_TEST_BOARD}")
message(STATUS "Chip:                 ${INTEGRATION_TEST_PROBE_RS_CHIP}")
message(STATUS "Probe:                ${INTEGRATION_TEST_PROBE}")
message(STATUS "MCU ID:               ${INTEGRATION_TEST_ID_ADDRESS} & ${INTEGRATION_TEST_ID_MASK} == ${INTEGRATION_TEST_ID_VALUE}")
message(STATUS "Flash size:           ${INTEGRATION_TEST_FLASH_SIZE_ADDRESS} == ${INTEGRATION_TEST_FLASH_SIZE_KB} KB")

#=========================== Testing libraries ================================#

enable_testing()

# Modules register their integration tests only if this flag is ON
set(INTEGRATION_TESTING_AVAILABLE       "ON")

# Unity framework for MCU. Output goes to the result mailbox.
add_library(unity STATIC ${UNITY_ROOT}/src/unity.c)

target_include_directories(unity
    PUBLIC
        ${UNITY_ROOT}/src
        ${INTEGRATION_TESTING_DIR}/ItCore
)

target_compile_definitions(unity
    PUBLIC
        UNITY_INCLUDE_CONFIG_H          # ItCore/unity_config.h - output to mailbox
        UNITY_INCLUDE_DOUBLE
        IT_OUTPUT_SIZE=${INTEGRATION_TEST_OUTPUT_SIZE}u
)

# Execution of test cases and result mailbox (target independent). Target
# interface (IntegrationTesting_Target.h) is implemented by every test set.
add_library(ItCore STATIC ${INTEGRATION_TESTING_DIR}/ItCore/IntegrationTesting.c)

target_link_libraries(ItCore
    PUBLIC
        unity
)

# Coverage of the tested code: serialization of the gcov counters after the last test case
if(INTEGRATION_TEST_COVERAGE)

    target_sources(ItCore
        PRIVATE
            ${INTEGRATION_TESTING_DIR}/ItCore/IntegrationTesting_Coverage.c
    )

    target_compile_definitions(ItCore
        PRIVATE
            IT_COVERAGE
            IT_COVERAGE_SIZE=${INTEGRATION_TEST_COVERAGE_SIZE}u
    )

    # Instrumentation of the libraries under test. -fprofile-info-section: no constructors, the
    # firmware registers the gcov information in the linker section .gcov_info; -fdata-sections:
    # the counters are in own sections (.bss.__gcov0.<function>), which the linker script
    # IntegrationTesting_GcovCounters.ld keeps over reset. The prefix maps make the names in the
    # .gcno / .gcda files relative to the project (the sources) and to the build folder, so
    # the data can be evaluated in another folder or on another machine than the one which built the
    # firmware (the coverage stage of a pipeline). The more specific map is the last one.
    set(IT_COVERAGE_COMPILE_OPTIONS
        --coverage
        -fprofile-info-section
        -fdata-sections
        "-fprofile-prefix-map=${CMAKE_SOURCE_DIR}=."
        "-fprofile-prefix-map=${CMAKE_BINARY_DIR}=."
    )

    set(IT_COVERAGE_LINK_OPTIONS
        --coverage
        "-Wl,-T,${INTEGRATION_TESTING_DIR}/ItCore/IntegrationTesting_GcovInfo.ld"
        "-Wl,-T,${INTEGRATION_TESTING_DIR}/ItCore/IntegrationTesting_GcovCounters.ld"
    )

endif()

#================================ Functions ===================================#

#------------------------------------------------------------------------------#
# Registers folder with integration tests of the module. Called from module
# CMakeLists.txt:
#
#   if(INTEGRATION_TESTING_AVAILABLE STREQUAL "ON")
#       IntegrationTesting_AddPath("${CMAKE_CURRENT_SOURCE_DIR}/Tests/IntegrationTests")
#   endif()
#
# Folders are only collected here, tests are created by
# IntegrationTesting_Generate() after all modules are processed.
#
# INTEGRATION_TEST_PATH_ARG [in]: Folder containing CMakeLists.txt of tests.
#------------------------------------------------------------------------------#
function(IntegrationTesting_AddPath INTEGRATION_TEST_PATH_ARG)

    get_filename_component(IT_PATH "${INTEGRATION_TEST_PATH_ARG}" ABSOLUTE)

    if(EXISTS "${IT_PATH}/CMakeLists.txt")
        set_property(GLOBAL APPEND PROPERTY INTEGRATION_TESTING_PATHS "${IT_PATH}")
    else()
        message(WARNING "Integration tests registered, but ${IT_PATH}/CMakeLists.txt does not exist.")
    endif()

endfunction(IntegrationTesting_AddPath)


#------------------------------------------------------------------------------#
# Creates all registered integration tests. Called by Build.cmake after Bsp,
# Middlewares and Application are processed and MCU flags are configured.
#
# Module libraries are excluded from "all" target - only test firmware (and
# libraries it links) is built.
#------------------------------------------------------------------------------#
function(IntegrationTesting_Generate)

    integrationTesting_ExcludeFromAll("${CMAKE_SOURCE_DIR}")

    get_property(IT_PATHS GLOBAL PROPERTY INTEGRATION_TESTING_PATHS)

    list(REMOVE_DUPLICATES IT_PATHS)

    foreach(IT_PATH IN LISTS IT_PATHS)

        file(RELATIVE_PATH IT_PATH_REL "${CMAKE_SOURCE_DIR}" "${IT_PATH}")

        message(STATUS "Integration tests registered: ${IT_PATH_REL}")

        add_subdirectory("${IT_PATH}" "${CMAKE_BINARY_DIR}/IntegrationTests/${IT_PATH_REL}")

    endforeach()

    list(LENGTH IT_PATHS IT_PATHS_CNT)

    if(IT_PATHS_CNT EQUAL 0)
        message(WARNING "No integration tests registered (IntegrationTesting_AddPath not called by any module).")
    endif()

    # Coverage targets of all tests
    integrationTesting_CoverageTargets()

endfunction(IntegrationTesting_Generate)


#------------------------------------------------------------------------------#
# Excludes all targets of the folder and its subfolders from "all" target.
#
# DIRECTORY_ARG [in]: Processed source folder (CMake directory scope).
#------------------------------------------------------------------------------#
function(integrationTesting_ExcludeFromAll DIRECTORY_ARG)

    get_property(DIR_TARGETS DIRECTORY "${DIRECTORY_ARG}" PROPERTY BUILDSYSTEM_TARGETS)
    get_property(SUB_DIRS    DIRECTORY "${DIRECTORY_ARG}" PROPERTY SUBDIRECTORIES)

    foreach(DIR_TARGET IN LISTS DIR_TARGETS)

        get_target_property(TARGET_TYPE ${DIR_TARGET} TYPE)

        if(NOT TARGET_TYPE STREQUAL "INTERFACE_LIBRARY")
            set_target_properties(${DIR_TARGET} PROPERTIES EXCLUDE_FROM_ALL TRUE)
        endif()

    endforeach()

    foreach(SUB_DIR IN LISTS SUB_DIRS)
        integrationTesting_ExcludeFromAll("${SUB_DIR}")
    endforeach()

endfunction(integrationTesting_ExcludeFromAll)


#------------------------------------------------------------------------------#
# Prepares the firmware of the test for the coverage: the libraries under test are
# compiled with the gcov instrumentation (once, a library is shared by the firmwares)
# and the firmware gets libgcov and the linker scripts of the coverage.
#
# TEST_TARGET   [in]: Test firmware
# IT_NAME       [in]: Name of the test (the default library under test is <IT_NAME>_Lib)
# COVERAGE_LIBS [in]: Libraries under test ("" = <IT_NAME>_Lib)
#------------------------------------------------------------------------------#
function(integrationTesting_Instrument TEST_TARGET IT_NAME COVERAGE_LIBS)

    if("${COVERAGE_LIBS}" STREQUAL "")
        set(COVERAGE_LIBS "${IT_NAME}_Lib")
    endif()

    get_property(INSTRUMENTED_LIBS GLOBAL PROPERTY INTEGRATION_TESTING_INSTRUMENTED_LIBS)

    set(FOUND_LIBS 0)

    foreach(COVERAGE_LIB IN LISTS COVERAGE_LIBS)

        if(NOT TARGET ${COVERAGE_LIB})
            message(STATUS "Coverage of ${TEST_TARGET}: library ${COVERAGE_LIB} does not exist - not instrumented.")
            continue()
        endif()

        if(NOT "${COVERAGE_LIB}" IN_LIST INSTRUMENTED_LIBS)
            target_compile_options(${COVERAGE_LIB} PRIVATE ${IT_COVERAGE_COMPILE_OPTIONS})
            set_property(GLOBAL APPEND PROPERTY INTEGRATION_TESTING_INSTRUMENTED_LIBS "${COVERAGE_LIB}")
        endif()

        math(EXPR FOUND_LIBS "${FOUND_LIBS} + 1")

    endforeach()

    if(FOUND_LIBS EQUAL 0)
        message(WARNING "Coverage of ${TEST_TARGET}: no library under test (${COVERAGE_LIBS}) - the report will not "
                        "contain the code of the test. List the libraries by COVERAGE_LIBS of the test set.")
    endif()

    target_link_options(${TEST_TARGET} PRIVATE ${IT_COVERAGE_LINK_OPTIONS})

    # The firmware is linked again when a linker script of the coverage changes
    set_property(TARGET ${TEST_TARGET} APPEND PROPERTY LINK_DEPENDS
        "${INTEGRATION_TESTING_DIR}/ItCore/IntegrationTesting_GcovInfo.ld"
        "${INTEGRATION_TESTING_DIR}/ItCore/IntegrationTesting_GcovCounters.ld")

endfunction(integrationTesting_Instrument)


#------------------------------------------------------------------------------#
# Creates the coverage targets of the integration tests (INTEGRATION_TEST_COVERAGE=ON),
# see Coverage.cmake: IntegrationTest_Coverage, IntegrationTest_CoverageSummary,
# IntegrationTest_CoverageReset and IntegrationTest_CoverageMerge (converts the stored
# coverage data of the firmwares to .gcda files again).
# Called by IntegrationTesting_Generate() after all tests are created.
#------------------------------------------------------------------------------#
function(integrationTesting_CoverageTargets)

    if(NOT INTEGRATION_TEST_COVERAGE)
        return()
    endif()

    Coverage_Find_Gcov(GCOV "${CMAKE_C_COMPILER}" "${CMAKE_C_COMPILER_ID}")

    if(NOT GCOV)
        message(FATAL_ERROR "INTEGRATION_TEST_COVERAGE is ON but gcov of the compiler ${CMAKE_C_COMPILER} was not found "
                            "next to it (gcov of another compiler gives wrong data).")
    endif()

    # gcov-tool and objcopy of the same toolchain (arm-none-eabi-gcc -> arm-none-eabi-gcov-tool,
    # arm-none-eabi-objcopy): they convert the coverage data read from the target
    get_filename_component(COMPILER_DIR  "${CMAKE_C_COMPILER}" DIRECTORY)
    get_filename_component(COMPILER_FILE "${CMAKE_C_COMPILER}" NAME)

    string(REGEX REPLACE "\\.exe$" "" COMPILER_FILE "${COMPILER_FILE}")

    foreach(TOOL IN ITEMS gcov-tool objcopy)

        string(REGEX REPLACE "gcc(-[0-9.]+)?$" "${TOOL}\\1" TOOL_NAME "${COMPILER_FILE}")
        string(MAKE_C_IDENTIFIER "${TOOL}" TOOL_ID)

        find_program(IT_TOOL_${TOOL_ID} NAMES "${TOOL_NAME}" HINTS "${COMPILER_DIR}" NO_DEFAULT_PATH NO_CACHE)

        if(NOT IT_TOOL_${TOOL_ID})
            message(FATAL_ERROR "INTEGRATION_TEST_COVERAGE is ON but ${TOOL_NAME} was not found next to the compiler ${CMAKE_C_COMPILER}.")
        endif()

    endforeach()

    set(GCOV_TOOL    "${IT_TOOL_gcov_tool}")
    set(OBJCOPY_TOOL "${IT_TOOL_objcopy}")

    message(STATUS "gcov:      ${GCOV}")
    message(STATUS "gcov-tool: ${GCOV_TOOL}")
    message(STATUS "objcopy:   ${OBJCOPY_TOOL}")

    # Conversion of the coverage data by "<NAME>.Run" (tools of the host configuration)
    file(APPEND "${INTEGRATION_TEST_HOST_CONFIG}"
"set(IT_COVERAGE_MERGE [==[ON]==])
set(IT_OBJCOPY    [==[${OBJCOPY_TOOL}]==])
set(IT_GCOV_TOOL  [==[${GCOV_TOOL}]==])
set(IT_BUILD_DIR  [==[${CMAKE_BINARY_DIR}]==])
")

    # Test sources and the target library of the vendor are not reported
    set(COVERAGE_EXCLUDES ".*/Tests/.*" ".*/Ral/.*")

    set(COVERAGE_CTEST_REPORT "")

    if(INTEGRATION_TEST_COVERAGE_CTEST_REPORT)
        set(COVERAGE_CTEST_REPORT CTEST_REPORT)
    endif()

    Coverage_Add_Targets(
        ${COVERAGE_CTEST_REPORT}
        PREFIX      IntegrationTest
        TITLE       "Integration tests coverage - ${CMAKE_PROJECT_NAME}"
        GCOV        "${GCOV}"
        ROOT        "${INTEGRATION_TEST_COVERAGE_ROOT}"
        SEARCH_DIRS "${CMAKE_BINARY_DIR}"
        EXCLUDES    ${COVERAGE_EXCLUDES}
        MIN_LINES   "${INTEGRATION_TEST_COVERAGE_MIN_LINES}"
        RELATIVE_PATHS
    )

    get_property(COVERAGE_DUMPS GLOBAL PROPERTY INTEGRATION_TESTING_COVERAGE_DUMPS)

    add_custom_target(IntegrationTest_CoverageMerge
        COMMAND "${CMAKE_COMMAND}"
                "-DIT_COV_DUMPS=${COVERAGE_DUMPS}"
                "-DIT_COV_BUILD_DIR=${CMAKE_BINARY_DIR}"
                "-DIT_OBJCOPY=${OBJCOPY_TOOL}"
                "-DIT_GCOV_TOOL=${GCOV_TOOL}"
                -P "${INTEGRATION_TESTING_DIR}/IntegrationTesting_Coverage.cmake"
        COMMENT "Converting the stored coverage data of the integration tests"
        VERBATIM
    )

endfunction(integrationTesting_CoverageTargets)

#------------------------------------------------------------------------------#
# Creates integration test firmware and registers its test cases in CTest.
#
# Generates Unity runner of TEST_SOURCE (CMake, no Ruby needed), builds
# firmware "IT_<NAME>" (.elf, .hex) and registers:
#   "<NAME>.Run"        - flashes and executes the firmware, stores the output
#                         (fixture of the test cases, label "integration")
#   "<NAME>.<function>" - result of one test function from the stored output
#
# See file header for the list of arguments.
#------------------------------------------------------------------------------#
function(IntegrationTesting_Add_Test)

    cmake_parse_arguments(IT
        ""
        "NAME;TEST_SOURCE;TIMEOUT;CASE_TIMEOUT"
        "SOURCES;INCLUDE_DIRS;DEFINITIONS;LINK_LIBS;COVERAGE_LIBS"
        ${ARGN})

    if(NOT IT_NAME OR NOT IT_TEST_SOURCE)
        message(FATAL_ERROR "IntegrationTesting_Add_Test: NAME and TEST_SOURCE are required.")
    endif()

    if(NOT IT_TIMEOUT)
        set(IT_TIMEOUT "${INTEGRATION_TEST_TIMEOUT}")
    endif()

    if(NOT IT_CASE_TIMEOUT)
        set(IT_CASE_TIMEOUT "${INTEGRATION_TEST_CASE_TIMEOUT}")
    endif()

    get_filename_component(IT_TEST_SOURCE "${IT_TEST_SOURCE}" ABSOLUTE)
    get_filename_component(TEST_SOURCE_NAME "${IT_TEST_SOURCE}" NAME)

    set(TEST_TARGET     "IT_${IT_NAME}")
    set(RUNNER_SOURCE   "${CMAKE_CURRENT_BINARY_DIR}/${TEST_TARGET}_Runner.c")
    set(OUTPUT_LOG      "${CMAKE_CURRENT_BINARY_DIR}/${TEST_TARGET}.log")

    # Test functions of the test file (the same rule as unit tests)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${IT_TEST_SOURCE}")

    file(STRINGS "${IT_TEST_SOURCE}" TEST_FUNCTIONS
         REGEX "^[ \t]*void[ \t]+It_[A-Za-z0-9_]*[ \t]*\\([ \t]*(void)?[ \t]*\\)")

    set(TEST_CASES "")

    foreach(TEST_FUNCTION IN LISTS TEST_FUNCTIONS)
        string(REGEX MATCH "It_[A-Za-z0-9_]*" TEST_CASE "${TEST_FUNCTION}")
        list(APPEND TEST_CASES "${TEST_CASE}")
    endforeach()

    list(LENGTH TEST_CASES TEST_CASES_CNT)

    if(TEST_CASES_CNT EQUAL 0)
        message(WARNING "IntegrationTesting_Add_Test: no test function found in ${IT_TEST_SOURCE}")
    endif()

    # Runner generation - table of test cases (line of the test function is reported by Unity)
    file(READ "${IT_TEST_SOURCE}" TEST_SOURCE_CONTENT)

    set(RUNNER_DECLARATIONS "")
    set(RUNNER_CASES        "")

    foreach(TEST_CASE IN LISTS TEST_CASES)

        string(REGEX MATCH "void[ \t]+${TEST_CASE}[ \t]*\\(" TEST_CASE_DEFINITION "${TEST_SOURCE_CONTENT}")
        string(FIND "${TEST_SOURCE_CONTENT}" "${TEST_CASE_DEFINITION}" TEST_CASE_POSITION)
        string(SUBSTRING "${TEST_SOURCE_CONTENT}" 0 ${TEST_CASE_POSITION} TEST_CASE_PREFIX)
        string(REGEX MATCHALL "\n" TEST_CASE_NEWLINES "${TEST_CASE_PREFIX}")
        list(LENGTH TEST_CASE_NEWLINES TEST_CASE_LINE)
        math(EXPR TEST_CASE_LINE "${TEST_CASE_LINE} + 1")

        string(APPEND RUNNER_DECLARATIONS "void ${TEST_CASE}( void );\n")
        string(APPEND RUNNER_CASES        "    { ${TEST_CASE}, \"${TEST_CASE}\", ${TEST_CASE_LINE}u },\n")

    endforeach()

    configure_file("${INTEGRATION_TESTING_DIR}/ItCore/IntegrationTesting_Runner.c.in" "${RUNNER_SOURCE}" @ONLY)

    # Test firmware
    add_executable(${TEST_TARGET}
        ${IT_TEST_SOURCE}
        ${RUNNER_SOURCE}
        ${IT_SOURCES}
    )

    set_target_properties(${TEST_TARGET} PROPERTIES SUFFIX ".elf")

    target_include_directories(${TEST_TARGET}
        PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}
            ${IT_INCLUDE_DIRS}
    )

    target_compile_definitions(${TEST_TARGET}
        PRIVATE
            INTEGRATION_TEST
            $<$<BOOL:${INTEGRATION_TEST_BOARD}>:IT_BOARD_${INTEGRATION_TEST_BOARD}>
            $<$<BOOL:${INTEGRATION_TEST_RUN_KNOWN_DEFECTS}>:IT_RUN_KNOWN_DEFECTS>
            ${IT_DEFINITIONS}
    )

    target_compile_options(${TEST_TARGET}
        PRIVATE
            -Wall -Wextra
    )

    # Own map file of every firmware (overrides the map of CMAKE_C_FLAGS)
    target_link_options(${TEST_TARGET}
        PRIVATE
            "-Wl,-Map=${CMAKE_CURRENT_BINARY_DIR}/${TEST_TARGET}.map"
    )

    target_link_libraries(${TEST_TARGET}
        PRIVATE
            ${IT_LINK_LIBS}
            ItCore
    )

    add_custom_command(
        TARGET ${TEST_TARGET}
        POST_BUILD
        COMMAND ${CMAKE_SIZE} $<TARGET_FILE:${TEST_TARGET}>
        COMMAND ${CMAKE_OBJCOPY} -O ihex $<TARGET_FILE:${TEST_TARGET}> ${CMAKE_CURRENT_BINARY_DIR}/${TEST_TARGET}.hex
        COMMENT "Integration test firmware ${TEST_TARGET}"
        VERBATIM
    )

    # Coverage of the libraries under test: instrumentation, linker scripts, the file with the
    # coverage data read from the target
    set(COVERAGE_DUMP_ARGUMENT "")

    if(INTEGRATION_TEST_COVERAGE)

        integrationTesting_Instrument(${TEST_TARGET} "${IT_NAME}" "${IT_COVERAGE_LIBS}")

        set(COVERAGE_DUMP "${CMAKE_CURRENT_BINARY_DIR}/${TEST_TARGET}.cov.ihex")

        set(COVERAGE_DUMP_ARGUMENT "-DIT_COVERAGE_DUMP=${COVERAGE_DUMP}")

        set_property(GLOBAL APPEND PROPERTY INTEGRATION_TESTING_COVERAGE_DUMPS "${COVERAGE_DUMP}")

    endif()

    # Execution of the firmware on target (fixture of all test cases)
    add_test(NAME "${IT_NAME}.Run"
             COMMAND ${CMAKE_COMMAND}
                     "-DIT_ELF=$<TARGET_FILE:${TEST_TARGET}>"
                     "-DIT_LOG=${OUTPUT_LOG}"
                     "-DIT_NM=${CMAKE_NM}"
                     "-DIT_CONFIG=${INTEGRATION_TEST_HOST_CONFIG}"
                     "-DIT_TIMEOUT=${IT_TIMEOUT}"
                     "-DIT_CASE_TIMEOUT=${IT_CASE_TIMEOUT}"
                     ${COVERAGE_DUMP_ARGUMENT}
                     -P "${INTEGRATION_TESTING_DIR}/IntegrationTesting_Run.cmake")

    math(EXPR RUN_TIMEOUT "${IT_TIMEOUT} + 60")

    set_tests_properties("${IT_NAME}.Run" PROPERTIES
        FIXTURES_SETUP  "${TEST_TARGET}"
        RUN_SERIAL      TRUE
        TIMEOUT         ${RUN_TIMEOUT}
        LABELS          "integration;${IT_NAME}"
    )

    # Result of every test function
    foreach(TEST_CASE IN LISTS TEST_CASES)

        add_test(NAME "${IT_NAME}.${TEST_CASE}"
                 COMMAND ${CMAKE_COMMAND}
                         "-DIT_LOG=${OUTPUT_LOG}"
                         "-DIT_CASE=${TEST_CASE}"
                         -P "${INTEGRATION_TESTING_DIR}/IntegrationTesting_Check.cmake")

        set_tests_properties("${IT_NAME}.${TEST_CASE}" PROPERTIES
            FIXTURES_REQUIRED       "${TEST_TARGET}"
            SKIP_REGULAR_EXPRESSION ":IGNORE"
            LABELS                  "integration;${IT_NAME}"
        )

    endforeach()

    message(STATUS "Integration test ${TEST_TARGET} created (${TEST_CASES_CNT} test cases)")

endfunction(IntegrationTesting_Add_Test)
