################################################################################
# Author: Mr.Nobody
# file:  IntegrationTesting_Check.cmake
# brief: Evaluates result of one test function from integration test output.
#
# Called by CTest (test "<NAME>.<function>", see IntegrationTesting.cmake):
#   cmake -DIT_LOG=<output.log> -DIT_CASE=<function> -P IntegrationTesting_Check.cmake
#
# Unity result line "<file>:<line>:<function>:PASS|FAIL|IGNORE[: message]" is
# printed. FAIL or missing result fails the test, IGNORE is reported as skipped
# (SKIP_REGULAR_EXPRESSION ":IGNORE").
################################################################################

cmake_minimum_required(VERSION 3.22)

if(NOT EXISTS "${IT_LOG}")
    message(FATAL_ERROR "Output of the test firmware ${IT_LOG} does not exist (test firmware was not executed).")
endif()

file(STRINGS "${IT_LOG}" RESULT_LINES REGEX ":${IT_CASE}:(PASS|FAIL|IGNORE)")

list(LENGTH RESULT_LINES RESULT_LINES_CNT)

if(NOT RESULT_LINES_CNT EQUAL 1)
    message(FATAL_ERROR "Result of ${IT_CASE} not found in ${IT_LOG} (${RESULT_LINES_CNT} results).")
endif()

message("${RESULT_LINES}")

string(FIND "${RESULT_LINES}" ":${IT_CASE}:FAIL" FAIL_POSITION)

if(NOT FAIL_POSITION EQUAL -1)
    message(FATAL_ERROR "Test ${IT_CASE} failed.")
endif()
