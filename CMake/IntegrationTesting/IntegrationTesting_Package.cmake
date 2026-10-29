################################################################################
# Author: Mr.Nobody
# file:  IntegrationTesting_Package.cmake
# brief: Packs the integration tests of a build into a relocatable test package
#        (README "Test package", a part of the IT agent interface) - the input of
#        run-it of an IT agent and of the jobs of the integration test pipeline
#        (the runner ItRun.cmake of EmBi_Tester).
#
#   cmake -DIT_BUILD_DIR=<build dir of the IntegrationTest build>
#         -DIT_PACKAGE_DIR=<package dir> -DIT_BOARD=<board name>
#         [-DIT_LABEL=<ctest label regex - only the tests of these labels, eg. one test set>]
#         [-DIT_PROBE_RS_VERSION=<x.y.z>] [-DIT_NM=<nm>]
#         [-DIT_SOURCE_MODULE=<name>] [-DIT_SOURCE_COMMIT=<sha>] [-DIT_SOURCE_RUN=<id>]
#         -P IntegrationTesting_Package.cmake
#
# The package is everything the board host needs to run the tests of one board
# - the host builds nothing and has no compiler (the tests are described by the
# model CTest exports):
#
#   <package>/
#     manifest.json            what is where (see below)
#     firmware/IT_<Name>.elf   test firmware (flashed by probe-rs)
#     firmware/IT_<Name>.nm    line "<address> B integrationTesting_Mailbox" and, for a
#                              firmware built with the coverage, the line of the buffer of
#                              the coverage data "<address> B integrationTesting_Coverage" -
#                              the host has no arm-none-eabi-nm (the runner
#                              gives IntegrationTesting_Run.cmake a stand-in)
#     host/                    host scripts of this platform (Run, Probe, Check
#                              and the files they include) in the directory layout
#                              they have in EmBi_Platform - they include each
#                              other relatively, also "../<dir>/<file>"
#     logs/                    created by the runner (output of the firmware)
#
# manifest.json:
#   schema        version of the manifest, the runner refuses unknown ones
#   created       UTC time of the packaging
#   board         name of the board (IT_BOARD_<name> selects the pins in the
#                 firmware - the package is valid for this board only)
#   source        module / commit / pipeline run the firmware was built from,
#                 commit of EmBi_Platform
#   probeRs       version of probe-rs the runner downloads (default: version of
#                 the probe-rs the build used)
#   hostConfig    values of IntegrationTesting_Host.cmake of the build (chip, ID
#                 and flash size registers) without the values of the machine of
#                 the build (IT_PROBE_RS, IT_PROBE, IT_HOST, IT_HOST_TOOLS, the
#                 coverage tools) - the runner writes the file again with probe-rs
#                 and probes of the host
#   tests         every CTest test: name, kind (run | check), host script,
#                 parameters (paths relative to the package) and properties
#   coverage      only with INTEGRATION_TEST_COVERAGE: where the firmware was built
#                 (originalBuildDir - the stream of the coverage data names the .gcda files
#                 by it) and the dumps (the runner stores the coverage data of the
#                 firmware in coverage/dumps/IT_<Name>.cov.ihex)
#   files         every file of the package with its SHA-256
#
# With the coverage (INTEGRATION_TEST_COVERAGE, EmBi_Platform/CMake/Coverage) the package
# also contains what the coverage stage needs to evaluate the dumps on another machine:
#   coverage/build/   the notes of the compiler (*.gcno) in the layout of the build folder
#   coverage/src/     the sources of the instrumented objects in the layout of the sources
#                     of the project (the names in the notes are relative to it)
#   coverage/tools/   the coverage scripts of EmBi_Platform of the commit the firmware was
#                     built from (Coverage_Report.cmake, IntegrationTesting_Coverage.cmake
#                     of the host scripts converts the dumps)
#
# The test model is read by "ctest --show-only=json-v1", the commands of the
# tests are only "cmake -D<name>=<value> ... -P <host script>". Anything else
# stops the packaging - the packager shall not silently produce a package the
# runner can not run.
################################################################################

cmake_minimum_required(VERSION 3.25)

#=============================== Constant values ==============================#

set(ITPKG_SCHEMA 1)

# Parameters of the test commands (IntegrationTesting.cmake)
set(ITPKG_RUN_PARAMETERS    IT_ELF IT_LOG IT_NM IT_CONFIG IT_TIMEOUT IT_CASE_TIMEOUT)
set(ITPKG_CHECK_PARAMETERS  IT_LOG IT_CASE)

# Parameter of the run test that exists only with the coverage (the file of the coverage data)
set(ITPKG_RUN_OPTIONAL_PARAMETERS IT_COVERAGE_DUMP)

# Values of the host configuration that belong to the host, not to the build:
# probe-rs of the board host and its probes (the build used the ones of the
# build machine), the IT agent the build was used for - the runner supplies them
set(ITPKG_HOST_CONFIG_VARIABLES IT_PROBE_RS IT_PROBE IT_HOST IT_HOST_TOOLS IT_HOST_PROBE_RS)

# Values of the host configuration for the conversion of the coverage data on the build machine
# (the board hosts only store the data, the coverage stage converts them)
list(APPEND ITPKG_HOST_CONFIG_VARIABLES IT_COVERAGE_MERGE IT_OBJCOPY IT_GCOV_TOOL IT_BUILD_DIR)

# Properties not carried over - location of the build tree, derived by CTest
set(ITPKG_DROPPED_PROPERTIES WORKING_DIRECTORY DEPENDS)

# Symbol of the result mailbox (IntegrationTesting_Run.cmake reads the address)
set(ITPKG_MAILBOX_SYMBOL    "integrationTesting_Mailbox")

