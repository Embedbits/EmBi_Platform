################################################################################
# Author: Mr.Nobody
# file:  UnitTesting.cmake
# brief: Host based unit testing - Unity, CMock, optional target emulation.
#
# Included by Build.cmake when CMAKE_BUILD_TYPE is "UnitTest". The code under
# test is compiled by host compiler (gcc / MinGW) unchanged.
#
# The framework is independent of MCU, BSP, MCAL and CPU architecture - it only
# builds the tests, runs them and evaluates the results (CTest, coverage).
# Every test set is independent and lists everything it needs. Optional host
# emulation of the target is selected by the test set:
#   ut_RegMem     - peripheral registers in host memory at Cortex-M addresses
#                   (RegMem/RegMem.h)
#   ut_CmsisHost  - CMSIS core intrinsics on host; its header
#                   UNIT_TESTING_CMSIS_HOST_HEADER replaces cmsis_gcc.h (ARM
#                   assembler) when listed in FORCE_INCLUDES
# Test sets are created from the template by Setup scripts (HelperTools/Test_Handler).
#
# Required tools (provided by artifacts "unity", "cmock", "ruby", "gcc" or by
# system installation):
#   UNITY_ROOT      - Unity root folder (src/unity.c, auto/generate_test_runner.rb)
#   CMOCK_ROOT      - CMock root folder (src/cmock.c, lib/cmock.rb)
#   RUBY_EXECUTABLE - Ruby interpreter, searched in PATH if not specified
# Each value can be passed as CMake parameter or as environment variable.
#
# Optional parameters:
#   UNIT_TEST_CONFIG_FILE - CMock / runner configuration (default UnitTesting.yml)
#   UNIT_TEST_COVERAGE    - OFF (default) / ON: gcov instrumentation of code
#                           under test and "UnitTest_Coverage" report target
#
# Registration in module CMakeLists.txt (same principle as Doxygen_AddPath):
#   if(UNIT_TESTING_AVAILABLE STREQUAL "ON")
#       UnitTesting_AddPath("${CMAKE_CURRENT_SOURCE_DIR}/Tests/UnitTests")
#   endif()
#
# Test definition (<Module>/Tests/UnitTests/CMakeLists.txt):
#   UnitTesting_Add_Test(
#       NAME          Gpio                                # Test name (CTest prefix)
#       TEST_SOURCE   Test_Gpio.c                         # Unity test file
#       UUT_SOURCES   ${GPIO_DIR}/Gpio.c                  # Code under test
#       MOCK_HEADERS  ${MCAL_DIR}/Rcc/Rcc_Port.h          # Headers mocked by CMock
#       SOURCES       ...                                 # Other test sources
#       INCLUDE_DIRS  ${GPIO_DIR} ${MCAL_DIR}/Rcc         # Include paths
#       DEFINITIONS   ...                                 # Compile definitions
#       LINK_LIBS     ut_RegMem ut_CmsisHost              # Linked libraries (target emulation, ...)
#       FORCE_INCLUDES ${UNIT_TESTING_CMSIS_HOST_HEADER}  # Headers included before every source
#                                                         # (test, code under test, HOST_LIBS)
#       HOST_LIBS     Ral_Lib                             # Target libraries compiled for host
#       COVERAGE_EXCLUDE ".*/Ral/.*"                      # Code excluded from coverage report
#       RUN_SERIAL                                        # Test uses HW model thread
#   )
#   Every "void Ut_...( void )" function in TEST_SOURCE is registered as
#   separate CTest test "<NAME>.<function>".
################################################################################

include_guard(GLOBAL)

#=============================== Constant values ==============================#

set(UNIT_TESTING_DIR                    "${CMAKE_CURRENT_LIST_DIR}")

set(UNIT_TEST_CONFIG_FILE               "${UNIT_TESTING_DIR}/UnitTesting.yml"
    CACHE FILEPATH                      "CMock and Unity runner configuration file")

option(UNIT_TEST_COVERAGE               "Instrument code under test by gcov" OFF)

option(UNIT_TEST_RUN_KNOWN_DEFECTS      "Execute tests of known defects (UT_KNOWN_DEFECT) instead of ignoring them" OFF)

# Compiler options of all target code built for host (tests, HOST_LIBS). 32-bit
# target code casts register addresses to uint32_t. It is safe on 64-bit host
# when the registers are mapped below 4 GB (eg. ut_RegMem), so the warnings are
# disabled.
set(UNIT_TEST_HOST_COMPILE_OPTIONS      -O0 -g3 -Wno-int-to-pointer-cast $<$<COMPILE_LANGUAGE:C>:-Wno-pointer-to-int-cast>)

