################################################################################
# Author: Mr.Nobody
# file:  CMakeLists.txt
# brief: Standalone unit testing of one EmBi module (without project).
#
# Only EmBi platform and the tested module are needed:
#
#   git clone <EmBi_Platform repository> EmBi_Platform  (incl. submodules)
#   git clone <module repository>        ModBus
#   cmake -S EmBi_Platform/CMake/UnitTesting/Standalone -B Build_UnitTest
#         -DUNIT_TEST_MODULE_PATH=ModBus
#   cmake --build Build_UnitTest
#   ctest --test-dir Build_UnitTest --output-on-failure --no-tests=error
#
# or all steps at once by script RunModuleTests.cmake (see README.md).
#
# Parameters:
#   UNIT_TEST_MODULE_PATH - Folder of tested module (its CMakeLists.txt calls
#                           UnitTesting_AddPath). It can be a list - modules
#                           the tested module depends on are listed first.
#   UNIT_TEST_TOOLS       - Source of host tools:
#                           ARTIFACTS (default) - ArtifactsHandler with
#                             Artifacts/<Win|Unix>/ArtifactsConfig.txt
#                             (or CONFIG_FILE_PATH given by user)
#                           SYSTEM - compiler and ruby from system PATH,
#                             Unity / CMock from UNITY_ROOT / CMOCK_ROOT or
#                             downloaded from GitHub (pinned versions)
#
#   UNIT_TEST_COVERAGE    - OFF (default) / ON: coverage of the tested modules (target
#                           UnitTest_Coverage, see UnitTesting.cmake); the paths of
#                           the report are relative to the common parent folder of the
#                           modules (UNIT_TEST_COVERAGE_ROOT)
#
# Limitation: modules depending on MCU (RAL / LL, TARGET_MCU) can not be tested
# standalone yet - they are tested in project UnitTest build.
################################################################################

cmake_minimum_required(VERSION 3.25)

#=============================== Constant values ==============================#

