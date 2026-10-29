################################################################################
# Author: Mr.Nobody
# file:  IntegrationTesting_AllBoards.cmake
# brief: Executes integration tests on all connected boards.
#
# Usage (from the project root folder with CMakePresets.json):
#   cmake -P EmBi_Platform/CMake/IntegrationTesting/IntegrationTesting_AllBoards.cmake
#   cmake -DIT_LABEL=Gpio -P EmBi_Platform/CMake/IntegrationTesting/IntegrationTesting_AllBoards.cmake
#
# Connected boards are detected first (IntegrationTesting_Detect.cmake) - the
# boards of this machine and of every IT agent of ItHosts.json; the MCU of every
# probe is identified by the MCU identification of the Ral presets, the optional
# board configuration of the project (ItBoards.json in the project root)
# names the boards, selects their presets and parameters. The boards file of
# connected boards (Build/IntegrationTestBoards.json) lists the boards (preset,
# parameters) and the targets (one physical board per probe).
#
# For every board the preset is configured with INTEGRATION_TEST_BOARD=<board>
# (parameters of the board are taken from the boards file of connected boards),
# the firmware is built and executed on every target of the board - the probe is
# selected by environment variable INTEGRATION_TEST_PROBE_SN, the IT agent of a
# target by INTEGRATION_TEST_HOST (and INTEGRATION_TEST_HOST_TOOLS), the run
# script checks the MCU before download. JUnit results are stored per target:
#   Build/<preset>/IntegrationTestResults_<sn>.xml          (this machine)
#   Build/<preset>/IntegrationTestResults_<host>_<sn>.xml   (IT agent <host>)
#
# Optional parameters:
#   IT_MCU_PRESETS_FILE - MCU identification (default Bsp/Ral/RalPresets.json)
#   IT_BOARDS_OVERRIDE  - Board configuration of the project (default ItBoards.json)
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
    set(IT_BOARDS_OVERRIDE              "${IT_PROJECT_DIR}/${IT_PROJECT_BOARDS_NAME}")
endif()

if(NOT IT_BOARDS_FILE)
    set(IT_BOARDS_FILE                  "${IT_PROJECT_DIR}/Build/IntegrationTestBoards.json")
endif()

#============================== Connected boards ==============================#

IntegrationTesting_DetectAllBoards("${IT_PROJECT_DIR}"
                                   "${IT_MCU_PRESETS_FILE}"
                                   "${IT_BOARDS_OVERRIDE}"
                                   "${IT_BOARDS_FILE}")

file(READ "${IT_BOARDS_FILE}" BOARDS_CONTENT)

string(JSON BOARDS_CNT ERROR_VARIABLE BOARDS_ERROR LENGTH "${BOARDS_CONTENT}" boards)
IntegrationTesting_ReadTargets(TARGETS_CNT "${IT_BOARDS_FILE}")

if(BOARDS_ERROR OR
   BOARDS_CNT EQUAL 0 OR
   TARGETS_CNT EQUAL 0)
    message(FATAL_ERROR "No board is connected (${IT_BOARDS_FILE}).")
endif()

# Agent tools of the IT agents (tools of ItHosts.json)
IntegrationTesting_ReadItHosts(IT_HOSTS "${IT_PROJECT_DIR}")

#=========================== Build and execution ==============================#

set(CTEST_FILTER "")

if(IT_LABEL)
    set(CTEST_FILTER -L "${IT_LABEL}")
endif()

set(SUMMARY     "")
set(FAILED_RUNS 0)

math(EXPR BOARDS_LAST "${BOARDS_CNT} - 1")
math(EXPR TARGETS_LAST "${TARGETS_CNT} - 1")