# Symbol of the buffer of the coverage data (firmware built with INTEGRATION_TEST_COVERAGE)
set(ITPKG_COVERAGE_SYMBOL   "integrationTesting_Coverage")

#================================ Functions ===================================#

# JSON string literal of VALUE
function(itPkg_JsonString OUT_VAR VALUE)

    string(REPLACE "\\" "\\\\" VALUE "${VALUE}")
    string(REPLACE "\"" "\\\"" VALUE "${VALUE}")
    string(REPLACE "\n" "\\n"  VALUE "${VALUE}")
    string(REPLACE "\t" "\\t"  VALUE "${VALUE}")

    set(${OUT_VAR} "\"${VALUE}\"" PARENT_SCOPE)

endfunction(itPkg_JsonString)

# Value of a property of the CTest test as CMake value (list for arrays)
function(itPkg_PropertyValue OUT_VAR TEST_JSON PROPERTY_INDEX)

    string(JSON VALUE_TYPE TYPE "${TEST_JSON}" properties ${PROPERTY_INDEX} value)

    if(VALUE_TYPE STREQUAL "ARRAY")
        string(JSON ITEM_CNT LENGTH "${TEST_JSON}" properties ${PROPERTY_INDEX} value)

        set(VALUE "")
        if(ITEM_CNT GREATER 0)
            math(EXPR ITEM_LAST "${ITEM_CNT} - 1")
            foreach(ITEM_IDX RANGE ${ITEM_LAST})
                string(JSON ITEM GET "${TEST_JSON}" properties ${PROPERTY_INDEX} value ${ITEM_IDX})
                list(APPEND VALUE "${ITEM}")
            endforeach()
        endif()
    else()
        string(JSON VALUE GET "${TEST_JSON}" properties ${PROPERTY_INDEX} value)
    endif()

    set(${OUT_VAR} "${VALUE}" PARENT_SCOPE)

endfunction(itPkg_PropertyValue)

# Name of a file of the package, unique in the package. Two different source
# files of the same name would overwrite each other.
function(itPkg_Register OUT_REL SOURCE_FILE SUBDIRECTORY)

    get_filename_component(FILE_NAME "${SOURCE_FILE}" NAME)
    string(MAKE_C_IDENTIFIER "ITPKG_SOURCE_${SUBDIRECTORY}_${FILE_NAME}" REGISTRY_VARIABLE)

    if(DEFINED ${REGISTRY_VARIABLE}
       AND NOT "${${REGISTRY_VARIABLE}}" STREQUAL "${SOURCE_FILE}")
        message(FATAL_ERROR "${SUBDIRECTORY}/${FILE_NAME} is used by two different files:\n"
                            "  ${${REGISTRY_VARIABLE}}\n  ${SOURCE_FILE}")
    endif()

    set(${REGISTRY_VARIABLE} "${SOURCE_FILE}" CACHE INTERNAL "")
    set(${OUT_REL} "${SUBDIRECTORY}/${FILE_NAME}" PARENT_SCOPE)

endfunction(itPkg_Register)

#============================== Parameters check ==============================#

foreach(PARAMETER IN ITEMS IT_BUILD_DIR IT_PACKAGE_DIR IT_BOARD)
    if(NOT ${PARAMETER})
        message(FATAL_ERROR "Parameter ${PARAMETER} is not set.")
    endif()
endforeach()

get_filename_component(IT_BUILD_DIR   "${IT_BUILD_DIR}"   ABSOLUTE)
get_filename_component(IT_PACKAGE_DIR "${IT_PACKAGE_DIR}" ABSOLUTE)

if(NOT EXISTS "${IT_BUILD_DIR}/CTestTestfile.cmake")
    message(FATAL_ERROR "${IT_BUILD_DIR} is not a build directory (CTestTestfile.cmake not found).")
endif()

# The package directory is recreated - only an empty directory or a previous
# package may be replaced
if(EXISTS "${IT_PACKAGE_DIR}")
    file(GLOB PACKAGE_CONTENT "${IT_PACKAGE_DIR}/*")
    if(PACKAGE_CONTENT
       AND NOT EXISTS "${IT_PACKAGE_DIR}/manifest.json")
        message(FATAL_ERROR "${IT_PACKAGE_DIR} is not empty and is not a package - not replaced.")
    endif()
    file(REMOVE_RECURSE "${IT_PACKAGE_DIR}")
endif()

# "ctest" is installed next to "cmake"
if(NOT CMAKE_CTEST_COMMAND)
    get_filename_component(CMAKE_BIN_DIR "${CMAKE_COMMAND}" DIRECTORY)
    find_program(CMAKE_CTEST_COMMAND ctest HINTS "${CMAKE_BIN_DIR}" NO_DEFAULT_PATH)
endif()

#=========================== 1: Test model of CTest ===========================#

# Only the tests of the labels IT_LABEL (eg. one test set for run-it of an IT agent)
set(CTEST_SELECTION "")
if(IT_LABEL)
    set(CTEST_SELECTION -L "${IT_LABEL}")
endif()

execute_process(
    COMMAND "${CMAKE_CTEST_COMMAND}" --test-dir "${IT_BUILD_DIR}" --show-only=json-v1 ${CTEST_SELECTION}
    RESULT_VARIABLE CTEST_RESULT
    OUTPUT_VARIABLE CTEST_JSON
    ERROR_VARIABLE  CTEST_ERROR
)

if(NOT CTEST_RESULT EQUAL 0)
    message(FATAL_ERROR "ctest --show-only failed (${CTEST_RESULT}): ${CTEST_ERROR}")
