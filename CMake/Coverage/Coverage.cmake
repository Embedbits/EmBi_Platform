################################################################################
# Author: Mr.Nobody
# file:  Coverage.cmake
# brief: Code coverage of the tests - report targets shared by the unit tests
#        (host) and the integration tests (target).
#
# The code under test is compiled with gcov instrumentation (--coverage), the
# executed tests write the counters (*.gcda), gcovr evaluates them together with
# the notes of the compiler (*.gcno) and creates the reports. Included by
# UnitTesting.cmake and IntegrationTesting.cmake, a project does not use it
# directly.
#
# Tools (artifacts, never the system):
#   GCOVR_EXECUTABLE - gcovr, artifact "gcovr" (exported by the artifact
#                      initialization) or the parameter / environment variable
#   gcov             - belongs to the compiler which built the tested code
#                      (artifacts gcc, gcc-arm-none-eabi), found next to it
#
# Outputs of a report (<build>/Coverage/...): HTML, Cobertura XML (Azure
# Pipelines), JSON tracefile (merge of the reports), JSON summary, text.
################################################################################

include_guard(GLOBAL)

#=============================== Constant values ==============================#

set(COVERAGE_SCRIPTS_DIR                "${CMAKE_CURRENT_LIST_DIR}")

#================================ Functions ===================================#

#------------------------------------------------------------------------------#
# Provides gcovr: the parameter GCOVR_EXECUTABLE, the environment variable, the
# artifact "gcovr" (GCOVR_EXECUTABLE exported by the artifact initialization).
# gcovr of the system (PATH) is searched only in the explicit SYSTEM mode of the
# standalone unit tests (UNIT_TEST_TOOLS=SYSTEM). The function stops the
# configuration when gcovr is not available - the coverage was requested.
#
# OPTION_NAME [in]: Option which requested the coverage (for the error message)
#------------------------------------------------------------------------------#
function(Coverage_Provide_Gcovr OPTION_NAME)

    if(NOT GCOVR_EXECUTABLE AND DEFINED ENV{GCOVR_EXECUTABLE})
        set(GCOVR_EXECUTABLE "$ENV{GCOVR_EXECUTABLE}" CACHE FILEPATH "gcovr" FORCE)
    endif()

    if(NOT GCOVR_EXECUTABLE AND "${UNIT_TEST_TOOLS}" STREQUAL "SYSTEM")
        find_program(GCOVR_EXECUTABLE gcovr)
    endif()

    if(NOT GCOVR_EXECUTABLE OR NOT EXISTS "${GCOVR_EXECUTABLE}")
        message(FATAL_ERROR "${OPTION_NAME} is ON but gcovr was not found ('${GCOVR_EXECUTABLE}'). "
                            "Add the artifact 'gcovr' to the artifacts list or pass -DGCOVR_EXECUTABLE=<path>.")
    endif()

    message(STATUS "gcovr: ${GCOVR_EXECUTABLE}")

endfunction(Coverage_Provide_Gcovr)


#------------------------------------------------------------------------------#
# Returns the gcov matching the compiler: gcov is next to the compiler with the
# same prefix and suffix of the name (gcc -> gcov, gcc-15 -> gcov-15,
# arm-none-eabi-gcc -> arm-none-eabi-gcov); the compilers based on LLVM (Clang)
# are used with "llvm-cov gcov" next to the compiler (not tested). A gcov of another compiler version
# gives wrong or no data, so the system is not searched.
#
# GCOV_VAR    [out]: Command of gcov for gcovr (--gcov-executable), "" if not found
# COMPILER    [in]:  C compiler (CMAKE_C_COMPILER)
# COMPILER_ID [in]:  Id of the compiler (CMAKE_C_COMPILER_ID)
#------------------------------------------------------------------------------#
function(Coverage_Find_Gcov GCOV_VAR COMPILER COMPILER_ID)

    set(GCOV_PATH      "")
    set(GCOV_ARGUMENTS "")

    get_filename_component(COMPILER_DIR  "${COMPILER}" DIRECTORY)
    get_filename_component(COMPILER_FILE "${COMPILER}" NAME)

    string(REGEX REPLACE "\\.exe$" "" COMPILER_FILE "${COMPILER_FILE}")

    if(COMPILER_ID MATCHES "Clang")

        find_program(LLVM_COV_PROGRAM NAMES llvm-cov HINTS "${COMPILER_DIR}" NO_DEFAULT_PATH NO_CACHE)

        if(LLVM_COV_PROGRAM)
            set(GCOV_PATH      "${LLVM_COV_PROGRAM}")
            set(GCOV_ARGUMENTS " gcov")
        endif()

    elseif(COMPILER_FILE MATCHES "^(.*)gcc(-[0-9.]+)?$")

        find_program(GCOV_PROGRAM NAMES "${CMAKE_MATCH_1}gcov${CMAKE_MATCH_2}" HINTS "${COMPILER_DIR}" NO_DEFAULT_PATH NO_CACHE)

        if(GCOV_PROGRAM)
            set(GCOV_PATH "${GCOV_PROGRAM}")
        endif()

    endif()

    # gcovr splits the command like a shell
    if(GCOV_PATH MATCHES " ")
        set(GCOV_PATH "\"${GCOV_PATH}\"")
    endif()

    set(${GCOV_VAR} "${GCOV_PATH}${GCOV_ARGUMENTS}" PARENT_SCOPE)

endfunction(Coverage_Find_Gcov)


