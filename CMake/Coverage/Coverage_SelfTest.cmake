################################################################################
# Author: Mr.Nobody
# file:  Coverage_SelfTest.cmake
# brief: Self-test of the coverage report on the host (gcovr, gcov, scripts, paths).
#
#   cmake [-DBUILD_DIR=<folder>] [-DTOOLS=ARTIFACTS|SYSTEM] [-DGENERATOR=<generator>]
#         [-DCMAKE_ARGS=<configuration arguments>] -P Coverage_SelfTest.cmake
#
# Executes the unit tests of the module SelfTest (Calc) with the coverage by the
# standalone unit testing (UnitTesting/Standalone/RunModuleTests.cmake) and checks
# the results against the known coverage of the module:
#   - the report: HTML, Cobertura XML, tracefile, JSON summary, text report; Calc.c has
#     11 of 14 lines and 2 of 3 functions covered (Calc_Unused is never called, the
#     branch of Calc_Clamp below the range is not tested),
#   - the table of the coverage (UnitTest_CoverageSummary) and the minimum of the
#     coverage (a required line coverage above the real one fails),
#   - the merge of tracefiles (the same tracefile twice does not change the percentage),
#   - the reset of the data (UnitTest_CoverageReset) and the report without data (fails).
#
# Parameters of RunModuleTests.cmake (TOOLS, GENERATOR, CMAKE_ARGS) are passed on,
# eg. -DCMAKE_ARGS=-DGCOVR_EXECUTABLE=<gcovr> for a gcovr which is not an artifact.
################################################################################

cmake_minimum_required(VERSION 3.25)

#=============================== Constant values ==============================#

set(SELFTEST_FILE               "SelfTest/Calc.c")
set(SELFTEST_LINES_TOTAL        14)
set(SELFTEST_LINES_COVERED      11)
set(SELFTEST_FUNCTIONS_TOTAL    3)
set(SELFTEST_FUNCTIONS_COVERED  2)

get_filename_component(COVERAGE_DIR "${CMAKE_CURRENT_LIST_DIR}" ABSOLUTE)
get_filename_component(PLATFORM_DIR "${COVERAGE_DIR}/../.." ABSOLUTE)

if(NOT BUILD_DIR)
    set(BUILD_DIR "Build_CoverageSelfTest")
endif()

get_filename_component(BUILD_DIR "${BUILD_DIR}" ABSOLUTE)

#================================ Functions ===================================#

#------------------------------------------------------------------------------#
# Fails the self-test.
#------------------------------------------------------------------------------#
function(selfTest_Fail MESSAGE_TEXT)

    message(FATAL_ERROR "Coverage self-test FAILED: ${MESSAGE_TEXT}")

endfunction(selfTest_Fail)


#------------------------------------------------------------------------------#
# Checks a numeric value of the JSON summary of the file.
#
# SUMMARY_JSON [in]: JSON summary of gcovr
# FIELD        [in]: Field of the file (line_total, ...)
# EXPECTED     [in]: Expected value
#------------------------------------------------------------------------------#
function(selfTest_Check_File SUMMARY_JSON FIELD EXPECTED)

    string(JSON FILES_CNT LENGTH "${SUMMARY_JSON}" files)

    if(NOT FILES_CNT EQUAL 1)
        selfTest_Fail("the summary contains ${FILES_CNT} files, expected only ${SELFTEST_FILE}.")
    endif()

    string(JSON FILE_NAME GET "${SUMMARY_JSON}" files 0 filename)
    string(JSON VALUE     GET "${SUMMARY_JSON}" files 0 ${FIELD})

    if(NOT FILE_NAME STREQUAL SELFTEST_FILE)
        selfTest_Fail("the file of the summary is '${FILE_NAME}', expected '${SELFTEST_FILE}'.")
    endif()

    if(NOT VALUE EQUAL EXPECTED)
        selfTest_Fail("${FIELD} of ${SELFTEST_FILE} is ${VALUE}, expected ${EXPECTED}.")
    endif()

    message(STATUS "OK: ${FIELD} = ${VALUE}")