endif()

string(JSON TESTS_CNT LENGTH "${CTEST_JSON}" tests)

if(TESTS_CNT EQUAL 0)
    message(FATAL_ERROR "${IT_BUILD_DIR} has no tests (label '${IT_LABEL}').")
endif()

#======================= 2: Tests of the manifest, sources ====================#

set(MANIFEST_TESTS  "[]")
set(SOURCE_ELFS     "")
set(SOURCE_LOGS     "")
set(SOURCE_SCRIPTS  "")
set(SOURCE_NMS      "")
set(SOURCE_CONFIGS  "")
set(RUN_LOGS        "")
set(CHECK_LOGS      "")
set(RUN_COUNT       0)
set(CHECK_COUNT     0)
set(COVERAGE_DUMPS  "")

math(EXPR TESTS_LAST "${TESTS_CNT} - 1")

foreach(TEST_IDX RANGE ${TESTS_LAST})

    string(JSON TEST_JSON GET "${CTEST_JSON}" tests ${TEST_IDX})
    string(JSON TEST_NAME GET "${TEST_JSON}" name)

    # ---- command: cmake -D<name>=<value> ... -P <script> ----
    foreach(PARAMETER IN LISTS ITPKG_RUN_PARAMETERS ITPKG_CHECK_PARAMETERS)
        unset(PARAM_${PARAMETER})
    endforeach()

    set(TEST_PARAMETERS "")
    set(TEST_SCRIPT     "")
    set(NEXT_IS_SCRIPT  OFF)

    # CTest leaves the command out when its executable is not found
    string(JSON COMMAND_CNT ERROR_VARIABLE COMMAND_ERROR LENGTH "${TEST_JSON}" command)

    if(COMMAND_ERROR)
        message(FATAL_ERROR "Test ${TEST_NAME}: CTest has no command for it (executable of the test not found?).")
    endif()

    math(EXPR COMMAND_LAST "${COMMAND_CNT} - 1")

    foreach(COMMAND_IDX RANGE ${COMMAND_LAST})
        string(JSON ELEMENT GET "${TEST_JSON}" command ${COMMAND_IDX})

        if(COMMAND_IDX EQUAL 0)
            get_filename_component(COMMAND_NAME "${ELEMENT}" NAME_WE)
            if(NOT COMMAND_NAME STREQUAL "cmake")
                message(FATAL_ERROR "Test ${TEST_NAME}: the command is '${ELEMENT}', only 'cmake -P' is supported.")
            endif()
        elseif(NEXT_IS_SCRIPT)
            set(TEST_SCRIPT "${ELEMENT}")
            set(NEXT_IS_SCRIPT OFF)
        elseif("${ELEMENT}" STREQUAL "-P")
            set(NEXT_IS_SCRIPT ON)
        elseif("${ELEMENT}" MATCHES "^-D([A-Za-z0-9_]+)=(.*)$")
            set(PARAM_${CMAKE_MATCH_1} "${CMAKE_MATCH_2}")
            list(APPEND TEST_PARAMETERS "${CMAKE_MATCH_1}")
        else()
            message(FATAL_ERROR "Test ${TEST_NAME}: unsupported command argument '${ELEMENT}'.")
        endif()
    endforeach()

    if(NOT TEST_SCRIPT)
        message(FATAL_ERROR "Test ${TEST_NAME}: the command has no script (-P).")
    endif()

    # ---- kind of the test ----
    if(DEFINED PARAM_IT_ELF)
        set(TEST_KIND       "run")
        set(EXPECTED_PARAMETERS ${ITPKG_RUN_PARAMETERS})
    elseif(DEFINED PARAM_IT_CASE)
        set(TEST_KIND       "check")
        set(EXPECTED_PARAMETERS ${ITPKG_CHECK_PARAMETERS})
    else()
        message(FATAL_ERROR "Test ${TEST_NAME}: neither IT_ELF (run) nor IT_CASE (check) is given.")
    endif()

    set(ALLOWED_PARAMETERS ${EXPECTED_PARAMETERS})

    if(TEST_KIND STREQUAL "run")
        list(APPEND ALLOWED_PARAMETERS ${ITPKG_RUN_OPTIONAL_PARAMETERS})
    endif()

    foreach(PARAMETER IN LISTS TEST_PARAMETERS)
        if(NOT PARAMETER IN_LIST ALLOWED_PARAMETERS)
            message(FATAL_ERROR "Test ${TEST_NAME}: unknown parameter ${PARAMETER} of a '${TEST_KIND}' test "
                                "(the format of IntegrationTesting.cmake changed - update "
                                "IntegrationTesting_Package.cmake).")
        endif()
    endforeach()

    foreach(PARAMETER IN LISTS EXPECTED_PARAMETERS)
        if(NOT PARAMETER IN_LIST TEST_PARAMETERS)
            message(FATAL_ERROR "Test ${TEST_NAME}: parameter ${PARAMETER} of a '${TEST_KIND}' test is missing.")
        endif()
    endforeach()

    # ---- files of the test, paths in the package ----
    # The path of the host script in the package is known only when all the host
    # scripts are (step 4): the manifest keeps the source path until then.
    set(SCRIPT_REL "${TEST_SCRIPT}")
    itPkg_Register(LOG_REL    "${PARAM_IT_LOG}" "logs")
    list(APPEND SOURCE_SCRIPTS "${TEST_SCRIPT}")

    set(TEST_OBJECT "{}")
    string(JSON TEST_OBJECT SET "${TEST_OBJECT}" parameters "{}")

    itPkg_JsonString(JSON_VALUE "${TEST_NAME}")
    string(JSON TEST_OBJECT SET "${TEST_OBJECT}" name "${JSON_VALUE}")
    itPkg_JsonString(JSON_VALUE "${TEST_KIND}")
    string(JSON TEST_OBJECT SET "${TEST_OBJECT}" kind "${JSON_VALUE}")
    itPkg_JsonString(JSON_VALUE "${SCRIPT_REL}")
    string(JSON TEST_OBJECT SET "${TEST_OBJECT}" script "${JSON_VALUE}")

    itPkg_JsonString(JSON_VALUE "${LOG_REL}")
    string(JSON TEST_OBJECT SET "${TEST_OBJECT}" parameters IT_LOG "${JSON_VALUE}")

    if(TEST_KIND STREQUAL "run")
        itPkg_Register(ELF_REL "${PARAM_IT_ELF}" "firmware")
        list(APPEND SOURCE_ELFS     "${PARAM_IT_ELF}")
        list(APPEND SOURCE_NMS      "${PARAM_IT_NM}")
        list(APPEND SOURCE_CONFIGS  "${PARAM_IT_CONFIG}")
        list(APPEND RUN_LOGS        "${LOG_REL}")
        math(EXPR RUN_COUNT "${RUN_COUNT} + 1")

        itPkg_JsonString(JSON_VALUE "${ELF_REL}")
        string(JSON TEST_OBJECT SET "${TEST_OBJECT}" parameters IT_ELF "${JSON_VALUE}")
        itPkg_JsonString(JSON_VALUE "${PARAM_IT_TIMEOUT}")
        string(JSON TEST_OBJECT SET "${TEST_OBJECT}" parameters IT_TIMEOUT "${JSON_VALUE}")
        itPkg_JsonString(JSON_VALUE "${PARAM_IT_CASE_TIMEOUT}")
        string(JSON TEST_OBJECT SET "${TEST_OBJECT}" parameters IT_CASE_TIMEOUT "${JSON_VALUE}")

        # File of the coverage data: written by the runner, the package only names it
        if(DEFINED PARAM_IT_COVERAGE_DUMP)
            get_filename_component(DUMP_NAME "${PARAM_IT_COVERAGE_DUMP}" NAME)
            set(DUMP_REL "coverage/dumps/${DUMP_NAME}")
            list(APPEND COVERAGE_DUMPS "${DUMP_REL}")

            itPkg_JsonString(JSON_VALUE "${DUMP_REL}")
            string(JSON TEST_OBJECT SET "${TEST_OBJECT}" parameters IT_COVERAGE_DUMP "${JSON_VALUE}")
        endif()
    else()
        math(EXPR CHECK_COUNT "${CHECK_COUNT} + 1")
        list(APPEND CHECK_LOGS "${LOG_REL}")

        itPkg_JsonString(JSON_VALUE "${PARAM_IT_CASE}")
        string(JSON TEST_OBJECT SET "${TEST_OBJECT}" parameters IT_CASE "${JSON_VALUE}")
    endif()

    # ---- properties (fixtures, labels, timeouts, ...) ----
    string(JSON TEST_OBJECT SET "${TEST_OBJECT}" properties "{}")

    string(JSON PROPERTY_CNT LENGTH "${TEST_JSON}" properties)
    if(PROPERTY_CNT GREATER 0)
        math(EXPR PROPERTY_LAST "${PROPERTY_CNT} - 1")
        foreach(PROPERTY_IDX RANGE ${PROPERTY_LAST})
            string(JSON PROPERTY_NAME GET "${TEST_JSON}" properties ${PROPERTY_IDX} name)
            if(PROPERTY_NAME IN_LIST ITPKG_DROPPED_PROPERTIES)
                continue()
            endif()

            itPkg_PropertyValue(PROPERTY_VALUE "${TEST_JSON}" ${PROPERTY_IDX})
            itPkg_JsonString(JSON_VALUE "${PROPERTY_VALUE}")
            string(JSON TEST_OBJECT SET "${TEST_OBJECT}" properties ${PROPERTY_NAME} "${JSON_VALUE}")
        endforeach()
    endif()

    string(JSON MANIFEST_TESTS SET "${MANIFEST_TESTS}" ${TEST_IDX} "${TEST_OBJECT}")

