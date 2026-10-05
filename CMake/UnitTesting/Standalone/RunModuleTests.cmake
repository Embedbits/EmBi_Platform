################################################################################
# Author: Mr.Nobody
# file:  RunModuleTests.cmake
# brief: Configures, builds and executes unit tests of one module (script mode).
#
# usage:
#   cmake -DMODULE_PATH=<module folder> -P EmBi_Platform/CMake/UnitTesting/Standalone/RunModuleTests.cmake
#
# Optional parameters:
#   BUILD_DIR   - Build folder (default: Build_UnitTest in current folder)
#   TOOLS       - ARTIFACTS (default) / SYSTEM, see CMakeLists.txt
#   GENERATOR   - CMake generator (default: Ninja if available, else CMake default)
#   CMAKE_ARGS  - Additional configuration arguments (list), eg.
#                 "-DUNITY_ROOT=/opt/Unity;-DCMOCK_ROOT=/opt/CMock"
#
# Results: <BUILD_DIR>/UnitTestResults.xml (JUnit), script fails if any test
# fails or no test exists.
################################################################################

cmake_minimum_required(VERSION 3.25)

if(NOT MODULE_PATH)
    message(FATAL_ERROR "MODULE_PATH is not set. Usage: cmake -DMODULE_PATH=<module folder> -P RunModuleTests.cmake")
endif()

# Relative paths are taken from the current folder
get_filename_component(MODULE_PATH "${MODULE_PATH}" ABSOLUTE)

if(NOT BUILD_DIR)
    set(BUILD_DIR "Build_UnitTest")
endif()

get_filename_component(BUILD_DIR "${BUILD_DIR}" ABSOLUTE)

if(NOT TOOLS)
    set(TOOLS "ARTIFACTS")
endif()

set(GENERATOR_ARGS "")

if(GENERATOR)
    set(GENERATOR_ARGS -G "${GENERATOR}")
elseif(TOOLS STREQUAL "SYSTEM")
    find_program(NINJA_EXECUTABLE ninja)

    if(NINJA_EXECUTABLE)
        set(GENERATOR_ARGS -G Ninja)
    endif()
else()
    # Ninja is provided by artifacts
    set(GENERATOR_ARGS -G Ninja)
endif()

#------------------------------------------------------------------------------#
# Runs one step, fails the script on error.
#------------------------------------------------------------------------------#
function(runModuleTests_Step STEP_NAME)

    message(STATUS "==== ${STEP_NAME}")

    execute_process(COMMAND ${ARGN} RESULT_VARIABLE STEP_RESULT)

    if(NOT STEP_RESULT EQUAL 0)
        message(FATAL_ERROR "${STEP_NAME} failed (${STEP_RESULT}).")
    endif()

endfunction()


runModuleTests_Step("Configuration"
    "${CMAKE_COMMAND}" -S "${CMAKE_CURRENT_LIST_DIR}" -B "${BUILD_DIR}" ${GENERATOR_ARGS}
    "-DUNIT_TEST_MODULE_PATH=${MODULE_PATH}"
    "-DUNIT_TEST_TOOLS=${TOOLS}"
    ${CMAKE_ARGS}
)

runModuleTests_Step("Build"
    "${CMAKE_COMMAND}" --build "${BUILD_DIR}"
)

runModuleTests_Step("Unit tests"
    "${CMAKE_CTEST_COMMAND}" --test-dir "${BUILD_DIR}" --output-on-failure --no-tests=error
    --output-junit "${BUILD_DIR}/UnitTestResults.xml"
)

message(STATUS "Unit tests passed, results: ${BUILD_DIR}/UnitTestResults.xml")
