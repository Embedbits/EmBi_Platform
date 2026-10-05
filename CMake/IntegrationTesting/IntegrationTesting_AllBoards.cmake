################################################################################
# Author: Mr.Nobody
# file:  IntegrationTesting_AllBoards.cmake
# brief: Executes integration tests on all connected boards.
#
# Usage (from the project root folder with CMakePresets.json):
#   cmake -P EmBi_Platform/CMake/IntegrationTesting/IntegrationTesting_AllBoards.cmake
#   cmake -DIT_LABEL=Gpio -P EmBi_Platform/CMake/IntegrationTesting/IntegrationTesting_AllBoards.cmake
#
# Connected ST-LINK probes are listed, the board of every probe ("Board Name",
# eg. NUCLEO-H503RB) selects preset of its MCU "<MCU>_IntegrationTest" - the
# MCU is derived from the board name (NUCLEO-H503RB -> STM32H503xB) and the
# board is passed to the build (INTEGRATION_TEST_BOARD, board dependent pins).
# Test firmware is built once per board type and executed on every connected
# board of this type - the probe is selected by environment variable
# INTEGRATION_TEST_PROBE_SN. JUnit results are stored per probe:
#   Build/<preset>/IntegrationTestResults_<sn>.xml
#
# Optional parameters:
#   STM32_PROGRAMMER_CLI - STM32CubeProgrammer CLI (default installation folders, PATH)
#   IT_LABEL             - CTest label filter (ctest -L), eg. module name
################################################################################

cmake_minimum_required(VERSION 3.25)

include("${CMAKE_CURRENT_LIST_DIR}/IntegrationTesting_Probe.cmake")

#=============================== Constant values ==============================#

# Suffix of integration test presets (CMakePresets.json)
set(IT_PRESET_SUFFIX                    "_IntegrationTest")

set(IT_PROJECT_DIR                      "${CMAKE_SOURCE_DIR}")
set(IT_PRESETS_FILE                     "${IT_PROJECT_DIR}/CMakePresets.json")

#============================= Tools localization =============================#

if(NOT EXISTS "${IT_PRESETS_FILE}")
    message(FATAL_ERROR "${IT_PRESETS_FILE} not found - execute the script from the project root folder.")
endif()

if(NOT STM32_PROGRAMMER_CLI AND DEFINED ENV{STM32_PROGRAMMER_CLI})
    set(STM32_PROGRAMMER_CLI "$ENV{STM32_PROGRAMMER_CLI}")
endif()

find_program(STM32_PROGRAMMER_CLI
    NAMES STM32_Programmer_CLI
    PATHS "C:/Program Files/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin"
          "C:/Program Files/ST/STM32Cube/STM32CubeProgrammer/bin"
          "$ENV{HOME}/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin"
          "/opt/st/stm32cubeprogrammer/bin"
)

if(NOT STM32_PROGRAMMER_CLI)
    message(FATAL_ERROR "STM32_Programmer_CLI not found. Pass -DSTM32_PROGRAMMER_CLI=<path>.")
endif()

#=========================== Connected boards =================================#

IntegrationTesting_ListProbes("${STM32_PROGRAMMER_CLI}" PROBE_SNS PROBE_BOARDS)

list(LENGTH PROBE_SNS PROBE_CNT)

if(PROBE_CNT EQUAL 0)
    message(FATAL_ERROR "No ST-LINK probe connected.")
endif()

file(READ "${IT_PRESETS_FILE}" PRESETS_CONTENT)

# Boards with integration test preset; per board (eg. NUCLEO-H533RE):
#   IT_BOARD_PRESET_<board> - preset of the MCU (STM32H533xE_IntegrationTest)
#   IT_BOARD_SNS_<board>    - serial numbers of connected probes
set(IT_BOARDS "")

math(EXPR PROBE_LAST "${PROBE_CNT} - 1")