endforeach()

if(RUN_COUNT EQUAL 0)
    message(FATAL_ERROR "${IT_BUILD_DIR} has no '.Run' test - nothing to run on the board.")
endif()

# Every result of a test function is evaluated from the output of a firmware
# that is run
foreach(CHECK_LOG IN LISTS CHECK_LOGS)
    if(NOT CHECK_LOG IN_LIST RUN_LOGS)
        message(FATAL_ERROR "A test evaluates ${CHECK_LOG} but no firmware writes it.")
    endif()
endforeach()

list(REMOVE_DUPLICATES SOURCE_ELFS)
list(REMOVE_DUPLICATES SOURCE_SCRIPTS)
list(REMOVE_DUPLICATES SOURCE_NMS)
list(REMOVE_DUPLICATES SOURCE_CONFIGS)

list(LENGTH SOURCE_CONFIGS CONFIG_COUNT)
if(NOT CONFIG_COUNT EQUAL 1)
    message(FATAL_ERROR "The tests use ${CONFIG_COUNT} host configurations (${SOURCE_CONFIGS}), one is expected.")
endif()

#=========================== 3: Firmware, mailbox symbol ======================#

if(IT_NM)
    set(NM_EXECUTABLE "${IT_NM}")
else()
    list(GET SOURCE_NMS 0 NM_EXECUTABLE)
endif()

if(NOT EXISTS "${NM_EXECUTABLE}")
    message(FATAL_ERROR "nm not found ('${NM_EXECUTABLE}'). Give -DIT_NM=<arm-none-eabi-nm>.")
