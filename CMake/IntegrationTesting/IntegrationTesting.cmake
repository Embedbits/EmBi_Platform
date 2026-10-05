################################################################################
# Author: Mr.Nobody
# file:  IntegrationTesting.cmake
# brief: Integration testing on target (Nucleo boards) - Unity on MCU, results
#        read by debug probe.
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
# script IntegrationTesting_Run.cmake finds the board, flashes the firmware by
# STM32_Programmer_CLI, waits for the end of the tests and reads the output over
# SWD. No peripheral (USART, pins) is used for results. Faults and blocked test
# cases are reported as failures and the execution continues by the next test.
#
# Required tools (parameter or environment variable):
#   UNITY_ROOT            - Unity root folder (src/unity.c), artifact "unity"
#   STM32_PROGRAMMER_CLI  - STM32CubeProgrammer CLI, searched in default
#                           installation folders and in PATH (probe search by
#                           board name, MCU check)
#   PROBE_RS_EXECUTABLE   - probe-rs, artifact "probe-rs" (download, mailbox
#                           access, reset). STM32CubeProgrammer clears NVIC
#                           interrupt enable registers on every connection
#                           (EmBi_Platform AB#342), probe-rs keeps them.
#
# Optional parameters:
#   INTEGRATION_TEST_BOARD        - Board name (eg. NUCLEO_H503RB), compile definition
#                                   IT_BOARD_<name> selects board dependent pins in tests.
#                                   The probe of the board is found by "Board Name"
#                                   reported by ST-LINK (NUCLEO-H503RB).
#   INTEGRATION_TEST_PROBE        - Probe connection arguments of STM32_Programmer_CLI
#                                   (default "port=SWD"). With "sn=..." the probe is
#                                   used directly (no search by board name). Environment
#                                   variable INTEGRATION_TEST_PROBE_SN selects the probe
#                                   when the tests are executed (more equal boards).
#   INTEGRATION_TEST_OUTPUT_SIZE  - Size of output buffer in bytes (default 4096)
#   INTEGRATION_TEST_TIMEOUT      - Default timeout of test firmware execution [s]
#   INTEGRATION_TEST_CASE_TIMEOUT - Default timeout of one test case [s], blocked test
#                                   case is aborted by host (reset of MCU)
#   INTEGRATION_TEST_RUN_KNOWN_DEFECTS - Execute tests marked by IT_KNOWN_DEFECT
#   INTEGRATION_TEST_DEBUG_TOOL   - Tool of target access during the test: PROBE_RS
#                                   (default if probe-rs is available) or CUBE
#                                   (STM32_Programmer_CLI only)
#   INTEGRATION_TEST_PROBE_RS_CHIP - probe-rs chip name (default derived from board:
#                                   NUCLEO_H503RB -> STM32H503RB)
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
#   )
#   CTest: "<NAME>.Run" executes the firmware (fixture), every
#   "void It_...( void )" function is registered as "<NAME>.<function>".
################################################################################

include_guard(GLOBAL)

#=============================== Constant values ==============================#

set(INTEGRATION_TESTING_DIR             "${CMAKE_CURRENT_LIST_DIR}")

set(INTEGRATION_TEST_PROBE              "port=SWD"
    CACHE STRING                        "STM32_Programmer_CLI connection arguments of the probe")

set(INTEGRATION_TEST_BOARD              ""
    CACHE STRING                        "Board used for integration tests (eg. NUCLEO_H503RB)")

set(INTEGRATION_TEST_OUTPUT_SIZE        "4096"
    CACHE STRING                        "Size of Unity output buffer in RAM [B]")

set(INTEGRATION_TEST_TIMEOUT            "60"
    CACHE STRING                        "Default timeout of integration test firmware execution [s]")

set(INTEGRATION_TEST_CASE_TIMEOUT       "10"
    CACHE STRING                        "Default timeout of one integration test case [s]")

option(INTEGRATION_TEST_RUN_KNOWN_DEFECTS "Execute tests of known defects (IT_KNOWN_DEFECT) instead of ignoring them" OFF)

# Build type specific flags (as CMAKE_C_FLAGS_DEBUG) - test firmware is debuggable
set(CMAKE_C_FLAGS_INTEGRATIONTEST       "${OPTIMIZATION_NONE} ${DEBUG_LEVEL_3}")
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

if(NOT STM32_PROGRAMMER_CLI AND DEFINED ENV{STM32_PROGRAMMER_CLI})
    set(STM32_PROGRAMMER_CLI "$ENV{STM32_PROGRAMMER_CLI}" CACHE FILEPATH "STM32CubeProgrammer CLI" FORCE)
endif()

find_program(STM32_PROGRAMMER_CLI
    NAMES STM32_Programmer_CLI
    PATHS "C:/Program Files/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin"
          "C:/Program Files/ST/STM32Cube/STM32CubeProgrammer/bin"
          "$ENV{HOME}/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin"
          "/opt/st/stm32cubeprogrammer/bin"
)

if(NOT STM32_PROGRAMMER_CLI)
    message(WARNING "STM32_Programmer_CLI not found. Test firmware is built, but tests cannot be executed. "
                    "Pass -DSTM32_PROGRAMMER_CLI=<path>.")
endif()

#=========================== Board identification =============================#