endfunction(selfTest_Check_File)


#------------------------------------------------------------------------------#
# Executes the process, the self-test fails if its exit code is not as expected.
#
# DESCRIPTION [in]: What the process does
# SHALL_FAIL  [in]: TRUE if the process shall fail
# ARGN        [in]: Command
#------------------------------------------------------------------------------#
function(selfTest_Run DESCRIPTION SHALL_FAIL)

    message(STATUS "==== ${DESCRIPTION}")

    execute_process(COMMAND ${ARGN} RESULT_VARIABLE RUN_RESULT OUTPUT_VARIABLE RUN_OUTPUT ERROR_VARIABLE RUN_ERROR)

    if(SHALL_FAIL AND RUN_RESULT EQUAL 0)
        message("${RUN_OUTPUT}${RUN_ERROR}")
        selfTest_Fail("${DESCRIPTION} succeeded, it shall fail.")
    elseif(NOT SHALL_FAIL AND NOT RUN_RESULT EQUAL 0)
        message("${RUN_OUTPUT}${RUN_ERROR}")
        selfTest_Fail("${DESCRIPTION} failed (${RUN_RESULT}).")
    endif()

    set(RUN_OUTPUT "${RUN_OUTPUT}${RUN_ERROR}" PARENT_SCOPE)

endfunction(selfTest_Run)

#============================ 1: Tests and report =============================#

set(RUN_ARGS "")

foreach(PARAMETER IN ITEMS TOOLS GENERATOR)
    if(${PARAMETER})
        list(APPEND RUN_ARGS "-D${PARAMETER}=${${PARAMETER}}")
    endif()
endforeach()

file(REMOVE_RECURSE "${BUILD_DIR}")

message(STATUS "==== Unit tests with the coverage and the report")

execute_process(
    COMMAND "${CMAKE_COMMAND}"
            "-DMODULE_PATH=${COVERAGE_DIR}/SelfTest" "-DBUILD_DIR=${BUILD_DIR}" -DCOVERAGE=ON ${RUN_ARGS}
            "-DCMAKE_ARGS=${CMAKE_ARGS}"
            -P "${PLATFORM_DIR}/CMake/UnitTesting/Standalone/RunModuleTests.cmake"
    RESULT_VARIABLE RUN_RESULT
)

if(NOT RUN_RESULT EQUAL 0)
    selfTest_Fail("the unit tests with the coverage failed (${RUN_RESULT}).")
endif()

set(REPORT_DIR "${BUILD_DIR}/Coverage")

foreach(OUTPUT IN ITEMS index.html Cobertura.xml coverage.json coverage-summary.json coverage.txt)
    if(NOT EXISTS "${REPORT_DIR}/${OUTPUT}")
        selfTest_Fail("the report does not contain ${OUTPUT}.")
    endif()
endforeach()

file(READ "${REPORT_DIR}/coverage-summary.json" SUMMARY_JSON)

selfTest_Check_File("${SUMMARY_JSON}" line_total        ${SELFTEST_LINES_TOTAL})
selfTest_Check_File("${SUMMARY_JSON}" line_covered      ${SELFTEST_LINES_COVERED})
selfTest_Check_File("${SUMMARY_JSON}" function_total    ${SELFTEST_FUNCTIONS_TOTAL})
selfTest_Check_File("${SUMMARY_JSON}" function_covered  ${SELFTEST_FUNCTIONS_COVERED})

file(READ "${REPORT_DIR}/Cobertura.xml" COBERTURA)

if(NOT COBERTURA MATCHES "filename=\"${SELFTEST_FILE}\"")
    selfTest_Fail("Cobertura.xml does not contain ${SELFTEST_FILE}.")
endif()

#============================== 2: Summary table ==============================#

selfTest_Run("Table of the coverage" FALSE
    "${CMAKE_COMMAND}" --build "${BUILD_DIR}" --target UnitTest_CoverageSummary)