endif()

file(MAKE_DIRECTORY "${IT_PACKAGE_DIR}/firmware" "${IT_PACKAGE_DIR}/host")

foreach(SOURCE_ELF IN LISTS SOURCE_ELFS)

    if(NOT EXISTS "${SOURCE_ELF}")
        message(FATAL_ERROR "Firmware ${SOURCE_ELF} does not exist (the build is not complete).")
    endif()

    get_filename_component(ELF_NAME "${SOURCE_ELF}" NAME)
    get_filename_component(ELF_BASE "${SOURCE_ELF}" NAME_WE)

    file(COPY_FILE "${SOURCE_ELF}" "${IT_PACKAGE_DIR}/firmware/${ELF_NAME}")

    execute_process(
        COMMAND "${NM_EXECUTABLE}" "${SOURCE_ELF}"
        RESULT_VARIABLE NM_RESULT
        OUTPUT_VARIABLE NM_OUTPUT
    )

    # Same pattern as IntegrationTesting_Run.cmake
    string(REGEX MATCH "([0-9A-Fa-f]+) [BbDd] ${ITPKG_MAILBOX_SYMBOL}" _ "${NM_OUTPUT}")

    if(NOT NM_RESULT EQUAL 0
       OR NOT CMAKE_MATCH_1)
        message(FATAL_ERROR "Symbol ${ITPKG_MAILBOX_SYMBOL} not found in ${SOURCE_ELF}.")
    endif()

    set(NM_LINES "${CMAKE_MATCH_1} B ${ITPKG_MAILBOX_SYMBOL}\n")

    # The host reads the buffer of the coverage data through the same stand-in of nm; the name is followed by the
    # end of the line (integrationTesting_Coverage_* are functions and variables of the coverage code, not the buffer)
    string(REGEX MATCH "([0-9A-Fa-f]+) [BbDd] ${ITPKG_COVERAGE_SYMBOL}[\r\n]" _ "${NM_OUTPUT}")

    if(CMAKE_MATCH_1)
        string(APPEND NM_LINES "${CMAKE_MATCH_1} B ${ITPKG_COVERAGE_SYMBOL}\n")
    endif()

    file(WRITE "${IT_PACKAGE_DIR}/firmware/${ELF_BASE}.nm" "${NM_LINES}")

endforeach()

#=============================== 4: Host scripts ==============================#

# The scripts include each other relatively (CMAKE_CURRENT_LIST_DIR, also into
# a neighbour directory: "${CMAKE_CURRENT_LIST_DIR}/../ArtifactsHandler/...").
# Every included file is a host file too.
set(SCRIPT_QUEUE ${SOURCE_SCRIPTS})
set(HOST_FILES   "")

while(SCRIPT_QUEUE)

    list(POP_FRONT SCRIPT_QUEUE SCRIPT)

    # "/../" of the includes is resolved
    get_filename_component(SCRIPT "${SCRIPT}" ABSOLUTE)

    if(SCRIPT IN_LIST HOST_FILES)
        continue()
    endif()

    if(NOT EXISTS "${SCRIPT}")
        message(FATAL_ERROR "Host script ${SCRIPT} does not exist.")
    endif()

    list(APPEND HOST_FILES "${SCRIPT}")

    get_filename_component(SCRIPT_DIR "${SCRIPT}" DIRECTORY)
    file(STRINGS "${SCRIPT}" INCLUDE_LINES REGEX "^[ \t]*include\\(\"\\$\\{CMAKE_CURRENT_LIST_DIR\\}/[^\"]+\"\\)")

    foreach(INCLUDE_LINE IN LISTS INCLUDE_LINES)
        string(REGEX MATCH "\\$\\{CMAKE_CURRENT_LIST_DIR\\}/([^\"]+)\"" _ "${INCLUDE_LINE}")
        list(APPEND SCRIPT_QUEUE "${SCRIPT_DIR}/${CMAKE_MATCH_1}")
    endforeach()

endwhile()

# The package keeps the directory layout of the host files (the relative
# includes have to work there): they are placed under host/ relative to the
# deepest directory all of them are in. Files of one directory stay flat.
list(GET HOST_FILES 0 FIRST_HOST_FILE)
get_filename_component(HOST_BASE "${FIRST_HOST_FILE}" DIRECTORY)

foreach(HOST_FILE IN LISTS HOST_FILES)

    string(FIND "${HOST_FILE}" "${HOST_BASE}/" BASE_POSITION)

    while(NOT BASE_POSITION EQUAL 0)
        get_filename_component(PARENT_DIR "${HOST_BASE}" DIRECTORY)

        if(PARENT_DIR STREQUAL HOST_BASE)
            message(FATAL_ERROR "The host scripts have no common directory (${FIRST_HOST_FILE}, ${HOST_FILE}).")
        endif()

        set(HOST_BASE "${PARENT_DIR}")
        string(FIND "${HOST_FILE}" "${HOST_BASE}/" BASE_POSITION)
    endwhile()

endforeach()

foreach(HOST_FILE IN LISTS HOST_FILES)

    file(RELATIVE_PATH HOST_RELATIVE "${HOST_BASE}" "${HOST_FILE}")
    get_filename_component(HOST_TARGET_DIR "${IT_PACKAGE_DIR}/host/${HOST_RELATIVE}" DIRECTORY)

    file(MAKE_DIRECTORY "${HOST_TARGET_DIR}")
    file(COPY_FILE "${HOST_FILE}" "${IT_PACKAGE_DIR}/host/${HOST_RELATIVE}")

endforeach()