# Header of CMSIS core emulation (ut_CmsisHost) - listed in FORCE_INCLUDES of
# the test set, replaces cmsis_gcc.h (ARM inline assembler) by host intrinsics
set(UNIT_TESTING_CMSIS_HOST_HEADER      "${UNIT_TESTING_DIR}/CmsisHost/CmsisHost.h")

# Additional compiler options of code under test
set(UNIT_TEST_UUT_COMPILE_OPTIONS       -Wall -Wextra)

#============================= Tools localization =============================#

foreach(TOOL_ROOT IN ITEMS UNITY_ROOT CMOCK_ROOT)

    if(NOT ${TOOL_ROOT} AND DEFINED ENV{${TOOL_ROOT}})
        set(${TOOL_ROOT} "$ENV{${TOOL_ROOT}}")
    endif()

    if(NOT ${TOOL_ROOT} OR NOT IS_DIRECTORY "${${TOOL_ROOT}}")
        message(FATAL_ERROR "${TOOL_ROOT} is not set or does not exist ('${${TOOL_ROOT}}'). "
                            "Add the artifact to ArtifactsConfig.txt or pass -D${TOOL_ROOT}=<path>.")
    endif()

    set(${TOOL_ROOT} "${${TOOL_ROOT}}" CACHE PATH "Unit testing tool root folder" FORCE)

endforeach()

if(NOT RUBY_EXECUTABLE AND DEFINED ENV{RUBY_EXECUTABLE})
    set(RUBY_EXECUTABLE "$ENV{RUBY_EXECUTABLE}" CACHE FILEPATH "Ruby interpreter" FORCE)
endif()

find_program(RUBY_EXECUTABLE ruby)

if(NOT RUBY_EXECUTABLE)
    message(FATAL_ERROR "Ruby not found. It is required by CMock and Unity runner generator. "
                        "Add artifact 'ruby' to ArtifactsConfig.txt or pass -DRUBY_EXECUTABLE=<path>.")
endif()

message(STATUS "Unity: ${UNITY_ROOT}")
message(STATUS "CMock: ${CMOCK_ROOT}")
message(STATUS "Ruby:  ${RUBY_EXECUTABLE}")

#=========================== Testing libraries ================================#

enable_testing()

# Modules register their unit tests only if this flag is ON (see UnitTesting_AddPath)
set(UNIT_TESTING_AVAILABLE              "ON")

# Unity framework
add_library(unity STATIC ${UNITY_ROOT}/src/unity.c)

target_include_directories(unity
    PUBLIC
        ${UNITY_ROOT}/src
)

target_compile_definitions(unity
    PUBLIC
        UNITY_USE_COMMAND_LINE_ARGS     # Test selection by generated runner ("-n")
        UNITY_INCLUDE_DOUBLE
)


# CMock framework
add_library(cmock STATIC ${CMOCK_ROOT}/src/cmock.c)

target_include_directories(cmock
    PUBLIC
        ${CMOCK_ROOT}/src
)

target_link_libraries(cmock
    PUBLIC
        unity
)


# Common helpers of unit tests (UT_KNOWN_DEFECT) - target independent
add_library(ut_Common INTERFACE)

target_include_directories(ut_Common
    INTERFACE
        ${UNIT_TESTING_DIR}/UtCommon
)


# Optional host emulation of the target, selected by the test set (LINK_LIBS).
# OBJECT libraries - RegMem maps the registers by constructor before main().

# Peripheral registers in host memory at Cortex-M addresses
add_library(ut_RegMem OBJECT ${UNIT_TESTING_DIR}/RegMem/RegMem.c)

target_include_directories(ut_RegMem
    PUBLIC
        ${UNIT_TESTING_DIR}/RegMem
)

# HW model thread of RegMem
set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads REQUIRED)

target_link_libraries(ut_RegMem
    PUBLIC
        Threads::Threads
)

# CMSIS core intrinsics on host (header forced by FORCE_INCLUDES of the test set)
add_library(ut_CmsisHost OBJECT ${UNIT_TESTING_DIR}/CmsisHost/CmsisHost.c)

target_include_directories(ut_CmsisHost
    PUBLIC
        ${UNIT_TESTING_DIR}/CmsisHost
)

