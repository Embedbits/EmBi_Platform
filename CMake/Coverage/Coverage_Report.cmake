################################################################################
# Author: Mr.Nobody
# file:  Coverage_Report.cmake
# brief: Creates the coverage report of the tests by gcovr.
#
# Called by the targets <Test>_Coverage (see Coverage.cmake):
#   cmake -DCOV_GCOVR=<gcovr> -DCOV_GCOV=<gcov> -DCOV_ROOT=<source root>
#         -DCOV_SEARCH_DIRS=<build folders> -DCOV_OUT_DIR=<report folder>
#         [-DCOV_EXCLUDES=<regular expressions>] [-DCOV_TRACEFILES=<json files>]
#         [-DCOV_TITLE=<text>] [-DCOV_GROUP=dir|file] [-DCOV_FILTER=<regex>]
#         [-DCOV_MIN_LINES=<percent>] -P Coverage_Report.cmake
#
#   COV_GCOVR        - gcovr executable (artifact gcovr)
#   COV_GCOV         - gcov of the compiler which built the tested code, the
#                      command if gcov has an argument ("llvm-cov gcov"); not
#                      needed when the report is created from tracefiles only
#   COV_ROOT         - root of the sources, the paths in the report are relative
#                      to it
#   COV_SEARCH_DIRS  - folders searched for the gcov data (.gcno / .gcda) -
#                      always the build folder of the tests, not the source root
#                      (it would merge the data of other build folders)
#   COV_TRACEFILES   - JSON tracefiles (coverage.json of previous reports)
#                      merged into the report, eg. of other MCUs or of the unit
#                      and integration tests; they replace COV_SEARCH_DIRS when
#                      it is empty
#   COV_EXCLUDES     - regular expressions of the paths excluded from the report
#   COV_RELATIVE     - ON: the gcov data name the sources relative to COV_ROOT (the code was
#                      compiled with -fprofile-prefix-map), gcovr runs in COV_ROOT and keeps the
#                      relative paths. The data can be evaluated in another folder than the one
#                      the code was compiled in.
#   COV_OUT_DIR      - folder of the report, outputs:
#                        index.html (+ files of the sources)   HTML report
#                        Cobertura.xml                         Azure Pipelines
#                        coverage.json                         tracefile (merge)
#                        coverage-summary.json                 summary (Coverage_Summary.cmake)
#                        coverage.txt                          text report
#   COV_GROUP / COV_FILTER / COV_MIN_LINES - the table printed after the report,
#                      see Coverage_Summary.cmake
#
# The script fails when there is no coverage data (the tests were not executed).
################################################################################

cmake_minimum_required(VERSION 3.25)

include("${CMAKE_CURRENT_LIST_DIR}/Coverage_Summary.cmake")

#============================== Parameters check ==============================#

foreach(PARAMETER IN ITEMS COV_GCOVR COV_ROOT COV_OUT_DIR)
    if(NOT ${PARAMETER})
        message(FATAL_ERROR "Parameter ${PARAMETER} is not set.")
    endif()
endforeach()

if(NOT EXISTS "${COV_GCOVR}")
    message(FATAL_ERROR "gcovr not found ('${COV_GCOVR}'). Add the artifact 'gcovr' or pass -DGCOVR_EXECUTABLE=<path>.")
endif()

if(NOT COV_SEARCH_DIRS AND NOT COV_TRACEFILES)
    message(FATAL_ERROR "Neither COV_SEARCH_DIRS nor COV_TRACEFILES is set.")
endif()

if(COV_SEARCH_DIRS AND NOT COV_GCOV)
    message(FATAL_ERROR "Parameter COV_GCOV (gcov of the compiler) is not set.")
endif()

if(NOT COV_TITLE)
    set(COV_TITLE "Code coverage")
endif()

if(NOT COV_GROUP)
    set(COV_GROUP "dir")
endif()

# Filter of the printed table (the report itself contains everything)
if(NOT COV_FILTER AND DEFINED ENV{COV_FILTER})
    set(COV_FILTER "$ENV{COV_FILTER}")
endif()

#============================= Coverage data check ============================#

# Data of the executed tests - a report without them would show 0 % and hide that
# the tests were not executed
set(DATA_FOUND FALSE)

foreach(SEARCH_DIR IN LISTS COV_SEARCH_DIRS)

    file(GLOB_RECURSE GCDA_FILES LIST_DIRECTORIES FALSE "${SEARCH_DIR}/*.gcda")

    if(GCDA_FILES)
        set(DATA_FOUND TRUE)
    endif()