# The tests of the manifest name their script by the source path so far
foreach(SOURCE_SCRIPT IN LISTS SOURCE_SCRIPTS)

    get_filename_component(HOST_FILE "${SOURCE_SCRIPT}" ABSOLUTE)
    file(RELATIVE_PATH HOST_RELATIVE "${HOST_BASE}" "${HOST_FILE}")

    itPkg_JsonString(OLD_VALUE "${SOURCE_SCRIPT}")
    itPkg_JsonString(NEW_VALUE "host/${HOST_RELATIVE}")
    string(REPLACE "${OLD_VALUE}" "${NEW_VALUE}" MANIFEST_TESTS "${MANIFEST_TESTS}")

    string(FIND "${MANIFEST_TESTS}" "${OLD_VALUE}" OLD_POSITION)
    if(NOT OLD_POSITION EQUAL -1)
        message(FATAL_ERROR "The path ${SOURCE_SCRIPT} of a host script is still in the manifest.")
    endif()

endforeach()

#============================ 5: Host configuration ===========================#

list(GET SOURCE_CONFIGS 0 SOURCE_CONFIG)

if(NOT EXISTS "${SOURCE_CONFIG}")
    message(FATAL_ERROR "Host configuration ${SOURCE_CONFIG} does not exist.")
endif()

# Lines "set(IT_<NAME> [==[<value>]==])" (IntegrationTesting.cmake)
file(STRINGS "${SOURCE_CONFIG}" CONFIG_LINES)

set(HOST_CONFIG_JSON "{}")
set(PROBE_RS_PATH    "")

foreach(CONFIG_LINE IN LISTS CONFIG_LINES)

    if("${CONFIG_LINE}" MATCHES "^[ \t]*(#.*)?$")
        continue()
    endif()

    if(NOT "${CONFIG_LINE}" MATCHES "^set\\((IT_[A-Z_]+)[ \t]+\\[==\\[(.*)\\]==\\]\\)$")
        message(FATAL_ERROR "${SOURCE_CONFIG}: unknown line '${CONFIG_LINE}' (the format of "
                            "IntegrationTesting.cmake changed - update IntegrationTesting_Package.cmake).")
    endif()

    set(CONFIG_NAME  "${CMAKE_MATCH_1}")
    set(CONFIG_VALUE "${CMAKE_MATCH_2}")

    if(CONFIG_NAME STREQUAL "IT_PROBE_RS")
        set(PROBE_RS_PATH "${CONFIG_VALUE}")
    endif()

    if(CONFIG_NAME IN_LIST ITPKG_HOST_CONFIG_VARIABLES)
        continue()
    endif()

    itPkg_JsonString(JSON_VALUE "${CONFIG_VALUE}")
    string(JSON HOST_CONFIG_JSON SET "${HOST_CONFIG_JSON}" ${CONFIG_NAME} "${JSON_VALUE}")

endforeach()

#============================ 5b: Coverage files ==============================#

set(COVERAGE_JSON "")

