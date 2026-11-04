# ==============================================================================
#
# Build handler CMake script.
#
# Build of the project and execution of unit / integration tests for MCU
# selected from the project presets (Setup.bat/sh options "Build" and "Tests")
# and generation of the project documentation (option "Documentation").
#
# MCUs of the project are taken from configure presets of the project
# CMakePresets.json (project root) - every MCU has generated presets
# <MCU>_Debug, <MCU>_Release, <MCU>_UnitTest and <MCU>_IntegrationTest.
#
# Unit tests run on host for selected MCU (<MCU>_UnitTest). Integration tests
# run on board - connected boards are detected when the boards are listed
# (IntegrationTesting_Detect.cmake: MCU of every probe identified by the Ral
# presets, optional ItBoards.json of the project as override, see
# IntegrationTesting/README.md) and stored in Build/IntegrationTestBoards.json.
# The list of the boards is the list of the targets - one physical board (probe)
# of this machine or of an IT agent of ItHosts.json per item; the preset of its
# board is configured with INTEGRATION_TEST_BOARD=<board>,
# INTEGRATION_TEST_PROBE=<probe of the target> and INTEGRATION_TEST_HOST=<IT
# agent of the target> (the firmware is executed there, IntegrationTesting_Run.cmake).
#
# Test sets are CTest labels of the build (every test set registers label of
# its name, UnitTesting_Add_Test / IntegrationTesting_Add_Test), one test set
# or all of them are executed and results are summarized from the JUnit file
# of the test preset (Build/<preset>/<Unit|Integration>TestResults.xml).
#
# Integration tests on all connected boards (last entry of the boards list):
# presets of all boards are only configured to collect their test sets, the
# execution is done by IntegrationTesting_AllBoards.cmake (connected boards are
# detected again, built and tested), results are summarized from the JUnit
# files per target (Build/<preset>/IntegrationTestResults_<sn>.xml,
# IntegrationTestResults_<host>_<sn>.xml of an IT agent).
#
# Besides numerical IDs of the interactive menu, the MCU, the test target and
# the test set can be selected by name (BUILD with MCU, TEST) - used by tasks
# of the VSCode project (Prj_VSCode_Handler.cmake). DETECT_BOARDS only detects
# the connected boards (this machine and the IT agents) without the numbered
# list of the menu - a task terminal takes no answer.
#
# Code coverage (-DTEST_COVERAGE=ON of TEST_BUILD, TEST_RUN, TEST): the tests are built with the
# gcov instrumentation of the tested code (UNIT_TEST_COVERAGE / INTEGRATION_TEST_COVERAGE, see
# Coverage/Coverage.cmake), the counters of earlier runs are deleted, after the tests the
# report is created (HTML, Cobertura XML, JSON in Build/<preset>/Coverage) and the table of the
# coverage by modules is printed. FUNCTION_ID=TEST_COVERAGE prints the table of the last report
# again. Not available for the integration tests on all connected boards.
#
# ==============================================================================


#===============================================================================
# Global variables
#===============================================================================