endforeach()

if(COV_SEARCH_DIRS AND NOT DATA_FOUND AND NOT COV_TRACEFILES)
    message(FATAL_ERROR "No coverage data (*.gcda) found in ${COV_SEARCH_DIRS}. Either the tests of the build configured "
                        "with the coverage option were not executed (ctest) or no tested source is instrumented "
                        "(the code under test has to be listed in UUT_SOURCES of the test set).")
endif()

foreach(TRACEFILE IN LISTS COV_TRACEFILES)
    if(NOT EXISTS "${TRACEFILE}")
        message(FATAL_ERROR "Tracefile ${TRACEFILE} does not exist.")
    endif()
endforeach()

#================================== Report ====================================#

# Outputs of the previous report only (the folder is not deleted as a whole)
file(GLOB OLD_OUTPUTS "${COV_OUT_DIR}/index*" "${COV_OUT_DIR}/Cobertura.xml" "${COV_OUT_DIR}/coverage*")

if(OLD_OUTPUTS)
    file(REMOVE ${OLD_OUTPUTS})
endif()

file(MAKE_DIRECTORY "${COV_OUT_DIR}")

set(GCOVR_ARGS
    --root "${COV_ROOT}"
    --exclude-unreachable-branches
    --exclude-throw-branches
    --merge-mode-functions merge-use-line-min
    --html-details "${COV_OUT_DIR}/index.html"
    --html-title "${COV_TITLE}"
    --cobertura "${COV_OUT_DIR}/Cobertura.xml"
    --json "${COV_OUT_DIR}/coverage.json"
    --json-summary "${COV_OUT_DIR}/coverage-summary.json"
    --txt "${COV_OUT_DIR}/coverage.txt"
)

if(COV_GCOV)
    list(APPEND GCOVR_ARGS --gcov-executable "${COV_GCOV}")
endif()

if(COV_SEARCH_DIRS)
    # Threads of the evaluation of the gcov files
    cmake_host_system_information(RESULT CPU_COUNT QUERY NUMBER_OF_LOGICAL_CORES)
    list(APPEND GCOVR_ARGS -j ${CPU_COUNT})
endif()

if(COV_RELATIVE)
    # The default filter (files under the root) does not know relative names; the files outside of the
    # root (the sources of the toolchain) have absolute names
    list(APPEND GCOVR_ARGS --filter ".*" --exclude "^/" --exclude "^[A-Za-z]:")
endif()

foreach(EXCLUDE IN LISTS COV_EXCLUDES)
    list(APPEND GCOVR_ARGS --exclude "${EXCLUDE}")
endforeach()

foreach(TRACEFILE IN LISTS COV_TRACEFILES)
    list(APPEND GCOVR_ARGS --add-tracefile "${TRACEFILE}")
endforeach()

message(STATUS "Creating the coverage report: ${COV_OUT_DIR}")

# The search folders are the last (positional) arguments
execute_process(
    COMMAND "${COV_GCOVR}" ${GCOVR_ARGS} ${COV_SEARCH_DIRS}
    WORKING_DIRECTORY "${COV_ROOT}"
    RESULT_VARIABLE GCOVR_RESULT
    OUTPUT_VARIABLE GCOVR_OUTPUT
    ERROR_VARIABLE  GCOVR_ERROR
)

if(NOT GCOVR_RESULT EQUAL 0)
    message("${GCOVR_OUTPUT}")
    message("${GCOVR_ERROR}")
    message(FATAL_ERROR "gcovr failed (${GCOVR_RESULT}).")
endif()

# Warnings of gcovr (parse errors, source not found) belong to the report
if(GCOVR_ERROR MATCHES "\\(WARNING\\)")
    message("${GCOVR_ERROR}")
endif()

#================================== Summary ===================================#

coverageSummary_Print(COV_LINES_PERCENT "${COV_OUT_DIR}/coverage-summary.json" "${COV_GROUP}" "${COV_FILTER}" "${COV_TITLE}")

message(STATUS "Coverage report: ${COV_OUT_DIR}/index.html")
message(STATUS "Cobertura XML:   ${COV_OUT_DIR}/Cobertura.xml")
message(STATUS "Tracefile:       ${COV_OUT_DIR}/coverage.json")

coverageSummary_Check("${COV_LINES_PERCENT}" "${COV_MIN_LINES}")