if(COVERAGE_DUMPS)

    # Root of the sources of the coverage (INTEGRATION_TEST_COVERAGE_ROOT) from the cache of the build
    file(STRINGS "${IT_BUILD_DIR}/CMakeCache.txt" ROOT_CACHE_LINE REGEX "^INTEGRATION_TEST_COVERAGE_ROOT:")
    string(REGEX REPLACE "^[^=]*=" "" COVERAGE_ROOT "${ROOT_CACHE_LINE}")

    if(NOT COVERAGE_ROOT)
        message(FATAL_ERROR "INTEGRATION_TEST_COVERAGE_ROOT not found in ${IT_BUILD_DIR}/CMakeCache.txt.")
    endif()

    # Notes of the compiler (*.gcno) in the layout of the build folder
    file(GLOB_RECURSE GCNO_FILES "${IT_BUILD_DIR}/*.gcno")

    if(NOT GCNO_FILES)
        message(FATAL_ERROR "The build ${IT_BUILD_DIR} has the coverage but no *.gcno file "
                            "(the libraries under test are not instrumented).")
    endif()

    foreach(GCNO_FILE IN LISTS GCNO_FILES)
        file(RELATIVE_PATH GCNO_REL "${IT_BUILD_DIR}" "${GCNO_FILE}")
        get_filename_component(GCNO_DIR "${IT_PACKAGE_DIR}/coverage/build/${GCNO_REL}" DIRECTORY)
        file(MAKE_DIRECTORY "${GCNO_DIR}")
        file(COPY_FILE "${GCNO_FILE}" "${IT_PACKAGE_DIR}/coverage/build/${GCNO_REL}")
    endforeach()

    list(LENGTH GCNO_FILES GCNO_COUNT)

    # Sources of the instrumented objects: the entries of compile_commands.json compiled with the
    # instrumentation ("command" line, then the "file" line of the same entry)
    if(NOT EXISTS "${IT_BUILD_DIR}/compile_commands.json")
        message(FATAL_ERROR "${IT_BUILD_DIR}/compile_commands.json does not exist (CMAKE_EXPORT_COMPILE_COMMANDS=ON) - "
                            "the instrumented sources cannot be found.")
    endif()

    # Lines as a list (the brackets and semicolons of the commands would break the list)
    file(READ "${IT_BUILD_DIR}/compile_commands.json" COMPILE_JSON)
    string(REPLACE "[" "(" COMPILE_JSON "${COMPILE_JSON}")
    string(REPLACE "]" ")" COMPILE_JSON "${COMPILE_JSON}")
    string(REPLACE ";" "," COMPILE_JSON "${COMPILE_JSON}")
    string(REPLACE "\n" ";" COMPILE_LINES "${COMPILE_JSON}")
    unset(COMPILE_JSON)

    set(COMMAND_INSTRUMENTED OFF)
    set(SOURCE_COUNT 0)
    set(SOURCE_DIRS "")

    foreach(COMPILE_LINE IN LISTS COMPILE_LINES)

        if("${COMPILE_LINE}" MATCHES "^[ \t]*\"command\":")
            if("${COMPILE_LINE}" MATCHES "-fprofile-info-section")
                set(COMMAND_INSTRUMENTED ON)
            else()
                set(COMMAND_INSTRUMENTED OFF)
            endif()
        elseif("${COMPILE_LINE}" MATCHES "^[ \t]*\"file\": \"(.*)\",?$")
            if(COMMAND_INSTRUMENTED)
                set(SOURCE_FILE "${CMAKE_MATCH_1}")
                file(RELATIVE_PATH SOURCE_REL "${COVERAGE_ROOT}" "${SOURCE_FILE}")

                if("${SOURCE_REL}" MATCHES "^\\.\\./")
                    message(FATAL_ERROR "The instrumented source ${SOURCE_FILE} is outside of the coverage root "
                                        "${COVERAGE_ROOT}.")
                endif()

                get_filename_component(SOURCE_DIR "${IT_PACKAGE_DIR}/coverage/src/${SOURCE_REL}" DIRECTORY)
                file(MAKE_DIRECTORY "${SOURCE_DIR}")
                file(COPY_FILE "${SOURCE_FILE}" "${IT_PACKAGE_DIR}/coverage/src/${SOURCE_REL}")

                get_filename_component(SOURCE_FILE_DIR "${SOURCE_FILE}" DIRECTORY)
                list(APPEND SOURCE_DIRS "${SOURCE_FILE_DIR}")

                math(EXPR SOURCE_COUNT "${SOURCE_COUNT} + 1")
            endif()
            set(COMMAND_INSTRUMENTED OFF)
        endif()

    endforeach()

    if(SOURCE_COUNT EQUAL 0)
        message(FATAL_ERROR "No instrumented source in ${IT_BUILD_DIR}/compile_commands.json.")
    endif()

    # Headers of the folders of the sources: inline functions of a header are in the notes of the
    # object which includes it, the report needs the header like the source
    list(REMOVE_DUPLICATES SOURCE_DIRS)

    foreach(SOURCE_DIR IN LISTS SOURCE_DIRS)
        file(GLOB SOURCE_HEADERS "${SOURCE_DIR}/*.h")

        foreach(SOURCE_HEADER IN LISTS SOURCE_HEADERS)
            file(RELATIVE_PATH HEADER_REL "${COVERAGE_ROOT}" "${SOURCE_HEADER}")
            get_filename_component(HEADER_DIR "${IT_PACKAGE_DIR}/coverage/src/${HEADER_REL}" DIRECTORY)
            file(MAKE_DIRECTORY "${HEADER_DIR}")
            file(COPY_FILE "${SOURCE_HEADER}" "${IT_PACKAGE_DIR}/coverage/src/${HEADER_REL}")
        endforeach()
    endforeach()

    # Coverage scripts of the platform commit of the host scripts
    list(GET SOURCE_SCRIPTS 0 FIRST_RUN_SCRIPT)
    get_filename_component(RUN_SCRIPT_DIR "${FIRST_RUN_SCRIPT}" DIRECTORY)
    get_filename_component(COVERAGE_SCRIPTS_DIR "${RUN_SCRIPT_DIR}/../Coverage" ABSOLUTE)

    file(GLOB COVERAGE_SCRIPTS "${COVERAGE_SCRIPTS_DIR}/Coverage*.cmake")
    list(FILTER COVERAGE_SCRIPTS EXCLUDE REGEX "Coverage_SelfTest\\.cmake$")

    if(NOT COVERAGE_SCRIPTS)
        message(FATAL_ERROR "Coverage scripts not found in ${COVERAGE_SCRIPTS_DIR}.")
    endif()

    file(MAKE_DIRECTORY "${IT_PACKAGE_DIR}/coverage/tools")

    foreach(COVERAGE_SCRIPT IN LISTS COVERAGE_SCRIPTS)
        get_filename_component(COVERAGE_SCRIPT_NAME "${COVERAGE_SCRIPT}" NAME)
        file(COPY_FILE "${COVERAGE_SCRIPT}" "${IT_PACKAGE_DIR}/coverage/tools/${COVERAGE_SCRIPT_NAME}")
    endforeach()

    # The package is evaluated by the host script, which converts the dumps
    get_filename_component(CONVERT_SCRIPT "${RUN_SCRIPT_DIR}/IntegrationTesting_Coverage.cmake" ABSOLUTE)
    file(COPY_FILE "${CONVERT_SCRIPT}" "${IT_PACKAGE_DIR}/coverage/tools/IntegrationTesting_Coverage.cmake")

    set(COVERAGE_JSON "{}")
    itPkg_JsonString(JSON_VALUE "${IT_BUILD_DIR}")
    string(JSON COVERAGE_JSON SET "${COVERAGE_JSON}" originalBuildDir "${JSON_VALUE}")

    set(DUMPS_JSON "[]")
    set(DUMP_IDX 0)
    foreach(DUMP_REL IN LISTS COVERAGE_DUMPS)
        itPkg_JsonString(JSON_VALUE "${DUMP_REL}")
        string(JSON DUMPS_JSON SET "${DUMPS_JSON}" ${DUMP_IDX} "${JSON_VALUE}")
        math(EXPR DUMP_IDX "${DUMP_IDX} + 1")
    endforeach()
    string(JSON COVERAGE_JSON SET "${COVERAGE_JSON}" dumps "${DUMPS_JSON}")

    message(STATUS "  coverage: ${GCNO_COUNT} .gcno files, ${SOURCE_COUNT} sources, ${DUMP_IDX} dumps")