#================================ Functions ===================================#

#------------------------------------------------------------------------------#
# Registers folder with unit tests of the module (same principle as
# Doxygen_AddPath). Called from module CMakeLists.txt:
#
#   if(UNIT_TESTING_AVAILABLE STREQUAL "ON")
#       UnitTesting_AddPath("${CMAKE_CURRENT_SOURCE_DIR}/Tests/UnitTests")
#   endif()
#
# Folders are only collected here, tests are created by UnitTesting_Generate()
# after all modules are processed (all module targets are known).
#
# UNIT_TEST_PATH_ARG [in]: Folder containing CMakeLists.txt of unit tests.
#------------------------------------------------------------------------------#
function(UnitTesting_AddPath UNIT_TEST_PATH_ARG)

    get_filename_component(UNIT_TEST_PATH "${UNIT_TEST_PATH_ARG}" ABSOLUTE)

    if(EXISTS "${UNIT_TEST_PATH}/CMakeLists.txt")
        set_property(GLOBAL APPEND PROPERTY UNIT_TESTING_PATHS "${UNIT_TEST_PATH}")
    else()
        message(WARNING "Unit tests registered, but ${UNIT_TEST_PATH}/CMakeLists.txt does not exist.")
    endif()

endfunction(UnitTesting_AddPath)


#------------------------------------------------------------------------------#
# Creates all registered unit tests (same principle as Doxygen_Generate).
# Called by Build.cmake after Bsp, Middlewares and Application are processed.
#
# Module libraries created during processing are excluded from "all" target -
# only test executables (and libraries they link) are built.
#------------------------------------------------------------------------------#
function(UnitTesting_Generate)

    # Module libraries are not built for host unless a test links them
    unitTesting_ExcludeFromAll("${CMAKE_SOURCE_DIR}")

    get_property(UNIT_TESTING_PATHS GLOBAL PROPERTY UNIT_TESTING_PATHS)

    list(REMOVE_DUPLICATES UNIT_TESTING_PATHS)

    foreach(UNIT_TEST_PATH IN LISTS UNIT_TESTING_PATHS)

        file(RELATIVE_PATH UNIT_TEST_PATH_REL "${CMAKE_SOURCE_DIR}" "${UNIT_TEST_PATH}")

        # Module outside of source tree (standalone module testing, see
        # Standalone/CMakeLists.txt) - build folder has to stay in build tree
        if(IS_ABSOLUTE "${UNIT_TEST_PATH_REL}" OR UNIT_TEST_PATH_REL MATCHES "^\\.\\./")
            string(REGEX REPLACE "^(\\.\\./)+" "" UNIT_TEST_PATH_REL "${UNIT_TEST_PATH_REL}")
            string(REGEX REPLACE "^[A-Za-z]:/" "" UNIT_TEST_PATH_REL "${UNIT_TEST_PATH_REL}")
            string(REGEX REPLACE "^/" "" UNIT_TEST_PATH_REL "${UNIT_TEST_PATH_REL}")
            set(UNIT_TEST_PATH_REL "External/${UNIT_TEST_PATH_REL}")
        endif()

        message(STATUS "Unit tests registered: ${UNIT_TEST_PATH_REL}")

        add_subdirectory("${UNIT_TEST_PATH}" "${CMAKE_BINARY_DIR}/UnitTests/${UNIT_TEST_PATH_REL}")

    endforeach()

    list(LENGTH UNIT_TESTING_PATHS UNIT_TESTING_PATHS_CNT)

    if(UNIT_TESTING_PATHS_CNT EQUAL 0)
        message(WARNING "No unit tests registered (UnitTesting_AddPath not called by any module).")
    endif()

    # Coverage report of all tests (excludes registered by the test sets)
    unitTesting_CoverageTarget()

endfunction(UnitTesting_Generate)


#------------------------------------------------------------------------------#
# Excludes all targets of the folder and its subfolders from "all" target.
#
# DIRECTORY_ARG [in]: Processed source folder (CMake directory scope).
#------------------------------------------------------------------------------#
function(unitTesting_ExcludeFromAll DIRECTORY_ARG)

    get_property(DIR_TARGETS DIRECTORY "${DIRECTORY_ARG}" PROPERTY BUILDSYSTEM_TARGETS)
    get_property(SUB_DIRS    DIRECTORY "${DIRECTORY_ARG}" PROPERTY SUBDIRECTORIES)

    foreach(DIR_TARGET IN LISTS DIR_TARGETS)

        get_target_property(TARGET_TYPE ${DIR_TARGET} TYPE)

        if(NOT TARGET_TYPE STREQUAL "INTERFACE_LIBRARY")
            set_target_properties(${DIR_TARGET} PROPERTIES EXCLUDE_FROM_ALL TRUE)
        endif()

    endforeach()

    foreach(SUB_DIR IN LISTS SUB_DIRS)
        unitTesting_ExcludeFromAll("${SUB_DIR}")
    endforeach()