foreach(PROBE_IDX RANGE ${PROBE_LAST})

    list(GET PROBE_SNS    ${PROBE_IDX} PROBE_SN)
    list(GET PROBE_BOARDS ${PROBE_IDX} PROBE_BOARD)

    # Board name contains MCU line, package and flash code of its MCU:
    # NUCLEO-H533RE -> STM32H533xE
    if(NOT PROBE_BOARD MATCHES "^[A-Z0-9]+-([A-Z][0-9A-Z][0-9A-Z][0-9A-Z])[A-Z0-9]([0-9A-Z])")
        message(STATUS "Board ${PROBE_BOARD} (sn=${PROBE_SN}) - MCU cannot be derived from board name, skipped")
        continue()
    endif()

    set(PRESET "STM32${CMAKE_MATCH_1}x${CMAKE_MATCH_2}${IT_PRESET_SUFFIX}")

    if(PRESETS_CONTENT MATCHES "\"name\"[ \t]*:[ \t]*\"${PRESET}\"")
        message(STATUS "Board ${PROBE_BOARD} (sn=${PROBE_SN}) -> preset ${PRESET}")
        list(APPEND IT_BOARDS "${PROBE_BOARD}")
        set(IT_BOARD_PRESET_${PROBE_BOARD} "${PRESET}")
        list(APPEND IT_BOARD_SNS_${PROBE_BOARD} "${PROBE_SN}")
    else()
        message(STATUS "Board ${PROBE_BOARD} (sn=${PROBE_SN}) - preset ${PRESET} does not exist, skipped")
    endif()

endforeach()

list(REMOVE_DUPLICATES IT_BOARDS)

if(NOT IT_BOARDS)
    message(FATAL_ERROR "No connected board has integration test preset.")
endif()

#=========================== Build and execution ==============================#

set(CTEST_FILTER "")

if(IT_LABEL)
    set(CTEST_FILTER -L "${IT_LABEL}")
endif()

set(SUMMARY     "")
set(FAILED_RUNS 0)

foreach(BOARD IN LISTS IT_BOARDS)

    set(PRESET "${IT_BOARD_PRESET_${BOARD}}")

    # ST-LINK reports board name with dash (NUCLEO-H533RE), CMake name uses
    # underscore - selects board dependent pins of the tests (IT_BOARD_<name>)
    string(REPLACE "-" "_" BOARD_DEFINE "${BOARD}")

    # Firmware for the board - built once per board type (boards with the
    # same MCU share the build folder of the preset, it is reconfigured)
    execute_process(
        COMMAND "${CMAKE_COMMAND}" --preset ${PRESET} -DINTEGRATION_TEST_BOARD=${BOARD_DEFINE}
        WORKING_DIRECTORY "${IT_PROJECT_DIR}"
        RESULT_VARIABLE   CONFIGURE_RESULT
    )

    if(CONFIGURE_RESULT EQUAL 0)
        execute_process(
            COMMAND "${CMAKE_COMMAND}" --build --preset ${PRESET}
            WORKING_DIRECTORY "${IT_PROJECT_DIR}"
            RESULT_VARIABLE   BUILD_RESULT
        )
    else()
        set(BUILD_RESULT "${CONFIGURE_RESULT}")
    endif()

    foreach(PROBE_SN IN LISTS IT_BOARD_SNS_${BOARD})

        if(BUILD_RESULT EQUAL 0)
            message(STATUS "Integration tests ${PRESET} on ${BOARD} sn=${PROBE_SN}")

            set(ENV{INTEGRATION_TEST_PROBE_SN} "${PROBE_SN}")

            execute_process(
                COMMAND "${CMAKE_CTEST_COMMAND}" --preset ${PRESET} ${CTEST_FILTER}
                        --output-junit "IntegrationTestResults_${PROBE_SN}.xml"
                WORKING_DIRECTORY "${IT_PROJECT_DIR}"
                RESULT_VARIABLE   TEST_RESULT
            )

            unset(ENV{INTEGRATION_TEST_PROBE_SN})

            if(TEST_RESULT EQUAL 0)
                set(RUN_STATE "PASSED")
            else()
                set(RUN_STATE "FAILED")
            endif()
        else()
            set(RUN_STATE "BUILD FAILED")
        endif()

        if(NOT RUN_STATE STREQUAL "PASSED")
            math(EXPR FAILED_RUNS "${FAILED_RUNS} + 1")
        endif()

        string(APPEND SUMMARY "\n  ${BOARD} ${PRESET} (sn=${PROBE_SN}): ${RUN_STATE}")

    endforeach()

endforeach()

message(STATUS "Integration tests on connected boards:${SUMMARY}")

if(FAILED_RUNS GREATER 0)
    message(FATAL_ERROR "Integration tests failed on ${FAILED_RUNS} board(s).")
endif()