# Set path to system configuration file
get_filename_component(SYSTEM_CONFIG_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/../../SysConfig.cmake" REALPATH)

# Include file with system configuration values
include("${SYSTEM_CONFIG_FILE_PATH}")

SysConfig_Get_ProjectRootPath(BUILD_HANDLER_PROJECT_ROOT)

set(BUILD_HANDLER_PRESETS_FILE  "${BUILD_HANDLER_PROJECT_ROOT}/CMakePresets.json")

# Connected boards (IntegrationTesting_Detect.cmake output, not versioned)
set(BUILD_HANDLER_BOARDS_FILE   "${BUILD_HANDLER_PROJECT_ROOT}/Build/IntegrationTestBoards.json")

# Build folder of a preset (binaryDir of PlatformPresets.json)
set(BUILD_HANDLER_BUILD_DIR     "${BUILD_HANDLER_PROJECT_ROOT}/Build")

# Preset suffixes generated for every MCU
set(BUILD_HANDLER_PRESET_TYPES  "Debug;Release;UnitTest;IntegrationTest")

# Labels of the frameworks (not test sets)
set(BUILD_HANDLER_FW_LABELS     "unit;integration")

# Integration tests on all connected boards
get_filename_component(BUILD_HANDLER_IT_ALL_BOARDS "${CMAKE_CURRENT_LIST_DIR}/../../IntegrationTesting/IntegrationTesting_AllBoards.cmake" REALPATH)
get_filename_component(BUILD_HANDLER_IT_DETECT "${CMAKE_CURRENT_LIST_DIR}/../../IntegrationTesting/IntegrationTesting_Detect.cmake" REALPATH)
set(BUILD_HANDLER_ALL_BOARDS_TEXT "All connected boards")

# Targets of the boards file of connected boards (physical boards of this machine and of the IT agents)
include("${CMAKE_CURRENT_LIST_DIR}/../../IntegrationTesting/IntegrationTesting_Detect.cmake")

# Optional MCU identification file of the detection (default Bsp/Ral/RalPresets.json)
set(BUILD_HANDLER_DETECT_ARGS   "")
if(IT_MCU_PRESETS_FILE)
    list(APPEND BUILD_HANDLER_DETECT_ARGS "-DIT_MCU_PRESETS_FILE=${IT_MCU_PRESETS_FILE}")
endif()

# Clean build - configuration without CMake cache (--fresh), build --clean-first
if(NOT DEFINED BUILD_CLEAN)
    set(BUILD_CLEAN OFF)
endif()

# Code coverage of the tests (instrumented build, report after the tests)
if(NOT DEFINED TEST_COVERAGE)
    set(TEST_COVERAGE OFF)
endif()

# Prefix of the coverage targets of the framework (UnitTest_Coverage, IntegrationTest_Coverage, ...)
set(BUILD_HANDLER_COVERAGE_PREFIX_UT "UnitTest")
set(BUILD_HANDLER_COVERAGE_PREFIX_IT "IntegrationTest")


#===============================================================================
# Functions
#===============================================================================

# ------------------------------------------------------------------------------
# Function: Build_Handler_GetMcuList
# Description: Collects MCUs of the configure presets of the project
#              CMakePresets.json (order of the presets file).
#
# OUT_MCU_LIST [out]: List of MCUs.
# ------------------------------------------------------------------------------
function(Build_Handler_GetMcuList OUT_MCU_LIST)

    if(NOT EXISTS "${BUILD_HANDLER_PRESETS_FILE}")
        message(FATAL_ERROR "${BUILD_HANDLER_PRESETS_FILE} not found - initialize the project first.")
    endif()

    file(READ "${BUILD_HANDLER_PRESETS_FILE}" PRESETS_CONTENT)

    string(JSON PRESETS_CNT ERROR_VARIABLE PRESETS_ERROR LENGTH "${PRESETS_CONTENT}" configurePresets)

    set(MCU_LIST "")

    if(NOT PRESETS_ERROR AND PRESETS_CNT GREATER 0)

        list(JOIN BUILD_HANDLER_PRESET_TYPES "|" TYPES_REGEX)
        math(EXPR PRESETS_LAST "${PRESETS_CNT} - 1")

        foreach(PRESET_IDX RANGE ${PRESETS_LAST})

            string(JSON PRESET_NAME GET "${PRESETS_CONTENT}" configurePresets ${PRESET_IDX} name)
            string(JSON PRESET_HIDDEN ERROR_VARIABLE HIDDEN_ERROR GET "${PRESETS_CONTENT}" configurePresets ${PRESET_IDX} hidden)

            if(NOT HIDDEN_ERROR AND PRESET_HIDDEN)
                continue()
            endif()

            if("${PRESET_NAME}" MATCHES "^(.+)_(${TYPES_REGEX})$")
                list(APPEND MCU_LIST "${CMAKE_MATCH_1}")
            endif()

        endforeach()

        list(REMOVE_DUPLICATES MCU_LIST)

    endif()

    if(NOT MCU_LIST)
        message(FATAL_ERROR "No MCU preset found in ${BUILD_HANDLER_PRESETS_FILE}.")
    endif()

    set(${OUT_MCU_LIST} "${MCU_LIST}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_DetectBoards
# Description: Detects connected boards (IntegrationTesting_Detect.cmake) and
#              writes Build/IntegrationTestBoards.json.
# ------------------------------------------------------------------------------
function(Build_Handler_DetectBoards)

    execute_process(
        COMMAND           "${CMAKE_COMMAND}" ${BUILD_HANDLER_DETECT_ARGS}
                          -DIT_BOARDS_FILE=${BUILD_HANDLER_BOARDS_FILE} -P "${BUILD_HANDLER_IT_DETECT}"
        WORKING_DIRECTORY "${BUILD_HANDLER_PROJECT_ROOT}"
        RESULT_VARIABLE   DETECT_RESULT
    )

    if(NOT DETECT_RESULT EQUAL 0)
        message(FATAL_ERROR "Detection of connected boards failed.")
    endif()
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_GetBoardList
# Description: Collects connected boards (Build/IntegrationTestBoards.json of
#              the last detection).
#
# OUT_BOARD_LIST  [out]: List of boards.
# OUT_PRESET_LIST [out]: List of configure presets of the boards.
# ------------------------------------------------------------------------------
function(Build_Handler_GetBoardList OUT_BOARD_LIST OUT_PRESET_LIST)

    if(NOT EXISTS "${BUILD_HANDLER_BOARDS_FILE}")
        message(FATAL_ERROR "${BUILD_HANDLER_BOARDS_FILE} not found - connected boards are not detected "
                            "(TEST_TARGET_LIST, see EmBi_Platform/CMake/IntegrationTesting/README.md).")
    endif()

    file(READ "${BUILD_HANDLER_BOARDS_FILE}" BOARDS_CONTENT)

    string(JSON BOARDS_CNT ERROR_VARIABLE BOARDS_ERROR LENGTH "${BOARDS_CONTENT}" boards)

    set(BOARD_LIST  "")
    set(PRESET_LIST "")

    if(NOT BOARDS_ERROR AND BOARDS_CNT GREATER 0)

        math(EXPR BOARDS_LAST "${BOARDS_CNT} - 1")

        foreach(BOARD_IDX RANGE ${BOARDS_LAST})

            string(JSON BOARD MEMBER "${BOARDS_CONTENT}" boards ${BOARD_IDX})
            string(JSON PRESET ERROR_VARIABLE PRESET_ERROR GET "${BOARDS_CONTENT}" boards ${BOARD} preset)

            if(PRESET_ERROR)
                message(WARNING "Board ${BOARD} has no \"preset\" in ${BUILD_HANDLER_BOARDS_FILE} - skipped.")
                continue()
            endif()

            list(APPEND BOARD_LIST  "${BOARD}")
            list(APPEND PRESET_LIST "${PRESET}")

        endforeach()

    endif()

    set(${OUT_BOARD_LIST}  "${BOARD_LIST}"  PARENT_SCOPE)
    set(${OUT_PRESET_LIST} "${PRESET_LIST}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_PrintList
# Description: Prints numbered list with "[0]" entry.
#
# IN_ZERO_TEXT [in]: Text of the entry 0.
# ARGN         [in]: Items of the list.
# ------------------------------------------------------------------------------
function(Build_Handler_PrintList IN_ZERO_TEXT)

    message("[0]: ${IN_ZERO_TEXT}")

    set(DISPLAY_INDEX 0)

    foreach(ITEM IN LISTS ARGN)
        math(EXPR DISPLAY_INDEX "${DISPLAY_INDEX} + 1")
        message("[${DISPLAY_INDEX}]: ${ITEM}")
    endforeach()
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_GetListItem
# Description: Item of a list selected by numerical ID (1 = first item).
#
# IN_LIST   [in]:  List.
# IN_ID     [in]:  Numerical ID of the item.
# IN_WHAT   [in]:  Name of the item for error message.
# OUT_ITEM  [out]: Selected item.
# ------------------------------------------------------------------------------
function(Build_Handler_GetListItem IN_LIST IN_ID IN_WHAT OUT_ITEM)

    list(LENGTH IN_LIST LIST_SIZE)

    if(NOT "${IN_ID}" MATCHES "^[0-9]+$" OR IN_ID LESS 1 OR IN_ID GREATER LIST_SIZE)
        message(FATAL_ERROR "Required ${IN_WHAT} ID '${IN_ID}' is not correct (1-${LIST_SIZE}).")
    endif()

    math(EXPR REAL_INDEX "${IN_ID} - 1")
    list(GET IN_LIST ${REAL_INDEX} ITEM)

    set(${OUT_ITEM} "${ITEM}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_GetListId
# Description: Numerical ID (1 = first item) of an item of a list selected by
#              name.
#
# IN_LIST   [in]:  List.
# IN_ITEM   [in]:  Name of the item.
# IN_WHAT   [in]:  Name of the item for error message.
# OUT_ID    [out]: Numerical ID of the item.
# ------------------------------------------------------------------------------
function(Build_Handler_GetListId IN_LIST IN_ITEM IN_WHAT OUT_ID)

    list(FIND IN_LIST "${IN_ITEM}" ITEM_INDEX)

    if(ITEM_INDEX EQUAL -1)
        list(JOIN IN_LIST ", " ITEMS_TEXT)
        message(FATAL_ERROR "Required ${IN_WHAT} '${IN_ITEM}' not found (${ITEMS_TEXT}).")
    endif()

    math(EXPR ITEM_ID "${ITEM_INDEX} + 1")

    set(${OUT_ID} "${ITEM_ID}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_Execute
# Description: Executes command in the project root, output to the console,
#              fatal error if the command fails.
#
# IN_STEP [in]: Name of the step for error message.
# ARGN    [in]: Command.
# ------------------------------------------------------------------------------
function(Build_Handler_Execute IN_STEP)

    execute_process(
        COMMAND           ${ARGN}
        WORKING_DIRECTORY "${BUILD_HANDLER_PROJECT_ROOT}"
        RESULT_VARIABLE   EXEC_RESULT
    )

    if(NOT EXEC_RESULT EQUAL 0)
        message(FATAL_ERROR "${IN_STEP} failed (${EXEC_RESULT}).")
    endif()
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_ConfigureAndBuild
# Description: Configures and builds the preset (clean build if BUILD_CLEAN).
#
# IN_PRESET [in]: Configure / build preset.
# ARGN      [in]: Additional configuration arguments.
# ------------------------------------------------------------------------------
function(Build_Handler_ConfigureAndBuild IN_PRESET)

    set(FRESH_ARG "")
    set(CLEAN_ARG "")

    if(BUILD_CLEAN)
        set(FRESH_ARG --fresh)
        set(CLEAN_ARG --clean-first)
    endif()

    message("=====================================")
    message("Configuration: ${IN_PRESET} ${FRESH_ARG} ${ARGN}")
    message("=====================================")
    Build_Handler_Execute("Configuration of ${IN_PRESET}" "${CMAKE_COMMAND}" --preset ${IN_PRESET} ${FRESH_ARG} ${ARGN})

    message("=====================================")
    message("Build: ${IN_PRESET} ${CLEAN_ARG}")
    message("=====================================")
    Build_Handler_Execute("Build of ${IN_PRESET}" "${CMAKE_COMMAND}" --build --preset ${IN_PRESET} ${CLEAN_ARG})
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_IsAllBoards
# Description: Checks if the test target ID selects all connected boards (the
#              entry after the last board of the boards list).
#
# IN_TEST_TYPE  [in]:  UT or IT.
# IN_TARGET_ID  [in]:  Numerical ID of the MCU / board.
# OUT_ALL       [out]: TRUE for all connected boards.
# ------------------------------------------------------------------------------
function(Build_Handler_IsAllBoards IN_TEST_TYPE IN_TARGET_ID OUT_ALL)

    set(ALL_BOARDS FALSE)

    if("${IN_TEST_TYPE}" STREQUAL "IT" AND
       "${IN_TARGET_ID}" MATCHES "^[0-9]+$")

        IntegrationTesting_ReadTargets(TARGETS_CNT "${BUILD_HANDLER_BOARDS_FILE}")
        math(EXPR ALL_BOARDS_ID "${TARGETS_CNT} + 1")

        if(IN_TARGET_ID EQUAL ALL_BOARDS_ID)
            set(ALL_BOARDS TRUE)
        endif()

    endif()

    set(${OUT_ALL} ${ALL_BOARDS} PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_GetTestPreset
# Description: Preset and configuration arguments of the test target selected
#              by ID - MCU (UT) or board (IT).
#
# IN_TEST_TYPE  [in]:  UT or IT.
# IN_TARGET_ID  [in]:  Numerical ID of the MCU / board.
# OUT_PRESET    [out]: Configure / build / test preset.
# OUT_ARGS      [out]: Additional configuration arguments.
# OUT_TARGET    [out]: Name of the MCU / board.
# ------------------------------------------------------------------------------
function(Build_Handler_GetTestPreset IN_TEST_TYPE IN_TARGET_ID OUT_PRESET OUT_ARGS OUT_TARGET)

    if("${IN_TEST_TYPE}" STREQUAL "UT")

        Build_Handler_GetMcuList(MCU_LIST)
        Build_Handler_GetListItem("${MCU_LIST}" "${IN_TARGET_ID}" "MCU" MCU)

        set(PRESET "${MCU}_UnitTest")
        # The report and the table are printed by Setup itself after the tests
        set(ARGS   "-DUNIT_TEST_COVERAGE=${TEST_COVERAGE};-DUNIT_TEST_COVERAGE_CTEST_REPORT=OFF")
        set(TARGET "${MCU}")

    elseif("${IN_TEST_TYPE}" STREQUAL "IT")

        # Target = one physical board (probe) of this machine or of an IT agent
        IntegrationTesting_ReadTargets(TARGETS_CNT "${BUILD_HANDLER_BOARDS_FILE}")

        if(NOT "${IN_TARGET_ID}" MATCHES "^[0-9]+$" OR
           IN_TARGET_ID LESS 1 OR
           IN_TARGET_ID GREATER TARGETS_CNT)
            message(FATAL_ERROR "Required board ID '${IN_TARGET_ID}' is not correct (1-${TARGETS_CNT}).")
        endif()

        math(EXPR TARGET_IDX "${IN_TARGET_ID} - 1")

        set(BOARD  "${IT_TARGET_${TARGET_IDX}_BOARD}")
        set(PRESET "${IT_TARGET_${TARGET_IDX}_PRESET}")
        set(HOST   "${IT_TARGET_${TARGET_IDX}_HOST}")

        if("${HOST}" STREQUAL "${IT_LOCAL_HOST}")
            set(HOST "")
        endif()

        set(ARGS   "-DINTEGRATION_TEST_BOARD=${BOARD}" "-DINTEGRATION_TEST_BOARDS_FILE=${BUILD_HANDLER_BOARDS_FILE}")
        list(APPEND ARGS "-DINTEGRATION_TEST_PROBE=${IT_TARGET_${TARGET_IDX}_PROBE}" "-DINTEGRATION_TEST_HOST=${HOST}")
        list(APPEND ARGS "-DINTEGRATION_TEST_COVERAGE=${TEST_COVERAGE}" "-DINTEGRATION_TEST_COVERAGE_CTEST_REPORT=OFF")
        set(TARGET "${IT_TARGET_${TARGET_IDX}_TEXT}")

    else()

        message(FATAL_ERROR "Required TEST_TYPE '${IN_TEST_TYPE}' is not correct (UT, IT).")

    endif()

    set(${OUT_PRESET} "${PRESET}" PARENT_SCOPE)
    set(${OUT_ARGS}   "${ARGS}"   PARENT_SCOPE)
    set(${OUT_TARGET} "${TARGET}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_GetTestSets
# Description: Test sets (CTest labels without labels of the frameworks) of the
#              built preset.
#
# IN_PRESET     [in]:  Built preset.
# OUT_TEST_SETS [out]: Sorted list of test sets.
# ------------------------------------------------------------------------------
function(Build_Handler_GetTestSets IN_PRESET OUT_TEST_SETS)

    set(PRESET_BUILD_DIR "${BUILD_HANDLER_BUILD_DIR}/${IN_PRESET}")

    if(NOT EXISTS "${PRESET_BUILD_DIR}/CTestTestfile.cmake")
        message(FATAL_ERROR "${IN_PRESET} is not built - no tests in ${PRESET_BUILD_DIR}.")
    endif()

    execute_process(
        COMMAND         "${CMAKE_CTEST_COMMAND}" --test-dir "${PRESET_BUILD_DIR}" --print-labels
        OUTPUT_VARIABLE LABELS_OUTPUT
        RESULT_VARIABLE LABELS_RESULT
    )

    if(NOT LABELS_RESULT EQUAL 0)
        message(FATAL_ERROR "Test sets of ${IN_PRESET} cannot be read (${LABELS_RESULT}).")
    endif()

    # Labels are listed as indented lines after "All Labels:"
    string(REPLACE "\n" ";" LABELS_LINES "${LABELS_OUTPUT}")

    set(TEST_SETS "")

    foreach(LINE IN LISTS LABELS_LINES)
        if("${LINE}" MATCHES "^[ \t]+([^ \t]+)[ \t]*$")
            if(NOT "${CMAKE_MATCH_1}" IN_LIST BUILD_HANDLER_FW_LABELS)
                list(APPEND TEST_SETS "${CMAKE_MATCH_1}")
            endif()
        endif()
    endforeach()

    list(REMOVE_DUPLICATES TEST_SETS)
    list(SORT TEST_SETS)

    set(${OUT_TEST_SETS} "${TEST_SETS}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_ConfigureAllBoards
# Description: Configures presets of all boards of the boards file (without
#              build - CTest tests are known after configuration) and collects
#              their test sets.
#
# OUT_TEST_SETS [out]: Sorted list of test sets of all boards.
# ------------------------------------------------------------------------------
function(Build_Handler_ConfigureAllBoards OUT_TEST_SETS)

    Build_Handler_GetBoardList(BOARD_LIST PRESET_LIST)

    set(ALL_TEST_SETS "")

    foreach(BOARD PRESET IN ZIP_LISTS BOARD_LIST PRESET_LIST)

        message("=====================================")
        message("Configuration: ${PRESET} (${BOARD})")
        message("=====================================")
        Build_Handler_Execute("Configuration of ${PRESET} (${BOARD})"
                              "${CMAKE_COMMAND}" --preset ${PRESET} -DINTEGRATION_TEST_BOARD=${BOARD}
                              -DINTEGRATION_TEST_BOARDS_FILE=${BUILD_HANDLER_BOARDS_FILE})

        Build_Handler_GetTestSets(${PRESET} TEST_SETS)
        list(APPEND ALL_TEST_SETS ${TEST_SETS})

    endforeach()

    list(REMOVE_DUPLICATES ALL_TEST_SETS)
    list(SORT ALL_TEST_SETS)

    set(${OUT_TEST_SETS} "${ALL_TEST_SETS}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_GetAllBoardsTestSets
# Description: Test sets of the configured presets of all boards of the boards
#              file (Build_Handler_ConfigureAllBoards).
#
# OUT_TEST_SETS [out]: Sorted list of test sets of all boards.
# ------------------------------------------------------------------------------
function(Build_Handler_GetAllBoardsTestSets OUT_TEST_SETS)

    Build_Handler_GetBoardList(BOARD_LIST PRESET_LIST)
    list(REMOVE_DUPLICATES PRESET_LIST)

    set(ALL_TEST_SETS "")

    foreach(PRESET IN LISTS PRESET_LIST)
        Build_Handler_GetTestSets(${PRESET} TEST_SETS)
        list(APPEND ALL_TEST_SETS ${TEST_SETS})
    endforeach()

    list(REMOVE_DUPLICATES ALL_TEST_SETS)
    list(SORT ALL_TEST_SETS)

    set(${OUT_TEST_SETS} "${ALL_TEST_SETS}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_GetAllBoardsJUnitFiles
# Description: JUnit files of integration tests on all connected boards (one
#              file per probe, IntegrationTesting_AllBoards.cmake).
#
# OUT_FILES [out]: List of JUnit files.
# ------------------------------------------------------------------------------
function(Build_Handler_GetAllBoardsJUnitFiles OUT_FILES)

    Build_Handler_GetBoardList(BOARD_LIST PRESET_LIST)
    list(REMOVE_DUPLICATES PRESET_LIST)

    set(FILES "")

    foreach(PRESET IN LISTS PRESET_LIST)
        file(GLOB PRESET_FILES "${BUILD_HANDLER_BUILD_DIR}/${PRESET}/IntegrationTestResults_*.xml")
        list(APPEND FILES ${PRESET_FILES})
    endforeach()

    set(${OUT_FILES} "${FILES}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_PrintResults
# Description: Prints summary of the tests from the JUnit file - results per
#              test set and list of not passed tests.
#
# IN_JUNIT_FILE [in]: JUnit file of the test preset.
# IN_TITLE      [in]: Title of the summary.
# ------------------------------------------------------------------------------
function(Build_Handler_PrintResults IN_JUNIT_FILE IN_TITLE)

    if(NOT EXISTS "${IN_JUNIT_FILE}")
        message(WARNING "Results file ${IN_JUNIT_FILE} not found - no summary.")
        return()
    endif()

    file(READ "${IN_JUNIT_FILE}" JUNIT_CONTENT)

    string(REGEX MATCHALL "<testcase [^>]*>" TEST_CASES "${JUNIT_CONTENT}")

    set(SETS        "")
    set(NOT_PASSED  "")
    set(TOTAL_PASS  0)
    set(TOTAL_FAIL  0)
    set(TOTAL_SKIP  0)

    foreach(TEST_CASE IN LISTS TEST_CASES)

        string(REGEX MATCH "name=\"([^\"]*)\"" _ "${TEST_CASE}")
        set(TEST_NAME "${CMAKE_MATCH_1}")

        string(REGEX MATCH "status=\"([^\"]*)\"" _ "${TEST_CASE}")
        set(TEST_STATUS "${CMAKE_MATCH_1}")

        # Test name <TestSet>.<function>
        string(REGEX REPLACE "\\..*$" "" TEST_SET "${TEST_NAME}")

        if(NOT "${TEST_SET}" IN_LIST SETS)
            list(APPEND SETS "${TEST_SET}")
            set(SET_${TEST_SET}_PASS 0)
            set(SET_${TEST_SET}_FAIL 0)
            set(SET_${TEST_SET}_SKIP 0)
        endif()

        if("${TEST_STATUS}" STREQUAL "run")
            set(RESULT PASS)
        elseif("${TEST_STATUS}" STREQUAL "fail")
            set(RESULT FAIL)
            list(APPEND NOT_PASSED "FAIL  ${TEST_NAME}")
        else()
            set(RESULT SKIP)
            list(APPEND NOT_PASSED "SKIP  ${TEST_NAME} (${TEST_STATUS})")
        endif()

        math(EXPR SET_${TEST_SET}_${RESULT} "${SET_${TEST_SET}_${RESULT}} + 1")
        math(EXPR TOTAL_${RESULT} "${TOTAL_${RESULT}} + 1")

    endforeach()

    message("")
    message("=====================================")
    message("Test results: ${IN_TITLE}")
    message("=====================================")

    foreach(TEST_SET IN LISTS SETS)

        if(SET_${TEST_SET}_FAIL GREATER 0)
            set(SET_STATE "FAILED")
        else()
            set(SET_STATE "PASSED")
        endif()

        message("${SET_STATE}  ${TEST_SET}: passed ${SET_${TEST_SET}_PASS}, failed ${SET_${TEST_SET}_FAIL}, skipped ${SET_${TEST_SET}_SKIP}")

    endforeach()

    if(NOT_PASSED)
        message("-------------------------------------")
        foreach(LINE IN LISTS NOT_PASSED)
            message("${LINE}")
        endforeach()
    endif()

    message("-------------------------------------")
    message("Total: passed ${TOTAL_PASS}, failed ${TOTAL_FAIL}, skipped ${TOTAL_SKIP}")
    message("Results: ${IN_JUNIT_FILE}")
    message("=====================================")
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_PrintMcuList
# Description: Prints MCUs of the project presets.
# ------------------------------------------------------------------------------
function(Build_Handler_PrintMcuList)

    Build_Handler_GetMcuList(MCU_LIST)
    Build_Handler_PrintList("Return back" ${MCU_LIST})
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_Build
# Description: Configures and builds the project for selected MCU.
#
# IN_MCU_ID     [in]: Numerical ID of the MCU (Build_Handler_PrintMcuList).
# IN_BUILD_TYPE [in]: Debug or Release.
# ------------------------------------------------------------------------------
function(Build_Handler_Build IN_MCU_ID IN_BUILD_TYPE)

    if(NOT "${IN_BUILD_TYPE}" MATCHES "^(Debug|Release)$")
        message(FATAL_ERROR "Required BUILD_TYPE '${IN_BUILD_TYPE}' is not correct (Debug, Release).")
    endif()

    Build_Handler_GetMcuList(MCU_LIST)
    Build_Handler_GetListItem("${MCU_LIST}" "${IN_MCU_ID}" "MCU" MCU)

    set(PRESET "${MCU}_${IN_BUILD_TYPE}")

    Build_Handler_ConfigureAndBuild(${PRESET})

    message("=====================================")
    message("Build ${PRESET} PASSED")
    message("Output: ${BUILD_HANDLER_BUILD_DIR}/${PRESET}")
    message("=====================================")
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_Get_BoardBuild
# Description: MCU, preset and build folder of the build of a board (a picked board, its configuration of
#              ItBoards.json - the boards file of the detection): Build/<MCU>_<build type>_<board>.
#
# IN_BOARD      [in]:  Board name (boards file of the detection).
# IN_BUILD_TYPE [in]:  Debug or Release.
# OUT_MCU       [out]: MCU of the board (its integration test preset).
# OUT_PRESET    [out]: Configure preset <MCU>_<build type>.
# OUT_DIR       [out]: Build folder of the board.
# ------------------------------------------------------------------------------
function(Build_Handler_Get_BoardBuild IN_BOARD IN_BUILD_TYPE OUT_MCU OUT_PRESET OUT_DIR)

    if(NOT EXISTS "${BUILD_HANDLER_BOARDS_FILE}")
        Build_Handler_DetectBoards()
    endif()

    file(READ "${BUILD_HANDLER_BOARDS_FILE}" BOARDS_CONTENT)
    string(JSON BOARD_PRESET ERROR_VARIABLE BOARD_ERROR GET "${BOARDS_CONTENT}" boards "${IN_BOARD}" preset)

    if(BOARD_ERROR)
        message(FATAL_ERROR "Board ${IN_BOARD} is not in ${BUILD_HANDLER_BOARDS_FILE} - detect the connected boards.")
    endif()

    string(REGEX REPLACE "_IntegrationTest$" "" BOARD_MCU "${BOARD_PRESET}")

    set(${OUT_MCU}    "${BOARD_MCU}"                                                       PARENT_SCOPE)
    set(${OUT_PRESET} "${BOARD_MCU}_${IN_BUILD_TYPE}"                                      PARENT_SCOPE)
    set(${OUT_DIR}    "${BUILD_HANDLER_BUILD_DIR}/${BOARD_MCU}_${IN_BUILD_TYPE}_${IN_BOARD}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_BuildBoard
# Description: Configures and builds the project for a board (Debug / Release): the preset of its MCU in a
#              build folder of the board with its configuration (TARGET_BOARD - fixture and own defines of
#              ItBoards.json, Build.cmake).
#
# IN_BOARD      [in]: Board name (boards file of the detection).
# IN_BUILD_TYPE [in]: Debug or Release.
# ------------------------------------------------------------------------------
function(Build_Handler_BuildBoard IN_BOARD IN_BUILD_TYPE)

    if(NOT "${IN_BUILD_TYPE}" MATCHES "^(Debug|Release)$")
        message(FATAL_ERROR "Required BUILD_TYPE '${IN_BUILD_TYPE}' is not correct (Debug, Release).")
    endif()

    # A target <board>@<host>:<probe> of the board lists selects its board
    string(REGEX REPLACE "@.*$" "" IN_BOARD "${IN_BOARD}")

    Build_Handler_Get_BoardBuild("${IN_BOARD}" "${IN_BUILD_TYPE}" MCU PRESET BOARD_DIR)

    set(FRESH_ARG "")
    set(CLEAN_ARG "")

    if(BUILD_CLEAN)
        set(FRESH_ARG --fresh)
        set(CLEAN_ARG --clean-first)
    endif()

    message("=====================================")
    message("Configuration: ${PRESET} of board ${IN_BOARD} ${FRESH_ARG}")
    message("=====================================")
    Build_Handler_Execute("Configuration of ${PRESET} of board ${IN_BOARD}"
                          "${CMAKE_COMMAND}"
                          --preset
                          ${PRESET}
                          -B
                          "${BOARD_DIR}"
                          "-DTARGET_BOARD=${IN_BOARD}"
                          "-DTARGET_BOARDS_FILE=${BUILD_HANDLER_BOARDS_FILE}"
                          ${FRESH_ARG})

    message("=====================================")
    message("Build: ${PRESET} of board ${IN_BOARD} ${CLEAN_ARG}")
    message("=====================================")
    Build_Handler_Execute("Build of ${PRESET} of board ${IN_BOARD}" "${CMAKE_COMMAND}" --build "${BOARD_DIR}" ${CLEAN_ARG})

    message("=====================================")
    message("Build ${PRESET} of board ${IN_BOARD} PASSED")
    message("Output: ${BOARD_DIR}")
    message("=====================================")
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_Docs
# Description: Generates Doxygen documentation of the project for selected MCU
#              (Debug preset configured with DOXYGEN_ENABLED=ON to its own build
#              folder <MCU>_Doxygen, target Doxygen). Requires doxygen artifact
#              (ArtifactsConfig.txt), graphviz artifact for diagrams.
#
# IN_MCU_ID [in]: Numerical ID of the MCU (Build_Handler_PrintMcuList).
# ------------------------------------------------------------------------------
function(Build_Handler_Docs IN_MCU_ID)

    Build_Handler_GetMcuList(MCU_LIST)
    Build_Handler_GetListItem("${MCU_LIST}" "${IN_MCU_ID}" "MCU" MCU)

    set(PRESET    "${MCU}_Debug")
    set(DOCS_DIR  "${BUILD_HANDLER_BUILD_DIR}/${MCU}_Doxygen")
    set(FRESH_ARG "")

    if(BUILD_CLEAN)
        set(FRESH_ARG --fresh)
    endif()

    message("=====================================")
    message("Configuration: ${PRESET} (documentation) ${FRESH_ARG}")
    message("=====================================")
    Build_Handler_Execute("Configuration of ${PRESET} documentation"
        "${CMAKE_COMMAND}" --preset ${PRESET} -B "${DOCS_DIR}" -DDOXYGEN_ENABLED=ON ${FRESH_ARG})

    message("=====================================")
    message("Documentation: ${MCU}")
    message("=====================================")
    Build_Handler_Execute("Documentation generation of ${MCU}"
        "${CMAKE_COMMAND}" --build "${DOCS_DIR}" --target Doxygen)

    message("=====================================")
    message("Documentation ${MCU} PASSED")
    message("Output: ${DOCS_DIR}/Doxygen/html/index.html")
    message("=====================================")
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_PrintTestTargetList
# Description: Prints MCUs (unit tests) or connected boards (integration tests,
#              detected first).
#
# IN_TEST_TYPE [in]: UT or IT.
# ------------------------------------------------------------------------------
function(Build_Handler_PrintTestTargetList IN_TEST_TYPE)

    if("${IN_TEST_TYPE}" STREQUAL "UT")

        Build_Handler_PrintMcuList()

    elseif("${IN_TEST_TYPE}" STREQUAL "IT")

        Build_Handler_DetectBoards()

        # One item per physical board (probe) of this machine and of the IT agents
        IntegrationTesting_ReadTargets(TARGETS_CNT "${BUILD_HANDLER_BOARDS_FILE}")

        set(ITEMS "")

        if(TARGETS_CNT GREATER 0)
            math(EXPR TARGETS_LAST "${TARGETS_CNT} - 1")
            foreach(TARGET_IDX RANGE ${TARGETS_LAST})
                list(APPEND ITEMS "${IT_TARGET_${TARGET_IDX}_TEXT} (${IT_TARGET_${TARGET_IDX}_PRESET})")
            endforeach()
        endif()

        if(ITEMS)
            list(APPEND ITEMS "${BUILD_HANDLER_ALL_BOARDS_TEXT}")
        endif()

        message("")
        Build_Handler_PrintList("Return back" ${ITEMS})

    else()

        message(FATAL_ERROR "Required TEST_TYPE '${IN_TEST_TYPE}' is not correct (UT, IT).")

    endif()
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_TestBuild
# Description: Configures and builds tests of the selected MCU / board and
#              prints its test sets.
#
# IN_TEST_TYPE [in]: UT or IT.
# IN_TARGET_ID [in]: Numerical ID of the MCU / board.
# ------------------------------------------------------------------------------
function(Build_Handler_TestBuild IN_TEST_TYPE IN_TARGET_ID)

    Build_Handler_IsAllBoards(${IN_TEST_TYPE} "${IN_TARGET_ID}" ALL_BOARDS)

    if(ALL_BOARDS AND TEST_COVERAGE)
        message(FATAL_ERROR "The code coverage is not available for the tests on all connected boards - select one board.")
    endif()

    if(ALL_BOARDS)
        # Connected boards are built by IntegrationTesting_AllBoards.cmake
        Build_Handler_ConfigureAllBoards(TEST_SETS)
        set(PRESET "boards file")
        set(TARGET "${BUILD_HANDLER_ALL_BOARDS_TEXT}")
    else()
        Build_Handler_GetTestPreset(${IN_TEST_TYPE} "${IN_TARGET_ID}" PRESET ARGS TARGET)
        Build_Handler_ConfigureAndBuild(${PRESET} ${ARGS})
        Build_Handler_GetTestSets(${PRESET} TEST_SETS)
    endif()

    if(NOT TEST_SETS)
        message(FATAL_ERROR "No test set registered in ${PRESET}.")
    endif()

    message("")
    message("Test sets of ${TARGET}:")
    Build_Handler_PrintList("All test sets" ${TEST_SETS})
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_TestRun
# Description: Executes one or all test sets of the built preset and prints
#              summary of the results.
#
# IN_TEST_TYPE [in]: UT or IT.
# IN_TARGET_ID [in]: Numerical ID of the MCU / board.
# IN_TEST_ID   [in]: Numerical ID of the test set, 0 = all test sets.
# ------------------------------------------------------------------------------
function(Build_Handler_TestRun IN_TEST_TYPE IN_TARGET_ID IN_TEST_ID)

    Build_Handler_IsAllBoards(${IN_TEST_TYPE} "${IN_TARGET_ID}" ALL_BOARDS)

    if(ALL_BOARDS)
        Build_Handler_TestRunAllBoards("${IN_TEST_ID}")
        return()
    endif()

    Build_Handler_GetTestPreset(${IN_TEST_TYPE} "${IN_TARGET_ID}" PRESET ARGS TARGET)

    set(CTEST_FILTER "")

    if(NOT "${IN_TEST_ID}" STREQUAL "0")
        Build_Handler_GetTestSets(${PRESET} TEST_SETS)
        Build_Handler_GetListItem("${TEST_SETS}" "${IN_TEST_ID}" "test set" TEST_SET)
        set(CTEST_FILTER -L "^${TEST_SET}$")
    else()
        set(TEST_SET "all test sets")
    endif()

    if("${IN_TEST_TYPE}" STREQUAL "UT")
        set(JUNIT_FILE "${BUILD_HANDLER_BUILD_DIR}/${PRESET}/UnitTestResults.xml")
    else()
        set(JUNIT_FILE "${BUILD_HANDLER_BUILD_DIR}/${PRESET}/IntegrationTestResults.xml")
    endif()

    # Results of previous execution are not mixed into the summary
    file(REMOVE "${JUNIT_FILE}")

    # The counters of the earlier runs are deleted: the report is the coverage of this run
    if(TEST_COVERAGE)
        Build_Handler_CoverageTarget(${IN_TEST_TYPE} ${PRESET} CoverageReset)
    endif()

    message("=====================================")
    message("Tests: ${PRESET} (${TARGET}), ${TEST_SET}")
    message("=====================================")

    execute_process(
        COMMAND           "${CMAKE_CTEST_COMMAND}" --preset ${PRESET} ${CTEST_FILTER}
        WORKING_DIRECTORY "${BUILD_HANDLER_PROJECT_ROOT}"
        RESULT_VARIABLE   TEST_RESULT
    )

    Build_Handler_PrintResults("${JUNIT_FILE}" "${PRESET} (${TARGET})")

    # The coverage of what ran is reported also when a test failed. The table of one test set shows
    # the folders named like the test set (the report is the same, it contains the other sources with
    # no executed line)
    if(TEST_COVERAGE)
        if(NOT "${IN_TEST_ID}" STREQUAL "0")
            set(ENV{COV_FILTER} "/${TEST_SET}/")
        endif()

        Build_Handler_CoverageTarget(${IN_TEST_TYPE} ${PRESET} Coverage)

        unset(ENV{COV_FILTER})
    endif()

    if(NOT TEST_RESULT EQUAL 0)
        message(FATAL_ERROR "Tests ${PRESET} FAILED.")
    endif()

    message("Tests ${PRESET} PASSED")
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_CoverageTarget
# Description: Builds a coverage target of the framework of the built preset
#              (Coverage: report + table, CoverageSummary: table of the last
#              report, CoverageReset: deletes the counters of earlier runs).
#
# IN_TEST_TYPE [in]: UT or IT.
# IN_PRESET    [in]: Built preset (configured with the coverage).
# IN_TARGET    [in]: Coverage, CoverageSummary or CoverageReset.
# ------------------------------------------------------------------------------
function(Build_Handler_CoverageTarget IN_TEST_TYPE IN_PRESET IN_TARGET)

    set(PREFIX "${BUILD_HANDLER_COVERAGE_PREFIX_${IN_TEST_TYPE}}")

    message("=====================================")
    message("Coverage: ${IN_PRESET}, ${PREFIX}_${IN_TARGET}")
    message("=====================================")
    Build_Handler_Execute("Coverage target ${PREFIX}_${IN_TARGET} of ${IN_PRESET}"
        "${CMAKE_COMMAND}" --build --preset ${IN_PRESET} --target ${PREFIX}_${IN_TARGET})

    if("${IN_TARGET}" STREQUAL "Coverage")
        message("Coverage report: ${BUILD_HANDLER_BUILD_DIR}/${IN_PRESET}/Coverage/index.html")
    endif()
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_TestCoverage
# Description: Prints the table of the coverage by modules of the last report
#              of the MCU / board (the tests were run with TEST_COVERAGE=ON).
#
# IN_TEST_TYPE [in]: UT or IT.
# IN_TARGET_ID [in]: Numerical ID of the MCU / board.
# ------------------------------------------------------------------------------
function(Build_Handler_TestCoverage IN_TEST_TYPE IN_TARGET_ID)

    Build_Handler_IsAllBoards(${IN_TEST_TYPE} "${IN_TARGET_ID}" ALL_BOARDS)

    if(ALL_BOARDS)
        message(FATAL_ERROR "The code coverage is not available for the tests on all connected boards - select one board.")
    endif()

    Build_Handler_GetTestPreset(${IN_TEST_TYPE} "${IN_TARGET_ID}" PRESET ARGS TARGET)

    if(NOT EXISTS "${BUILD_HANDLER_BUILD_DIR}/${PRESET}/Coverage/coverage-summary.json")
        message(FATAL_ERROR "There is no coverage report of ${PRESET} - run the tests with the code coverage first.")
    endif()

    Build_Handler_CoverageTarget(${IN_TEST_TYPE} ${PRESET} CoverageSummary)
    message("Coverage report: ${BUILD_HANDLER_BUILD_DIR}/${PRESET}/Coverage/index.html")
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_TestRunAllBoards
# Description: Executes one or all test sets of integration tests on all
#              connected boards (IntegrationTesting_AllBoards.cmake) and prints
#              summary of the results per probe.
#
# IN_TEST_ID [in]: Numerical ID of the test set (Build_Handler_ConfigureAllBoards),
#                  0 = all test sets.
# ------------------------------------------------------------------------------
function(Build_Handler_TestRunAllBoards IN_TEST_ID)

    set(IT_LABEL_ARG "")

    if(NOT "${IN_TEST_ID}" STREQUAL "0")

        Build_Handler_GetAllBoardsTestSets(TEST_SETS)
        Build_Handler_GetListItem("${TEST_SETS}" "${IN_TEST_ID}" "test set" TEST_SET)
        set(IT_LABEL_ARG "-DIT_LABEL=^${TEST_SET}$")

    else()
        set(TEST_SET "all test sets")
    endif()

    # Results of previous execution are not mixed into the summary
    Build_Handler_GetAllBoardsJUnitFiles(OLD_FILES)

    if(OLD_FILES)
        file(REMOVE ${OLD_FILES})
    endif()

    message("=====================================")
    message("Integration tests: ${BUILD_HANDLER_ALL_BOARDS_TEXT}, ${TEST_SET}")
    message("=====================================")

    execute_process(
        COMMAND           "${CMAKE_COMMAND}" ${BUILD_HANDLER_DETECT_ARGS} -DIT_BOARDS_FILE=${BUILD_HANDLER_BOARDS_FILE}
                          ${IT_LABEL_ARG} -P "${BUILD_HANDLER_IT_ALL_BOARDS}"
        WORKING_DIRECTORY "${BUILD_HANDLER_PROJECT_ROOT}"
        RESULT_VARIABLE   TEST_RESULT
    )

    Build_Handler_GetAllBoardsJUnitFiles(JUNIT_FILES)

    foreach(JUNIT_FILE IN LISTS JUNIT_FILES)

        # Build/<preset>/IntegrationTestResults_<sn>.xml
        get_filename_component(PRESET_DIR "${JUNIT_FILE}" DIRECTORY)
        get_filename_component(PRESET "${PRESET_DIR}" NAME)
        get_filename_component(JUNIT_NAME "${JUNIT_FILE}" NAME_WE)
        string(REGEX REPLACE "^IntegrationTestResults_" "" PROBE_SN "${JUNIT_NAME}")

        Build_Handler_PrintResults("${JUNIT_FILE}" "${PRESET} (probe ${PROBE_SN})")

    endforeach()

    if(NOT TEST_RESULT EQUAL 0)
        message(FATAL_ERROR "Integration tests on connected boards FAILED.")
    endif()

    message("Integration tests on connected boards PASSED")
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_GetTestTargetId
# Description: Numerical ID of the test target selected by name - MCU (UT) or
#              connected physical board (IT, boards are detected first: ID
#              <board>@<host>:<probe> or the name of a board with one physical
#              board), name BUILD_HANDLER_ALL_BOARDS_TEXT selects all connected boards.
#
# IN_TEST_TYPE [in]:  UT or IT.
# IN_TARGET    [in]:  Name of the MCU / ID of the physical board.
# OUT_ID       [out]: Numerical ID of the MCU / board.
# ------------------------------------------------------------------------------
function(Build_Handler_GetTestTargetId IN_TEST_TYPE IN_TARGET OUT_ID)

    if("${IN_TEST_TYPE}" STREQUAL "UT")

        Build_Handler_GetMcuList(MCU_LIST)
        Build_Handler_GetListId("${MCU_LIST}" "${IN_TARGET}" "MCU" TARGET_ID)

    elseif("${IN_TEST_TYPE}" STREQUAL "IT")

        Build_Handler_DetectBoards()
        IntegrationTesting_ReadTargets(TARGETS_CNT "${BUILD_HANDLER_BOARDS_FILE}")

        if(TARGETS_CNT EQUAL 0)
            message(FATAL_ERROR "No connected board detected.")
        endif()

        # ID of a physical board (<board>@<host>:<probe>) or name of a board with one physical board
        if("${IN_TARGET}" STREQUAL "${BUILD_HANDLER_ALL_BOARDS_TEXT}")
            math(EXPR TARGET_ID "${TARGETS_CNT} + 1")
        else()
            IntegrationTesting_FindTarget(TARGET_IDX ${TARGETS_CNT} "${IN_TARGET}")
            if(TARGET_IDX EQUAL -1)
                message(FATAL_ERROR "Required connected board '${IN_TARGET}' not found.")
            endif()
            math(EXPR TARGET_ID "${TARGET_IDX} + 1")
        endif()

    else()

        message(FATAL_ERROR "Required TEST_TYPE '${IN_TEST_TYPE}' is not correct (UT, IT).")

    endif()

    set(${OUT_ID} "${TARGET_ID}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Build_Handler_Test
# Description: Builds tests of the MCU / board selected by name and executes
#              the test set selected by name (non-interactive TEST_BUILD and
#              TEST_RUN).
#
# IN_TEST_TYPE [in]: UT or IT.
# IN_TARGET    [in]: Name of the MCU (UT), ID of a connected physical board or
#                    BUILD_HANDLER_ALL_BOARDS_TEXT (IT).
# IN_TEST_SET  [in]: Name of the test set, empty = all test sets.
# ------------------------------------------------------------------------------
function(Build_Handler_Test IN_TEST_TYPE IN_TARGET IN_TEST_SET)

    Build_Handler_GetTestTargetId(${IN_TEST_TYPE} "${IN_TARGET}" TARGET_ID)
    Build_Handler_TestBuild(${IN_TEST_TYPE} ${TARGET_ID})

    set(TEST_ID 0)

    if(NOT "${IN_TEST_SET}" STREQUAL "")

        Build_Handler_IsAllBoards(${IN_TEST_TYPE} ${TARGET_ID} ALL_BOARDS)

        if(ALL_BOARDS)
            Build_Handler_GetAllBoardsTestSets(TEST_SETS)
        else()
            Build_Handler_GetTestPreset(${IN_TEST_TYPE} ${TARGET_ID} PRESET ARGS TARGET)
            Build_Handler_GetTestSets(${PRESET} TEST_SETS)
        endif()

        Build_Handler_GetListId("${TEST_SETS}" "${IN_TEST_SET}" "test set" TEST_ID)

    endif()

    Build_Handler_TestRun(${IN_TEST_TYPE} ${TARGET_ID} ${TEST_ID})
endfunction()


#==============================================================================#
# Script mode
#
# cmake -DFUNCTION_ID="MCU_LIST"                                          -P Build_Handler.cmake : List MCUs of the project presets
# cmake -DFUNCTION_ID="BUILD"       -DMCU_ID=3 -DBUILD_TYPE=Debug         -P Build_Handler.cmake : Configure and build MCU 3 (Debug / Release)
# cmake -DFUNCTION_ID="DOCS"        -DMCU_ID=3                            -P Build_Handler.cmake : Generate Doxygen documentation of MCU 3 (MCU=<name> by name)
# cmake -DFUNCTION_ID="TEST_TARGET_LIST" -DTEST_TYPE=UT                   -P Build_Handler.cmake : List MCUs (UT) or boards (IT)
# cmake -DFUNCTION_ID="DETECT_BOARDS"                                    -P Build_Handler.cmake : Detect connected boards (IT), no numbered list
# cmake -DFUNCTION_ID="TEST_BUILD"  -DTEST_TYPE=IT -DTARGET_ID=1          -P Build_Handler.cmake : Configure and build tests of board 1, list test sets
# cmake -DFUNCTION_ID="TEST_RUN"    -DTEST_TYPE=IT -DTARGET_ID=1 -DTEST_ID=0 -P Build_Handler.cmake : Execute all test sets (0) of board 1, summary
# cmake -DFUNCTION_ID="TEST_BUILD"  -DTEST_TYPE=IT -DTARGET_ID=<boards+1>  -P Build_Handler.cmake : Configure presets of all boards, list test sets
# cmake -DFUNCTION_ID="TEST_RUN"    -DTEST_TYPE=IT -DTARGET_ID=<boards+1> -DTEST_ID=2 -P Build_Handler.cmake : Execute test set 2 on all connected boards, summary
# cmake -DFUNCTION_ID="TEST_BUILD"  -DTEST_TYPE=UT -DTARGET_ID=1 -DTEST_COVERAGE=ON -P Build_Handler.cmake : Build the tests with the code coverage (TEST_RUN with it: report + table)
# cmake -DFUNCTION_ID="TEST_COVERAGE" -DTEST_TYPE=UT -DTARGET_ID=1                  -P Build_Handler.cmake : Table of the coverage of the last report (TARGET=<name> by name)
#
# Selection by name (VSCode tasks), -DBUILD_CLEAN=ON for clean build (BUILD, TEST, TEST_BUILD):
# cmake -DFUNCTION_ID="BUILD"       -DMCU=STM32F407xG -DBUILD_TYPE=Debug  -P Build_Handler.cmake : Configure and build MCU STM32F407xG
# cmake -DFUNCTION_ID="BUILD"       -DBOARD=STM32H503xB -DBUILD_TYPE=Debug -P Build_Handler.cmake : Build of a board (its configuration, Build/<MCU>_Debug_<board>)
# cmake -DFUNCTION_ID="TEST"        -DTEST_TYPE=UT -DTARGET=STM32F407xG -DTEST_SET=Gpio -P Build_Handler.cmake : Build and execute test set Gpio (empty = all)
# cmake -DFUNCTION_ID="TEST"        -DTEST_TYPE=IT -DTARGET="All connected boards" -P Build_Handler.cmake : Detect boards, build and execute all test sets on all boards
# cmake -DFUNCTION_ID="TEST"        -DTEST_TYPE=IT -DTARGET="STM32H503xB@TestAgent:0483:374e:<SN>" -DTEST_SET=Gpio -P Build_Handler.cmake : Test set Gpio on the board of the IT agent TestAgent
#==============================================================================#
if(CMAKE_SCRIPT_MODE_FILE AND
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)

    if("${FUNCTION_ID}" STREQUAL "MCU_LIST")

        Build_Handler_PrintMcuList()

    elseif("${FUNCTION_ID}" STREQUAL "BUILD" AND
           NOT "${BOARD}" STREQUAL "")

        Build_Handler_BuildBoard("${BOARD}" "${BUILD_TYPE}")

    elseif("${FUNCTION_ID}" STREQUAL "BUILD")

        if(NOT "${MCU}" STREQUAL "")
            Build_Handler_GetMcuList(MCU_LIST)
            Build_Handler_GetListId("${MCU_LIST}" "${MCU}" "MCU" MCU_ID)
        endif()

        Build_Handler_Build("${MCU_ID}" "${BUILD_TYPE}")

    elseif("${FUNCTION_ID}" STREQUAL "DOCS")

        if(NOT "${MCU}" STREQUAL "")
            Build_Handler_GetMcuList(MCU_LIST)
            Build_Handler_GetListId("${MCU_LIST}" "${MCU}" "MCU" MCU_ID)
        endif()

        Build_Handler_Docs("${MCU_ID}")

    elseif("${FUNCTION_ID}" STREQUAL "TEST")

        Build_Handler_Test("${TEST_TYPE}" "${TARGET}" "${TEST_SET}")

    elseif("${FUNCTION_ID}" STREQUAL "TEST_TARGET_LIST")

        Build_Handler_PrintTestTargetList("${TEST_TYPE}")

    elseif("${FUNCTION_ID}" STREQUAL "DETECT_BOARDS")

        Build_Handler_DetectBoards()

    elseif("${FUNCTION_ID}" STREQUAL "TEST_COVERAGE")

        if(NOT "${TARGET}" STREQUAL "")
            Build_Handler_GetTestTargetId("${TEST_TYPE}" "${TARGET}" TARGET_ID)
        endif()

        Build_Handler_TestCoverage("${TEST_TYPE}" "${TARGET_ID}")

    elseif("${FUNCTION_ID}" STREQUAL "TEST_BUILD")

        Build_Handler_TestBuild("${TEST_TYPE}" "${TARGET_ID}")

    elseif("${FUNCTION_ID}" STREQUAL "TEST_RUN")

        if(NOT DEFINED TEST_ID OR NOT "${TEST_ID}" MATCHES "^[0-9]+$")
            message(FATAL_ERROR "Required TEST_ID is not correct.")
        endif()

        Build_Handler_TestRun("${TEST_TYPE}" "${TARGET_ID}" "${TEST_ID}")

    else()

        message(FATAL_ERROR "Unknown FUNCTION_ID '${FUNCTION_ID}'.")

    endif()

endif()