endfunction(unitTesting_ExcludeFromAll)


#------------------------------------------------------------------------------#
# Creates unit test executable and registers its test cases in CTest.
#
# Generates CMock mocks of MOCK_HEADERS and Unity runner of TEST_SOURCE, builds
# executable "UT_<NAME>" and registers every test function as CTest test
# "<NAME>.<function>" (labels "unit" and "<NAME>").
#
# See file header for the list of arguments.
#------------------------------------------------------------------------------#
function(UnitTesting_Add_Test)

    cmake_parse_arguments(UT
        "RUN_SERIAL"
        "NAME;TEST_SOURCE"
        "UUT_SOURCES;MOCK_HEADERS;SOURCES;INCLUDE_DIRS;DEFINITIONS;LINK_LIBS;FORCE_INCLUDES;HOST_LIBS;COVERAGE_EXCLUDE"
        ${ARGN})

    if(NOT UT_NAME OR NOT UT_TEST_SOURCE)
        message(FATAL_ERROR "UnitTesting_Add_Test: NAME and TEST_SOURCE are required.")
    endif()

    get_filename_component(UT_TEST_SOURCE "${UT_TEST_SOURCE}" ABSOLUTE)

    set(TEST_TARGET     "UT_${UT_NAME}")
    set(GENERATED_DIR   "${CMAKE_CURRENT_BINARY_DIR}/${TEST_TARGET}_Gen")
    set(MOCKS_DIR       "${GENERATED_DIR}/Mocks")

    file(MAKE_DIRECTORY "${MOCKS_DIR}")

    # Mocks generation
    set(MOCK_SOURCES "")

    foreach(MOCK_HEADER IN LISTS UT_MOCK_HEADERS)

        get_filename_component(MOCK_HEADER "${MOCK_HEADER}" ABSOLUTE)
        get_filename_component(MOCK_HEADER_NAME "${MOCK_HEADER}" NAME_WE)

        set(MOCK_SOURCE "${MOCKS_DIR}/Mock${MOCK_HEADER_NAME}.c")

        # UNITY_DIR - CMock takes Unity helper scripts (auto/type_sanitizer.rb)
        # from the Unity artifact, its own vendor/unity submodule is not
        # part of the cmock artifact package.
        add_custom_command(
            OUTPUT  "${MOCK_SOURCE}" "${MOCKS_DIR}/Mock${MOCK_HEADER_NAME}.h"
            COMMAND "${CMAKE_COMMAND}" -E env "UNITY_DIR=${UNITY_ROOT}"
                    "${RUBY_EXECUTABLE}" "${CMOCK_ROOT}/lib/cmock.rb"
                    "-o${UNIT_TEST_CONFIG_FILE}"
                    "--mock_path=${MOCKS_DIR}"
                    "${MOCK_HEADER}"
            DEPENDS "${MOCK_HEADER}" "${UNIT_TEST_CONFIG_FILE}"
            COMMENT "Generating mock Mock${MOCK_HEADER_NAME} (${UT_NAME})"
            VERBATIM
        )

        list(APPEND MOCK_SOURCES "${MOCK_SOURCE}")

    endforeach()

    # Test runner generation
    get_filename_component(TEST_SOURCE_NAME "${UT_TEST_SOURCE}" NAME_WE)

    set(RUNNER_SOURCE "${GENERATED_DIR}/${TEST_SOURCE_NAME}_Runner.c")

    add_custom_command(
        OUTPUT  "${RUNNER_SOURCE}"
        COMMAND "${RUBY_EXECUTABLE}" "${UNITY_ROOT}/auto/generate_test_runner.rb"
                "${UNIT_TEST_CONFIG_FILE}"
                "${UT_TEST_SOURCE}"
                "${RUNNER_SOURCE}"
        DEPENDS "${UT_TEST_SOURCE}" "${UNIT_TEST_CONFIG_FILE}"
        COMMENT "Generating test runner ${TEST_SOURCE_NAME}_Runner.c (${UT_NAME})"
        VERBATIM
    )

    # Runner includes headers of the test file, thus test written in C++
    # (eg. C++ modules) needs runner compiled as C++ too
    get_filename_component(TEST_SOURCE_EXT "${UT_TEST_SOURCE}" LAST_EXT)

    if(TEST_SOURCE_EXT MATCHES "^\\.(cpp|cc|cxx)$")
        set_source_files_properties("${RUNNER_SOURCE}" PROPERTIES LANGUAGE CXX)
    endif()

    # Test executable
    add_executable(${TEST_TARGET}
        ${UT_TEST_SOURCE}
        ${RUNNER_SOURCE}
        ${UT_UUT_SOURCES}
        ${UT_SOURCES}
        ${MOCK_SOURCES}
    )

    target_include_directories(${TEST_TARGET}
        PRIVATE
            ${MOCKS_DIR}
            ${CMAKE_CURRENT_SOURCE_DIR}
            ${UT_INCLUDE_DIRS}
    )

    target_compile_definitions(${TEST_TARGET}
        PRIVATE
            UNIT_TEST
            $<$<BOOL:${UNIT_TEST_RUN_KNOWN_DEFECTS}>:UT_RUN_KNOWN_DEFECTS>
            ${UT_DEFINITIONS}
    )

    # Headers included before every source of the test set (eg. CMSIS emulation)
    set(FORCE_INCLUDE_OPTIONS "")

    foreach(FORCE_INCLUDE IN LISTS UT_FORCE_INCLUDES)
        get_filename_component(FORCE_INCLUDE "${FORCE_INCLUDE}" ABSOLUTE)
        list(APPEND FORCE_INCLUDE_OPTIONS "SHELL:-include \"${FORCE_INCLUDE}\"")
    endforeach()

    target_compile_options(${TEST_TARGET}
        PRIVATE
            ${UNIT_TEST_HOST_COMPILE_OPTIONS}
            ${FORCE_INCLUDE_OPTIONS}
    )

    # Target libraries compiled for host - configured once by the first test
    # set, other test sets have to use the same FORCE_INCLUDES
    foreach(HOST_LIB IN LISTS UT_HOST_LIBS)

        if(NOT TARGET ${HOST_LIB})
            message(FATAL_ERROR "UnitTesting_Add_Test (${UT_NAME}): HOST_LIBS target ${HOST_LIB} does not exist.")
        endif()

        get_target_property(HOST_LIB_CONFIG ${HOST_LIB} UNIT_TEST_HOST_CONFIG)

        if(NOT HOST_LIB_CONFIG)
            target_compile_options(${HOST_LIB} PRIVATE ${UNIT_TEST_HOST_COMPILE_OPTIONS} ${FORCE_INCLUDE_OPTIONS})
            set_target_properties(${HOST_LIB} PROPERTIES UNIT_TEST_HOST_CONFIG "FORCE_INCLUDES:${UT_FORCE_INCLUDES}")
        elseif(NOT HOST_LIB_CONFIG STREQUAL "FORCE_INCLUDES:${UT_FORCE_INCLUDES}")
            message(WARNING "UnitTesting_Add_Test (${UT_NAME}): HOST_LIBS ${HOST_LIB} is already configured "
                            "with other FORCE_INCLUDES (${HOST_LIB_CONFIG}).")
        endif()

    endforeach()

    # Coverage excludes of the test set (one report of all tests)
    set_property(GLOBAL APPEND PROPERTY UNIT_TESTING_COVERAGE_EXCLUDES ${UT_COVERAGE_EXCLUDE})

    target_link_libraries(${TEST_TARGET}
        PRIVATE
            cmock
            unity
            ut_Common
            ${UT_HOST_LIBS}
            ${UT_LINK_LIBS}
    )

    # Self-contained executable - MinGW runtime DLLs (libwinpthread-1.dll, ...)
    # are on PATH only while CMake configures (gcc artifact), not when CTest
    # runs the test.
    if(MINGW)
        target_link_options(${TEST_TARGET} PRIVATE -static)
    endif()

    # Code under test is compiled with warnings (and optionally with coverage)
    set(UUT_OPTIONS ${UNIT_TEST_UUT_COMPILE_OPTIONS})

    if(UNIT_TEST_COVERAGE)
        list(APPEND UUT_OPTIONS --coverage)
        target_link_options(${TEST_TARGET} PRIVATE --coverage)
    endif()

    set_source_files_properties(${UT_UUT_SOURCES}
        TARGET_DIRECTORY ${TEST_TARGET}
        PROPERTIES COMPILE_OPTIONS "${UUT_OPTIONS}"
    )

    # Registration of every test function as separate CTest test
    file(STRINGS "${UT_TEST_SOURCE}" TEST_FUNCTIONS
         REGEX "^[ \t]*void[ \t]+Ut_[A-Za-z0-9_]*[ \t]*\\([ \t]*(void)?[ \t]*\\)")

    set(TEST_CASES_CNT 0)

    foreach(TEST_FUNCTION IN LISTS TEST_FUNCTIONS)

        string(REGEX MATCH "Ut_[A-Za-z0-9_]*" TEST_CASE "${TEST_FUNCTION}")

        add_test(NAME "${UT_NAME}.${TEST_CASE}"
                 COMMAND ${TEST_TARGET} -n ${TEST_CASE})

        # Exactly one test has to be executed. Protects against a test which is
        # silently not executed (eg. renamed function without new configuration).
        set_tests_properties("${UT_NAME}.${TEST_CASE}" PROPERTIES
            PASS_REGULAR_EXPRESSION "\n1 Tests 0 Failures"
            SKIP_REGULAR_EXPRESSION ":IGNORE"
            LABELS                  "unit;${UT_NAME}"
        )

        # Tests using HW model thread (RegMem_Set_ModelActive) need free CPU
        if(UT_RUN_SERIAL)
            set_tests_properties("${UT_NAME}.${TEST_CASE}" PROPERTIES RUN_SERIAL TRUE)
        endif()

        math(EXPR TEST_CASES_CNT "${TEST_CASES_CNT} + 1")

    endforeach()

    if(TEST_CASES_CNT EQUAL 0)
        message(WARNING "UnitTesting_Add_Test: no test function found in ${UT_TEST_SOURCE}")
    endif()

    message(STATUS "Unit test ${TEST_TARGET} created (${TEST_CASES_CNT} test cases)")