get_filename_component(EMBI_PLATFORM_DIR "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)

set(UNIT_TEST_TOOLS                     "ARTIFACTS"
    CACHE STRING                        "Source of unit testing host tools (ARTIFACTS / SYSTEM)")

set_property(CACHE UNIT_TEST_TOOLS PROPERTY STRINGS "ARTIFACTS" "SYSTEM")

# Versions of Unity / CMock downloaded in SYSTEM mode (if not provided by user)
set(UNIT_TEST_UNITY_GIT_TAG             "v2.7.0")
set(UNIT_TEST_CMOCK_GIT_TAG             "v2.7.0")

set(CMAKE_BUILD_TYPE                    "UnitTest" CACHE STRING "Build type" FORCE)

#============================ Parameters check ================================#

if(NOT UNIT_TEST_MODULE_PATH)
    message(FATAL_ERROR "UNIT_TEST_MODULE_PATH is not set. Pass -DUNIT_TEST_MODULE_PATH=<folder of tested module>.")
endif()

set(UNIT_TEST_MODULE_DIRS "")

foreach(MODULE_PATH IN LISTS UNIT_TEST_MODULE_PATH)

    # Relative path is taken from the folder where cmake was called (shell
    # provides it in PWD), otherwise from this folder. Absolute path is preferred.
    get_filename_component(MODULE_DIR "${MODULE_PATH}" ABSOLUTE)

    if(NOT EXISTS "${MODULE_DIR}/CMakeLists.txt" AND DEFINED ENV{PWD})
        get_filename_component(MODULE_DIR "${MODULE_PATH}" ABSOLUTE BASE_DIR "$ENV{PWD}")
    endif()

    if(NOT EXISTS "${MODULE_DIR}/CMakeLists.txt")
        message(FATAL_ERROR "Module '${MODULE_PATH}' not found (CMakeLists.txt does not exist).")
    endif()

    list(APPEND UNIT_TEST_MODULE_DIRS "${MODULE_DIR}")

endforeach()

# Root of the coverage report: the common parent folder of the modules (the source folder
# of this project is the folder of the platform)
if(NOT DEFINED CACHE{UNIT_TEST_COVERAGE_ROOT})

    list(GET UNIT_TEST_MODULE_DIRS 0 COVERAGE_ROOT_DIR)
    get_filename_component(COVERAGE_ROOT_DIR "${COVERAGE_ROOT_DIR}" DIRECTORY)

    foreach(MODULE_DIR IN LISTS UNIT_TEST_MODULE_DIRS)

        while(TRUE)

            string(LENGTH "${COVERAGE_ROOT_DIR}/" ROOT_PREFIX_LENGTH)
            string(SUBSTRING "${MODULE_DIR}/" 0 ${ROOT_PREFIX_LENGTH} MODULE_PREFIX)

            get_filename_component(PARENT_DIR "${COVERAGE_ROOT_DIR}" DIRECTORY)

            # The root of the file system (modules on different drives) ends the search
            if(MODULE_PREFIX STREQUAL "${COVERAGE_ROOT_DIR}/" OR PARENT_DIR STREQUAL COVERAGE_ROOT_DIR)
                break()
            endif()

            set(COVERAGE_ROOT_DIR "${PARENT_DIR}")

        endwhile()

    endforeach()

    set(UNIT_TEST_COVERAGE_ROOT "${COVERAGE_ROOT_DIR}" CACHE PATH "Root of the sources in the coverage report")

endif()

#============================ Artifacts preparation ===========================#

if(UNIT_TEST_TOOLS STREQUAL "ARTIFACTS")

    if(NOT EXISTS "${EMBI_PLATFORM_DIR}/CMake/ArtifactsHandler/ArtifactsHandler.cmake")
        message(FATAL_ERROR "ArtifactsHandler not found in ${EMBI_PLATFORM_DIR}/CMake/ArtifactsHandler. "
                            "Check EMBI_PLATFORM_DIR (the EmBi platform clone) or use -DUNIT_TEST_TOOLS=SYSTEM.")
    endif()

    # Host specific tools - gcc, ruby and ninja artifacts are released per OS
    if(NOT CONFIG_FILE_PATH AND NOT DEFINED ENV{CONFIG_FILE_PATH})
        if(CMAKE_HOST_WIN32)
            set(CONFIG_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/Artifacts/Win")
        else()
            set(CONFIG_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/Artifacts/Unix")
        endif()
    endif()

    include("${EMBI_PLATFORM_DIR}/CMake/ArtifactsHandler/ArtifactsHandler.cmake")

elseif(NOT UNIT_TEST_TOOLS STREQUAL "SYSTEM")
    message(FATAL_ERROR "Invalid value '${UNIT_TEST_TOOLS}' of UNIT_TEST_TOOLS (ARTIFACTS / SYSTEM).")
endif()

#=========================== Project configuration ============================#

project(EmBi_ModuleUnitTests LANGUAGES C CXX)

set(CMAKE_C_STANDARD                    17)
set(CMAKE_C_STANDARD_REQUIRED           ON)
set(CMAKE_C_EXTENSIONS                  ON)

set(CMAKE_CXX_STANDARD                  17)
set(CMAKE_CXX_STANDARD_REQUIRED         ON)

set(CMAKE_EXPORT_COMPILE_COMMANDS       ON)

#======================== Unity and CMock (SYSTEM mode) =======================#

if(UNIT_TEST_TOOLS STREQUAL "SYSTEM")

    include(FetchContent)

    # SOURCE_SUBDIR without CMakeLists.txt - sources are only downloaded, the
    # libraries are created by UnitTesting.cmake
    if(NOT UNITY_ROOT AND NOT DEFINED ENV{UNITY_ROOT})

        FetchContent_Declare(EmBiUt_Unity
            GIT_REPOSITORY  https://github.com/ThrowTheSwitch/Unity.git
            GIT_TAG         ${UNIT_TEST_UNITY_GIT_TAG}
            GIT_SHALLOW     TRUE
            SOURCE_SUBDIR   _NoCMakeProject
        )

        FetchContent_MakeAvailable(EmBiUt_Unity)

        set(UNITY_ROOT "${embiut_unity_SOURCE_DIR}")

    endif()

    if(NOT CMOCK_ROOT AND NOT DEFINED ENV{CMOCK_ROOT})

        # Submodules (vendor/unity, vendor/c_exception) are required by cmock.rb
        FetchContent_Declare(EmBiUt_CMock
            GIT_REPOSITORY  https://github.com/ThrowTheSwitch/CMock.git
            GIT_TAG         ${UNIT_TEST_CMOCK_GIT_TAG}
            GIT_SHALLOW     TRUE
            SOURCE_SUBDIR   _NoCMakeProject
        )

        FetchContent_MakeAvailable(EmBiUt_CMock)

        set(CMOCK_ROOT "${embiut_cmock_SOURCE_DIR}")

    endif()

endif()

#============================== Unit testing ==================================#

include("${EMBI_PLATFORM_DIR}/CMake/UnitTesting/UnitTesting.cmake")

# Tested module (and its dependencies) register unit tests by UnitTesting_AddPath()
foreach(MODULE_DIR IN LISTS UNIT_TEST_MODULE_DIRS)

    get_filename_component(MODULE_NAME "${MODULE_DIR}" NAME)

    message(STATUS "Module processed: ${MODULE_DIR}")

    add_subdirectory("${MODULE_DIR}" "${CMAKE_BINARY_DIR}/Modules/${MODULE_NAME}")

endforeach()

get_property(REGISTERED_TESTS GLOBAL PROPERTY UNIT_TESTING_PATHS)

if(NOT REGISTERED_TESTS)
    message(FATAL_ERROR "No unit tests registered. Module CMakeLists.txt shall call "
                        "UnitTesting_AddPath() when UNIT_TESTING_AVAILABLE is ON.")
endif()

UnitTesting_Generate()
