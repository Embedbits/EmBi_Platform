################################################################################
#
# Tests initialization.
#
# Copies the testing template (unit and / or integration tests) into the module.
# Called by ModuleInit (new module) or directly by Setup scripts for existing
# module. Existing files are never overwritten.
#
# Structure of tests of the module:
#
# Module                            (Variable TEST_INIT_MODULE_NAME)
# ├── CMakeLists.txt                (+ UnitTesting_AddPath / IntegrationTesting_AddPath)
# └── Tests
#     ├── UnitTests
#     │   ├── CMakeLists.txt        (UnitTesting_Add_Test)
#     │   └── Test_Module.c         (Unity test cases on host)
#     └── IntegrationTests
#         ├── CMakeLists.txt        (IntegrationTesting_Add_Test)
#         ├── ItTest_Module.c       (Unity test cases on target)
#         ├── ItTarget_Module.c     (Target interface - entry point, init, faults, reset)
#         └── BspMain.h             (Entry point called by StartUp)
#
# The testing frameworks are independent of the target - every test set
# initializes everything it needs itself (see UnitTesting / IntegrationTesting
# README).
#
# Direct call:
#   cmake -DTEST_INIT_MODULE_PATH=<path> -DTEST_INIT_MODULE_NAME=<name>
#         [-DTEST_INIT_TYPES=UT;IT] -P CMake/HelperTools/Test_Handler/TestInit.cmake
#
################################################################################
cmake_minimum_required(VERSION 3.21)

#==============================================================================#
# Global variables
#==============================================================================#

