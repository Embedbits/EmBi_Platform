################################################################################
# Author: Mr.Nobody
# file:  IntegrationTesting_AllBoards.cmake
# brief: Executes integration tests on all connected boards.
#
# Usage (from the project root folder with CMakePresets.json):
#   cmake -P EmBi_Platform/CMake/IntegrationTesting/IntegrationTesting_AllBoards.cmake
#   cmake -DIT_LABEL=Gpio -P EmBi_Platform/CMake/IntegrationTesting/IntegrationTesting_AllBoards.cmake
#
# Connected boards are detected first (IntegrationTesting_Detect.cmake) - MCU of
# every probe is identified by the MCU identification of the Ral presets, the
# optional boards file of the project (IntegrationTestBoards.json in the project
# root) names the boards, selects their presets and parameters. The boards file
# of connected boards (Build/IntegrationTestBoards.json) lists preset and probes
# of every board.
#
# For every board the preset is configured with INTEGRATION_TEST_BOARD=<board>
# (parameters of the board are taken from the boards file of connected boards),
# the firmware is built and executed on every probe of the board - the probe is
# selected by environment variable INTEGRATION_TEST_PROBE_SN, the run script
# checks the MCU before download. JUnit results are stored per probe:
#   Build/<preset>/IntegrationTestResults_<sn>.xml
#
# Optional parameters:
#   IT_MCU_PRESETS_FILE - MCU identification (default Bsp/Ral/RalPresets.json)
#   IT_BOARDS_OVERRIDE  - Boards file of the project (default IntegrationTestBoards.json)
#   IT_BOARDS_FILE      - Boards file of connected boards (default Build/IntegrationTestBoards.json)
#   IT_LABEL            - CTest label filter (ctest -L), eg. module name
################################################################################

cmake_minimum_required(VERSION 3.25)

include("${CMAKE_CURRENT_LIST_DIR}/IntegrationTesting_Detect.cmake")

#=============================== Constant values ==============================#

set(IT_PROJECT_DIR                      "${CMAKE_SOURCE_DIR}")

if(NOT IT_MCU_PRESETS_FILE)
    set(IT_MCU_PRESETS_FILE             "${IT_PROJECT_DIR}/Bsp/Ral/RalPresets.json")
endif()

if(NOT IT_BOARDS_OVERRIDE)
    set(IT_BOARDS_OVERRIDE              "${IT_PROJECT_DIR}/IntegrationTestBoards.json")
endif()

if(NOT IT_BOARDS_FILE)
    set(IT_BOARDS_FILE                  "${IT_PROJECT_DIR}/Build/IntegrationTestBoards.json")
endif()

#============================== Connected boards ==============================#

IntegrationTesting_DetectBoards("${IT_PROJECT_DIR}" "${IT_MCU_PRESETS_FILE}" "${IT_BOARDS_OVERRIDE}" "${IT_BOARDS_FILE}")

file(READ "${IT_BOARDS_FILE}" BOARDS_CONTENT)

string(JSON BOARDS_CNT ERROR_VARIABLE BOARDS_ERROR LENGTH "${BOARDS_CONTENT}" boards)

if(BOARDS_ERROR OR BOARDS_CNT EQUAL 0)
    message(FATAL_ERROR "No board is connected (${IT_BOARDS_FILE}).")
endif()

#=========================== Build and execution ==============================#

set(CTEST_FILTER "")

if(IT_LABEL)
    set(CTEST_FILTER -L "${IT_LABEL}")
endif()

set(SUMMARY     "")
set(FAILED_RUNS 0)

math(EXPR BOARDS_LAST "${BOARDS_CNT} - 1")

foreach(BOARD_IDX RANGE ${BOARDS_LAST})

    string(JSON BOARD  MEMBER "${BOARDS_CONTENT}" boards ${BOARD_IDX})
    string(JSON PRESET GET    "${BOARDS_CONTENT}" boards ${BOARD} preset)
    string(JSON PROBES_CNT    LENGTH "${BOARDS_CONTENT}" boards ${BOARD} probes)

    # Configuration of the board - parameters and probes of the board from the
    # boards file of connected boards
    execute_process(
        COMMAND "${CMAKE_COMMAND}" --preset ${PRESET} -DINTEGRATION_TEST_BOARD=${BOARD}
                -DINTEGRATION_TEST_BOARDS_FILE=${IT_BOARDS_FILE}
        WORKING_DIRECTORY "${IT_PROJECT_DIR}"
        RESULT_VARIABLE   CONFIGURE_RESULT
    )

    if(CONFIGURE_RESULT EQUAL 0)
        execute_process(
            COMMAND "${CMAKE_COMMAND}" --build --preset ${PRESET}
            WORKING_DIRECTORY "${IT_PROJECT_DIR}"
            RESULT_VARIABLE   BUILD_RESULT
        )
    endif()

    math(EXPR PROBES_LAST "${PROBES_CNT} - 1")

    foreach(PROBE_IDX RANGE ${PROBES_LAST})

        string(JSON PROBE GET "${BOARDS_CONTENT}" boards ${BOARD} probes ${PROBE_IDX})

        # Serial number of the probe (VID:PID:SN), whole selector without it
        string(REGEX REPLACE "^[0-9A-Fa-f]+:[0-9A-Fa-f]+:" "" PROBE_SN "${PROBE}")
        string(REPLACE ":" "_" PROBE_SN "${PROBE_SN}")

        if(NOT CONFIGURE_RESULT EQUAL 0)
            set(RUN_STATE "CONFIGURE FAILED")
        elseif(NOT BUILD_RESULT EQUAL 0)
            set(RUN_STATE "BUILD FAILED")
        else()
            message(STATUS "Integration tests ${PRESET} on ${BOARD} probe ${PROBE}")

            set(ENV{INTEGRATION_TEST_PROBE_SN} "${PROBE}")

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
        endif()

        if(NOT RUN_STATE STREQUAL "PASSED")
            math(EXPR FAILED_RUNS "${FAILED_RUNS} + 1")
        endif()

        string(APPEND SUMMARY "\n  ${BOARD} ${PRESET} (${PROBE}): ${RUN_STATE}")

    endforeach()

endforeach()

message(STATUS "Integration tests on connected boards:${SUMMARY}")

if(FAILED_RUNS GREATER 0)
    message(FATAL_ERROR "Integration tests failed on ${FAILED_RUNS} board(s).")
endif()
