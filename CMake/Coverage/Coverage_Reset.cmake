################################################################################
# Author: Mr.Nobody
# file:  Coverage_Reset.cmake
# brief: Deletes the gcov data of the executed tests (counters of earlier runs).
#
# Called by the targets <Test>_CoverageReset (see Coverage.cmake):
#   cmake -DCOV_SEARCH_DIRS=<build folders> -P Coverage_Reset.cmake
#
# The counters in *.gcda files are added up by every run of the tests, so the
# report of a build folder shows all runs since the last reset. A run of the tests
# which shall be measured alone starts with the reset (the pipelines build in a
# clean folder and do not need it).
################################################################################

cmake_minimum_required(VERSION 3.25)

if(NOT COV_SEARCH_DIRS)
    message(FATAL_ERROR "Parameter COV_SEARCH_DIRS is not set.")
endif()

set(DELETED_CNT 0)

foreach(SEARCH_DIR IN LISTS COV_SEARCH_DIRS)

    file(GLOB_RECURSE GCDA_FILES LIST_DIRECTORIES FALSE "${SEARCH_DIR}/*.gcda")

    foreach(GCDA_FILE IN LISTS GCDA_FILES)
        file(REMOVE "${GCDA_FILE}")
        math(EXPR DELETED_CNT "${DELETED_CNT} + 1")
    endforeach()

endforeach()

message(STATUS "Coverage data deleted: ${DELETED_CNT} files")