# Set path to system configuration file
get_filename_component(TEST_INIT_SYSTEM_CONFIG_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/../../SysConfig.cmake" REALPATH)

# Include file with system configuration values
include("${TEST_INIT_SYSTEM_CONFIG_FILE_PATH}")

# Read project root folder path
SysConfig_Get_ProjectRootPath(PROJECT_ROOT_PATH)

# Template folder captured at include time (TestInit may be called from other files)
set(TEST_INIT_TEMPLATE_DIR "${CMAKE_CURRENT_LIST_DIR}/Template")

#------------------------------------------------------------------------------#
# Copies one template file into the module (existing file is kept).
#
# TEMPLATE_ARG [in]: Template file relative to the template folder.
# OUTPUT_ARG   [in]: Output file (absolute path).
#------------------------------------------------------------------------------#
function(testInit_CopyTemplate TEMPLATE_ARG OUTPUT_ARG)

    if(EXISTS "${OUTPUT_ARG}")
        message(STATUS "${OUTPUT_ARG} already exists, kept.")
    else()
        configure_file("${TEST_INIT_TEMPLATE_DIR}/${TEMPLATE_ARG}" "${OUTPUT_ARG}" @ONLY)
        message(STATUS "${OUTPUT_ARG} created.")
    endif()

endfunction()


#------------------------------------------------------------------------------#
# Copies template of the test cases file into the module, if the test folder
# does not contain any test cases file yet (eg. Test_Module.cpp of C++ module).
#
# TEMPLATE_ARG [in]: Template file relative to the template folder.
# OUTPUT_ARG   [in]: Output file (absolute path).
# PATTERN_ARG  [in]: Glob of existing test cases files (eg. ItTest_*.c*).
#------------------------------------------------------------------------------#
function(testInit_CopyTestTemplate TEMPLATE_ARG OUTPUT_ARG PATTERN_ARG)

    get_filename_component(OUTPUT_DIR "${OUTPUT_ARG}" DIRECTORY)
    file(GLOB EXISTING_TESTS "${OUTPUT_DIR}/${PATTERN_ARG}")

    if(EXISTING_TESTS)
        message(STATUS "Test cases file already exists (${EXISTING_TESTS}), kept.")
    else()
        testInit_CopyTemplate("${TEMPLATE_ARG}" "${OUTPUT_ARG}")
    endif()

endfunction()


#------------------------------------------------------------------------------#
# Adds registration of the tests into CMakeLists.txt of the module (if missing).
#
# CMAKELISTS_ARG [in]: CMakeLists.txt of the module.
# FUNCTION_ARG   [in]: Registration function (UnitTesting_AddPath, ...).
# BLOCK_ARG      [in]: Registration block appended to the file.
#------------------------------------------------------------------------------#
function(testInit_AddRegistration CMAKELISTS_ARG FUNCTION_ARG BLOCK_ARG)

    if(NOT EXISTS "${CMAKELISTS_ARG}")
        message(WARNING "${CMAKELISTS_ARG} does not exist - add ${FUNCTION_ARG}() to CMakeLists.txt of the module.")
        return()
    endif()

    file(READ "${CMAKELISTS_ARG}" CMAKELISTS_CONTENT)

    if(CMAKELISTS_CONTENT MATCHES "${FUNCTION_ARG}")
        message(STATUS "${FUNCTION_ARG}() already in ${CMAKELISTS_ARG}.")
    else()
        file(APPEND "${CMAKELISTS_ARG}" "${BLOCK_ARG}")
        message(STATUS "${FUNCTION_ARG}() added to ${CMAKELISTS_ARG}.")
    endif()

endfunction()


#------------------------------------------------------------------------------#
# Copies the testing template into the module.
#
# MODULE_PATH_ARG [in]: Path to the module location relative to project root
#                       (without module name in it).
# MODULE_NAME_ARG [in]: Name of the module (folder name).
# TEST_TYPES_ARG  [in]: List of test types - UT (unit tests), IT (integration
#                       tests). Empty or ALL = both.
#------------------------------------------------------------------------------#
function(TestInit MODULE_PATH_ARG MODULE_NAME_ARG TEST_TYPES_ARG)

    set(MODULE_DIR "${PROJECT_ROOT_PATH}/${MODULE_PATH_ARG}/${MODULE_NAME_ARG}")

    if(NOT IS_DIRECTORY "${MODULE_DIR}")
        message(FATAL_ERROR "Module ${MODULE_NAME_ARG} does not exist (${MODULE_DIR}).")
    endif()

    if(NOT TEST_TYPES_ARG OR TEST_TYPES_ARG STREQUAL "ALL")
        set(TEST_TYPES_ARG "UT;IT")
    endif()

    message(STATUS "Initializing tests (${TEST_TYPES_ARG}) of module ${MODULE_NAME_ARG} on path ${MODULE_PATH_ARG} ...")

    # Placeholders of the templates (same rules as SwModule_Handler templates)
    string(SUBSTRING "${MODULE_NAME_ARG}" 0 1 FIRST_CHAR)
    string(TOLOWER "${FIRST_CHAR}" FIRST_CHAR_LOWER)
    string(SUBSTRING "${MODULE_NAME_ARG}" 1 -1 REST)

    set(MODULE_NAME "${MODULE_NAME_ARG}")
    set(TYPE_NAME   "${FIRST_CHAR_LOWER}${REST}")
    string(TOUPPER "${MODULE_NAME_ARG}" MACRO_NAME)

    # Read author name from git global configuration
    execute_process(COMMAND git config --global user.name
                    OUTPUT_VARIABLE AUTHOR
                    OUTPUT_STRIP_TRAILING_WHITESPACE)

    if("UT" IN_LIST TEST_TYPES_ARG)

        set(UT_DIR "${MODULE_DIR}/Tests/UnitTests")
        file(MAKE_DIRECTORY "${UT_DIR}")

        testInit_CopyTemplate("UnitTests/CMakeLists.txt.in"  "${UT_DIR}/CMakeLists.txt")
        testInit_CopyTestTemplate("UnitTests/Test_Module.c.in" "${UT_DIR}/Test_${MODULE_NAME_ARG}.c" "Test_*.c*")

        testInit_AddRegistration("${MODULE_DIR}/CMakeLists.txt" "UnitTesting_AddPath"
"
#========================= Unit tests configuration ===========================#
if(UNIT_TESTING_AVAILABLE STREQUAL \"ON\")
    UnitTesting_AddPath(\"\${CMAKE_CURRENT_SOURCE_DIR}/Tests/UnitTests\")
endif()
")

    endif()

    if("IT" IN_LIST TEST_TYPES_ARG)

        set(IT_DIR "${MODULE_DIR}/Tests/IntegrationTests")
        file(MAKE_DIRECTORY "${IT_DIR}")

        testInit_CopyTemplate("IntegrationTests/CMakeLists.txt.in"    "${IT_DIR}/CMakeLists.txt")
        testInit_CopyTestTemplate("IntegrationTests/ItTest_Module.c.in" "${IT_DIR}/ItTest_${MODULE_NAME_ARG}.c" "ItTest_*.c*")
        testInit_CopyTemplate("IntegrationTests/ItTarget_Module.c.in" "${IT_DIR}/ItTarget_${MODULE_NAME_ARG}.c")
        testInit_CopyTemplate("IntegrationTests/BspMain.h.in"         "${IT_DIR}/BspMain.h")

        testInit_AddRegistration("${MODULE_DIR}/CMakeLists.txt" "IntegrationTesting_AddPath"
"
#===================== Integration tests configuration ========================#
if(INTEGRATION_TESTING_AVAILABLE STREQUAL \"ON\")
    IntegrationTesting_AddPath(\"\${CMAKE_CURRENT_SOURCE_DIR}/Tests/IntegrationTests\")
endif()
")

    endif()

    message(STATUS "Tests initialization finish.")

endfunction()

#==============================================================================#
# Main functionality
#==============================================================================#
# Check if run directly with cmake -P
if(CMAKE_SCRIPT_MODE_FILE AND
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE AND
   DEFINED TEST_INIT_MODULE_PATH AND
   DEFINED TEST_INIT_MODULE_NAME)

    if(NOT DEFINED TEST_INIT_TYPES)
        set(TEST_INIT_TYPES "ALL")
    endif()

    TestInit("${TEST_INIT_MODULE_PATH}"
             "${TEST_INIT_MODULE_NAME}"
             "${TEST_INIT_TYPES}")

endif()