if(NOT RUN_OUTPUT MATCHES "SelfTest[ ]+11/14[ ]+78\\.5%")
    message("${RUN_OUTPUT}")
    selfTest_Fail("the table of the coverage does not contain the row of the module SelfTest (11/14 78.5%).")
endif()

# The same table from the command line (nothing else than CMake is needed)
selfTest_Run("Table of the coverage by files" FALSE
    "${CMAKE_COMMAND}" "-DCOV_SUMMARY_FILE=${REPORT_DIR}/coverage-summary.json" -DCOV_GROUP=file
    -P "${COVERAGE_DIR}/Coverage_Summary.cmake")

if(NOT RUN_OUTPUT MATCHES "SelfTest/Calc\\.c[ ]+11/14[ ]+78\\.5%")
    message("${RUN_OUTPUT}")
    selfTest_Fail("the table by files does not contain the row of SelfTest/Calc.c.")
endif()

# Minimum of the coverage
selfTest_Run("Required line coverage 78 % (reached)" FALSE
    "${CMAKE_COMMAND}" "-DCOV_SUMMARY_FILE=${REPORT_DIR}/coverage-summary.json" -DCOV_MIN_LINES=78
    -P "${COVERAGE_DIR}/Coverage_Summary.cmake")

selfTest_Run("Required line coverage 79 % (not reached)" TRUE
    "${CMAKE_COMMAND}" "-DCOV_SUMMARY_FILE=${REPORT_DIR}/coverage-summary.json" -DCOV_MIN_LINES=79
    -P "${COVERAGE_DIR}/Coverage_Summary.cmake")

#============================ 3: Merge of tracefiles ==========================#

file(STRINGS "${BUILD_DIR}/CMakeCache.txt" GCOVR_CACHE_LINE REGEX "^GCOVR_EXECUTABLE:")
string(REGEX REPLACE "^[^=]*=" "" GCOVR_PATH "${GCOVR_CACHE_LINE}")

file(STRINGS "${BUILD_DIR}/CMakeCache.txt" ROOT_CACHE_LINE REGEX "^UNIT_TEST_COVERAGE_ROOT:")
string(REGEX REPLACE "^[^=]*=" "" ROOT_PATH "${ROOT_CACHE_LINE}")

set(MERGED_DIR "${BUILD_DIR}/CoverageMerged")

selfTest_Run("Merge of the same tracefile twice" FALSE
    "${CMAKE_COMMAND}" "-DCOV_GCOVR=${GCOVR_PATH}" "-DCOV_ROOT=${ROOT_PATH}"
    "-DCOV_TRACEFILES=${REPORT_DIR}/coverage.json;${REPORT_DIR}/coverage.json"
    "-DCOV_OUT_DIR=${MERGED_DIR}" -P "${COVERAGE_DIR}/Coverage_Report.cmake")

file(READ "${MERGED_DIR}/coverage-summary.json" MERGED_JSON)

selfTest_Check_File("${MERGED_JSON}" line_total   ${SELFTEST_LINES_TOTAL})
selfTest_Check_File("${MERGED_JSON}" line_covered ${SELFTEST_LINES_COVERED})

#=============================== 4: Data reset ================================#

selfTest_Run("Reset of the coverage data" FALSE
    "${CMAKE_COMMAND}" --build "${BUILD_DIR}" --target UnitTest_CoverageReset)

file(GLOB_RECURSE GCDA_FILES "${BUILD_DIR}/*.gcda")

if(GCDA_FILES)
    selfTest_Fail("the reset did not delete the coverage data: ${GCDA_FILES}")
endif()

selfTest_Run("Report without coverage data" TRUE
    "${CMAKE_COMMAND}" --build "${BUILD_DIR}" --target UnitTest_Coverage)

if(NOT RUN_OUTPUT MATCHES "No coverage data")
    message("${RUN_OUTPUT}")
    selfTest_Fail("the report without data did not say that there is no coverage data.")
endif()

message(STATUS "Coverage self-test passed.")