foreach(BOARD_IDX RANGE ${BOARDS_LAST})

    string(JSON BOARD  MEMBER "${BOARDS_CONTENT}" boards ${BOARD_IDX})
    string(JSON PRESET GET    "${BOARDS_CONTENT}" boards ${BOARD} preset)

    # Targets of the board
    set(BOARD_TARGETS "")
    foreach(TARGET_IDX RANGE ${TARGETS_LAST})
        if("${IT_TARGET_${TARGET_IDX}_BOARD}" STREQUAL "${BOARD}")
            list(APPEND BOARD_TARGETS ${TARGET_IDX})
        endif()
    endforeach()

    # A list of indexes ("0") is compared as text - "0" is false as a condition
    if("${BOARD_TARGETS}" STREQUAL "")
        continue()
    endif()

    # Configuration of the board - parameters of the board from the boards file of connected boards; no probe
    # and no IT agent of an earlier run of one target (every target gives them by the environment variables)
    set(CONFIGURE_ARGS --preset ${PRESET} -DINTEGRATION_TEST_BOARD=${BOARD})
    list(APPEND CONFIGURE_ARGS -DINTEGRATION_TEST_BOARDS_FILE=${IT_BOARDS_FILE})
    list(APPEND CONFIGURE_ARGS -DINTEGRATION_TEST_PROBE= -DINTEGRATION_TEST_HOST=)

    execute_process(
        COMMAND "${CMAKE_COMMAND}" ${CONFIGURE_ARGS}
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

    foreach(TARGET_IDX IN LISTS BOARD_TARGETS)

        set(PROBE "${IT_TARGET_${TARGET_IDX}_PROBE}")
        set(HOST  "${IT_TARGET_${TARGET_IDX}_HOST}")

        # Serial number of the probe (VID:PID:SN), whole selector without it; the host of a target of an
        # IT agent is a part of the name of its JUnit file
        string(REGEX REPLACE "^[0-9A-Fa-f]+:[0-9A-Fa-f]+:" "" PROBE_SN "${PROBE}")
        string(REPLACE ":" "_" PROBE_SN "${PROBE_SN}")

        if(NOT "${HOST}" STREQUAL "${IT_LOCAL_HOST}")
            set(PROBE_SN "${HOST}_${PROBE_SN}")
        endif()

        if(NOT CONFIGURE_RESULT EQUAL 0)
            set(RUN_STATE "CONFIGURE FAILED")
        elseif(NOT BUILD_RESULT EQUAL 0)
            set(RUN_STATE "BUILD FAILED")
        else()
            message(STATUS "Integration tests ${PRESET} on ${IT_TARGET_${TARGET_IDX}_TEXT} (probe ${PROBE})")

            set(ENV{INTEGRATION_TEST_PROBE_SN} "${PROBE}")

            if("${HOST}" STREQUAL "${IT_LOCAL_HOST}")
                unset(ENV{INTEGRATION_TEST_HOST})
                unset(ENV{INTEGRATION_TEST_HOST_TOOLS})
            else()
                set(ENV{INTEGRATION_TEST_HOST} "${IT_TARGET_${TARGET_IDX}_TARGET}")
                set(ENV{INTEGRATION_TEST_HOST_TOOLS} "${IT_HOST_${HOST}_TOOLS}")
            endif()

            execute_process(
                COMMAND "${CMAKE_CTEST_COMMAND}" --preset ${PRESET} ${CTEST_FILTER}
                        --output-junit "IntegrationTestResults_${PROBE_SN}.xml"
                WORKING_DIRECTORY "${IT_PROJECT_DIR}"
                RESULT_VARIABLE   TEST_RESULT
            )

            unset(ENV{INTEGRATION_TEST_PROBE_SN})
            unset(ENV{INTEGRATION_TEST_HOST})
            unset(ENV{INTEGRATION_TEST_HOST_TOOLS})

            if(TEST_RESULT EQUAL 0)
                set(RUN_STATE "PASSED")
            else()
                set(RUN_STATE "FAILED")
            endif()
        endif()

        if(NOT RUN_STATE STREQUAL "PASSED")
            math(EXPR FAILED_RUNS "${FAILED_RUNS} + 1")
        endif()

        string(APPEND SUMMARY "\n  ${IT_TARGET_${TARGET_IDX}_TEXT} ${PRESET} (${PROBE}): ${RUN_STATE}")

    endforeach()

endforeach()

message(STATUS "Integration tests on connected boards:${SUMMARY}")

if(FAILED_RUNS GREATER 0)
    message(FATAL_ERROR "Integration tests failed on ${FAILED_RUNS} board(s).")
endif()