endif()

#============================ 6: Version of probe-rs ==========================#

if(NOT IT_PROBE_RS_VERSION)
    if(EXISTS "${PROBE_RS_PATH}")
        execute_process(
            COMMAND "${PROBE_RS_PATH}" --version
            RESULT_VARIABLE PROBE_RS_RESULT
            OUTPUT_VARIABLE PROBE_RS_OUTPUT
        )
        string(REGEX MATCH "[0-9]+\\.[0-9]+\\.[0-9]+" IT_PROBE_RS_VERSION "${PROBE_RS_OUTPUT}")
    endif()
endif()

if(NOT IT_PROBE_RS_VERSION)
    message(FATAL_ERROR "Version of probe-rs is not known (the probe-rs of the build '${PROBE_RS_PATH}' "
                        "was not found). Give -DIT_PROBE_RS_VERSION=<x.y.z>.")
endif()

#================================ 7: Manifest =================================#

# EmBi_Platform commit = repository of the host scripts
list(GET SOURCE_SCRIPTS 0 FIRST_SCRIPT)
get_filename_component(FIRST_SCRIPT_DIR "${FIRST_SCRIPT}" DIRECTORY)

execute_process(
    COMMAND git -C "${FIRST_SCRIPT_DIR}" rev-parse HEAD
    RESULT_VARIABLE GIT_RESULT
    OUTPUT_VARIABLE PLATFORM_COMMIT
    ERROR_QUIET
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

if(NOT GIT_RESULT EQUAL 0)
    set(PLATFORM_COMMIT "unknown")
endif()

string(TIMESTAMP CREATED "%Y-%m-%dT%H:%M:%SZ" UTC)

set(MANIFEST "{}")
string(JSON MANIFEST SET "${MANIFEST}" schema ${ITPKG_SCHEMA})

itPkg_JsonString(JSON_VALUE "${CREATED}")
string(JSON MANIFEST SET "${MANIFEST}" created "${JSON_VALUE}")
itPkg_JsonString(JSON_VALUE "${IT_BOARD}")
string(JSON MANIFEST SET "${MANIFEST}" board "${JSON_VALUE}")

string(JSON MANIFEST SET "${MANIFEST}" source "{}")
itPkg_JsonString(JSON_VALUE "${IT_SOURCE_MODULE}")
string(JSON MANIFEST SET "${MANIFEST}" source module "${JSON_VALUE}")
itPkg_JsonString(JSON_VALUE "${IT_SOURCE_COMMIT}")
string(JSON MANIFEST SET "${MANIFEST}" source commit "${JSON_VALUE}")
itPkg_JsonString(JSON_VALUE "${IT_SOURCE_RUN}")
string(JSON MANIFEST SET "${MANIFEST}" source run "${JSON_VALUE}")
itPkg_JsonString(JSON_VALUE "${PLATFORM_COMMIT}")
string(JSON MANIFEST SET "${MANIFEST}" source platformCommit "${JSON_VALUE}")

string(JSON MANIFEST SET "${MANIFEST}" probeRs "{}")
itPkg_JsonString(JSON_VALUE "${IT_PROBE_RS_VERSION}")
string(JSON MANIFEST SET "${MANIFEST}" probeRs version "${JSON_VALUE}")

string(JSON MANIFEST SET "${MANIFEST}" hostConfig "${HOST_CONFIG_JSON}")
string(JSON MANIFEST SET "${MANIFEST}" tests "${MANIFEST_TESTS}")

if(COVERAGE_JSON)
    string(JSON MANIFEST SET "${MANIFEST}" coverage "${COVERAGE_JSON}")
endif()

# Files of the package (the output logs are written by the runner)
file(GLOB_RECURSE PACKAGE_FILES RELATIVE "${IT_PACKAGE_DIR}" "${IT_PACKAGE_DIR}/*")
list(SORT PACKAGE_FILES)

set(MANIFEST_FILES "[]")
set(FILE_IDX 0)

foreach(PACKAGE_FILE IN LISTS PACKAGE_FILES)
    file(SHA256 "${IT_PACKAGE_DIR}/${PACKAGE_FILE}" FILE_HASH)

    set(FILE_OBJECT "{}")
    itPkg_JsonString(JSON_VALUE "${PACKAGE_FILE}")
    string(JSON FILE_OBJECT SET "${FILE_OBJECT}" path "${JSON_VALUE}")
    itPkg_JsonString(JSON_VALUE "${FILE_HASH}")
    string(JSON FILE_OBJECT SET "${FILE_OBJECT}" sha256 "${JSON_VALUE}")

    string(JSON MANIFEST_FILES SET "${MANIFEST_FILES}" ${FILE_IDX} "${FILE_OBJECT}")
    math(EXPR FILE_IDX "${FILE_IDX} + 1")
endforeach()

string(JSON MANIFEST SET "${MANIFEST}" files "${MANIFEST_FILES}")

file(WRITE "${IT_PACKAGE_DIR}/manifest.json" "${MANIFEST}\n")

message(STATUS "Integration test package: ${IT_PACKAGE_DIR}")
message(STATUS "  board ${IT_BOARD}, probe-rs ${IT_PROBE_RS_VERSION}, EmBi_Platform ${PLATFORM_COMMIT}")
message(STATUS "  ${RUN_COUNT} firmware, ${CHECK_COUNT} test functions, ${FILE_IDX} files")