endfunction(UnitTesting_Add_Test)

#============================= Coverage report ================================#

#------------------------------------------------------------------------------#
# Creates coverage report target "UnitTest_Coverage" (UNIT_TEST_COVERAGE=ON).
# Called by UnitTesting_Generate() after all tests are created - excludes
# registered by the test sets (COVERAGE_EXCLUDE) are known.
#------------------------------------------------------------------------------#
function(unitTesting_CoverageTarget)

    if(NOT UNIT_TEST_COVERAGE)
        return()
    endif()

    find_program(GCOVR_EXECUTABLE gcovr)

    if(NOT GCOVR_EXECUTABLE)
        message(WARNING "UNIT_TEST_COVERAGE is ON but gcovr was not found. Coverage report target is not available.")
        return()
    endif()

    set(COVERAGE_DIR "${CMAKE_BINARY_DIR}/Coverage")

    # Test sources and generated mocks are never reported, other excludes are
    # registered by the test sets
    get_property(COVERAGE_EXCLUDES GLOBAL PROPERTY UNIT_TESTING_COVERAGE_EXCLUDES)

    set(COVERAGE_EXCLUDES ".*/Tests/.*" ".*/Mocks/.*" ${COVERAGE_EXCLUDES})
    list(REMOVE_DUPLICATES COVERAGE_EXCLUDES)

    set(COVERAGE_EXCLUDE_ARGS "")

    foreach(COVERAGE_EXCLUDE IN LISTS COVERAGE_EXCLUDES)
        list(APPEND COVERAGE_EXCLUDE_ARGS --exclude "${COVERAGE_EXCLUDE}")
    endforeach()

    # Cobertura XML is consumed by Azure Pipelines (PublishCodeCoverageResults)
    add_custom_target(UnitTest_Coverage
        COMMAND ${CMAKE_COMMAND} -E make_directory "${COVERAGE_DIR}"
        COMMAND "${GCOVR_EXECUTABLE}"
                --root "${CMAKE_SOURCE_DIR}"
                --object-directory "${CMAKE_BINARY_DIR}"
                ${COVERAGE_EXCLUDE_ARGS}
                --html-details "${COVERAGE_DIR}/index.html"
                --cobertura "${COVERAGE_DIR}/Cobertura.xml"
                --print-summary
        WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
        COMMENT "Generating unit test coverage report"
        VERBATIM
    )

endfunction(unitTesting_CoverageTarget)