#------------------------------------------------------------------------------#
# Creates the targets of the coverage of one kind of tests:
#   <PREFIX>_Coverage         report (HTML, Cobertura, JSON) + the table of the coverage
#   <PREFIX>_CoverageSummary  the table of the last report only
#   <PREFIX>_CoverageReset    deletes the counters of the earlier runs (*.gcda)
#
# PREFIX      [in]: Prefix of the targets (UnitTest, IntegrationTest)
# TITLE       [in]: Title of the report
# GCOV        [in]: gcov command for gcovr (Coverage_Find_Gcov)
# ROOT        [in]: Root of the sources
# SEARCH_DIRS [in]: Build folders with the gcov data
# EXCLUDES    [in]: Regular expressions of the excluded paths
# MIN_LINES   [in]: Required line coverage in percent (0 = not checked)
# OUTPUT_DIR  [in]: Folder of the report (default <build>/Coverage)
# RELATIVE_PATHS [in]: The gcov data name the sources relative to the root (-fprofile-prefix-map,
#                     the data of the integration tests can be evaluated in another folder)
# CTEST_REPORT   [in]: ctest creates the report and prints the table after the last test: the file
#                     CTestCustom.cmake of the build folder runs <PREFIX>_Coverage as CTEST_CUSTOM_POST_TEST
#                     (no test case is added). Without it a CTestCustom.cmake written by this function is deleted.
#------------------------------------------------------------------------------#
function(Coverage_Add_Targets)

    cmake_parse_arguments(COV
        "RELATIVE_PATHS;CTEST_REPORT"
        "PREFIX;TITLE;GCOV;ROOT;MIN_LINES;OUTPUT_DIR"
        "SEARCH_DIRS;EXCLUDES"
        ${ARGN})

    foreach(ARGUMENT IN ITEMS PREFIX GCOV ROOT SEARCH_DIRS)
        if(NOT COV_${ARGUMENT})
            message(FATAL_ERROR "Coverage_Add_Targets: ${ARGUMENT} is required.")
        endif()
    endforeach()

    if(NOT COV_OUTPUT_DIR)
        set(COV_OUTPUT_DIR "${CMAKE_BINARY_DIR}/Coverage")
    endif()

    if(NOT COV_MIN_LINES)
        set(COV_MIN_LINES 0)
    endif()

    if(COV_RELATIVE_PATHS)
        set(COV_RELATIVE ON)
    else()
        set(COV_RELATIVE OFF)
    endif()

    add_custom_target(${COV_PREFIX}_Coverage
        COMMAND "${CMAKE_COMMAND}"
                "-DCOV_GCOVR=${GCOVR_EXECUTABLE}"
                "-DCOV_GCOV=${COV_GCOV}"
                "-DCOV_ROOT=${COV_ROOT}"
                "-DCOV_SEARCH_DIRS=${COV_SEARCH_DIRS}"
                "-DCOV_EXCLUDES=${COV_EXCLUDES}"
                "-DCOV_OUT_DIR=${COV_OUTPUT_DIR}"
                "-DCOV_TITLE=${COV_TITLE}"
                "-DCOV_MIN_LINES=${COV_MIN_LINES}"
                "-DCOV_RELATIVE=${COV_RELATIVE}"
                -P "${COVERAGE_SCRIPTS_DIR}/Coverage_Report.cmake"
        COMMENT "Creating the coverage report (${COV_PREFIX})"
        USES_TERMINAL
        VERBATIM
    )

    add_custom_target(${COV_PREFIX}_CoverageSummary
        COMMAND "${CMAKE_COMMAND}"
                "-DCOV_SUMMARY_FILE=${COV_OUTPUT_DIR}/coverage-summary.json"
                "-DCOV_TITLE=${COV_TITLE}"
                "-DCOV_MIN_LINES=${COV_MIN_LINES}"
                -P "${COVERAGE_SCRIPTS_DIR}/Coverage_Summary.cmake"
        COMMENT "Coverage summary (${COV_PREFIX})"
        USES_TERMINAL
        VERBATIM
    )

    add_custom_target(${COV_PREFIX}_CoverageReset
        COMMAND "${CMAKE_COMMAND}"
                "-DCOV_SEARCH_DIRS=${COV_SEARCH_DIRS}"
                -P "${COVERAGE_SCRIPTS_DIR}/Coverage_Reset.cmake"
        COMMENT "Deleting the coverage data (${COV_PREFIX})"
        VERBATIM
    )

    # The report and the table after the tests of a plain ctest. ctest runs the command itself (the variable
    # CMAKE_COMMAND is not defined there), so the paths are written into the file.
    set(COV_CTEST_FILE "${CMAKE_BINARY_DIR}/CTestCustom.cmake")

    if(COV_CTEST_REPORT)
        file(WRITE "${COV_CTEST_FILE}"
            "# Generated by Coverage_Add_Targets (Coverage.cmake): the coverage report after the tests\n"
            "set(CTEST_CUSTOM_POST_TEST \"\\\"${CMAKE_COMMAND}\\\" --build \\\"${CMAKE_BINARY_DIR}\\\" --target ${COV_PREFIX}_Coverage\")\n")
    elseif(EXISTS "${COV_CTEST_FILE}")
        file(READ "${COV_CTEST_FILE}" COV_CTEST_OLD)

        if(COV_CTEST_OLD MATCHES "Generated by Coverage_Add_Targets")
            file(REMOVE "${COV_CTEST_FILE}")
        endif()
    endif()

endfunction(Coverage_Add_Targets)