# ST-LINK reports board name with dash (NUCLEO-H503RB), CMake name uses underscore
string(REPLACE "_" "-" INTEGRATION_TEST_BOARD_NAME "${INTEGRATION_TEST_BOARD}")

#=========================== Target access tool ===============================#

if(NOT PROBE_RS_EXECUTABLE)
    find_program(PROBE_RS_EXECUTABLE NAMES probe-rs)
endif()

if(PROBE_RS_EXECUTABLE)
    set(IT_DEFAULT_DEBUG_TOOL "PROBE_RS")
else()
    set(IT_DEFAULT_DEBUG_TOOL "CUBE")
endif()

set(INTEGRATION_TEST_DEBUG_TOOL         "${IT_DEFAULT_DEBUG_TOOL}"
    CACHE STRING                        "Tool of target access during integration tests (PROBE_RS / CUBE)")
set_property(CACHE INTEGRATION_TEST_DEBUG_TOOL PROPERTY STRINGS PROBE_RS CUBE)

# probe-rs chip name - MCU of the Nucleo board (NUCLEO-H503RB -> STM32H503RB)
string(REGEX REPLACE "^NUCLEO-" "STM32" IT_DEFAULT_PROBE_RS_CHIP "${INTEGRATION_TEST_BOARD_NAME}")

set(INTEGRATION_TEST_PROBE_RS_CHIP      "${IT_DEFAULT_PROBE_RS_CHIP}"
    CACHE STRING                        "probe-rs chip name of the board MCU (eg. STM32H503RB)")

set(IT_PROBE_RS_ARG "")

if(INTEGRATION_TEST_DEBUG_TOOL STREQUAL "PROBE_RS")
    if(NOT PROBE_RS_EXECUTABLE)
        message(WARNING "INTEGRATION_TEST_DEBUG_TOOL is PROBE_RS, but probe-rs was not found. "
                        "Add artifact 'probe-rs' or pass -DPROBE_RS_EXECUTABLE=<path>.")
    elseif(NOT INTEGRATION_TEST_PROBE_RS_CHIP)
        message(WARNING "probe-rs chip is not known (INTEGRATION_TEST_BOARD is not set). "
                        "Pass -DINTEGRATION_TEST_PROBE_RS_CHIP=<chip>.")
    else()
        set(IT_PROBE_RS_ARG "${PROBE_RS_EXECUTABLE}")
    endif()
endif()

# Device ID of the MCU (DBGMCU_IDCODE DEV_ID, reported by STM32_Programmer_CLI).
# Host checks it before download - firmware is built for this MCU only.
string(REGEX MATCH "^STM32([A-Z][0-9A-Z][0-9A-Z][0-9A-Z])" _ "${TARGET_MCU}")
set(IT_MCU_LINE "${CMAKE_MATCH_1}")

set(INTEGRATION_TEST_DEVICE_ID "")

if(IT_MCU_LINE STREQUAL "H503")
    set(INTEGRATION_TEST_DEVICE_ID "0x474")
elseif(IT_MCU_LINE MATCHES "^H5[23]3$")
    set(INTEGRATION_TEST_DEVICE_ID "0x478")
elseif(IT_MCU_LINE MATCHES "^H56[23]$" OR IT_MCU_LINE STREQUAL "H573")
    set(INTEGRATION_TEST_DEVICE_ID "0x484")
else()
    message(STATUS "Device ID of ${TARGET_MCU} is not known - MCU on the board is not checked.")
endif()

message(STATUS "Unity:                ${UNITY_ROOT}")
message(STATUS "STM32_Programmer_CLI: ${STM32_PROGRAMMER_CLI}")
message(STATUS "Probe:                ${INTEGRATION_TEST_PROBE}")
message(STATUS "Debug tool:           ${INTEGRATION_TEST_DEBUG_TOOL} ${IT_PROBE_RS_ARG} ${INTEGRATION_TEST_PROBE_RS_CHIP}")
message(STATUS "Board:                ${INTEGRATION_TEST_BOARD_NAME}")
message(STATUS "Device ID:            ${INTEGRATION_TEST_DEVICE_ID}")

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
        "SOURCES;INCLUDE_DIRS;DEFINITIONS;LINK_LIBS"
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

    # Execution of the firmware on target (fixture of all test cases)
    add_test(NAME "${IT_NAME}.Run"
             COMMAND ${CMAKE_COMMAND}
                     "-DIT_ELF=$<TARGET_FILE:${TEST_TARGET}>"
                     "-DIT_LOG=${OUTPUT_LOG}"
                     "-DIT_NM=${CMAKE_NM}"
                     "-DIT_PROGRAMMER=${STM32_PROGRAMMER_CLI}"
                     "-DIT_PROBE=${INTEGRATION_TEST_PROBE}"
                     "-DIT_BOARD=${INTEGRATION_TEST_BOARD_NAME}"
                     "-DIT_DEVICE_ID=${INTEGRATION_TEST_DEVICE_ID}"
                     "-DIT_PROBE_RS=${IT_PROBE_RS_ARG}"
                     "-DIT_PROBE_RS_CHIP=${INTEGRATION_TEST_PROBE_RS_CHIP}"
                     "-DIT_TIMEOUT=${IT_TIMEOUT}"
                     "-DIT_CASE_TIMEOUT=${IT_CASE_TIMEOUT}"
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
