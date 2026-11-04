################################################################################
#
# VSCode project initialization CMake script.
#
# The project gets following VSCode configuration:
#
# Project_root/
# │
# ...
# └── .vscode
#     ├── tasks.json                (Build, clean rebuild, flash, unit tests,
#     │                              integration tests, detection of boards,
#     │                              serial monitor of a board of an IT agent,
#     │                              Setup)
#     ├── launch.json               (probe-rs debugging of the MCU firmware and
#     │                              integration test firmwares, gdb debugging
#     │                              of unit tests)
#     ├── settings.json             (CMake Tools with project presets,
#     │                              IntelliSense, excludes - other settings of
#     │                              an existing file are kept)
#     ├── c_cpp_properties.json     (IntelliSense configuration from CMake Tools)
#     └── extensions.json           (Recommended extensions)
#
# Tasks select the MCU, build type, board and test set from lists and execute
# Build_Handler.cmake (same build and test flow as Setup options Build and
# Tests). Debug configurations are generated for the MCUs selected by the user
# without access to hardware and without running any tool. The generated files
# contain no static values of the project (lists of MCUs, boards, test sets,
# chip, SVD file, firmware files, gdb) - they are inputs resolved by CMake (this
# script, extension Tasks Shell Input) when a task or a debug configuration is
# started. The SVD file of the MCU (peripheral registers of the debugger) is taken
# from the Ral module Svd of the BSP, no file of the host is used.
# probe-rs is started through CMake (Prj_VSCode_ProbeRs.cmake), the artifact is
# downloaded by the preLaunchTask of the debug configurations.
#
# Generated files start with the comment VSCODE_GENERATED_MARK. Existing files
# without the mark (created by user or other tools) are kept as <file>.bak.
#
# User can execute initialization through this CMake script - generation is
# repeated after change of MCUs, boards or test sets of the project.
#
################################################################################

# Set path to system configuration file
get_filename_component(SYSTEM_CONFIG_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/../../SysConfig.cmake" REALPATH)

# Include file with system configuration values
include("${SYSTEM_CONFIG_FILE_PATH}")

# MCUs of the project presets, detection of connected boards
include("${CMAKE_CURRENT_LIST_DIR}/../Build_Handler/Build_Handler.cmake")

# probe-rs artifact lookup, MCU identification of the Ral presets
include("${CMAKE_CURRENT_LIST_DIR}/../../IntegrationTesting/IntegrationTesting_Probe.cmake")

# Connected boards of this machine and of the IT agents (targets of the debug configurations of a picked board)
include("${CMAKE_CURRENT_LIST_DIR}/../../IntegrationTesting/IntegrationTesting_Detect.cmake")

# Listening ports of this machine (the tunnel of the serial monitor of a board of an IT agent)
include("${CMAKE_CURRENT_LIST_DIR}/../../IntegrationTesting/IntegrationTesting_DebugServer.cmake")

# Section of the option bytes of the MCUs of the project in the project CMakeLists.txt, option bytes of a firmware
# written by the flash
include("${CMAKE_CURRENT_LIST_DIR}/../../OptionBytes/OptionBytes.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../OptionBytes/OptionBytes_Flash.cmake")

#==============================================================================#
# Global variables
#==============================================================================#

# Read project root folder path
SysConfig_Get_ProjectRootPath(PROJECT_ROOT_PATH)

# Read platform root folder path (Bsp - the parent folder of the projects of the cores of a multi-core MCU)
SysConfig_Get_PlatformRootPath(PLATFORM_ROOT_PATH)

set(VSCODE_DIR                  "${PROJECT_ROOT_PATH}/.vscode")

# Project of a core of a multi-core MCU (subfolder of the platform root folder): its tasks are hidden, the VS Code
# workspace of the projects of the cores has them once with the selection of the core ("All cores" - the projects
# of all cores one after another, RUN_CORES of this handler started in the platform root folder)
if("${PROJECT_ROOT_PATH}" STREQUAL "${PLATFORM_ROOT_PATH}")
    set(VSCODE_CORE_PROJECT     FALSE)
else()
    set(VSCODE_CORE_PROJECT     TRUE)
endif()

set(VSCODE_ALL_CORES_OPTION     "All cores")
file(RELATIVE_PATH VSCODE_ROOT_HANDLER "${PLATFORM_ROOT_PATH}" "${CMAKE_CURRENT_LIST_FILE}")

# Core of the project (TARGET_CORE of the project CMakeLists.txt, "" = the default core) - the core of the debug
# configurations (Prj_VSCode_GetCoreIndex)
set(VSCODE_TARGET_CORE          "")
if(EXISTS "${PROJECT_ROOT_PATH}/CMakeLists.txt")
    file(STRINGS "${PROJECT_ROOT_PATH}/CMakeLists.txt" CORE_LINE REGEX "^[ \t]*set\\(TARGET_CORE[ \t]+\"[^\"]*\"")
    if(CORE_LINE MATCHES "set\\(TARGET_CORE[ \t]+\"([^\"]*)\"")
        set(VSCODE_TARGET_CORE  "${CMAKE_MATCH_1}")
    endif()
endif()

# Mark of the generated files (first line)
set(VSCODE_GENERATED_MARK       "// Generated by EmBi_Platform Setup (VSCode project initialization).")

# Scripts executed by tasks (relative to project root)
file(RELATIVE_PATH VSCODE_BUILD_HANDLER "${PROJECT_ROOT_PATH}"
     "${CMAKE_CURRENT_LIST_DIR}/../Build_Handler/Build_Handler.cmake")
file(RELATIVE_PATH VSCODE_HANDLER "${PROJECT_ROOT_PATH}" "${CMAKE_CURRENT_LIST_FILE}")
file(RELATIVE_PATH VSCODE_PROBE_RS_SCRIPT "${PROJECT_ROOT_PATH}" "${CMAKE_CURRENT_LIST_DIR}/Prj_VSCode_ProbeRs.cmake")

# Project structure handler - projects of the cores of a multi-core MCU (CORE_PROJECTS)
set(VSCODE_PRJ_HANDLER          "${CMAKE_CURRENT_LIST_DIR}/Prj_Handler.cmake")

# Task of the debug configurations (preLaunchTask) providing the probe-rs artifact
set(VSCODE_PROVIDE_PROBE_RS_TASK "EmBi: Provide probe-rs")  # <task> <MCU>

# Tasks of the debug configurations of a picked board (preLaunchTask, background): the Debug firmware is built
# (or not, integration test firmware) and the debug server of the board is started (Prj_VSCode_ProbeRs.cmake)
set(VSCODE_DEBUG_SERVE_TASK      "EmBi: Prepare debugging on board")
set(VSCODE_DEBUG_SERVE_TEST_TASK "EmBi: Prepare debugging of an integration test on board")

# Lines of the debug server - start of the task and the server listening (the debug configuration connects then)
set(VSCODE_DEBUG_BEGIN_PATTERN   "EmBi: preparing debugging")
set(VSCODE_DEBUG_READY_PATTERN   "EmBi: debug server listening on port")

# Board picked by the inputs of the debug configurations of a picked board (written by DEBUG_BOARD_SERVER,
# read by the preLaunchTask)
set(VSCODE_DEBUG_TARGET_FILE    "${PROJECT_ROOT_PATH}/Build/DebugTarget.cmake")

# Ports of the debug server of a picked board: 127.0.0.1 of this machine (the tunnel of an IT agent) and of the
# agent - <base> + hash of the board % <range> (the ports of the excluded port ranges of Windows are skipped)
set(VSCODE_DEBUG_LOCAL_PORT_BASE  30000)
set(VSCODE_DEBUG_REMOTE_PORT_BASE 40000)
set(VSCODE_DEBUG_PORT_RANGE       10000)

# Debugging of all cores of a multi-core MCU in one session (VS Code workspace of the projects of the cores): GDB
# server of probe-rs (all cores of one architecture as threads) on 127.0.0.1 of this machine - <base> + hash of the MCU
# % VSCODE_DEBUG_PORT_RANGE; the session of the extension cortex-debug connects when probe-rs prints the ready line
set(VSCODE_GDB_LOCAL_PORT_BASE    40000)
set(VSCODE_GDB_READY_PATTERN      "EmBi: GDB server listening on port")
set(VSCODE_GDB_EXTENSION          "marus25.cortex-debug")

# GDB server of all cores (background process of the preLaunchTask): process id of a server of a previous session
# (stopped by the next start) and output; the server is stopped when the session ends (no connection after one) or
# when no session connects within VSCODE_GDB_CONNECT_TIMEOUT seconds
set(VSCODE_GDB_SERVER_PID_FILE    "${PROJECT_ROOT_PATH}/Build/AllCoresGdbServer.pid")
set(VSCODE_GDB_SERVER_LOG_FILE    "${PROJECT_ROOT_PATH}/Build/AllCoresGdbServer.log")
set(VSCODE_GDB_CONNECT_TIMEOUT    300)

# Serial monitor of a board of an IT agent (task, embi-agent serial-server): ports of its tunnel - 127.0.0.1 of this
# machine (the Serial Monitor connects there in TCP mode) and of the agent, the range as for the debug server - and
# the baud rates of the input (the first one is the default)
set(VSCODE_SERIAL_LOCAL_PORT_BASE  20000)
set(VSCODE_SERIAL_REMOTE_PORT_BASE 50000)
set(VSCODE_SERIAL_BAUD_RATES       115200 9600 19200 38400 57600 230400 460800 921600)
file(RELATIVE_PATH VSCODE_SETUP_DIR "${PROJECT_ROOT_PATH}" "${CMAKE_CURRENT_LIST_DIR}/../../..")

# Ral presets with MCU identification
set(VSCODE_RAL_PRESETS_FILE     "${PLATFORM_ROOT_PATH}/Bsp/Ral/RalPresets.json")

# SVD files of the Ral module Svd - <Device>.svd in the root of the module and the file
# Devices.csv (Device;Core;File;Pack), which assigns the SVD file to a device
set(VSCODE_SVD_DIR              "${PLATFORM_ROOT_PATH}/Bsp/Ral/Svd")

# Board configuration of the project (ItBoards.json)
set(VSCODE_PROJECT_BOARDS_FILE  "${PROJECT_ROOT_PATH}/${IT_PROJECT_BOARDS_NAME}")

# Folders not searched for tests
set(VSCODE_EXCLUDED_DIRS        "Build;EmBi_Platform;STM32CubeIDE;.git;.vscode;.settings")

# Recommended extensions (Serial Monitor - firmware output over ST-LINK VCP, Tasks Shell Input - inputs of the
# debug configurations resolved by CMake)
set(VSCODE_EXTENSIONS           "ms-vscode.cmake-tools;ms-vscode.cpptools;probe-rs.probe-rs-debugger;ms-vscode.vscode-serial-monitor;augustocdias.tasks-shell-input")

# Max length of one line arrays of strings
set(VSCODE_LINE_LENGTH          100)

# gcc problem matcher with file paths of the compiler (absolute or relative)
set(VSCODE_PROBLEM_MATCHER      "{ \"base\": \"$gcc\", \"fileLocation\": [ \"autoDetect\", \"\${workspaceFolder}\" ] }")


#==============================================================================#
# Functions
#==============================================================================#

# ------------------------------------------------------------------------------
# Function: Prj_VSCode_JsonString
# Description: JSON string of the text.
#
# OUT_JSON [out]: JSON string.
# IN_TEXT  [in]:  Text.
# ------------------------------------------------------------------------------
function(Prj_VSCode_JsonString OUT_JSON IN_TEXT)

    string(REPLACE "\\" "\\\\" TEXT "${IN_TEXT}")
    string(REPLACE "\"" "\\\"" TEXT "${TEXT}")

    set(${OUT_JSON} "\"${TEXT}\"" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_JsonStringArray
# Description: JSON array of strings - one line, multi-line if the line is
#              longer than VSCODE_LINE_LENGTH.
#
# OUT_JSON [out]: JSON array.
# ARGN     [in]:  Strings.
# ------------------------------------------------------------------------------
function(Prj_VSCode_JsonStringArray OUT_JSON)

    set(ITEMS "")

    foreach(TEXT IN LISTS ARGN)
        Prj_VSCode_JsonString(ITEM "${TEXT}")
        list(APPEND ITEMS "${ITEM}")
    endforeach()

    list(JOIN ITEMS ", " LINE)
    string(LENGTH "${LINE}" LINE_LENGTH)

    if(NOT ITEMS)
        set(ARRAY "[]")
    elseif(LINE_LENGTH GREATER VSCODE_LINE_LENGTH)
        Prj_VSCode_JsonArray(ARRAY ${ITEMS})
    else()
        set(ARRAY "[ ${LINE} ]")
    endif()

    set(${OUT_JSON} "${ARRAY}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_JsonObject
# Description: Multi-line JSON object, nested values are indented.
#
# OUT_JSON [out]: JSON object.
# ARGN     [in]:  Pairs of member name and JSON value (values without ';').
# ------------------------------------------------------------------------------
function(Prj_VSCode_JsonObject OUT_JSON)

    set(MEMBERS "")

    while(ARGN)
        list(POP_FRONT ARGN NAME VALUE)
        Prj_VSCode_JsonString(NAME "${NAME}")
        string(REPLACE "\n" "\n    " VALUE "${VALUE}")
        list(APPEND MEMBERS "    ${NAME}: ${VALUE}")
    endwhile()

    if(MEMBERS)
        list(JOIN MEMBERS ",\n" MEMBERS)
        set(${OUT_JSON} "{\n${MEMBERS}\n}" PARENT_SCOPE)
    else()
        set(${OUT_JSON} "{}" PARENT_SCOPE)
    endif()
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_JsonArray
# Description: Multi-line JSON array, nested values are indented.
#
# OUT_JSON [out]: JSON array.
# ARGN     [in]:  JSON values (without ';').
# ------------------------------------------------------------------------------
function(Prj_VSCode_JsonArray OUT_JSON)

    set(ITEMS "")

    foreach(VALUE IN LISTS ARGN)
        string(REPLACE "\n" "\n    " VALUE "${VALUE}")
        list(APPEND ITEMS "    ${VALUE}")
    endforeach()

    if(ITEMS)
        list(JOIN ITEMS ",\n" ITEMS)
        set(${OUT_JSON} "[\n${ITEMS}\n]" PARENT_SCOPE)
    else()
        set(${OUT_JSON} "[]" PARENT_SCOPE)
    endif()
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_WriteFile
# Description: Writes generated file of the .vscode folder. Existing file
#              without the generated mark is kept as <file>.bak.
#
# IN_NAME    [in]: File name.
# IN_CONTENT [in]: Content without the generated mark.
# ------------------------------------------------------------------------------
function(Prj_VSCode_WriteFile IN_NAME IN_CONTENT)

    set(FILE_PATH "${VSCODE_DIR}/${IN_NAME}")
    set(CONTENT   "${VSCODE_GENERATED_MARK}\n${IN_CONTENT}\n")

    if(EXISTS "${FILE_PATH}")

        file(READ "${FILE_PATH}" OLD_CONTENT)
        string(FIND "${OLD_CONTENT}" "${VSCODE_GENERATED_MARK}" MARK_POS)

        if(NOT MARK_POS EQUAL 0)
            file(COPY_FILE "${FILE_PATH}" "${FILE_PATH}.bak")
            message("Existing ${IN_NAME} kept as ${IN_NAME}.bak")
        endif()

    endif()

    file(WRITE "${FILE_PATH}" "${CONTENT}")
    message("Generated: .vscode/${IN_NAME}")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_GetFirmwareName
# Description: File name of the project firmware (project name of the root
#              CMakeLists.txt, "<name>_${CMAKE_BUILD_TYPE}" + ".elf").
#
# IN_BUILD_TYPE [in]:  Debug or Release.
# OUT_NAME      [out]: File name of the firmware.
# ARGV2         [in]:  Project folder (optional, default the project root - the project of another core).
# ------------------------------------------------------------------------------
function(Prj_VSCode_GetFirmwareName IN_BUILD_TYPE OUT_NAME)

    set(PROJECT_NAME_TEXT "")
    set(PROJECT_DIR "${PROJECT_ROOT_PATH}")
    if(ARGC GREATER 2)
        set(PROJECT_DIR "${ARGV2}")
    endif()

    if(EXISTS "${PROJECT_DIR}/CMakeLists.txt")
        file(STRINGS "${PROJECT_DIR}/CMakeLists.txt" NAME_LINE REGEX "^[ \t]*set\\(PROJECT_NAME[ \t]+\"[^\"]+\"")
        if(NAME_LINE MATCHES "set\\(PROJECT_NAME[ \t]+\"([^\"]+)\"")
            set(PROJECT_NAME_TEXT "${CMAKE_MATCH_1}")
        endif()
    endif()

    if(PROJECT_NAME_TEXT STREQUAL "")
        message(WARNING "PROJECT_NAME not found in ${PROJECT_DIR}/CMakeLists.txt - firmware name Project_Template_<build type> is used. "
                        "Enter the firmware name in the VSCode project initialization of Setup.")
        set(PROJECT_NAME_TEXT "Project_Template_\${CMAKE_BUILD_TYPE}")
    endif()

    string(REPLACE "\${CMAKE_BUILD_TYPE}" "${IN_BUILD_TYPE}" PROJECT_NAME_TEXT "${PROJECT_NAME_TEXT}")

    set(${OUT_NAME} "${PROJECT_NAME_TEXT}.elf" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_SetFirmwareName
# Description: Sets the firmware name in the root CMakeLists.txt - PROJECT_NAME
#              is set to "<name>_${CMAKE_BUILD_TYPE}" (the file name of the
#              firmware is <name>_<build type>.elf).
#
# IN_NAME [in]: Firmware name without build type (empty = not changed).
# ------------------------------------------------------------------------------
function(Prj_VSCode_SetFirmwareName IN_NAME)

    if("${IN_NAME}" STREQUAL "")
        return()
    endif()

    if(NOT "${IN_NAME}" MATCHES "^[A-Za-z0-9_.-]+$")
        message(FATAL_ERROR "Firmware name '${IN_NAME}' is not correct (letters, digits, '_', '-' and '.' only, no spaces).")
    endif()

    set(CMAKELISTS_FILE "${PROJECT_ROOT_PATH}/CMakeLists.txt")

    if(NOT EXISTS "${CMAKELISTS_FILE}")
        message(FATAL_ERROR "${CMAKELISTS_FILE} not found - run \"BSP module - Configuration\" first (project structure initialization).")
    endif()

    file(READ "${CMAKELISTS_FILE}" CMAKELISTS_CONTENT)

    set(NAME_REGEX "(^|\n)([ \t]*set[(]PROJECT_NAME[ \t]+)\"[^\"\n]*\"")

    if(NOT "${CMAKELISTS_CONTENT}" MATCHES "${NAME_REGEX}")
        message(FATAL_ERROR "set(PROJECT_NAME \"...\") not found in ${CMAKELISTS_FILE} - firmware name cannot be set.")
    endif()

    string(REGEX REPLACE "${NAME_REGEX}" "\\1\\2\"${IN_NAME}_\${CMAKE_BUILD_TYPE}\""
           CMAKELISTS_CONTENT "${CMAKELISTS_CONTENT}")

    file(WRITE "${CMAKELISTS_FILE}" "${CMAKELISTS_CONTENT}")
    message("Firmware name: ${IN_NAME}_<build type> (CMakeLists.txt)")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_PrintFirmwareName
# Description: Prints the current firmware name of the root CMakeLists.txt.
# ------------------------------------------------------------------------------
function(Prj_VSCode_PrintFirmwareName)

    set(CURRENT "")

    if(EXISTS "${PROJECT_ROOT_PATH}/CMakeLists.txt")
        file(STRINGS "${PROJECT_ROOT_PATH}/CMakeLists.txt" NAME_LINE REGEX "^[ \t]*set\\(PROJECT_NAME[ \t]+\"[^\"]+\"")
        if(NAME_LINE MATCHES "set\\(PROJECT_NAME[ \t]+\"([^\"]+)\"")
            set(CURRENT "${CMAKE_MATCH_1}")
        endif()
    endif()

    if("${CURRENT}" STREQUAL "")
        message("Current firmware name: not set")
    else()
        string(REPLACE "_\${CMAKE_BUILD_TYPE}" "" CURRENT "${CURRENT}")
        message("Current firmware name: ${CURRENT}")
    endif()
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_GetTestFirmwares
# Description: Test executables of the project - test sets registered in
#              <module>/Tests/<UnitTests|IntegrationTests>/CMakeLists.txt
#              (UnitTesting_Add_Test / IntegrationTesting_Add_Test NAME). Paths
#              are relative to the tests folder of the build
#              (Build/<preset>/<UnitTests|IntegrationTests>). The project of a core
#              of a multi-core MCU has the tests of the shared Bsp of the platform
#              root folder too (unit tests in External/Bsp - UnitTesting_Generate,
#              integration tests in ../Bsp - IntegrationTesting_Generate).
#
# IN_TESTS_DIR [in]:  UnitTests or IntegrationTests.
# OUT_LIST     [out]: Sorted list of <module path>/Tests/<dir>/<UT|IT>_<NAME><suffix>.
# ------------------------------------------------------------------------------
function(Prj_VSCode_GetTestFirmwares IN_TESTS_DIR OUT_LIST)

    if("${IN_TESTS_DIR}" STREQUAL "UnitTests")
        set(PREFIX "UT_")
        set(SUFFIX "")
        if(CMAKE_HOST_WIN32)
            set(SUFFIX ".exe")
        endif()
    else()
        set(PREFIX "IT_")
        set(SUFFIX ".elf")
    endif()

    file(GLOB TOP_DIRS LIST_DIRECTORIES true RELATIVE "${PROJECT_ROOT_PATH}" "${PROJECT_ROOT_PATH}/*")

    if(VSCODE_CORE_PROJECT)
        file(RELATIVE_PATH SHARED_BSP_DIR "${PROJECT_ROOT_PATH}" "${PLATFORM_ROOT_PATH}/Bsp")
        list(APPEND TOP_DIRS "${SHARED_BSP_DIR}")
    endif()

    set(FIRMWARES "")

    foreach(TOP_DIR IN LISTS TOP_DIRS)

        if(NOT IS_DIRECTORY "${PROJECT_ROOT_PATH}/${TOP_DIR}" OR "${TOP_DIR}" IN_LIST VSCODE_EXCLUDED_DIRS)
            continue()
        endif()

        file(GLOB_RECURSE TEST_LISTS RELATIVE "${PROJECT_ROOT_PATH}" "${PROJECT_ROOT_PATH}/${TOP_DIR}/CMakeLists.txt")
        list(FILTER TEST_LISTS INCLUDE REGEX "/Tests/${IN_TESTS_DIR}/CMakeLists\\.txt$")

        foreach(TEST_LIST IN LISTS TEST_LISTS)

            file(READ "${PROJECT_ROOT_PATH}/${TEST_LIST}" TEST_CONTENT)
            string(REGEX MATCHALL "_Add_Test\\([ \t\r\n]*NAME[ \t]+[A-Za-z0-9_]+" TESTS "${TEST_CONTENT}")
            get_filename_component(TEST_DIR "${TEST_LIST}" DIRECTORY)

            if("${IN_TESTS_DIR}" STREQUAL "UnitTests")
                string(REGEX REPLACE "^(\\.\\./)+" "External/" TEST_DIR "${TEST_DIR}")
            endif()

            foreach(TEST IN LISTS TESTS)
                string(REGEX REPLACE "^.*NAME[ \t]+" "" TEST_NAME "${TEST}")
                list(APPEND FIRMWARES "${TEST_DIR}/${PREFIX}${TEST_NAME}${SUFFIX}")
            endforeach()

        endforeach()

    endforeach()

    list(REMOVE_DUPLICATES FIRMWARES)
    list(SORT FIRMWARES)

    set(${OUT_LIST} "${FIRMWARES}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_GetBoardValue
# Description: Value of the first board of the boards file with the integration
#              test preset of the MCU.
#
# IN_BOARDS_FILE [in]:  Boards file.
# IN_MCU         [in]:  MCU.
# OUT_VALUE      [out]: Value ("" if not found).
# ARGN           [in]:  Path of the value in the board object.
# ------------------------------------------------------------------------------
function(Prj_VSCode_GetBoardValue IN_BOARDS_FILE IN_MCU OUT_VALUE)

    set(VALUE "")

    if(EXISTS "${IN_BOARDS_FILE}")

        file(READ "${IN_BOARDS_FILE}" BOARDS_CONTENT)
        string(JSON BOARDS_CNT ERROR_VARIABLE BOARDS_ERROR LENGTH "${BOARDS_CONTENT}" boards)

        if(NOT BOARDS_ERROR AND BOARDS_CNT GREATER 0)

            math(EXPR BOARDS_LAST "${BOARDS_CNT} - 1")

            foreach(BOARD_IDX RANGE ${BOARDS_LAST})

                string(JSON BOARD MEMBER "${BOARDS_CONTENT}" boards ${BOARD_IDX})
                string(JSON PRESET ERROR_VARIABLE PRESET_ERROR GET "${BOARDS_CONTENT}" boards "${BOARD}" preset)

                if(NOT PRESET_ERROR AND "${PRESET}" STREQUAL "${IN_MCU}_IntegrationTest")
                    string(JSON BOARD_VALUE ERROR_VARIABLE VALUE_ERROR GET "${BOARDS_CONTENT}" boards "${BOARD}" ${ARGN})
                    if(NOT VALUE_ERROR AND NOT "${BOARD_VALUE}" STREQUAL "")
                        set(VALUE "${BOARD_VALUE}")
                        break()
                    endif()
                endif()

            endforeach()

        endif()

    endif()

    set(${OUT_VALUE} "${VALUE}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_GetChip
# Description: probe-rs chip of the MCU - board chip of the project boards file,
#              device of the MCU identification or MCU name, the first one
#              probe-rs knows (the first candidate without probe-rs).
#
# IN_MCU   [in]:  MCU.
# OUT_CHIP [out]: probe-rs chip.
# ------------------------------------------------------------------------------
function(Prj_VSCode_GetChip IN_MCU OUT_CHIP)

    Prj_VSCode_GetBoardValue("${VSCODE_PROJECT_BOARDS_FILE}" "${IN_MCU}" BOARD_CHIP cacheVariables INTEGRATION_TEST_PROBE_RS_CHIP)

    set(CANDIDATES "")

    foreach(CANDIDATE IN ITEMS "${BOARD_CHIP}" "${IT_MCU_${IN_MCU}_DEVICE}" "${IN_MCU}")
        if(NOT "${CANDIDATE}" STREQUAL "")
            list(APPEND CANDIDATES "${CANDIDATE}")
        endif()
    endforeach()

    list(GET CANDIDATES 0 CHIP)

    if(VSCODE_PROBE_RS)

        set(CHIP_FOUND FALSE)

        foreach(CANDIDATE IN LISTS CANDIDATES)
            execute_process(COMMAND "${VSCODE_PROBE_RS}" chip info "${CANDIDATE}"
                            RESULT_VARIABLE CHIP_RESULT OUTPUT_QUIET ERROR_QUIET)
            if(CHIP_RESULT EQUAL 0)
                set(CHIP "${CANDIDATE}")
                set(CHIP_FOUND TRUE)
                break()
            endif()
        endforeach()

        if(NOT CHIP_FOUND)
            list(JOIN CANDIDATES ", " CANDIDATES_TEXT)
            message(WARNING "probe-rs knows no chip of ${IN_MCU} (${CANDIDATES_TEXT}) - set INTEGRATION_TEST_PROBE_RS_CHIP "
                        "of the board in ItBoards.json.")
        endif()

    endif()

    set(${OUT_CHIP} "${CHIP}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_GetCoreIndex
# Description: Index of the core of the project (VSCODE_TARGET_CORE) in the cores
#              of the MCU - probe-rs coreIndex of the debug configurations and the
#              core of the row of the SVD file (Devices.csv). The cores of the MCU
#              identification of the Ral presets (IT_MCU_<MCU>_CORES, it has to be
#              read by IntegrationTesting_ReadMcuIdentification), probe-rs and
#              Devices.csv are in the order of the pack description (STM32H755:
#              CM7 0, CM4 1). The default core of the project and an MCU with one
#              core have the index 0.
#
# IN_MCU    [in]:  MCU.
# OUT_INDEX [out]: Index of the core.
# ------------------------------------------------------------------------------
function(Prj_VSCode_GetCoreIndex IN_MCU OUT_INDEX)

    set(CORE_INDEX 0)

    if(NOT "${VSCODE_TARGET_CORE}" STREQUAL "")
        list(FIND IT_MCU_${IN_MCU}_CORES "${VSCODE_TARGET_CORE}" CORE_INDEX)
        if(CORE_INDEX LESS 0)
            set(CORE_INDEX 0)
        endif()
    endif()

    set(${OUT_INDEX} ${CORE_INDEX} PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_GetSvd
# Description: SVD file of the MCU from the Ral module Svd of the BSP
#              (VSCODE_SVD_DIR). The file Devices.csv of the module (Device;Core;File;Pack,
#              generated by the importer from the pack descriptions of ST) assigns the
#              SVD file to a device; the row of the core of the project
#              (Prj_VSCode_GetCoreIndex) is the one of the debug configuration (a multi
#              core device, e.g. STM32H745, has a row per core).
#              The device of the MCU identification of the Ral presets
#              (IT_MCU_<MCU>_DEVICE, it has to be read by
#              IntegrationTesting_ReadMcuIdentification) is searched first, then
#              the first device that matches the MCU name ("x" of the name stands
#              for any character, e.g. STM32F722xE - STM32F722IE).
#
# IN_MCU  [in]:  MCU.
# OUT_SVD [out]: SVD file ("" if not found).
# ------------------------------------------------------------------------------
function(Prj_VSCode_GetSvd IN_MCU OUT_SVD)

    set(DEVICES_FILE "${VSCODE_SVD_DIR}/Devices.csv")

    if(NOT EXISTS "${DEVICES_FILE}")
        set(${OUT_SVD} "" PARENT_SCOPE)
        return()
    endif()

    string(REPLACE "x" "." MCU_REGEX "${IN_MCU}")
    set(IDENTIFIED_DEVICE "${IT_MCU_${IN_MCU}_DEVICE}")
    Prj_VSCode_GetCoreIndex(${IN_MCU} CORE_INDEX)

    # the rows are not changed by list() - it would split them at the semicolons
    file(STRINGS "${DEVICES_FILE}" ROWS)

    set(DEVICE_SVD "")
    set(REGEX_SVD "")

    foreach(ROW IN LISTS ROWS)

        # Device;Core;File;Pack - only the core of the project is used by the debug configuration (the header row has
        # no number)
        if(NOT ROW MATCHES "^([^;]+);${CORE_INDEX};([^;]+);")
            continue()
        endif()

        set(ROW_DEVICE "${CMAKE_MATCH_1}")
        set(ROW_FILE "${CMAKE_MATCH_2}")

        if(NOT "${IDENTIFIED_DEVICE}" STREQUAL "" AND "${ROW_DEVICE}" STREQUAL "${IDENTIFIED_DEVICE}")
            set(DEVICE_SVD "${ROW_FILE}")
            break()
        endif()

        if("${REGEX_SVD}" STREQUAL "" AND "${ROW_DEVICE}" MATCHES "^${MCU_REGEX}$")
            set(REGEX_SVD "${ROW_FILE}")
        endif()

    endforeach()

    if("${DEVICE_SVD}" STREQUAL "")
        set(DEVICE_SVD "${REGEX_SVD}")
    endif()

    if(NOT "${DEVICE_SVD}" STREQUAL "" AND EXISTS "${VSCODE_SVD_DIR}/${DEVICE_SVD}")
        set(${OUT_SVD} "${VSCODE_SVD_DIR}/${DEVICE_SVD}" PARENT_SCOPE)
    else()
        set(${OUT_SVD} "" PARENT_SCOPE)
    endif()
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_CmakeTask
# Description: Task executing a CMake script of the platform.
#
# OUT_JSON  [out]: JSON task.
# IN_LABEL  [in]:  Label of the task.
# IN_DETAIL [in]:  Description of the task.
# IN_GROUP  [in]:  JSON group of the task ("" = none).
# IN_HIDE   [in]:  TRUE - task is hidden (preLaunchTask of debug configurations).
# IN_SCRIPT [in]:  Script (relative to project root).
# ARGN      [in]:  Script parameters (-D...).
# ------------------------------------------------------------------------------
function(Prj_VSCode_CmakeTask OUT_JSON IN_LABEL IN_DETAIL IN_GROUP IN_HIDE IN_SCRIPT)

    Prj_VSCode_JsonString(LABEL "${IN_LABEL}")
    Prj_VSCode_JsonString(DETAIL "${IN_DETAIL}")
    Prj_VSCode_JsonStringArray(ARGS ${ARGN} -P "${IN_SCRIPT}")

    set(MEMBERS label "${LABEL}" detail "${DETAIL}" type "\"process\"" command "\"cmake\"" args "${ARGS}")

    # A hidden task is not a default build or test task (task of the project of a core - the workspace has it)
    if(IN_GROUP AND NOT IN_HIDE)
        list(APPEND MEMBERS group "${IN_GROUP}")
    endif()

    if(IN_HIDE)
        list(APPEND MEMBERS hide "true")
    endif()

    list(APPEND MEMBERS problemMatcher "${VSCODE_PROBLEM_MATCHER}")

    Prj_VSCode_JsonObject(TASK ${MEMBERS})

    set(${OUT_JSON} "${TASK}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_WorkspaceTask
# Description: CMake task of the VS Code workspace of the projects of the cores
#              - a task of the projects (IN_CORES TRUE: RUN_CORES in the platform
#              root folder runs it in the projects of the selected cores, input
#              "core") or a task run in the project of the first core.
#
# OUT_JSON  [out]: JSON task.
# IN_LABEL  [in]:  Label of the task.
# IN_DETAIL [in]:  Description of the task.
# IN_GROUP  [in]:  Group of the task (JSON, "" = no group).
# IN_CORES  [in]:  TRUE - the task of the selected cores.
# IN_SCRIPT [in]:  Script (relative to the project root of a core).
# ARGN      [in]:  Script parameters (-D...).
# ------------------------------------------------------------------------------
function(Prj_VSCode_WorkspaceTask OUT_JSON IN_LABEL IN_DETAIL IN_GROUP IN_CORES IN_SCRIPT)

    Prj_VSCode_GetCoreProjects(CORES)
    list(GET CORES 0 FIRST_CORE)

    if(IN_CORES)
        list(JOIN CORES "," ALL_CORES)
        list(JOIN ARGN "|" CORE_ARGS)
        Prj_VSCode_JsonStringArray(ARGS -DFUNCTION_ID=RUN_CORES "-DCORES=\${input:core}" "-DALL_CORES=${ALL_CORES}"
                                   "-DCORE_ARGS=${CORE_ARGS}|-P|${IN_SCRIPT}" -P "${VSCODE_ROOT_HANDLER}")
        set(CWD "\${workspaceFolder:${FIRST_CORE}}/..")
    else()
        Prj_VSCode_JsonStringArray(ARGS ${ARGN} -P "${IN_SCRIPT}")
        set(CWD "\${workspaceFolder:${FIRST_CORE}}")
    endif()

    Prj_VSCode_JsonString(LABEL "${IN_LABEL}")
    Prj_VSCode_JsonString(DETAIL "${IN_DETAIL}")
    Prj_VSCode_JsonString(CWD_JSON "${CWD}")
    string(REPLACE "\${workspaceFolder}" "${CWD}" PROBLEM_MATCHER "${VSCODE_PROBLEM_MATCHER}")

    set(MEMBERS label "${LABEL}" detail "${DETAIL}" type "\"process\"" command "\"cmake\"" args "${ARGS}"
                options "{ \"cwd\": ${CWD_JSON} }")

    if(IN_GROUP)
        list(APPEND MEMBERS group "${IN_GROUP}")
    endif()

    list(APPEND MEMBERS problemMatcher "${PROBLEM_MATCHER}")

    Prj_VSCode_JsonObject(TASK ${MEMBERS})

    set(${OUT_JSON} "${TASK}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_PickInput
# Description: Input of tasks / debug configurations selected from a list.
#
# OUT_JSON       [out]: JSON input.
# IN_ID          [in]:  ID of the input (${input:<id>}).
# IN_DESCRIPTION [in]:  Description of the input.
# IN_DEFAULT     [in]:  Default option.
# ARGN           [in]:  Options.
# ------------------------------------------------------------------------------
function(Prj_VSCode_PickInput OUT_JSON IN_ID IN_DESCRIPTION IN_DEFAULT)

    Prj_VSCode_JsonString(ID "${IN_ID}")
    Prj_VSCode_JsonString(DESCRIPTION "${IN_DESCRIPTION}")
    Prj_VSCode_JsonString(DEFAULT "${IN_DEFAULT}")
    Prj_VSCode_JsonStringArray(OPTIONS ${ARGN})

    Prj_VSCode_JsonObject(INPUT id "${ID}" type "\"pickString\"" description "${DESCRIPTION}"
                                options "${OPTIONS}" default "${DEFAULT}")

    set(${OUT_JSON} "${INPUT}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_GenerateTasks
# Description: Generates tasks.json.
#
# IN_MCU_LIST       [in]: MCUs of the project.
# IN_DEBUG_MCU_LIST [in]: MCUs of the debug configurations (hidden build tasks).
# ------------------------------------------------------------------------------
function(Prj_VSCode_GenerateTasks IN_MCU_LIST IN_DEBUG_MCU_LIST)

    set(MCU_ARG "-DMCU=\${input:mcu}")
    set(TYPE_ARG "-DBUILD_TYPE=\${input:buildType}")

    # Visible tasks: label, description, group, TRUE - task of the selected cores in the workspace of the projects
    # of the cores, script, parameters (the tasks of the project of a core are hidden)
    set(BUILD_SPEC   "EmBi: Build"
                     "Configure and build the project for the selected MCU and build type"
                     "{ \"kind\": \"build\", \"isDefault\": true }" TRUE "${VSCODE_BUILD_HANDLER}"
                     -DFUNCTION_ID=BUILD ${MCU_ARG} ${TYPE_ARG})

    set(REBUILD_SPEC "EmBi: Clean rebuild"
                     "Configure without CMake cache and rebuild the project for the selected MCU and build type"
                     "\"build\"" TRUE "${VSCODE_BUILD_HANDLER}"
                     -DFUNCTION_ID=BUILD ${MCU_ARG} ${TYPE_ARG} -DBUILD_CLEAN=ON)

    set(BOARD_BUILD_SPEC "EmBi: Build for board"
                         "Build for a picked board in its build folder (its fixture and own defines)"
                         "\"build\""
                         TRUE
                         "${VSCODE_BUILD_HANDLER}"
                         -DFUNCTION_ID=BUILD
                         "-DBOARD=\${input:buildBoard}"
                         ${TYPE_ARG})

    # The MCU and the build of the picked board (this machine or IT agent) - the same build as its debugging
    set(FLASH_SPEC "EmBi: Flash"
                   "Build for a picked board (its MCU and configuration), flash it by probe-rs and reset the MCU"
                   ""
                   TRUE
                   "${VSCODE_HANDLER}"
                   -DFUNCTION_ID=FLASH
                   "-DTARGET=\${input:flashBoard}"
                   ${TYPE_ARG})

    set(UT_SPEC "EmBi: Unit tests"
                "Build unit tests of the selected MCU (host) and execute the selected test set"
                "{ \"kind\": \"test\", \"isDefault\": true }" TRUE "${VSCODE_BUILD_HANDLER}"
                -DFUNCTION_ID=TEST -DTEST_TYPE=UT "-DTARGET=\${input:mcu}" "-DTEST_SET=\${input:utTestSet}")

    set(IT_SPEC "EmBi: Integration tests"
                "Detect connected boards, build integration tests of the selected board and execute the selected test set"
                "\"test\"" TRUE "${VSCODE_BUILD_HANDLER}"
                -DFUNCTION_ID=TEST -DTEST_TYPE=IT "-DTARGET=\${input:itBoard}" "-DTEST_SET=\${input:itTestSet}")

    set(DETECT_SPEC "EmBi: Detect connected boards"
                    "List boards connected to debug probes (Build/IntegrationTestBoards.json)"
                    "" FALSE "${VSCODE_BUILD_HANDLER}"
                    -DFUNCTION_ID=DETECT_BOARDS)

    # The virtual COM port of a board of an IT agent on 127.0.0.1 of this machine - the Serial Monitor connects there
    # in TCP mode, the task runs until it is terminated
    set(SERIAL_SPEC "EmBi: Serial monitor on board"
                    "Open the virtual COM port of a board of an IT agent for the Serial Monitor (TCP mode)"
                    ""
                    FALSE
                    "${VSCODE_HANDLER}"
                    -DFUNCTION_ID=SERIAL_SERVE
                    "-DTARGET=\${input:serialBoard}"
                    "-DBAUD=\${input:serialBaud}")

    set(TASKS "")
    set(WORKSPACE_TASKS "")

    foreach(SPEC IN ITEMS BUILD_SPEC REBUILD_SPEC BOARD_BUILD_SPEC FLASH_SPEC UT_SPEC IT_SPEC DETECT_SPEC SERIAL_SPEC)

        list(POP_FRONT ${SPEC} LABEL DETAIL GROUP CORES SCRIPT)

        Prj_VSCode_CmakeTask(TASK "${LABEL}" "${DETAIL}" "${GROUP}" ${VSCODE_CORE_PROJECT} "${SCRIPT}" ${${SPEC}})
        list(APPEND TASKS "${TASK}")

        if(VSCODE_CORE_PROJECT)
            Prj_VSCode_WorkspaceTask(TASK "${LABEL}" "${DETAIL}" "${GROUP}" ${CORES} "${SCRIPT}" ${${SPEC}})
            list(APPEND WORKSPACE_TASKS "${TASK}")
        endif()

    endforeach()

    # Setup menu in the terminal
    Prj_VSCode_JsonString(SETUP_SH "bash ${VSCODE_SETUP_DIR}/Setup.sh")
    file(TO_NATIVE_PATH "${VSCODE_SETUP_DIR}/Setup.bat" SETUP_BAT_PATH)
    string(REPLACE "/" "\\" SETUP_BAT_PATH "${SETUP_BAT_PATH}")
    Prj_VSCode_JsonString(SETUP_BAT "${SETUP_BAT_PATH}")
    Prj_VSCode_JsonObject(SETUP_WINDOWS command "${SETUP_BAT}"
                          options "{ \"shell\": { \"executable\": \"cmd.exe\", \"args\": [ \"/d\", \"/c\" ] } }")
    set(SETUP_MEMBERS label "\"EmBi: Setup\"" detail "\"EmBi_Platform Setup menu\"" type "\"shell\""
                      command "${SETUP_SH}" windows "${SETUP_WINDOWS}"
                      presentation "{ \"focus\": true, \"panel\": \"dedicated\" }" problemMatcher "[]")

    if(VSCODE_CORE_PROJECT)
        Prj_VSCode_GetCoreProjects(CORES)
        list(GET CORES 0 FIRST_CORE)
        Prj_VSCode_JsonObject(SETUP_TASK ${SETUP_MEMBERS} options "{ \"cwd\": \"\${workspaceFolder:${FIRST_CORE}}\" }")
        list(APPEND WORKSPACE_TASKS "${SETUP_TASK}")
        list(APPEND SETUP_MEMBERS hide "true")
    endif()

    Prj_VSCode_JsonObject(SETUP_TASK ${SETUP_MEMBERS})
    list(APPEND TASKS "${SETUP_TASK}")

    # Build of the debug firmware and probe-rs before debugging (preLaunchTask) - probe-rs of the
    # version configured for the integration test preset of the MCU, downloaded by the artifacts
    # handler if it is missing
    foreach(MCU IN LISTS IN_DEBUG_MCU_LIST)
        Prj_VSCode_CmakeTask(PROVIDE_TASK "${VSCODE_PROVIDE_PROBE_RS_TASK} ${MCU}"
                             "Find or download the probe-rs artifact (configured version) used by the debug configurations of ${MCU}" ""
                             TRUE "${VSCODE_PROBE_RS_SCRIPT}" -DFUNCTION_ID=PROVIDE -DMCU=${MCU})
        list(APPEND TASKS "${PROVIDE_TASK}")

        Prj_VSCode_CmakeTask(MCU_TASK "EmBi: Build ${MCU}_Debug" "Configure and build ${MCU} Debug" "" TRUE
                             "${VSCODE_BUILD_HANDLER}" -DFUNCTION_ID=BUILD -DMCU=${MCU} -DBUILD_TYPE=Debug)
        list(APPEND TASKS "${MCU_TASK}")

        # Option bytes of the Debug firmware written when the chip has other values (the debug session flashes the
        # firmware only)
        Prj_VSCode_CmakeTask(OPTION_BYTES_TASK "EmBi: Option bytes ${MCU}_Debug"
                             "Write the option bytes of the Debug firmware of ${MCU} when the chip has other values" ""
                             TRUE "${VSCODE_HANDLER}" -DFUNCTION_ID=OPTION_BYTES -DMCU=${MCU})
        list(APPEND TASKS "${OPTION_BYTES_TASK}")

        set(PREPARE_STEPS "EmBi: Build ${MCU}_Debug" "${VSCODE_PROVIDE_PROBE_RS_TASK} ${MCU}")

        # Project of a core of a multi-core MCU: the Debug firmware of the other cores built and flashed (the debug
        # session flashes and debugs the core of the project only)
        if(VSCODE_CORE_PROJECT)
            Prj_VSCode_CmakeTask(OTHER_CORES_TASK "EmBi: Other cores ${MCU}_Debug"
                                 "Build and flash the Debug firmware of the other cores of ${MCU}" ""
                                 TRUE "${VSCODE_HANDLER}" -DFUNCTION_ID=OTHER_CORES -DMCU=${MCU})
            list(APPEND TASKS "${OTHER_CORES_TASK}")
            list(APPEND PREPARE_STEPS "EmBi: Other cores ${MCU}_Debug")
        endif()

        list(APPEND PREPARE_STEPS "EmBi: Option bytes ${MCU}_Debug")
        Prj_VSCode_JsonStringArray(DEPENDS_ON ${PREPARE_STEPS})
        Prj_VSCode_JsonObject(PREPARE_TASK label "\"EmBi: Prepare ${MCU}_Debug\"" dependsOn "${DEPENDS_ON}"
                              dependsOrder "\"sequence\"" hide "true")
        list(APPEND TASKS "${PREPARE_TASK}")
    endforeach()

    # Debug server of a picked board (this machine or IT agent) - preLaunchTask of the debug configurations
    # of a picked board, with the build of the Debug firmware and without it (integration test firmware)
    Prj_VSCode_DebugServeTask(SERVE_TASK "${VSCODE_DEBUG_SERVE_TASK}" ON)
    Prj_VSCode_DebugServeTask(SERVE_TEST_TASK "${VSCODE_DEBUG_SERVE_TEST_TASK}" OFF)
    list(APPEND TASKS "${SERVE_TASK}" "${SERVE_TEST_TASK}")

    Prj_VSCode_JsonArray(TASKS ${TASKS})

    # Inputs - the lists are resolved by CMake when the task is started (MCUs of the presets, boards of the
    # project and of the detection, test sets registered in the project)
    Prj_VSCode_ShellInput(MCU_INPUT mcu "MCU" FALSE -DFUNCTION_ID=PICK_MCU)
    Prj_VSCode_PickInput(TYPE_INPUT buildType "Build type" Debug Debug Release)
    Prj_VSCode_ShellInput(BOARD_INPUT itBoard "Board of the integration tests" FALSE -DFUNCTION_ID=PICK_BOARD)
    Prj_VSCode_ShellInput(BUILD_BOARD_INPUT buildBoard "Board of the build" FALSE -DFUNCTION_ID=PICK_DEBUG_BOARD)
    Prj_VSCode_ShellInput(FLASH_BOARD_INPUT flashBoard "Board to flash" FALSE -DFUNCTION_ID=PICK_DEBUG_BOARD)
    Prj_VSCode_ShellInput(UT_SET_INPUT utTestSet "Test set of the unit tests" FALSE
                          -DFUNCTION_ID=PICK_TEST_SET -DTEST_TYPE=UT)
    Prj_VSCode_ShellInput(IT_SET_INPUT itTestSet "Test set of the integration tests" FALSE
                          -DFUNCTION_ID=PICK_TEST_SET -DTEST_TYPE=IT)
    Prj_VSCode_ShellInput(SERIAL_BOARD_INPUT
                          serialBoard
                          "Board of an IT agent for the serial monitor"
                          FALSE
                          -DFUNCTION_ID=PICK_SERIAL_BOARD)
    list(GET VSCODE_SERIAL_BAUD_RATES 0 SERIAL_BAUD_DEFAULT)
    Prj_VSCode_PickInput(SERIAL_BAUD_INPUT
                         serialBaud
                         "Baud rate of the virtual COM port"
                         ${SERIAL_BAUD_DEFAULT}
                         ${VSCODE_SERIAL_BAUD_RATES})

    set(INPUT_LIST "${MCU_INPUT}"
                   "${TYPE_INPUT}"
                   "${BOARD_INPUT}"
                   "${BUILD_BOARD_INPUT}"
                   "${FLASH_BOARD_INPUT}"
                   "${UT_SET_INPUT}"
                   "${IT_SET_INPUT}"
                   "${SERIAL_BOARD_INPUT}"
                   "${SERIAL_BAUD_INPUT}")

    Prj_VSCode_JsonArray(INPUTS ${INPUT_LIST})

    # Tasks and inputs of the VS Code workspace of the projects of the cores (Prj_VSCode_GenerateWorkspace): the
    # inputs run in the project of the first core, with own task IDs (the extension finds an input by it), and the
    # selection of the core
    if(VSCODE_CORE_PROJECT)

        Prj_VSCode_GetCoreProjects(CORES)
        list(GET CORES 0 FIRST_CORE)

        Prj_VSCode_PickInput(CORE_INPUT core "Core - project of the core" "${VSCODE_ALL_CORES_OPTION}"
                             "${VSCODE_ALL_CORES_OPTION}" ${CORES})
        set(WORKSPACE_INPUTS "${CORE_INPUT}")

        foreach(INPUT IN LISTS INPUT_LIST)
            string(REPLACE "\"cwd\": \"\${workspaceFolder}\"" "\"cwd\": \"\${workspaceFolder:${FIRST_CORE}}\""
                   INPUT "${INPUT}")
            string(REPLACE "\"taskId\": \"" "\"taskId\": \"workspace_" INPUT "${INPUT}")
            list(APPEND WORKSPACE_INPUTS "${INPUT}")
        endforeach()

        set(VSCODE_WORKSPACE_TASKS  "${WORKSPACE_TASKS}"  PARENT_SCOPE)
        set(VSCODE_WORKSPACE_INPUTS "${WORKSPACE_INPUTS}" PARENT_SCOPE)

    endif()

    Prj_VSCode_JsonObject(CONTENT version "\"2.0.0\"" options "{ \"cwd\": \"\${workspaceFolder}\" }"
                          presentation "{ \"panel\": \"dedicated\", \"clear\": true }"
                          tasks "${TASKS}" inputs "${INPUTS}")

    Prj_VSCode_WriteFile("tasks.json" "${CONTENT}")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_ProbeRsConfig
# Description: probe-rs debug configuration (generated without running
#              probe-rs - the chip is an input resolved by CMake, chip_<MCU>).
#              The debug adapter is started through CMake (Prj_VSCode_ProbeRs.cmake),
#              which runs the probe-rs artifact of the artifacts cache - the
#              configuration has no path of probe-rs.
#
# OUT_JSON       [out]: JSON debug configuration.
# IN_NAME        [in]:  Name of the configuration.
# IN_REQUEST     [in]:  launch (flash and run) or attach.
# IN_MCU         [in]:  MCU.
# IN_PROGRAM     [in]:  Firmware (ELF).
# IN_PRELAUNCH   [in]:  preLaunchTask ("" = none).
# ------------------------------------------------------------------------------
function(Prj_VSCode_ProbeRsConfig OUT_JSON IN_NAME IN_REQUEST IN_MCU IN_PROGRAM IN_PRELAUNCH)

    Prj_VSCode_JsonString(NAME "${IN_NAME}")
    Prj_VSCode_JsonString(REQUEST "${IN_REQUEST}")
    Prj_VSCode_JsonString(PROGRAM "${IN_PROGRAM}")
    set(CHIP "\"\${input:chip_${IN_MCU}}\"")

    set(MEMBERS type "\"probe-rs-debug\"" request "${REQUEST}" name "${NAME}" cwd "\"\${workspaceFolder}\"")

    # The extension adds "--port <port> --vscode" to the arguments - they follow "--" and are
    # passed to probe-rs by the script; the probe is selected by the debug adapter
    Prj_VSCode_JsonStringArray(RUNTIME_ARGS -DFUNCTION_ID=DAP_SERVER -DMCU=${IN_MCU} -P "${VSCODE_PROBE_RS_SCRIPT}" -- dap-server)

    list(APPEND MEMBERS runtimeExecutable "\"cmake\"" runtimeArgs "${RUNTIME_ARGS}" chip "${CHIP}" connectUnderReset "false")

    if("${IN_REQUEST}" STREQUAL "launch")
        list(APPEND MEMBERS flashingConfig "{ \"flashingEnabled\": true, \"haltAfterReset\": false }")
    endif()

    # Core of the project (Prj_VSCode_GetCoreIndex), SVD file (peripheral registers) of the core is an input resolved
    # by CMake - Prj_VSCode_PrintDebugSvd
    # RTT channels of the firmware in the terminal of the debug session (no control block = not shown)
    Prj_VSCode_GetCoreIndex(${IN_MCU} CORE_INDEX)
    set(CORE_MEMBERS coreIndex "${CORE_INDEX}" programBinary "${PROGRAM}" svdFile "\"\${input:svd_${IN_MCU}}\""
                     rttEnabled "true")

    Prj_VSCode_JsonObject(CORE ${CORE_MEMBERS})
    Prj_VSCode_JsonArray(CORES "${CORE}")
    list(APPEND MEMBERS coreConfigs "${CORES}" consoleLogLevel "\"Console\"")

    if(IN_PRELAUNCH)
        Prj_VSCode_JsonString(PRELAUNCH "${IN_PRELAUNCH}")
        list(APPEND MEMBERS preLaunchTask "${PRELAUNCH}")
    endif()

    Prj_VSCode_JsonObject(CONFIG ${MEMBERS})

    set(${OUT_JSON} "${CONFIG}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_ProbeRsBoardConfig
# Description: probe-rs debug configuration of a picked board - a board of this machine or of an IT agent
#              (input debugBoard, connected boards of the detection). The preLaunchTask starts the debug
#              server of the board (Prj_VSCode_ProbeRs.cmake DEBUG_SERVE: here or on the agent over ssh -tt -L)
#              and the configuration connects to it (server 127.0.0.1:<port>); the extension sends the
#              firmware and the SVD file to the server (remoteServerMode), the server needs no file of
#              this machine. The probe of the board is given, so two boards of one MCU are told apart.
#              The input debugBoard is the first member: the other inputs use its value
#              (${input:debugBoard} in their commands) and VS Code resolves the inputs in the order of the
#              members.
#
# OUT_JSON      [out]: JSON debug configuration.
# IN_NAME       [in]:  Name of the configuration.
# IN_PROGRAM    [in]:  Firmware (ELF).
# IN_PRELAUNCH  [in]:  preLaunchTask (VSCODE_DEBUG_SERVE_TASK or VSCODE_DEBUG_SERVE_TEST_TASK).
# IN_CORE_INDEX [in]:  probe-rs coreIndex - the core of the project (Prj_VSCode_GetCoreIndex).
# ------------------------------------------------------------------------------
function(Prj_VSCode_ProbeRsBoardConfig OUT_JSON IN_NAME IN_PROGRAM IN_PRELAUNCH IN_CORE_INDEX)

    Prj_VSCode_JsonString(NAME "${IN_NAME}")
    Prj_VSCode_JsonString(PROGRAM "${IN_PROGRAM}")
    Prj_VSCode_JsonString(PRELAUNCH "${IN_PRELAUNCH}")

    set(MEMBERS type "\"probe-rs-debug\"")
    list(APPEND MEMBERS request "\"launch\"")
    list(APPEND MEMBERS name "${NAME}")
    list(APPEND MEMBERS embiBoard "\"\${input:debugBoard}\"")
    list(APPEND MEMBERS cwd "\"\${workspaceFolder}\"")
    list(APPEND MEMBERS server "\"\${input:debugServer}\"")
    list(APPEND MEMBERS remoteServerMode "true")
    list(APPEND MEMBERS probe "\"\${input:debugProbe}\"")
    list(APPEND MEMBERS chip "\"\${input:debugChip}\"")
    list(APPEND MEMBERS connectUnderReset "false")
    list(APPEND MEMBERS flashingConfig "{ \"flashingEnabled\": true, \"haltAfterReset\": false }")

    set(CORE_MEMBERS coreIndex "${IN_CORE_INDEX}")
    list(APPEND CORE_MEMBERS programBinary "${PROGRAM}")
    list(APPEND CORE_MEMBERS svdFile "\"\${input:debugSvd}\"")
    list(APPEND CORE_MEMBERS rttEnabled "true")

    Prj_VSCode_JsonObject(CORE ${CORE_MEMBERS})
    Prj_VSCode_JsonArray(CORES "${CORE}")

    list(APPEND MEMBERS coreConfigs "${CORES}")
    list(APPEND MEMBERS consoleLogLevel "\"Console\"")
    list(APPEND MEMBERS preLaunchTask "${PRELAUNCH}")

    Prj_VSCode_JsonObject(CONFIG ${MEMBERS})

    set(${OUT_JSON} "${CONFIG}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_DebugServeTask
# Description: preLaunchTask of the debug configurations of a picked board (background task): builds the
#              Debug firmware (IN_BUILD) and starts the debug server of the board (Prj_VSCode_ProbeRs.cmake
#              DEBUG_SERVE). VS Code starts the debug session when the server prints
#              VSCODE_DEBUG_READY_PATTERN, the task ends with the session.
#
# OUT_JSON [out]: JSON task.
# IN_LABEL [in]:  Label of the task.
# IN_BUILD [in]:  ON - the Debug firmware of the MCU of the board is built first.
# ------------------------------------------------------------------------------
function(Prj_VSCode_DebugServeTask OUT_JSON IN_LABEL IN_BUILD)

    Prj_VSCode_JsonString(LABEL "${IN_LABEL}")
    Prj_VSCode_JsonStringArray(ARGS -DFUNCTION_ID=DEBUG_SERVE -DBUILD=${IN_BUILD} -P "${VSCODE_PROBE_RS_SCRIPT}")
    Prj_VSCode_JsonString(BEGIN_PATTERN "${VSCODE_DEBUG_BEGIN_PATTERN}")
    Prj_VSCode_JsonString(READY_PATTERN "${VSCODE_DEBUG_READY_PATTERN}")

    set(BACKGROUND "{ \"activeBegin\": true, \"beginsPattern\": ${BEGIN_PATTERN}, \"endsPattern\": ${READY_PATTERN} }")
    set(LOCATION "[ \"autoDetect\", \"\${workspaceFolder}\" ]")
    set(MATCHER "{ \"base\": \"$gcc\", \"fileLocation\": ${LOCATION}, \"background\": ${BACKGROUND} }")

    set(MEMBERS label "${LABEL}")
    list(APPEND MEMBERS detail "\"Start the debug server of the picked board (this machine or IT agent)\"")
    list(APPEND MEMBERS type "\"process\"")
    list(APPEND MEMBERS command "\"cmake\"")
    list(APPEND MEMBERS args "${ARGS}")
    list(APPEND MEMBERS isBackground "true")
    list(APPEND MEMBERS hide "true")
    list(APPEND MEMBERS problemMatcher "${MATCHER}")

    Prj_VSCode_JsonObject(TASK ${MEMBERS})

    set(${OUT_JSON} "${TASK}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_ShellInput
# Description: Input of debug configurations resolved by CMake (extension Tasks
#              Shell Input): the script of this handler is executed when the
#              debug configuration is started, every line of its output is an
#              option (<value>|<label>|<description>).
#
# OUT_JSON       [out]: JSON input.
# IN_ID          [in]:  ID of the input (${input:<id>}).
# IN_DESCRIPTION [in]:  Description of the input.
# IN_FIRST       [in]:  TRUE - the first line of the output is used without asking.
# ARGN           [in]:  Script parameters (-D...).
# ------------------------------------------------------------------------------
function(Prj_VSCode_ShellInput OUT_JSON IN_ID IN_DESCRIPTION IN_FIRST)

    Prj_VSCode_JsonString(ID "${IN_ID}")
    Prj_VSCode_JsonString(DESCRIPTION "${IN_DESCRIPTION}")
    Prj_VSCode_JsonStringArray(COMMAND_ARGS ${ARGN} -P "${VSCODE_HANDLER}")

    # taskId: the extension finds the input by it - by the command alone the last input with the same
    # command wins (buildBoard of tasks.json took the pick of debugBoard of launch.json). The extension
    # searches the inputs of all folders of a workspace - the project of a core has own task IDs (<core>_<id>,
    # the projects of the cores have the same inputs)
    if(VSCODE_CORE_PROJECT)
        get_filename_component(PROJECT_FOLDER "${PROJECT_ROOT_PATH}" NAME)
        Prj_VSCode_JsonString(TASK_ID "${PROJECT_FOLDER}_${IN_ID}")
    else()
        set(TASK_ID "${ID}")
    endif()

    set(ARG_MEMBERS command "\"cmake\"" commandArgs "${COMMAND_ARGS}" cwd "\"\${workspaceFolder}\""
                    fieldSeparator "\"|\"" description "${DESCRIPTION}" taskId "${TASK_ID}")

    if(IN_FIRST)
        list(APPEND ARG_MEMBERS useFirstResult "true")
    endif()

    Prj_VSCode_JsonObject(INPUT_ARGS ${ARG_MEMBERS})
    Prj_VSCode_JsonObject(INPUT id "${ID}" type "\"command\"" command "\"shellCommand.execute\"" args "${INPUT_ARGS}")

    set(${OUT_JSON} "${INPUT}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_GenerateLaunch
# Description: Generates launch.json - for every MCU debugging of the Debug
#              firmware (build, flash, run), attach to the running firmware and
#              debugging of an integration test firmware, debugging of unit
#              tests (host gdb). The file contains no static values of the
#              project - the chip, the SVD file, the firmware files, the lists of
#              tests and the gdb are resolved by CMake (inputs executed by the
#              handler, DEBUG_CHIP, DEBUG_SVD, DEBUG_FIRMWARE, DEBUG_TESTS and
#              DEBUG_GDB) when the debug configuration is started, thus new tests,
#              the changes of the firmware name and the SVD files of the BSP are
#              used without the initialization.
#
# IN_MCU_LIST       [in]: MCUs of the project.
# IN_DEBUG_MCU_LIST [in]: MCUs of the debug configurations.
# ------------------------------------------------------------------------------
function(Prj_VSCode_GenerateLaunch IN_MCU_LIST IN_DEBUG_MCU_LIST)

    set(CONFIGS "")
    set(INPUTS "")

    # Cores of the MCUs (core of the project of a core - Prj_VSCode_GetCoreIndex)
    IntegrationTesting_ReadMcuIdentification(IDENTIFIED_MCUS "${VSCODE_RAL_PRESETS_FILE}")

    foreach(MCU IN LISTS IN_DEBUG_MCU_LIST)

        # Firmware of the MCU (build directory and file name of the project)
        Prj_VSCode_ShellInput(FIRMWARE_INPUT "firmware_${MCU}" "Debug firmware of ${MCU}" TRUE
                              -DFUNCTION_ID=DEBUG_FIRMWARE -DMCU=${MCU} -DBUILD_TYPE=Debug)

        Prj_VSCode_ShellInput(CHIP_INPUT "chip_${MCU}" "probe-rs chip of ${MCU}" TRUE
                              -DFUNCTION_ID=DEBUG_CHIP -DMCU=${MCU})

        Prj_VSCode_ShellInput(SVD_INPUT "svd_${MCU}" "SVD file of ${MCU} (module Svd of the BSP)" TRUE
                              -DFUNCTION_ID=DEBUG_SVD -DMCU=${MCU})

        Prj_VSCode_ShellInput(IT_INPUT "itTest_${MCU}" "Integration test of ${MCU} (built by task EmBi: Integration tests)" FALSE
                              -DFUNCTION_ID=DEBUG_TESTS -DTEST_TYPE=IT -DMCU=${MCU})

        list(APPEND INPUTS "${CHIP_INPUT}" "${SVD_INPUT}" "${FIRMWARE_INPUT}" "${IT_INPUT}")

        Prj_VSCode_ProbeRsConfig(DEBUG_CONFIG "EmBi: Debug ${MCU}" launch ${MCU}
                                 "\${input:firmware_${MCU}}" "EmBi: Prepare ${MCU}_Debug")
        Prj_VSCode_ProbeRsConfig(ATTACH_CONFIG "EmBi: Attach ${MCU}" attach ${MCU}
                                 "\${input:firmware_${MCU}}" "${VSCODE_PROVIDE_PROBE_RS_TASK} ${MCU}")
        Prj_VSCode_ProbeRsConfig(IT_CONFIG "EmBi: Debug integration test ${MCU}" launch ${MCU}
                                 "\${input:itTest_${MCU}}" "${VSCODE_PROVIDE_PROBE_RS_TASK} ${MCU}")

        list(APPEND CONFIGS "${DEBUG_CONFIG}" "${ATTACH_CONFIG}" "${IT_CONFIG}")

        # Unit tests of the MCU - host executables of its unit test build, host gdb of its preset
        Prj_VSCode_JsonObject(PRETTY_PRINT description "\"Enable pretty-printing\""
                              text "\"-enable-pretty-printing\"" ignoreFailures "true")
        Prj_VSCode_JsonArray(SETUP_COMMANDS "${PRETTY_PRINT}")

        Prj_VSCode_JsonObject(UT_CONFIG type "\"cppdbg\"" request "\"launch\"" name "\"EmBi: Debug unit test ${MCU}\""
                              program "\"\${input:utTest_${MCU}}\""
                              cwd "\"\${workspaceFolder}\"" stopAtEntry "false" externalConsole "false"
                              MIMode "\"gdb\"" miDebuggerPath "\"\${input:gdb_${MCU}}\"" setupCommands "${SETUP_COMMANDS}")

        Prj_VSCode_ShellInput(UT_INPUT "utTest_${MCU}" "Unit test of ${MCU} (built by task EmBi: Unit tests)" FALSE
                              -DFUNCTION_ID=DEBUG_TESTS -DTEST_TYPE=UT -DMCU=${MCU})
        Prj_VSCode_ShellInput(GDB_INPUT "gdb_${MCU}" "Host gdb of the unit tests of ${MCU}" TRUE
                              -DFUNCTION_ID=DEBUG_GDB -DMCU=${MCU})

        list(APPEND CONFIGS "${UT_CONFIG}")
        list(APPEND INPUTS "${UT_INPUT}" "${GDB_INPUT}")

    endforeach()

    # Debugging of a picked board - boards of this machine and of the IT agents of ItHosts.json (detected
    # when the configuration is started), the chip, the SVD file, the firmware and the debug server resolved
    # from the picked board
    set(TARGET_ARG "-DTARGET=\${input:debugBoard}")

    Prj_VSCode_ShellInput(BOARD_IN debugBoard "Board to debug" FALSE -DFUNCTION_ID=PICK_DEBUG_BOARD)
    Prj_VSCode_ShellInput(SERVER_IN debugServer "Debug server" TRUE -DFUNCTION_ID=DEBUG_BOARD_SERVER ${TARGET_ARG})
    Prj_VSCode_ShellInput(PROBE_IN debugProbe "Probe" TRUE -DFUNCTION_ID=DEBUG_BOARD_PROBE ${TARGET_ARG})
    Prj_VSCode_ShellInput(CHIP_IN debugChip "probe-rs chip" TRUE -DFUNCTION_ID=DEBUG_BOARD_CHIP ${TARGET_ARG})
    Prj_VSCode_ShellInput(SVD_IN debugSvd "SVD file" TRUE -DFUNCTION_ID=DEBUG_BOARD_SVD ${TARGET_ARG})
    Prj_VSCode_ShellInput(FW_IN debugFirmware "Debug firmware" TRUE -DFUNCTION_ID=DEBUG_BOARD_FIRMWARE ${TARGET_ARG})
    Prj_VSCode_ShellInput(TEST_IN debugTest "Integration test" FALSE -DFUNCTION_ID=DEBUG_BOARD_TESTS ${TARGET_ARG})

    list(APPEND INPUTS "${BOARD_IN}" "${SERVER_IN}" "${PROBE_IN}" "${CHIP_IN}" "${SVD_IN}" "${FW_IN}" "${TEST_IN}")

    # The board is picked when the configuration is started - the core of the project in the first MCU of the project
    # (the MCUs of a project of a core have the cores in the same order)
    set(BOARD_CORE_INDEX 0)
    if(IN_MCU_LIST)
        list(GET IN_MCU_LIST 0 FIRST_MCU)
        Prj_VSCode_GetCoreIndex(${FIRST_MCU} BOARD_CORE_INDEX)
    endif()

    Prj_VSCode_ProbeRsBoardConfig(BOARD_CONFIG
                                  "EmBi: Debug on board"
                                  "\${input:debugFirmware}"
                                  "${VSCODE_DEBUG_SERVE_TASK}"
                                  ${BOARD_CORE_INDEX})
    Prj_VSCode_ProbeRsBoardConfig(BOARD_TEST_CONFIG
                                  "EmBi: Debug integration test on board"
                                  "\${input:debugTest}"
                                  "${VSCODE_DEBUG_SERVE_TEST_TASK}"
                                  ${BOARD_CORE_INDEX})

    list(APPEND CONFIGS "${BOARD_CONFIG}" "${BOARD_TEST_CONFIG}")

    Prj_VSCode_JsonArray(CONFIGS ${CONFIGS})
    Prj_VSCode_JsonArray(INPUTS ${INPUTS})

    Prj_VSCode_JsonObject(CONTENT version "\"0.2.0\"" configurations "${CONFIGS}" inputs "${INPUTS}")

    Prj_VSCode_WriteFile("launch.json" "${CONTENT}")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_WorkspaceInput
# Description: Input of the VS Code workspace of the projects of the cores - the input of a project of a core executed
#              in the folder of a core (${workspaceFolder:<core>}) with an own task ID (workspace_<task ID>).
#
# IN_OUT_JSON [in/out]: JSON input (Prj_VSCode_ShellInput).
# IN_CORE     [in]:     Core (folder of the workspace).
# ------------------------------------------------------------------------------
function(Prj_VSCode_WorkspaceInput IN_OUT_JSON IN_CORE)

    string(REPLACE "\"cwd\": \"\${workspaceFolder}\"" "\"cwd\": \"\${workspaceFolder:${IN_CORE}}\"" INPUT
           "${${IN_OUT_JSON}}")
    string(REPLACE "\"taskId\": \"" "\"taskId\": \"workspace_" INPUT "${INPUT}")

    set(${IN_OUT_JSON} "${INPUT}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_AllCoresLaunch
# Description: Debug configurations "EmBi: Debug all cores <MCU>" of the VS Code workspace of the projects of the cores
#              (project of a core only) - every debug MCU with all cores of the projects: one session of the extension
#              cortex-debug with the GDB server of probe-rs (all cores of one architecture as threads, no RTT), the
#              symbols of the Debug firmware of every core, the SVD file of the first core, arm-none-eabi-gdb of the
#              artifacts. The preLaunchTask (background task "EmBi: Prepare all cores <MCU>_Debug",
#              Prj_VSCode_ServeAllCores) builds and flashes the firmware of all cores and starts the GDB server; the
#              session attaches to the running firmware (the cores are halted). Sets in the parent scope
#              VSCODE_WORKSPACE_LAUNCH_CONFIGS, VSCODE_WORKSPACE_LAUNCH_INPUTS and VSCODE_WORKSPACE_LAUNCH_TASKS (empty
#              in a project of a single-core MCU).
#
# IN_DEBUG_MCU_LIST [in]: MCUs of the debug configurations.
# ------------------------------------------------------------------------------
function(Prj_VSCode_AllCoresLaunch IN_DEBUG_MCU_LIST)

    set(CONFIGS "")
    set(INPUTS "")
    set(TASKS "")

    if(VSCODE_CORE_PROJECT)
        Prj_VSCode_GetCoreProjects(CORES)
    else()
        set(CORES "")
    endif()

    list(LENGTH CORES CORE_COUNT)

    if(CORE_COUNT GREATER 1)

        list(GET CORES 0 FIRST_CORE)
        IntegrationTesting_ReadMcuIdentification(IDENTIFIED_MCUS "${VSCODE_RAL_PRESETS_FILE}")

        foreach(MCU IN LISTS IN_DEBUG_MCU_LIST)

            # MCU with the cores of all projects
            set(ALL_CORES TRUE)
            foreach(CORE IN LISTS CORES)
                if(NOT CORE IN_LIST IT_MCU_${MCU}_CORES)
                    set(ALL_CORES FALSE)
                endif()
            endforeach()

            if(NOT ALL_CORES)
                continue()
            endif()

            # Debug firmware of every core - resolved in the folder of its project
            set(SYMBOLS "")
            foreach(CORE IN LISTS CORES)
                Prj_VSCode_ShellInput(FIRMWARE_INPUT "allCores_firmware_${CORE}_${MCU}"
                                      "Debug firmware of ${MCU} (core ${CORE})" TRUE
                                      -DFUNCTION_ID=DEBUG_FIRMWARE -DMCU=${MCU} -DBUILD_TYPE=Debug)
                Prj_VSCode_WorkspaceInput(FIRMWARE_INPUT ${CORE})
                list(APPEND INPUTS "${FIRMWARE_INPUT}")
                list(APPEND SYMBOLS "\${input:allCores_firmware_${CORE}_${MCU}}")
            endforeach()

            Prj_VSCode_ShellInput(SVD_INPUT "allCores_svd_${MCU}" "SVD file of ${MCU} (core ${FIRST_CORE})" TRUE
                                  -DFUNCTION_ID=DEBUG_SVD -DMCU=${MCU})
            Prj_VSCode_ShellInput(GDB_INPUT "allCores_gdb_${MCU}" "arm-none-eabi-gdb of ${MCU}" TRUE
                                  -DFUNCTION_ID=TARGET_GDB -DMCU=${MCU})
            Prj_VSCode_ShellInput(SERVER_INPUT "allCores_gdbServer_${MCU}" "GDB server of all cores of ${MCU}" TRUE
                                  -DFUNCTION_ID=GDB_SERVER -DMCU=${MCU})

            foreach(INPUT_NAME IN ITEMS SVD_INPUT GDB_INPUT SERVER_INPUT)
                Prj_VSCode_WorkspaceInput(${INPUT_NAME} ${FIRST_CORE})
                list(APPEND INPUTS "${${INPUT_NAME}}")
            endforeach()

            set(PREPARE_LABEL "EmBi: Prepare all cores ${MCU}_Debug")
            Prj_VSCode_JsonStringArray(SYMBOL_FILES ${SYMBOLS})
            Prj_VSCode_JsonString(PREPARE_JSON "${PREPARE_LABEL}")

            set(MEMBERS type "\"cortex-debug\"")
            list(APPEND MEMBERS request "\"attach\"")
            list(APPEND MEMBERS name "\"EmBi: Debug all cores ${MCU}\"")
            list(APPEND MEMBERS cwd "\"\${workspaceFolder:${FIRST_CORE}}\"")
            list(APPEND MEMBERS servertype "\"external\"")
            list(APPEND MEMBERS gdbTarget "\"\${input:allCores_gdbServer_${MCU}}\"")
            list(APPEND MEMBERS gdbPath "\"\${input:allCores_gdb_${MCU}}\"")
            list(APPEND MEMBERS executable "\"\${input:allCores_firmware_${FIRST_CORE}_${MCU}}\"")
            list(APPEND MEMBERS symbolFiles "${SYMBOL_FILES}")
            list(APPEND MEMBERS svdFile "\"\${input:allCores_svd_${MCU}}\"")
            list(APPEND MEMBERS preLaunchTask "${PREPARE_JSON}")
            Prj_VSCode_JsonObject(CONFIG ${MEMBERS})
            list(APPEND CONFIGS "${CONFIG}")

            # Background task: firmware of all cores, GDB server
            Prj_VSCode_JsonStringArray(ARGS -DFUNCTION_ID=SERVE_ALL_CORES -DMCU=${MCU} -P "${VSCODE_HANDLER}")
            Prj_VSCode_JsonString(BEGIN_PATTERN "${VSCODE_DEBUG_BEGIN_PATTERN}")
            Prj_VSCode_JsonString(READY_PATTERN "${VSCODE_GDB_READY_PATTERN}")
            set(BACKGROUND "{ \"activeBegin\": true, \"beginsPattern\": ${BEGIN_PATTERN}, ")
            string(APPEND BACKGROUND "\"endsPattern\": ${READY_PATTERN} }")
            set(LOCATION "[ \"autoDetect\", \"\${workspaceFolder:${FIRST_CORE}}\" ]")
            set(MATCHER "{ \"base\": \"$gcc\", \"fileLocation\": ${LOCATION}, \"background\": ${BACKGROUND} }")

            set(MEMBERS label "${PREPARE_JSON}")
            list(APPEND MEMBERS detail "\"Build and flash the Debug firmware of all cores of ${MCU}, start the GDB server\"")
            list(APPEND MEMBERS type "\"process\"")
            list(APPEND MEMBERS command "\"cmake\"")
            list(APPEND MEMBERS args "${ARGS}")
            list(APPEND MEMBERS options "{ \"cwd\": \"\${workspaceFolder:${FIRST_CORE}}\" }")
            list(APPEND MEMBERS isBackground "true")
            list(APPEND MEMBERS hide "true")
            list(APPEND MEMBERS problemMatcher "${MATCHER}")
            Prj_VSCode_JsonObject(TASK ${MEMBERS})
            list(APPEND TASKS "${TASK}")

        endforeach()

    endif()

    set(VSCODE_WORKSPACE_LAUNCH_CONFIGS "${CONFIGS}" PARENT_SCOPE)
    set(VSCODE_WORKSPACE_LAUNCH_INPUTS  "${INPUTS}"  PARENT_SCOPE)
    set(VSCODE_WORKSPACE_LAUNCH_TASKS   "${TASKS}"   PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_JsonValue
# Description: JSON text of a member of a parsed JSON object (string(JSON GET)
#              returns raw strings and ON / OFF for booleans).
#
# OUT_JSON   [out]: JSON value.
# IN_CONTENT [in]:  JSON object.
# IN_NAME    [in]:  Member name.
# ------------------------------------------------------------------------------
function(Prj_VSCode_JsonValue OUT_JSON IN_CONTENT IN_NAME)

    string(JSON VALUE_TYPE TYPE "${IN_CONTENT}" "${IN_NAME}")
    string(JSON VALUE GET "${IN_CONTENT}" "${IN_NAME}")

    if(VALUE_TYPE STREQUAL "STRING")
        Prj_VSCode_JsonString(VALUE "${VALUE}")
    elseif(VALUE_TYPE STREQUAL "BOOLEAN")
        if(VALUE)
            set(VALUE "true")
        else()
            set(VALUE "false")
        endif()
    elseif(VALUE_TYPE STREQUAL "NULL")
        set(VALUE "null")
    endif()

    set(${OUT_JSON} "${VALUE}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_GenerateSettings
# Description: Generates settings.json - settings of the platform are set,
#              other settings of an existing file are kept (comments and
#              trailing commas are removed, file is kept as settings.json.bak if
#              it was not generated).
# ------------------------------------------------------------------------------
function(Prj_VSCode_GenerateSettings)

    set(SETTINGS "{}")
    set(SETTINGS_FILE "${VSCODE_DIR}/settings.json")

    if(EXISTS "${SETTINGS_FILE}")

        file(READ "${SETTINGS_FILE}" OLD_SETTINGS)

        # JSON with comments - line comments and trailing commas removed
        string(REGEX REPLACE "\n[ \t]*//[^\n]*" "\n" OLD_SETTINGS "\n${OLD_SETTINGS}")
        string(REGEX REPLACE ",([ \t\r\n]*[]}])" "\\1" OLD_SETTINGS "${OLD_SETTINGS}")

        string(JSON SETTINGS_TYPE ERROR_VARIABLE SETTINGS_ERROR TYPE "${OLD_SETTINGS}")

        if(NOT SETTINGS_ERROR AND SETTINGS_TYPE STREQUAL "OBJECT")
            set(SETTINGS "${OLD_SETTINGS}")
        else()
            message(WARNING "settings.json cannot be parsed (${SETTINGS_ERROR}) - generated without its settings.")
        endif()

    endif()

    # Settings of the platform
    string(JSON SETTINGS SET "${SETTINGS}" "cmake.useCMakePresets" "\"always\"")
    string(JSON SETTINGS SET "${SETTINGS}" "cmake.configureOnOpen" "false")
    string(JSON SETTINGS SET "${SETTINGS}" "C_Cpp.default.configurationProvider" "\"ms-vscode.cmake-tools\"")

    # Merged object settings
    foreach(ITEM IN ITEMS "search.exclude|Build/**|true"
                          "files.watcherExclude|**/Build/**|true"
                          "files.associations|*.c.in|\"c\""
                          "files.associations|*.h.in|\"c\"")
        string(REPLACE "|" ";" ITEM "${ITEM}")
        list(GET ITEM 0 NAME)
        list(GET ITEM 1 KEY)
        list(GET ITEM 2 VALUE)

        string(JSON NAME_TYPE ERROR_VARIABLE NAME_ERROR TYPE "${SETTINGS}" "${NAME}")
        if(NAME_ERROR OR NOT NAME_TYPE STREQUAL "OBJECT")
            string(JSON SETTINGS SET "${SETTINGS}" "${NAME}" "{}")
        endif()
        string(JSON SETTINGS SET "${SETTINGS}" "${NAME}" "${KEY}" "${VALUE}")
    endforeach()

    # Default settings (kept if set)
    string(JSON RULERS ERROR_VARIABLE RULERS_ERROR GET "${SETTINGS}" "editor.rulers")
    if(RULERS_ERROR)
        # Max line length of the coding style
        string(JSON SETTINGS SET "${SETTINGS}" "editor.rulers" "[ 120 ]")
    endif()

    # Members of the formatted output
    string(JSON MEMBERS_CNT LENGTH "${SETTINGS}")
    math(EXPR MEMBERS_LAST "${MEMBERS_CNT} - 1")

    set(MEMBERS "")

    foreach(MEMBER_IDX RANGE ${MEMBERS_LAST})
        string(JSON NAME MEMBER "${SETTINGS}" ${MEMBER_IDX})
        Prj_VSCode_JsonValue(VALUE "${SETTINGS}" "${NAME}")
        string(REPLACE ";" "\\;" VALUE "${VALUE}")
        list(APPEND MEMBERS "${NAME}" "${VALUE}")
    endforeach()

    Prj_VSCode_JsonObject(CONTENT ${MEMBERS})

    Prj_VSCode_WriteFile("settings.json" "${CONTENT}")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_GetMissingExtensions
# Description: Recommended extensions (VSCODE_EXTENSIONS) that are not installed.
#              The extension folders of VSCode (VSCode, Insiders, VSCodium,
#              Cursor, remote server of the user) are searched for the folder
#              <id>-<version>, extensions uninstalled but not yet deleted
#              (.obsolete) are ignored. The code command is not needed.
#
# OUT_LIST [out]: Missing extensions (IDs).
# ------------------------------------------------------------------------------
function(Prj_VSCode_GetMissingExtensions OUT_LIST)

    set(EXTENSION_DIRS "")

    foreach(HOME_VAR IN ITEMS USERPROFILE HOME)
        if(DEFINED ENV{${HOME_VAR}})
            file(TO_CMAKE_PATH "$ENV{${HOME_VAR}}" HOME_DIR)
            foreach(SUB_DIR IN ITEMS .vscode .vscode-insiders .vscode-oss .vscode-server .vscode-server-insiders .cursor)
                if(IS_DIRECTORY "${HOME_DIR}/${SUB_DIR}/extensions")
                    list(APPEND EXTENSION_DIRS "${HOME_DIR}/${SUB_DIR}/extensions")
                endif()
            endforeach()
        endif()
    endforeach()

    list(REMOVE_DUPLICATES EXTENSION_DIRS)

    set(MISSING "")

    foreach(EXTENSION IN LISTS VSCODE_EXTENSIONS)

        string(TOLOWER "${EXTENSION}" EXTENSION_LOWER)

        set(INSTALLED FALSE)

        foreach(EXTENSION_DIR IN LISTS EXTENSION_DIRS)

            set(OBSOLETE "")

            if(EXISTS "${EXTENSION_DIR}/.obsolete")
                file(READ "${EXTENSION_DIR}/.obsolete" OBSOLETE)
            endif()

            file(GLOB FOLDERS LIST_DIRECTORIES true "${EXTENSION_DIR}/${EXTENSION_LOWER}-[0-9]*")

            foreach(FOLDER IN LISTS FOLDERS)
                get_filename_component(FOLDER_NAME "${FOLDER}" NAME)
                string(FIND "${OBSOLETE}" "\"${FOLDER_NAME}\"" OBSOLETE_POS)
                if(IS_DIRECTORY "${FOLDER}" AND OBSOLETE_POS EQUAL -1)
                    set(INSTALLED TRUE)
                endif()
            endforeach()

        endforeach()

        if(NOT INSTALLED)
            list(APPEND MISSING "${EXTENSION}")
        endif()

    endforeach()

    set(${OUT_LIST} "${MISSING}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_PrintMissingExtensions
# Description: Prints the missing extensions to the standard output, one per line
#              (nothing if all are installed) - the Setup menu offers their
#              installation.
# ------------------------------------------------------------------------------
function(Prj_VSCode_PrintMissingExtensions)

    Prj_VSCode_GetMissingExtensions(MISSING)

    if(MISSING)
        Prj_VSCode_PrintOptions(${MISSING})
    endif()
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_InstallExtensions
# Description: Installs the missing recommended extensions by the code command of
#              VSCode (the extensions are downloaded from the Marketplace).
# ------------------------------------------------------------------------------
function(Prj_VSCode_InstallExtensions)

    Prj_VSCode_GetMissingExtensions(MISSING)

    if(NOT MISSING)
        message("All recommended extensions are installed.")
        return()
    endif()

    find_program(VSCODE_CLI NAMES code.cmd code NO_CACHE)

    if(NOT VSCODE_CLI)
        list(JOIN MISSING ", " MISSING_TEXT)
        message(FATAL_ERROR "The code command of VSCode was not found - install the extensions in VSCode (Extensions, "
                            "recommended): ${MISSING_TEXT}.")
    endif()

    foreach(EXTENSION IN LISTS MISSING)

        message("Installing ${EXTENSION} ...")

        execute_process(COMMAND "${VSCODE_CLI}" --install-extension ${EXTENSION} RESULT_VARIABLE INSTALL_RESULT)

        if(NOT INSTALL_RESULT EQUAL 0)
            message(WARNING "Installation of ${EXTENSION} failed (${INSTALL_RESULT}).")
        endif()

    endforeach()

    message("Restart VSCode (or reload the window) to activate the extensions.")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_Init
# Description: Generates VSCode configuration of the project.
#
# IN_MCU_IDS [in]: Numerical IDs of the MCUs of debug configurations separated
#                  by comma (Prj_VSCode_PrintMcuList), 0 = all MCUs. The MCUs are
#                  selected by the user, no hardware is accessed. An MCU name is
#                  taken as it is (projects of the cores - Prj_VSCode_InitCoreProjects).
# IN_FIRMWARE_NAME [in]: Firmware name (without build type) set to the root
#                  CMakeLists.txt, empty = current name is kept.
# ------------------------------------------------------------------------------
function(Prj_VSCode_Init IN_MCU_IDS IN_FIRMWARE_NAME)

    Build_Handler_GetMcuList(MCU_LIST)

    string(REPLACE "," ";" MCU_IDS "${IN_MCU_IDS}")
    string(REPLACE " " "" MCU_IDS "${MCU_IDS}")
    list(REMOVE_ITEM MCU_IDS "")

    # "0" (all MCUs) is false as a CMake condition - compared as text
    if("${MCU_IDS}" STREQUAL "")
        message(FATAL_ERROR "No MCU selected - enter MCU IDs of the debug configurations (0 = all MCUs).")
    endif()

    # MCUs of the debug configurations - all or selected
    set(DEBUG_MCU_LIST "")

    if("0" IN_LIST MCU_IDS)

        set(DEBUG_MCU_LIST "${MCU_LIST}")

    else()

        foreach(MCU_ID IN LISTS MCU_IDS)
            if(MCU_ID IN_LIST MCU_LIST)
                set(MCU "${MCU_ID}")
            else()
                Build_Handler_GetListItem("${MCU_LIST}" "${MCU_ID}" "MCU" MCU)
            endif()
            list(APPEND DEBUG_MCU_LIST "${MCU}")
        endforeach()

    endif()

    Prj_VSCode_SetFirmwareName("${IN_FIRMWARE_NAME}")

    # Option bytes of the MCUs of the project in the project CMakeLists.txt
    OptionBytes_UpdateSection("${PROJECT_ROOT_PATH}/CMakeLists.txt" "${VSCODE_RAL_PRESETS_FILE}" "${MCU_LIST}")

    list(REMOVE_DUPLICATES DEBUG_MCU_LIST)

    list(JOIN DEBUG_MCU_LIST ", " DEBUG_MCUS_TEXT)

    message("")
    message("Debug configurations: ${DEBUG_MCUS_TEXT}")
    message("")

    file(MAKE_DIRECTORY "${VSCODE_DIR}")

    Prj_VSCode_GenerateTasks("${MCU_LIST}" "${DEBUG_MCU_LIST}")
    Prj_VSCode_GenerateLaunch("${MCU_LIST}" "${DEBUG_MCU_LIST}")
    Prj_VSCode_GenerateSettings()

    Prj_VSCode_JsonObject(CPP_CONFIG name "\"EmBi\"" configurationProvider "\"ms-vscode.cmake-tools\"")
    Prj_VSCode_JsonArray(CPP_CONFIGS "${CPP_CONFIG}")
    Prj_VSCode_JsonObject(CPP_CONTENT configurations "${CPP_CONFIGS}" version "4")
    Prj_VSCode_WriteFile("c_cpp_properties.json" "${CPP_CONTENT}")

    Prj_VSCode_JsonStringArray(EXTENSIONS ${VSCODE_EXTENSIONS})
    Prj_VSCode_JsonObject(EXTENSIONS_CONTENT recommendations "${EXTENSIONS}")
    Prj_VSCode_WriteFile("extensions.json" "${EXTENSIONS_CONTENT}")

    Prj_VSCode_AllCoresLaunch("${DEBUG_MCU_LIST}")
    Prj_VSCode_GenerateWorkspace("${VSCODE_WORKSPACE_TASKS}" "${VSCODE_WORKSPACE_INPUTS}")

    message("")

    if(VSCODE_CORE_PROJECT)
        get_filename_component(PROJECT_FOLDER "${PROJECT_ROOT_PATH}" NAME)
        message("VSCode project of the core ${PROJECT_FOLDER} initialized.")
    else()
        message("VSCode project initialized - open the project root folder in VSCode.")
        Prj_VSCode_InitCoreProjects("${MCU_LIST}" "${DEBUG_MCU_LIST}" "${IN_FIRMWARE_NAME}")
    endif()

    Prj_VSCode_GetMissingExtensions(MISSING_EXTENSIONS)

    if(MISSING_EXTENSIONS)
        list(JOIN MISSING_EXTENSIONS ", " MISSING_EXTENSIONS_TEXT)
        message("Not installed extensions used by the generated configuration: ${MISSING_EXTENSIONS_TEXT}")
        message("(the Setup menu offers their installation, or install the recommended extensions in VSCode)")
    else()
        # All recommended extensions are installed
    endif()
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_InitCoreProjects
# Description: Projects of the cores of a multi-core MCU - the VSCode project
#              initialization of a project whose MCUs (BSP) include a multi-core
#              MCU (cores of the identification of its Ral preset) creates the
#              project of every core and the workspace of the projects (Prj_Handler
#              CORE_PROJECTS with the cores of the first multi-core MCU). The
#              projects of the cores get the debug configurations of the selected
#              multi-core MCUs (all MCUs of the core if none is selected) and the
#              firmware name with the core (<name>_<core>).
#
# IN_MCU_LIST       [in]: MCUs of the project.
# IN_DEBUG_MCU_LIST [in]: MCUs of the debug configurations.
# IN_FIRMWARE_NAME  [in]: Firmware name (empty = the names of the projects of the cores are kept).
# ------------------------------------------------------------------------------
function(Prj_VSCode_InitCoreProjects IN_MCU_LIST IN_DEBUG_MCU_LIST IN_FIRMWARE_NAME)

    IntegrationTesting_ReadMcuIdentification(IDENTIFIED_MCUS "${VSCODE_RAL_PRESETS_FILE}")

    set(MULTI_CORE_MCUS "")
    foreach(MCU IN LISTS IN_MCU_LIST)
        list(LENGTH IT_MCU_${MCU}_CORES CORE_COUNT)
        if(CORE_COUNT GREATER 1)
            list(APPEND MULTI_CORE_MCUS "${MCU}")
        endif()
    endforeach()

    if(NOT MULTI_CORE_MCUS)
        return()
    endif()

    set(DEBUG_MCUS "")
    foreach(MCU IN LISTS IN_DEBUG_MCU_LIST)
        if(MCU IN_LIST MULTI_CORE_MCUS)
            list(APPEND DEBUG_MCUS "${MCU}")
        endif()
    endforeach()

    if(DEBUG_MCUS)
        list(JOIN DEBUG_MCUS "," CORE_MCU_IDS)
    else()
        set(CORE_MCU_IDS 0)
    endif()

    list(GET MULTI_CORE_MCUS 0 CORES_MCU)
    list(JOIN MULTI_CORE_MCUS ", " MULTI_CORE_MCUS_TEXT)

    message("")
    message("Multi-core MCUs: ${MULTI_CORE_MCUS_TEXT} - projects of the cores of ${CORES_MCU}")

    execute_process(COMMAND "${CMAKE_COMMAND}" -DFUNCTION_ID=CORE_PROJECTS
                                               "-DMCU=${CORES_MCU}"
                                               "-DMCU_IDS=${CORE_MCU_IDS}"
                                               "-DFIRMWARE_NAME=${IN_FIRMWARE_NAME}"
                                               -P "${VSCODE_PRJ_HANDLER}"
                    WORKING_DIRECTORY "${PROJECT_ROOT_PATH}"
                    RESULT_VARIABLE CORES_RESULT)

    if(NOT CORES_RESULT EQUAL 0)
        message(FATAL_ERROR "Projects of the cores of ${CORES_MCU} were not created.")
    endif()

    get_filename_component(WORKSPACE_NAME "${PLATFORM_ROOT_PATH}" NAME)
    message("Projects of the cores - open ${WORKSPACE_NAME}.code-workspace in VSCode.")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_GetCoreProjects
# Description: Projects of the cores of a multi-core MCU - the cores of
#              TARGET_CORES of the project CMakeLists.txt (and the core of the
#              project) whose project exists in the platform root folder, in
#              the order of TARGET_CORES.
#
# OUT_CORES [out]: Cores (folders of their projects).
# ------------------------------------------------------------------------------
function(Prj_VSCode_GetCoreProjects OUT_CORES)

    set(TARGET_CORES "")
    file(STRINGS "${PROJECT_ROOT_PATH}/CMakeLists.txt" CORES_LINE REGEX "^[ \t]*set\\(TARGET_CORES[ \t]+\"[^\"]*\"")
    if(CORES_LINE MATCHES "set\\(TARGET_CORES[ \t]+\"([^\"]*)\"")
        # file(STRINGS) returns ";" of the line as "\;"
        string(REPLACE "\\;" ";" TARGET_CORES "${CMAKE_MATCH_1}")
    endif()

    get_filename_component(PROJECT_FOLDER "${PROJECT_ROOT_PATH}" NAME)
    if(NOT PROJECT_FOLDER IN_LIST TARGET_CORES)
        list(APPEND TARGET_CORES "${PROJECT_FOLDER}")
    endif()

    set(CORES "")
    foreach(CORE IN LISTS TARGET_CORES)
        if(EXISTS "${PLATFORM_ROOT_PATH}/${CORE}/CMakeLists.txt")
            list(APPEND CORES "${CORE}")
        endif()
    endforeach()

    set(${OUT_CORES} "${CORES}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_GenerateWorkspace
# Description: Writes the VS Code workspace of the projects of the cores of a
#              multi-core MCU (project of a core - the project root folder is a
#              subfolder of the platform root folder): <platform root>/<name of
#              the platform root>.code-workspace with the projects of the cores
#              (Prj_VSCode_GetCoreProjects), the shared Bsp and the tasks of the
#              projects - once, with the selection of the core (the tasks of the
#              projects are hidden) - and the debug configurations of all cores
#              (VSCODE_WORKSPACE_LAUNCH_* of Prj_VSCode_AllCoresLaunch). A project
#              in the platform root folder has no workspace.
#
# IN_TASKS  [in]: Tasks of the workspace (Prj_VSCode_GenerateTasks).
# IN_INPUTS [in]: Inputs of the tasks of the workspace.
# ------------------------------------------------------------------------------
function(Prj_VSCode_GenerateWorkspace IN_TASKS IN_INPUTS)

    if(NOT VSCODE_CORE_PROJECT)
        return()
    endif()

    Prj_VSCode_GetCoreProjects(CORES)

    set(FOLDERS "")
    foreach(CORE IN LISTS CORES)
        Prj_VSCode_JsonString(CORE_JSON "${CORE}")
        Prj_VSCode_JsonObject(FOLDER name "${CORE_JSON}" path "${CORE_JSON}")
        list(APPEND FOLDERS "${FOLDER}")
    endforeach()

    Prj_VSCode_JsonObject(FOLDER name "\"Bsp\"" path "\"Bsp\"")
    list(APPEND FOLDERS "${FOLDER}")

    Prj_VSCode_JsonArray(FOLDERS_JSON ${FOLDERS})
    Prj_VSCode_JsonObject(SETTINGS "cmake.configureOnOpen" "false")

    Prj_VSCode_JsonArray(TASKS_JSON ${IN_TASKS} ${VSCODE_WORKSPACE_LAUNCH_TASKS})
    Prj_VSCode_JsonArray(INPUTS_JSON ${IN_INPUTS})
    Prj_VSCode_JsonObject(TASKS_CONTENT version "\"2.0.0\"" presentation "{ \"panel\": \"dedicated\", \"clear\": true }"
                          tasks "${TASKS_JSON}" inputs "${INPUTS_JSON}")

    set(WORKSPACE_MEMBERS folders "${FOLDERS_JSON}" settings "${SETTINGS}" tasks "${TASKS_CONTENT}")

    # Debug configurations of all cores (Prj_VSCode_AllCoresLaunch) - the extension cortex-debug recommended by the
    # workspace only (the projects keep their recommendations)
    if(VSCODE_WORKSPACE_LAUNCH_CONFIGS)
        Prj_VSCode_JsonArray(LAUNCH_CONFIGS_JSON ${VSCODE_WORKSPACE_LAUNCH_CONFIGS})
        Prj_VSCode_JsonArray(LAUNCH_INPUTS_JSON ${VSCODE_WORKSPACE_LAUNCH_INPUTS})
        Prj_VSCode_JsonObject(LAUNCH_CONTENT version "\"0.2.0\"" configurations "${LAUNCH_CONFIGS_JSON}"
                              inputs "${LAUNCH_INPUTS_JSON}")
        Prj_VSCode_JsonStringArray(WORKSPACE_EXTENSIONS ${VSCODE_GDB_EXTENSION})
        Prj_VSCode_JsonObject(EXTENSIONS_CONTENT recommendations "${WORKSPACE_EXTENSIONS}")
        list(APPEND WORKSPACE_MEMBERS launch "${LAUNCH_CONTENT}" extensions "${EXTENSIONS_CONTENT}")
    endif()

    Prj_VSCode_JsonObject(WORKSPACE_CONTENT ${WORKSPACE_MEMBERS})

    get_filename_component(WORKSPACE_NAME "${PLATFORM_ROOT_PATH}" NAME)
    set(WORKSPACE_FILE "${PLATFORM_ROOT_PATH}/${WORKSPACE_NAME}.code-workspace")

    file(WRITE "${WORKSPACE_FILE}" "${VSCODE_GENERATED_MARK}\n${WORKSPACE_CONTENT}\n")
    message("Generated: ${WORKSPACE_NAME}.code-workspace (projects of the cores: ${CORES})")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_RunCores
# Description: Runs a task of the projects of the cores of a multi-core MCU
#              (task of the VS Code workspace, started in the platform root
#              folder) in the project of the selected core or in the projects of
#              all cores one after another. A failed project stops the task.
#
# IN_CORES     [in]: Selected core or VSCODE_ALL_CORES_OPTION.
# IN_ALL_CORES [in]: Cores of the projects separated by "," (order of the run).
# IN_CORE_ARGS [in]: Parameters of cmake in the project of a core separated by "|".
# ------------------------------------------------------------------------------
function(Prj_VSCode_RunCores IN_CORES IN_ALL_CORES IN_CORE_ARGS)

    if("${IN_CORES}" STREQUAL "${VSCODE_ALL_CORES_OPTION}")
        string(REPLACE "," ";" CORES "${IN_ALL_CORES}")
    else()
        set(CORES "${IN_CORES}")
    endif()

    string(REPLACE "|" ";" CORE_ARGS "${IN_CORE_ARGS}")

    foreach(CORE IN LISTS CORES)

        if(NOT EXISTS "${PLATFORM_ROOT_PATH}/${CORE}/CMakeLists.txt")
            message(FATAL_ERROR "Project of the core ${CORE} not found (${PLATFORM_ROOT_PATH}/${CORE}).")
        endif()

        message("")
        message("==================== Project of the core ${CORE} ====================")

        execute_process(COMMAND "${CMAKE_COMMAND}" ${CORE_ARGS}
                        WORKING_DIRECTORY "${PLATFORM_ROOT_PATH}/${CORE}"
                        RESULT_VARIABLE CORE_RESULT)

        if(NOT CORE_RESULT EQUAL 0)
            message(FATAL_ERROR "Project of the core ${CORE} failed - the projects of the next cores are not processed.")
        endif()

    endforeach()
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_PrintMcuList
# Description: Prints MCUs of the project presets.
# ------------------------------------------------------------------------------
function(Prj_VSCode_PrintMcuList)

    Build_Handler_GetMcuList(MCU_LIST)
    Build_Handler_PrintList("All MCUs" ${MCU_LIST})
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_AgentFirmwareCall
# Description: Command of the agent tools (IT agent interface) with a firmware of the board of an IT agent: the
#              files are copied into a folder of the agent (new-package), the command gets the folder, the
#              firmware, the probe, the chip, probe-rs of the version of this machine and the holder of the probe
#              lock, the folder is removed (remove-package).
#
# OUT_ERROR   [out]: Error of the command ("" - done).
# IN_ACTION   [in]:  Action for the errors ("Flash").
# IN_IDX      [in]:  Index of the target (Prj_VSCode_GetTarget).
# IN_FILES    [in]:  Files of the folder, the firmware first.
# IN_CHIP     [in]:  probe-rs chip.
# IN_HOLDER   [in]:  Holder of the probe lock.
# IN_COMMAND  [in]:  Command (flash), its other options follow (ARGN).
# ------------------------------------------------------------------------------
function(Prj_VSCode_AgentFirmwareCall OUT_ERROR IN_ACTION IN_IDX IN_FILES IN_CHIP IN_HOLDER IN_COMMAND)

    set(HOST       "${IT_TARGET_${IN_IDX}_HOST}")
    set(SSH_TARGET "${IT_TARGET_${IN_IDX}_TARGET}")
    set(TEXT       "${IT_TARGET_${IN_IDX}_TEXT}")

    IntegrationTesting_ReadItHosts(HOSTS "${PROJECT_ROOT_PATH}")
    set(TOOLS "${IT_HOST_${HOST}_TOOLS}")

    IntegrationTesting_Get_ProbeRsVersion(PROBE_RS_VERSION "${VSCODE_PROBE_RS}")

    IntegrationTesting_AgentCall(NEW_JSON NEW_ERROR "${SSH_TARGET}" "${TOOLS}" "" new-package)

    if(NOT "${NEW_ERROR}" STREQUAL "")
        message(FATAL_ERROR "${IN_ACTION} of ${TEXT} failed: ${NEW_ERROR}.")
    endif()

    string(JSON REMOTE_DIR GET "${NEW_JSON}" dir)

    if(NOT "${REMOTE_DIR}" MATCHES "${IT_AGENT_PACKAGE_PATTERN}")
        message(FATAL_ERROR "The IT agent ${HOST} gave the package folder '${REMOTE_DIR}'.")
    endif()

    # The files alone in a folder - the content of the folder is copied
    list(GET IN_FILES 0 FIRMWARE_PATH)
    get_filename_component(FIRMWARE_NAME "${FIRMWARE_PATH}" NAME)
    get_filename_component(FIRMWARE_DIR "${FIRMWARE_PATH}" DIRECTORY)
    set(PACKAGE_DIR "${FIRMWARE_DIR}/FlashPackage")
    file(REMOVE_RECURSE "${PACKAGE_DIR}")
    file(COPY ${IN_FILES} DESTINATION "${PACKAGE_DIR}")

    IntegrationTesting_RemotePut(PUT_RESULT "${SSH_TARGET}" "${PACKAGE_DIR}" "${REMOTE_DIR}")
    file(REMOVE_RECURSE "${PACKAGE_DIR}")

    set(CALL_ERROR "the firmware could not be copied to the agent")

    if(PUT_RESULT EQUAL 0)
        IntegrationTesting_AgentCall(CALL_JSON
                                     CALL_ERROR
                                     "${SSH_TARGET}"
                                     "${TOOLS}"
                                     "TTY;PRINT"
                                     ${IN_COMMAND}
                                     --package
                                     "${REMOTE_DIR}"
                                     --firmware
                                     "${FIRMWARE_NAME}"
                                     --probe
                                     "${IT_TARGET_${IN_IDX}_PROBE}"
                                     --chip
                                     "${IN_CHIP}"
                                     --probe-rs
                                     "${PROBE_RS_VERSION}"
                                     --holder
                                     "${IN_HOLDER}"
                                     ${ARGN})
    endif()

    IntegrationTesting_AgentCall(REMOVE_JSON
                                 REMOVE_ERROR
                                 "${SSH_TARGET}"
                                 "${TOOLS}"
                                 ""
                                 remove-package
                                 --package
                                 "${REMOTE_DIR}")

    set(${OUT_ERROR} "${CALL_ERROR}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_FlashRemote
# Description: Flashes a firmware to the board of an IT agent through its agent tools (IT agent interface):
#              the firmware is copied into a folder of the agent (new-package), flashed by embi-agent flash
#              (probe-rs of the version of this machine, probe lock of the agent) and the folder is removed
#              (remove-package).
#
# IN_IDX      [in]: Index of the target (Prj_VSCode_GetTarget).
# IN_FIRMWARE [in]: Firmware file.
# IN_CHIP     [in]: probe-rs chip.
# IN_HOLDER   [in]: Holder of the probe lock.
# ------------------------------------------------------------------------------
function(Prj_VSCode_FlashRemote IN_IDX IN_FIRMWARE IN_CHIP IN_HOLDER)

    Prj_VSCode_AgentFirmwareCall(FLASH_ERROR Flash ${IN_IDX} "${IN_FIRMWARE}" "${IN_CHIP}" "${IN_HOLDER}" flash)

    # Agent tools older than this platform
    if("${FLASH_ERROR}" MATCHES "^Unknown command")
        string(APPEND FLASH_ERROR " - the agent tools of ${IT_TARGET_${IN_IDX}_HOST} are older than this platform, "
                                  "the pipeline ItAgentUpdate of EmBi_Tester updates them")
    endif()

    if(NOT "${FLASH_ERROR}" STREQUAL "")
        message(FATAL_ERROR "Flash of ${IT_TARGET_${IN_IDX}_TEXT} failed: ${FLASH_ERROR}")
    endif()
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_OptionBytesRemote
# Description: Writes the option bytes of a firmware (ELF section .option_bytes) to the board of an IT agent
#              through its agent tools: embi-agent option-bytes with the firmware and OptionBytes_Flash.cmake of
#              this platform (script mode) in a folder of the agent - only the option bytes which differ from the
#              chip are written. Agent tools without the command - warning, the option bytes are not written.
#
# IN_IDX      [in]: Index of the target (Prj_VSCode_GetTarget).
# IN_FIRMWARE [in]: Firmware file.
# IN_CHIP     [in]: probe-rs chip.
# IN_HOLDER   [in]: Holder of the probe lock.
# ------------------------------------------------------------------------------
function(Prj_VSCode_OptionBytesRemote IN_IDX IN_FIRMWARE IN_CHIP IN_HOLDER)

    set(SCRIPT "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../../OptionBytes/OptionBytes_Flash.cmake")
    get_filename_component(SCRIPT_NAME "${SCRIPT}" NAME)

    Prj_VSCode_AgentFirmwareCall(OPTION_BYTES_ERROR
                                 "Option bytes"
                                 ${IN_IDX}
                                 "${IN_FIRMWARE};${SCRIPT}"
                                 "${IN_CHIP}"
                                 "${IN_HOLDER}"
                                 option-bytes
                                 --script
                                 "${SCRIPT_NAME}")

    # Agent tools older than this platform
    if("${OPTION_BYTES_ERROR}" MATCHES "^Unknown command")
        message(WARNING "The option bytes of ${IN_FIRMWARE} are not written to ${IT_TARGET_${IN_IDX}_TEXT} - the "
                        "agent tools of ${IT_TARGET_${IN_IDX}_HOST} are older than this platform, the pipeline "
                        "ItAgentUpdate of EmBi_Tester updates them.")
        return()
    endif()

    if(NOT "${OPTION_BYTES_ERROR}" STREQUAL "")
        message(FATAL_ERROR "Option bytes of ${IT_TARGET_${IN_IDX}_TEXT} failed: ${OPTION_BYTES_ERROR}")
    endif()
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_CompareCoreOptionBytes
# Description: The projects of the cores of a multi-core MCU flash one chip - the option bytes of the firmware of
#              this project (ELF section .option_bytes) have to be the ones of the firmware of every other core built
#              in the same build folder of its project (same MCU, build type and board). A core without the built
#              firmware is not compared (a project of one core works alone). A difference stops the flash.
#
# IN_FIRMWARE   [in]: Firmware of this project.
# IN_BUILD_TYPE [in]: Debug or Release.
# ------------------------------------------------------------------------------
function(Prj_VSCode_CompareCoreOptionBytes IN_FIRMWARE IN_BUILD_TYPE)

    if(NOT VSCODE_CORE_PROJECT)
        return()
    endif()

    get_filename_component(PROJECT_FOLDER "${PROJECT_ROOT_PATH}" NAME)
    get_filename_component(FIRMWARE_DIR "${IN_FIRMWARE}" DIRECTORY)
    file(RELATIVE_PATH BUILD_FOLDER "${PROJECT_ROOT_PATH}" "${FIRMWARE_DIR}")

    Prj_VSCode_GetCoreProjects(CORES)

    foreach(CORE IN LISTS CORES)

        if(CORE STREQUAL PROJECT_FOLDER)
            continue()
        endif()

        Prj_VSCode_GetFirmwareName(${IN_BUILD_TYPE} OTHER_FIRMWARE "${PLATFORM_ROOT_PATH}/${CORE}")
        set(OTHER_PATH "${PLATFORM_ROOT_PATH}/${CORE}/${BUILD_FOLDER}/${OTHER_FIRMWARE}")

        if(NOT EXISTS "${OTHER_PATH}")
            message("Option bytes: no firmware of the project ${CORE} (${BUILD_FOLDER}) - not compared.")
            continue()
        endif()

        OptionBytes_Compare(DIFFERENCE "${IN_FIRMWARE}" "${OTHER_PATH}")

        if(NOT "${DIFFERENCE}" STREQUAL "")
            string(REPLACE " | " ";" DIFFERENCE "${DIFFERENCE}")
            list(GET DIFFERENCE 0 OWN_VALUES)
            list(GET DIFFERENCE 1 OTHER_VALUES)
            message(FATAL_ERROR "Option bytes of the project ${PROJECT_FOLDER} (${OWN_VALUES}) differ from the project "
                                "${CORE} (${OTHER_VALUES}, ${OTHER_PATH}) - the projects of the cores flash one chip, "
                                "set the same option bytes in both. Not flashed.")
        endif()

    endforeach()
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_WriteOptionBytes
# Description: Writes the option bytes of a firmware (ELF section .option_bytes, OptionBytes_Apply) to the chip by
#              probe-rs of this machine - nothing when the chip has the values.
#
# IN_FIRMWARE [in]: Firmware.
# IN_PROBE_RS [in]: probe-rs executable.
# IN_CHIP     [in]: probe-rs chip.
# IN_PROBE    [in]: Probe ("" - the only connected probe, as the debug configurations of an MCU).
# ------------------------------------------------------------------------------
function(Prj_VSCode_WriteOptionBytes IN_FIRMWARE IN_PROBE_RS IN_CHIP IN_PROBE)

    set(PROBE_ARGS --chip ${IN_CHIP})
    if(NOT "${IN_PROBE}" STREQUAL "")
        list(APPEND PROBE_ARGS --probe ${IN_PROBE})
    endif()
    list(APPEND PROBE_ARGS --non-interactive)

    OptionBytes_Apply(OPTION_BYTES_TEXT "${IN_FIRMWARE}" "${IN_PROBE_RS}" "${PROBE_ARGS}")

    if(NOT "${OPTION_BYTES_TEXT}" STREQUAL "")
        message("${OPTION_BYTES_TEXT}")
    endif()
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_DebugOptionBytes
# Description: Step of the preLaunchTask of the debug configurations - the option bytes of the Debug firmware
#              (ELF section .option_bytes) are written when the chip has other values: the firmware of the MCU
#              (task "EmBi: Option bytes <MCU>_Debug", the only connected probe as the debug configuration) or of
#              the picked board (DEBUG_SERVE of Prj_VSCode_ProbeRs.cmake). A board of an IT agent - by its agent
#              tools (Prj_VSCode_OptionBytesRemote).
#
# IN_MCU [in]: MCU (the debug configurations of the MCU).
# IN_ID  [in]: ID of the picked board ("" - IN_MCU).
# ------------------------------------------------------------------------------
function(Prj_VSCode_DebugOptionBytes IN_MCU IN_ID)

    Prj_VSCode_GetFirmwareName(Debug FIRMWARE)
    set(PROBE "")
    set(HOST "${IT_LOCAL_HOST}")

    if(NOT "${IN_ID}" STREQUAL "")
        Prj_VSCode_GetTarget("${IN_ID}" TARGET_IDX)
        set(MCU   "${IT_TARGET_${TARGET_IDX}_MCU}")
        set(PROBE "${IT_TARGET_${TARGET_IDX}_PROBE}")
        set(HOST  "${IT_TARGET_${TARGET_IDX}_HOST}")
        Build_Handler_Get_BoardBuild("${IT_TARGET_${TARGET_IDX}_BOARD}" Debug BOARD_MCU BOARD_PRESET BOARD_DIR)
        set(FIRMWARE_PATH "${BOARD_DIR}/${FIRMWARE}")
    else()
        set(MCU "${IN_MCU}")
        set(FIRMWARE_PATH "${BUILD_HANDLER_BUILD_DIR}/${MCU}_Debug/${FIRMWARE}")
    endif()

    if(NOT EXISTS "${FIRMWARE_PATH}")
        message(FATAL_ERROR "Debug firmware ${FIRMWARE_PATH} not found - it is built by the debug configuration.")
    endif()

    OptionBytes_ReadElf(OPTION_BYTES_LINES "${FIRMWARE_PATH}")
    if(NOT OPTION_BYTES_LINES)
        return()
    endif()

    Prj_VSCode_CompareCoreOptionBytes("${FIRMWARE_PATH}" Debug)

    IntegrationTesting_ProvideProbeRs(VSCODE_PROBE_RS "${PROJECT_ROOT_PATH}" "${MCU}")
    IntegrationTesting_ReadMcuIdentification(IDENTIFIED_MCUS "${VSCODE_RAL_PRESETS_FILE}")
    Prj_VSCode_GetChip(${MCU} CHIP)
    IntegrationTesting_Get_LockHolder(HOLDER "option bytes")

    if(NOT "${HOST}" STREQUAL "${IT_LOCAL_HOST}")
        Prj_VSCode_OptionBytesRemote(${TARGET_IDX} "${FIRMWARE_PATH}" "${CHIP}" "${HOLDER}")
        return()
    endif()

    if(NOT "${PROBE}" STREQUAL "")
        IntegrationTesting_LockProbe(USED_BY "${PROBE}" 0 "${HOLDER}")
        if(NOT "${USED_BY}" STREQUAL "")
            message(FATAL_ERROR "The board is used by ${USED_BY} - option bytes not written.")
        endif()
    endif()

    Prj_VSCode_WriteOptionBytes("${FIRMWARE_PATH}" "${VSCODE_PROBE_RS}" "${CHIP}" "${PROBE}")

    if(NOT "${PROBE}" STREQUAL "")
        IntegrationTesting_UnlockProbe("${PROBE}")
    endif()
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_FlashOtherCores
# Description: Step of the preLaunchTask of the debug configurations of the project of a core of a multi-core MCU -
#              the Debug firmware of the projects of the other cores is built (the MCU of the debug configuration,
#              or the picked board) and flashed (probe-rs download with verification; a board of an IT agent by its
#              agent tools): a debug session of probe-rs flashes and debugs one core only, the core of this project.
#              Nothing in a project of a single-core MCU.
#
# IN_MCU [in]: MCU (the debug configurations of the MCU).
# IN_ID  [in]: ID of the picked board ("" - IN_MCU).
# ------------------------------------------------------------------------------
function(Prj_VSCode_FlashOtherCores IN_MCU IN_ID)

    if(NOT VSCODE_CORE_PROJECT)
        return()
    endif()

    get_filename_component(PROJECT_FOLDER "${PROJECT_ROOT_PATH}" NAME)
    Prj_VSCode_GetCoreProjects(CORES)
    list(REMOVE_ITEM CORES "${PROJECT_FOLDER}")

    if(NOT CORES)
        return()
    endif()

    set(PROBE "")
    set(HOST "${IT_LOCAL_HOST}")

    if(NOT "${IN_ID}" STREQUAL "")
        Prj_VSCode_GetTarget("${IN_ID}" TARGET_IDX)
        set(MCU   "${IT_TARGET_${TARGET_IDX}_MCU}")
        set(PROBE "${IT_TARGET_${TARGET_IDX}_PROBE}")
        set(HOST  "${IT_TARGET_${TARGET_IDX}_HOST}")
        set(BOARD "${IT_TARGET_${TARGET_IDX}_BOARD}")
        Build_Handler_Get_BoardBuild("${BOARD}" Debug BOARD_MCU BOARD_PRESET BUILD_DIR)
        set(BUILD_ARGS -DFUNCTION_ID=BUILD "-DBOARD=${BOARD}" -DBUILD_TYPE=Debug)
    else()
        set(MCU "${IN_MCU}")
        set(BUILD_DIR "${BUILD_HANDLER_BUILD_DIR}/${MCU}_Debug")
        set(BUILD_ARGS -DFUNCTION_ID=BUILD "-DMCU=${MCU}" -DBUILD_TYPE=Debug)
    endif()

    # The build folder of the debug configuration in the project of the other core
    file(RELATIVE_PATH BUILD_FOLDER "${PROJECT_ROOT_PATH}" "${BUILD_DIR}")

    IntegrationTesting_ProvideProbeRs(VSCODE_PROBE_RS "${PROJECT_ROOT_PATH}" "${MCU}")
    IntegrationTesting_ReadMcuIdentification(IDENTIFIED_MCUS "${VSCODE_RAL_PRESETS_FILE}")
    Prj_VSCode_GetChip(${MCU} CHIP)
    IntegrationTesting_Get_LockHolder(HOLDER "debugging of the other core")

    foreach(CORE IN LISTS CORES)

        message("==================== Debug firmware of the core ${CORE} ====================")

        execute_process(COMMAND "${CMAKE_COMMAND}" ${BUILD_ARGS}
                                -P "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../Build_Handler/Build_Handler.cmake"
                        WORKING_DIRECTORY "${PLATFORM_ROOT_PATH}/${CORE}"
                        RESULT_VARIABLE BUILD_RESULT)

        if(NOT BUILD_RESULT EQUAL 0)
            message(FATAL_ERROR "Debug build of the project of the core ${CORE} failed - the core ${PROJECT_FOLDER} is "
                                "not debugged.")
        endif()

        Prj_VSCode_GetFirmwareName(Debug FIRMWARE "${PLATFORM_ROOT_PATH}/${CORE}")
        set(FIRMWARE_PATH "${PLATFORM_ROOT_PATH}/${CORE}/${BUILD_FOLDER}/${FIRMWARE}")

        if("${HOST}" STREQUAL "${IT_LOCAL_HOST}")

            set(PROBE_ARGS --chip ${CHIP})
            if(NOT "${PROBE}" STREQUAL "")
                list(APPEND PROBE_ARGS --probe ${PROBE})
                IntegrationTesting_LockProbe(USED_BY "${PROBE}" 0 "${HOLDER}")
                if(NOT "${USED_BY}" STREQUAL "")
                    message(FATAL_ERROR "The board is used by ${USED_BY} - the firmware of the core ${CORE} is not "
                                        "flashed.")
                endif()
            endif()

            Build_Handler_Execute("Flashing of ${FIRMWARE} (core ${CORE})" "${VSCODE_PROBE_RS}" download ${PROBE_ARGS}
                                  --verify "${FIRMWARE_PATH}")

            if(NOT "${PROBE}" STREQUAL "")
                IntegrationTesting_UnlockProbe("${PROBE}")
            endif()

        else()

            Prj_VSCode_FlashRemote(${TARGET_IDX} "${FIRMWARE_PATH}" "${CHIP}" "${HOLDER}")

        endif()

    endforeach()
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_Flash
# Description: Task "EmBi: Flash" - builds the project for the picked board (the preset of its MCU with the
#              configuration of the board in its build folder - the build of its debugging), flashes the
#              firmware by probe-rs to the board and resets its MCU. A board of this machine is flashed by
#              probe-rs of this machine under the probe lock, a board of an IT agent by its agent tools
#              (Prj_VSCode_FlashRemote).
#
# IN_ID         [in]: ID of the picked board.
# IN_BUILD_TYPE [in]: Debug or Release.
# ------------------------------------------------------------------------------
function(Prj_VSCode_Flash IN_ID IN_BUILD_TYPE)

    Prj_VSCode_GetTarget("${IN_ID}" TARGET_IDX)

    set(MCU   "${IT_TARGET_${TARGET_IDX}_MCU}")
    set(BOARD "${IT_TARGET_${TARGET_IDX}_BOARD}")
    set(TEXT  "${IT_TARGET_${TARGET_IDX}_TEXT}")

    Build_Handler_BuildBoard("${BOARD}" "${IN_BUILD_TYPE}")
    Build_Handler_Get_BoardBuild("${BOARD}" "${IN_BUILD_TYPE}" BOARD_MCU BOARD_PRESET BOARD_DIR)
    Prj_VSCode_GetFirmwareName(${IN_BUILD_TYPE} FIRMWARE)
    set(FIRMWARE_PATH "${BOARD_DIR}/${FIRMWARE}")

    # probe-rs artifact in the version configured for the integration test preset of the MCU - found in
    # the artifacts cache or downloaded by the artifacts handler (an IT agent uses the same version)
    IntegrationTesting_ProvideProbeRs(VSCODE_PROBE_RS "${PROJECT_ROOT_PATH}" "${MCU}")

    IntegrationTesting_ReadMcuIdentification(IDENTIFIED_MCUS "${VSCODE_RAL_PRESETS_FILE}")
    Prj_VSCode_GetChip(${MCU} CHIP)

    IntegrationTesting_Get_LockHolder(HOLDER "flashing")

    message("=====================================")
    message("Flash: ${FIRMWARE_PATH}")
    message("Board ${TEXT}, chip ${CHIP}")
    message("=====================================")

    # Option bytes of the firmware (ELF section .option_bytes) - the projects of the cores of a multi-core MCU set
    # the same ones
    Prj_VSCode_CompareCoreOptionBytes("${FIRMWARE_PATH}" ${IN_BUILD_TYPE})
    OptionBytes_ReadElf(OPTION_BYTES_LINES "${FIRMWARE_PATH}")

    if("${IT_TARGET_${TARGET_IDX}_HOST}" STREQUAL "${IT_LOCAL_HOST}")

        set(PROBE "${IT_TARGET_${TARGET_IDX}_PROBE}")

        IntegrationTesting_LockProbe(USED_BY "${PROBE}" 0 "${HOLDER}")

        if(NOT "${USED_BY}" STREQUAL "")
            message(FATAL_ERROR "${TEXT} is used by ${USED_BY} - it is not flashed.")
        endif()

        set(PROBE_ARGS --chip ${CHIP} --probe ${PROBE})
        Build_Handler_Execute("Flashing of ${FIRMWARE}" "${VSCODE_PROBE_RS}" download ${PROBE_ARGS} "${FIRMWARE_PATH}")
        Prj_VSCode_WriteOptionBytes("${FIRMWARE_PATH}" "${VSCODE_PROBE_RS}" "${CHIP}" "${PROBE}")
        Build_Handler_Execute("Reset of ${MCU}" "${VSCODE_PROBE_RS}" reset ${PROBE_ARGS})

    else()

        Prj_VSCode_FlashRemote(${TARGET_IDX} "${FIRMWARE_PATH}" "${CHIP}" "${HOLDER}")

        if(OPTION_BYTES_LINES)
            Prj_VSCode_OptionBytesRemote(${TARGET_IDX} "${FIRMWARE_PATH}" "${CHIP}" "${HOLDER}")
        endif()

    endif()

    message("=====================================")
    message("Flash of ${TEXT} PASSED")
    message("=====================================")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_PrintOptions
# Description: Prints options of an input of a debug configuration to the
#              standard output, one per line (<value>|<label>|<description>).
#              message() prints to the standard error output, thus the options
#              are printed by the echo of CMake.
#
# ARGN [in]: Lines.
# ------------------------------------------------------------------------------
function(Prj_VSCode_PrintOptions)

    list(JOIN ARGN "\n" TEXT)

    execute_process(COMMAND "${CMAKE_COMMAND}" -E echo "${TEXT}")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_PrintDebugFirmware
# Description: Prints the firmware file of the project built for the MCU - build
#              directory of the preset and the firmware name of the root
#              CMakeLists.txt (the same file the flash task uses).
#
# IN_MCU        [in]: MCU.
# IN_BUILD_TYPE [in]: Debug or Release.
# ------------------------------------------------------------------------------
function(Prj_VSCode_PrintDebugFirmware IN_MCU IN_BUILD_TYPE)

    Prj_VSCode_GetFirmwareName(${IN_BUILD_TYPE} FIRMWARE)

    Prj_VSCode_PrintOptions("${BUILD_HANDLER_BUILD_DIR}/${IN_MCU}_${IN_BUILD_TYPE}/${FIRMWARE}")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_PrintDebugChip
# Description: Prints the probe-rs chip of the MCU (Prj_VSCode_GetChip). The chip
#              is checked by probe-rs ("chip info") if the probe-rs artifact is
#              in the artifacts cache (it is not downloaded here).
#
# IN_MCU [in]: MCU.
# ------------------------------------------------------------------------------
function(Prj_VSCode_PrintDebugChip IN_MCU)

    IntegrationTesting_FindProbeRs(VSCODE_PROBE_RS "${PROJECT_ROOT_PATH}" "${IN_MCU}")
    IntegrationTesting_ReadMcuIdentification(IDENTIFIED_MCUS "${VSCODE_RAL_PRESETS_FILE}")

    Prj_VSCode_GetChip(${IN_MCU} CHIP)

    Prj_VSCode_PrintOptions("${CHIP}")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_PrintDebugSvd
# Description: Prints the SVD file of the MCU from the Ral module Svd of the BSP
#              (Prj_VSCode_GetSvd). An MCU without an SVD file (the BSP without the
#              module Svd, a device ST delivers no SVD file for) is not an error of
#              the debug session: the input prints the path where the file would be
#              and warns - the debugger reports a missing file by a warning and runs
#              without the peripheral registers (an empty value of the input is not
#              possible, the input fails without an output).
#
# IN_MCU [in]: MCU.
# ------------------------------------------------------------------------------
function(Prj_VSCode_PrintDebugSvd IN_MCU)

    IntegrationTesting_ReadMcuIdentification(IDENTIFIED_MCUS "${VSCODE_RAL_PRESETS_FILE}")

    Prj_VSCode_GetSvd(${IN_MCU} SVD)

    if("${SVD}" STREQUAL "")
        set(SVD "${VSCODE_SVD_DIR}/NO_SVD_FILE_OF_${IN_MCU}")
        message(WARNING "No SVD file of ${IN_MCU} in ${VSCODE_SVD_DIR} (module Svd of Ral: Devices.csv with "
                         "<Device>.svd) - the BSP of the project has no module Svd or ST delivers no SVD file of the "
                         "device. The debug session runs without the peripheral registers.")
    endif()

    Prj_VSCode_PrintOptions("${SVD}")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_PrintDebugGdb
# Description: Prints the host gdb of the unit tests of the MCU - gdb of the
#              artifact in the version configured for the unit test preset of the
#              MCU (artifact gdb, otherwise artifact gcc), never the newest cached
#              version and never gdb installed in the system (the system
#              requirements are CMake and git only).
#
# IN_MCU [in]: MCU.
# ------------------------------------------------------------------------------
function(Prj_VSCode_PrintDebugGdb IN_MCU)

    set(PRESET "${IN_MCU}_UnitTest")

    foreach(ARTIFACT IN ITEMS gdb gcc)

        ArtifactsResolver_Get_BinDir(BIN_DIR RECORD "${PROJECT_ROOT_PATH}" "${PRESET}" ${ARTIFACT})

        if("${RECORD}" STREQUAL "")
            continue()
        endif()

        if("${BIN_DIR}" STREQUAL "")
            message(FATAL_ERROR "The artifact ${ARTIFACT} (configured: ${RECORD}) is not in the artifacts cache - it is "
                                "downloaded by the task \"EmBi: Unit tests\" of ${IN_MCU}.")
        endif()

        file(GLOB_RECURSE GDB_FILES "${BIN_DIR}/*gdb" "${BIN_DIR}/*gdb.exe")
        list(FILTER GDB_FILES INCLUDE REGEX "/bin/gdb(\\.exe)?$")

        foreach(GDB_FILE IN LISTS GDB_FILES)
            if(NOT IS_DIRECTORY "${GDB_FILE}")
                Prj_VSCode_PrintOptions("${GDB_FILE}")
                return()
            endif()
        endforeach()

        if("${ARTIFACT}" STREQUAL "gcc")
            message(FATAL_ERROR "gdb is not a part of the artifact gcc (configured: ${RECORD}, ${BIN_DIR}) - add an artifact "
                                "gdb to the unit test preset. gdb of the system is not used.")
        endif()

    endforeach()

    message(FATAL_ERROR "No artifact with gdb (gdb, gcc) is configured for the preset ${PRESET}. gdb of the system is not used.")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_PrintTestSets
# Description: Prints the test sets (names of the tests registered in the
#              project, Prj_VSCode_GetTestFirmwares) - the first option is
#              an empty value = all test sets.
#
# IN_TEST_TYPE [in]: UT or IT.
# ------------------------------------------------------------------------------
function(Prj_VSCode_PrintTestSets IN_TEST_TYPE)

    if("${IN_TEST_TYPE}" STREQUAL "UT")
        Prj_VSCode_GetTestFirmwares(UnitTests TESTS)
    elseif("${IN_TEST_TYPE}" STREQUAL "IT")
        Prj_VSCode_GetTestFirmwares(IntegrationTests TESTS)
    else()
        message(FATAL_ERROR "Required TEST_TYPE '${IN_TEST_TYPE}' is not correct (UT, IT).")
    endif()

    set(TEST_SETS "")

    foreach(TEST IN LISTS TESTS)
        get_filename_component(TEST_NAME "${TEST}" NAME_WE)
        string(REGEX REPLACE "^(UT|IT)_" "" TEST_NAME "${TEST_NAME}")
        list(APPEND TEST_SETS "${TEST_NAME}")
    endforeach()

    list(REMOVE_DUPLICATES TEST_SETS)
    list(SORT TEST_SETS)

    Prj_VSCode_PrintOptions("|All test sets" ${TEST_SETS})
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_DetectTargets
# Description: Detects the connected boards of this machine and of the IT agents of ItHosts.json
#              (IntegrationTesting_Detect.cmake, its output is not printed - an input prints only its
#              options) and reads the targets (IntegrationTesting_ReadTargets).
#
# OUT_COUNT [out]: Count of the targets (IT_TARGET_<idx>_* in the parent scope).
# ------------------------------------------------------------------------------
function(Prj_VSCode_DetectTargets OUT_COUNT)

    set(DETECT_ARGS -DIT_BOARDS_FILE=${BUILD_HANDLER_BOARDS_FILE} -P "${BUILD_HANDLER_IT_DETECT}")

    execute_process(COMMAND "${CMAKE_COMMAND}" ${DETECT_ARGS}
                    WORKING_DIRECTORY "${PROJECT_ROOT_PATH}"
                    RESULT_VARIABLE DETECT_RESULT
                    OUTPUT_VARIABLE DETECT_OUTPUT
                    ERROR_VARIABLE  DETECT_OUTPUT)

    if(NOT DETECT_RESULT EQUAL 0)
        message("Detection of connected boards failed:\n${DETECT_OUTPUT}")
    endif()

    IntegrationTesting_ReadTargets(TARGETS_CNT "${BUILD_HANDLER_BOARDS_FILE}")

    math(EXPR TARGETS_LAST "${TARGETS_CNT} - 1")
    if(TARGETS_CNT GREATER 0)
        foreach(TARGET_IDX RANGE ${TARGETS_LAST})
            foreach(SUFFIX IN LISTS IT_TARGET_SUFFIXES)
                set(IT_TARGET_${TARGET_IDX}_${SUFFIX} "${IT_TARGET_${TARGET_IDX}_${SUFFIX}}" PARENT_SCOPE)
            endforeach()
        endforeach()
    endif()

    set(${OUT_COUNT} ${TARGETS_CNT} PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_GetFailedHosts
# Description: Text of the IT agents whose detection failed (member "failed" of the boards file of the
#              detection): " Detection of <host> (<target>) failed: <error>." per agent.
#
# OUT_TEXT [out]: Text ("" when the detection of every agent was done).
# ------------------------------------------------------------------------------
function(Prj_VSCode_GetFailedHosts OUT_TEXT)

    set(TEXT "")

    if(EXISTS "${BUILD_HANDLER_BOARDS_FILE}")

        file(READ "${BUILD_HANDLER_BOARDS_FILE}" BOARDS_CONTENT)
        string(JSON FAILED_CNT ERROR_VARIABLE FAILED_ERROR LENGTH "${BOARDS_CONTENT}" failed)

        if(FAILED_ERROR)
            set(FAILED_CNT 0)
        endif()

        if(FAILED_CNT GREATER 0)
            math(EXPR FAILED_LAST "${FAILED_CNT} - 1")
            foreach(FAILED_IDX RANGE ${FAILED_LAST})
                string(JSON HOST   GET "${BOARDS_CONTENT}" failed ${FAILED_IDX} host)
                string(JSON TARGET GET "${BOARDS_CONTENT}" failed ${FAILED_IDX} target)
                string(JSON ERROR  GET "${BOARDS_CONTENT}" failed ${FAILED_IDX} error)
                if(NOT "${ERROR}" MATCHES "[.?!]$")
                    string(APPEND ERROR ".")
                endif()
                string(APPEND TEXT " Detection of ${HOST} (${TARGET}) failed: ${ERROR}")
            endforeach()
        endif()

    endif()

    set(${OUT_TEXT} "${TEXT}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_PrintTargets
# Description: Prints the connected boards of this machine and of the IT agents (detected now) - one
#              option per physical board: <ID>|<board> - <name of the board>|<host>.
#
# IN_ALL_BOARDS   [in]: TRUE - the option BUILD_HANDLER_ALL_BOARDS_TEXT is printed too.
# IN_REMOTE_ONLY  [in]: TRUE - only the boards of the IT agents (serial monitor).
# ------------------------------------------------------------------------------
function(Prj_VSCode_PrintTargets IN_ALL_BOARDS IN_REMOTE_ONLY)

    Prj_VSCode_DetectTargets(TARGETS_CNT)

    set(LINES "")

    if(TARGETS_CNT GREATER 0)

        math(EXPR TARGETS_LAST "${TARGETS_CNT} - 1")

        foreach(TARGET_IDX RANGE ${TARGETS_LAST})

            if(IN_REMOTE_ONLY AND
               "${IT_TARGET_${TARGET_IDX}_HOST}" STREQUAL "${IT_LOCAL_HOST}")
                continue()
            endif()

            if("${IT_TARGET_${TARGET_IDX}_HOST}" STREQUAL "${IT_LOCAL_HOST}")
                set(DESCRIPTION "this machine")
            else()
                set(DESCRIPTION "${IT_TARGET_${TARGET_IDX}_HOST} (${IT_TARGET_${TARGET_IDX}_TARGET})")
            endif()

            if(NOT "${IT_TARGET_${TARGET_IDX}_FEATURES}" STREQUAL "")
                string(APPEND DESCRIPTION " - ${IT_TARGET_${TARGET_IDX}_FEATURES}")
            endif()

            if(NOT "${IT_TARGET_${TARGET_IDX}_USED_BY}" STREQUAL "")
                string(APPEND DESCRIPTION " - used by ${IT_TARGET_${TARGET_IDX}_USED_BY}")
            endif()

            set(LABEL "${IT_TARGET_${TARGET_IDX}_BOARD} - ${IT_TARGET_${TARGET_IDX}_LABEL}")
            list(APPEND LINES "${IT_TARGET_${TARGET_IDX}_ID}|${LABEL}|${DESCRIPTION}")

        endforeach()

    endif()

    if(IN_ALL_BOARDS AND
       LINES)
        list(APPEND LINES "${BUILD_HANDLER_ALL_BOARDS_TEXT}")
    endif()

    if(NOT LINES)
        # No output - the error of the input shows this text, with the IT agents whose detection failed
        if(IN_REMOTE_ONLY)
            set(TEXT "No board is connected to an IT agent of ItHosts.json.")
        else()
            set(TEXT "No board is connected to this machine or to an IT agent of ItHosts.json.")
        endif()
        Prj_VSCode_GetFailedHosts(FAILED_TEXT)
        message("${TEXT}${FAILED_TEXT}")
        return()
    endif()

    Prj_VSCode_PrintOptions(${LINES})
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_GetTarget
# Description: Target (physical board) of an input by its ID - the boards file of the detection done by
#              the input of the board (Prj_VSCode_PrintTargets). The MCU is the one of its preset.
#
# IN_ID   [in]:  ID of the target (<board>@<host>:<probe>).
# OUT_IDX [out]: Index of the target (IT_TARGET_<idx>_* and IT_TARGET_<idx>_MCU in the parent scope).
# ------------------------------------------------------------------------------
function(Prj_VSCode_GetTarget IN_ID OUT_IDX)

    IntegrationTesting_ReadTargets(TARGETS_CNT "${BUILD_HANDLER_BOARDS_FILE}")
    IntegrationTesting_FindTarget(TARGET_IDX ${TARGETS_CNT} "${IN_ID}")

    if(TARGET_IDX EQUAL -1)
        message(FATAL_ERROR "Board '${IN_ID}' is not connected - pick the board again.")
    endif()

    foreach(SUFFIX IN LISTS IT_TARGET_SUFFIXES)
        set(IT_TARGET_${TARGET_IDX}_${SUFFIX} "${IT_TARGET_${TARGET_IDX}_${SUFFIX}}" PARENT_SCOPE)
    endforeach()

    string(REGEX REPLACE "_IntegrationTest$" "" MCU "${IT_TARGET_${TARGET_IDX}_PRESET}")
    set(IT_TARGET_${TARGET_IDX}_MCU "${MCU}" PARENT_SCOPE)

    set(${OUT_IDX} ${TARGET_IDX} PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_GetServerPorts
# Description: Ports of a server of a target (debug server, serial server) - 127.0.0.1 of this machine (the
#              debug configuration or the Serial Monitor connects there, the tunnel of an IT agent listens
#              there) and of the agent. They are given by the hash of the target (of its probe on the agent),
#              the same target gets the same ports; a local port of an excluded port range of Windows (netsh)
#              is moved behind it.
#
# IN_IDX         [in]:  Index of the target (Prj_VSCode_GetTarget).
# IN_LOCAL_BASE  [in]:  First port of this machine (VSCODE_DEBUG_PORT_RANGE ports).
# IN_REMOTE_BASE [in]:  First port of the agent (VSCODE_DEBUG_PORT_RANGE ports).
# OUT_LOCAL      [out]: Port of this machine.
# OUT_REMOTE     [out]: Port of the agent.
# ------------------------------------------------------------------------------
function(Prj_VSCode_GetServerPorts IN_IDX IN_LOCAL_BASE IN_REMOTE_BASE OUT_LOCAL OUT_REMOTE)

    string(MD5 LOCAL_HASH "${IT_TARGET_${IN_IDX}_ID}")
    string(SUBSTRING "${LOCAL_HASH}" 0 6 LOCAL_HASH)
    math(EXPR LOCAL_PORT "${IN_LOCAL_BASE} + 0x${LOCAL_HASH} % ${VSCODE_DEBUG_PORT_RANGE}")

    IntegrationTesting_Get_LockKey(PROBE_KEY "${IT_TARGET_${IN_IDX}_PROBE}")
    string(MD5 REMOTE_HASH "${PROBE_KEY}")
    string(SUBSTRING "${REMOTE_HASH}" 0 6 REMOTE_HASH)
    math(EXPR REMOTE_PORT "${IN_REMOTE_BASE} + 0x${REMOTE_HASH} % ${VSCODE_DEBUG_PORT_RANGE}")

    Prj_VSCode_FreePort(${LOCAL_PORT} LOCAL_PORT)

    set(${OUT_LOCAL}  ${LOCAL_PORT}  PARENT_SCOPE)
    set(${OUT_REMOTE} ${REMOTE_PORT} PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_FreePort
# Description: A port of this machine outside of the excluded port ranges of Windows (netsh) - a port of a range is
#              moved behind it.
#
# IN_PORT  [in]:  Port.
# OUT_PORT [out]: The port or the next port outside of the excluded port ranges.
# ------------------------------------------------------------------------------
function(Prj_VSCode_FreePort IN_PORT OUT_PORT)

    set(LOCAL_PORT ${IN_PORT})

    if(CMAKE_HOST_WIN32)

        execute_process(COMMAND netsh int ipv4 show excludedportrange protocol=tcp
                        OUTPUT_VARIABLE NETSH_OUTPUT
                        ERROR_QUIET)

        string(REGEX MATCHALL "[0-9]+[ \t]+[0-9]+" EXCLUDED_RANGES "${NETSH_OUTPUT}")

        foreach(TRY_IDX RANGE 1 ${VSCODE_DEBUG_PORT_RANGE})

            set(EXCLUDED FALSE)

            foreach(EXCLUDED_RANGE IN LISTS EXCLUDED_RANGES)
                string(REGEX MATCH "([0-9]+)[ \t]+([0-9]+)" RANGE_MATCH "${EXCLUDED_RANGE}")
                if(LOCAL_PORT GREATER_EQUAL CMAKE_MATCH_1 AND
                   LOCAL_PORT LESS_EQUAL CMAKE_MATCH_2)
                    set(EXCLUDED TRUE)
                endif()
            endforeach()

            if(NOT EXCLUDED)
                break()
            endif()

            math(EXPR LOCAL_PORT "${LOCAL_PORT} + 1")

        endforeach()

    endif()

    set(${OUT_PORT} ${LOCAL_PORT} PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_GetGdbPort
# Description: Port of the GDB server of all cores of a multi-core MCU (debug configuration "EmBi: Debug all cores
#              <MCU>" of the VS Code workspace) on 127.0.0.1 of this machine - the hash of the MCU, the same MCU gets
#              the same port (the input of the debug configuration and its preLaunchTask compute it separately).
#
# IN_MCU   [in]:  MCU.
# OUT_PORT [out]: Port.
# ------------------------------------------------------------------------------
function(Prj_VSCode_GetGdbPort IN_MCU OUT_PORT)

    string(MD5 MCU_HASH "${IN_MCU}")
    string(SUBSTRING "${MCU_HASH}" 0 6 MCU_HASH)
    math(EXPR PORT "${VSCODE_GDB_LOCAL_PORT_BASE} + 0x${MCU_HASH} % ${VSCODE_DEBUG_PORT_RANGE}")

    Prj_VSCode_FreePort(${PORT} PORT)

    set(${OUT_PORT} ${PORT} PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_PrintTargetGdb
# Description: Prints the gdb of the MCU (arm-none-eabi-gdb of the artifact gcc-arm-none-eabi in the version configured
#              for the Debug preset of the MCU) - gdb of the debug configuration "EmBi: Debug all cores <MCU>", never
#              gdb installed in the system.
#
# IN_MCU [in]: MCU.
# ------------------------------------------------------------------------------
function(Prj_VSCode_PrintTargetGdb IN_MCU)

    ArtifactsResolver_Get_BinDir(BIN_DIR RECORD "${PROJECT_ROOT_PATH}" "${IN_MCU}_Debug" gcc-arm-none-eabi)

    if("${RECORD}" STREQUAL "")
        message(FATAL_ERROR "No artifact gcc-arm-none-eabi is configured for the preset ${IN_MCU}_Debug.")
    endif()

    if("${BIN_DIR}" STREQUAL "")
        message(FATAL_ERROR "The artifact gcc-arm-none-eabi (configured: ${RECORD}) is not in the artifacts cache - it is "
                            "downloaded by the build of ${IN_MCU}.")
    endif()

    file(GLOB_RECURSE GDB_FILES "${BIN_DIR}/*arm-none-eabi-gdb" "${BIN_DIR}/*arm-none-eabi-gdb.exe")
    list(FILTER GDB_FILES INCLUDE REGEX "/bin/arm-none-eabi-gdb(\\.exe)?$")

    foreach(GDB_FILE IN LISTS GDB_FILES)
        if(NOT IS_DIRECTORY "${GDB_FILE}")
            Prj_VSCode_PrintOptions("${GDB_FILE}")
            return()
        endif()
    endforeach()

    message(FATAL_ERROR "arm-none-eabi-gdb is not a part of the artifact gcc-arm-none-eabi (configured: ${RECORD}, "
                        "${BIN_DIR}). gdb of the system is not used.")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_ServeAllCores
# Description: preLaunchTask of the debug configuration "EmBi: Debug all cores <MCU>" of the VS Code workspace of the
#              projects of the cores (background task, run in the project of the first core): the Debug firmware of
#              every core is built and flashed (probe-rs download with verification, the only connected probe as the
#              debug configurations of the MCU), the option bytes of the projects are compared and written, the MCU is
#              reset and the GDB server of probe-rs (all cores as threads) waits on 127.0.0.1:<port> for the session
#              of cortex-debug (it prints VSCODE_GDB_READY_PATTERN). The GDB server keeps listening after a session,
#              the task stops it when the session disconnects (or after VSCODE_GDB_CONNECT_TIMEOUT without a
#              session) and ends.
#
# IN_MCU [in]: MCU.
# ------------------------------------------------------------------------------
function(Prj_VSCode_ServeAllCores IN_MCU)

    message(STATUS "${VSCODE_DEBUG_BEGIN_PATTERN} of all cores of ${IN_MCU}")

    # A GDB server left by a previous session holds the probe
    Prj_VSCode_StopGdbServer()

    Prj_VSCode_GetCoreProjects(CORES)

    IntegrationTesting_ProvideProbeRs(VSCODE_PROBE_RS "${PROJECT_ROOT_PATH}" "${IN_MCU}")
    IntegrationTesting_ReadMcuIdentification(IDENTIFIED_MCUS "${VSCODE_RAL_PRESETS_FILE}")
    Prj_VSCode_GetChip(${IN_MCU} CHIP)

    set(FIRMWARES "")

    foreach(CORE IN LISTS CORES)

        message("==================== Debug firmware of the core ${CORE} ====================")

        execute_process(COMMAND "${CMAKE_COMMAND}" -DFUNCTION_ID=BUILD "-DMCU=${IN_MCU}" -DBUILD_TYPE=Debug
                                -P "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../Build_Handler/Build_Handler.cmake"
                        WORKING_DIRECTORY "${PLATFORM_ROOT_PATH}/${CORE}"
                        RESULT_VARIABLE BUILD_RESULT)

        if(NOT BUILD_RESULT EQUAL 0)
            message(FATAL_ERROR "Debug build of the project of the core ${CORE} failed - the cores are not debugged.")
        endif()

        Prj_VSCode_GetFirmwareName(Debug FIRMWARE "${PLATFORM_ROOT_PATH}/${CORE}")
        set(FIRMWARE_PATH "${PLATFORM_ROOT_PATH}/${CORE}/Build/${IN_MCU}_Debug/${FIRMWARE}")

        Build_Handler_Execute("Flashing of ${FIRMWARE} (core ${CORE})" "${VSCODE_PROBE_RS}" download --chip ${CHIP}
                              --verify "${FIRMWARE_PATH}")

        list(APPEND FIRMWARES "${FIRMWARE_PATH}")

    endforeach()

    # Option bytes - the projects of the cores flash one chip, they set the same ones
    list(GET FIRMWARES 0 FIRST_FIRMWARE)
    foreach(FIRMWARE_PATH IN LISTS FIRMWARES)
        OptionBytes_Compare(DIFFERENCE "${FIRST_FIRMWARE}" "${FIRMWARE_PATH}")
        if(NOT "${DIFFERENCE}" STREQUAL "")
            message(FATAL_ERROR "Option bytes of ${FIRST_FIRMWARE} and ${FIRMWARE_PATH} differ (${DIFFERENCE}) - the "
                                "projects of the cores flash one chip, set the same option bytes in all. Not debugged.")
        endif()
    endforeach()

    Prj_VSCode_WriteOptionBytes("${FIRST_FIRMWARE}" "${VSCODE_PROBE_RS}" "${CHIP}" "")
    Build_Handler_Execute("Reset of ${IN_MCU}" "${VSCODE_PROBE_RS}" reset --chip ${CHIP})

    # GDB server in the background - it keeps listening after the session, the task stops it when the session ends
    Prj_VSCode_GetGdbPort(${IN_MCU} PORT)
    Prj_VSCode_StartGdbServer(SERVER_PID "${VSCODE_PROBE_RS}" "${CHIP}" ${PORT})

    if("${SERVER_PID}" STREQUAL "")
        message(FATAL_ERROR "The GDB server of probe-rs (${VSCODE_PROBE_RS}) is not started.")
    endif()

    set(LISTENING FALSE)
    foreach(POLL RANGE 100)
        IntegrationTesting_IsListening(LISTENING ${PORT})
        if(LISTENING)
            break()
        endif()
        execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep 0.2)
    endforeach()

    if(NOT LISTENING)
        Prj_VSCode_StopGdbServer()
        set(SERVER_OUTPUT "")
        foreach(LOG_FILE IN ITEMS "${VSCODE_GDB_SERVER_LOG_FILE}" "${VSCODE_GDB_SERVER_LOG_FILE}.err")
            if(EXISTS "${LOG_FILE}")
                file(READ "${LOG_FILE}" LOG_CONTENT)
                string(APPEND SERVER_OUTPUT "${LOG_CONTENT}")
            endif()
        endforeach()
        message(FATAL_ERROR "The GDB server of probe-rs does not listen on 127.0.0.1:${PORT}:\n${SERVER_OUTPUT}")
    endif()

    message(STATUS "${VSCODE_GDB_READY_PATTERN} ${PORT} (all cores of ${IN_MCU})")

    # The session connects, its end closes the connection
    set(CONNECTED_ONCE FALSE)
    set(WAITED 0)

    while(TRUE)

        execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep 1)

        Prj_VSCode_GdbServerAlive(ALIVE)
        if(NOT ALIVE)
            break()
        endif()

        IntegrationTesting_IsConnected(CONNECTED ${PORT})
        if(CONNECTED)
            set(CONNECTED_ONCE TRUE)
        elseif(CONNECTED_ONCE)
            break()
        else()
            math(EXPR WAITED "${WAITED} + 1")
            if(WAITED GREATER VSCODE_GDB_CONNECT_TIMEOUT)
                message(WARNING "No debug session connected to the GDB server within ${VSCODE_GDB_CONNECT_TIMEOUT} s.")
                break()
            endif()
        endif()

    endwhile()

    Prj_VSCode_StopGdbServer()
    message(STATUS "EmBi: GDB server of all cores of ${IN_MCU} ended")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_StartGdbServer
# Description: Starts the GDB server of probe-rs (all cores of the chip) in the background on 127.0.0.1:<port> - its
#              output goes to VSCODE_GDB_SERVER_LOG_FILE, its process id to VSCODE_GDB_SERVER_PID_FILE (the only
#              connected probe).
#
# OUT_PID     [out]: Process id ("" - not started).
# IN_PROBE_RS [in]:  probe-rs executable.
# IN_CHIP     [in]:  probe-rs chip.
# IN_PORT     [in]:  Port of 127.0.0.1.
# ------------------------------------------------------------------------------
function(Prj_VSCode_StartGdbServer OUT_PID IN_PROBE_RS IN_CHIP IN_PORT)

    file(REMOVE "${VSCODE_GDB_SERVER_LOG_FILE}" "${VSCODE_GDB_SERVER_LOG_FILE}.err")

    if(CMAKE_HOST_WIN32)
        set(SERVER_ARGS "gdb --chip ${IN_CHIP} --gdb-connection-string 127.0.0.1:${IN_PORT}")
        # The process id goes through a file: probe-rs inherits the handles of PowerShell, a pipe of execute_process
        # would be kept open by it and execute_process would wait for its end (as itRun_TraceStart)
        execute_process(
            COMMAND powershell -NoProfile -NonInteractive -Command
                    "(Start-Process -FilePath '${IN_PROBE_RS}' -ArgumentList '${SERVER_ARGS}' -RedirectStandardOutput '${VSCODE_GDB_SERVER_LOG_FILE}' -RedirectStandardError '${VSCODE_GDB_SERVER_LOG_FILE}.err' -WindowStyle Hidden -PassThru).Id"
            OUTPUT_FILE "${VSCODE_GDB_SERVER_PID_FILE}.out"
            ERROR_FILE  "${VSCODE_GDB_SERVER_PID_FILE}.err"
        )
        file(READ "${VSCODE_GDB_SERVER_PID_FILE}.out" SERVER_PID)
        string(STRIP "${SERVER_PID}" SERVER_PID)
        file(REMOVE "${VSCODE_GDB_SERVER_PID_FILE}.out" "${VSCODE_GDB_SERVER_PID_FILE}.err")
    else()
        execute_process(
            COMMAND sh -c "\"$0\" gdb --chip \"$1\" --gdb-connection-string \"$2\" > \"$3\" 2> \"$3.err\" & echo $!"
                    "${IN_PROBE_RS}" "${IN_CHIP}" "127.0.0.1:${IN_PORT}" "${VSCODE_GDB_SERVER_LOG_FILE}"
            OUTPUT_VARIABLE SERVER_PID
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
    endif()

    if(NOT SERVER_PID MATCHES "^[0-9]+$")
        set(SERVER_PID "")
    endif()

    file(WRITE "${VSCODE_GDB_SERVER_PID_FILE}" "${SERVER_PID}")
    set(${OUT_PID} "${SERVER_PID}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_GdbServerAlive
# Description: Checks whether the GDB server of VSCODE_GDB_SERVER_PID_FILE runs.
#
# OUT_ALIVE [out]: TRUE while the process runs.
# ------------------------------------------------------------------------------
function(Prj_VSCode_GdbServerAlive OUT_ALIVE)

    set(ALIVE FALSE)
    set(SERVER_PID "")

    if(EXISTS "${VSCODE_GDB_SERVER_PID_FILE}")
        file(READ "${VSCODE_GDB_SERVER_PID_FILE}" SERVER_PID)
        string(STRIP "${SERVER_PID}" SERVER_PID)
    endif()

    if(SERVER_PID MATCHES "^[0-9]+$")
        if(CMAKE_HOST_WIN32)
            execute_process(
                COMMAND powershell -NoProfile -NonInteractive -Command
                        "if (Get-Process -Id ${SERVER_PID} -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
                RESULT_VARIABLE ALIVE_RESULT
                OUTPUT_QUIET
                ERROR_QUIET
            )
        else()
            execute_process(COMMAND kill -0 ${SERVER_PID} RESULT_VARIABLE ALIVE_RESULT OUTPUT_QUIET ERROR_QUIET)
        endif()
        if(ALIVE_RESULT EQUAL 0)
            set(ALIVE TRUE)
        endif()
    endif()

    set(${OUT_ALIVE} ${ALIVE} PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_StopGdbServer
# Description: Stops the GDB server of VSCODE_GDB_SERVER_PID_FILE (the probe is free for the next session) - nothing
#              when no server runs.
# ------------------------------------------------------------------------------
function(Prj_VSCode_StopGdbServer)

    Prj_VSCode_GdbServerAlive(ALIVE)

    if(ALIVE)
        file(READ "${VSCODE_GDB_SERVER_PID_FILE}" SERVER_PID)
        string(STRIP "${SERVER_PID}" SERVER_PID)
        if(CMAKE_HOST_WIN32)
            execute_process(
                COMMAND powershell -NoProfile -NonInteractive -Command
                        "Stop-Process -Id ${SERVER_PID} -Force -ErrorAction SilentlyContinue"
                OUTPUT_QUIET
                ERROR_QUIET
            )
        else()
            execute_process(COMMAND kill -INT ${SERVER_PID} OUTPUT_QUIET ERROR_QUIET)
            execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep 1)
            execute_process(COMMAND kill -KILL ${SERVER_PID} OUTPUT_QUIET ERROR_QUIET)
        endif()
    endif()

    file(REMOVE "${VSCODE_GDB_SERVER_PID_FILE}")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_PrintDebugBoardServer
# Description: Prints the debug server of the picked board (127.0.0.1:<local port>, member "server" of
#              the debug configuration) and writes the picked board into VSCODE_DEBUG_TARGET_FILE for the
#              preLaunchTask (Prj_VSCode_ProbeRs.cmake DEBUG_SERVE).
#
# IN_ID [in]: ID of the picked board.
# ------------------------------------------------------------------------------
function(Prj_VSCode_PrintDebugBoardServer IN_ID)

    Prj_VSCode_GetTarget("${IN_ID}" TARGET_IDX)
    Prj_VSCode_GetServerPorts(${TARGET_IDX}
                              ${VSCODE_DEBUG_LOCAL_PORT_BASE}
                              ${VSCODE_DEBUG_REMOTE_PORT_BASE}
                              LOCAL_PORT
                              REMOTE_PORT)

    set(HOST "${IT_TARGET_${TARGET_IDX}_HOST}")
    set(HOST_TOOLS "")

    if(NOT "${HOST}" STREQUAL "${IT_LOCAL_HOST}")
        IntegrationTesting_ReadItHosts(HOSTS "${PROJECT_ROOT_PATH}")
        set(HOST_TOOLS "${IT_HOST_${HOST}_TOOLS}")
    endif()

    set(CONTENT "# Generated by the input debugServer of the debug configurations of a picked board (VS Code)\n")
    string(APPEND CONTENT "set(DEBUG_TARGET_ID     [==[${IT_TARGET_${TARGET_IDX}_ID}]==])\n")
    string(APPEND CONTENT "set(DEBUG_TARGET_TEXT   [==[${IT_TARGET_${TARGET_IDX}_TEXT}]==])\n")
    string(APPEND CONTENT "set(DEBUG_MCU           [==[${IT_TARGET_${TARGET_IDX}_MCU}]==])\n")
    string(APPEND CONTENT "set(DEBUG_BOARD         [==[${IT_TARGET_${TARGET_IDX}_BOARD}]==])\n")
    string(APPEND CONTENT "set(DEBUG_HOST          [==[${HOST}]==])\n")
    string(APPEND CONTENT "set(DEBUG_SSH_TARGET    [==[${IT_TARGET_${TARGET_IDX}_TARGET}]==])\n")
    string(APPEND CONTENT "set(DEBUG_HOST_TOOLS    [==[${HOST_TOOLS}]==])\n")
    string(APPEND CONTENT "set(DEBUG_PROBE         [==[${IT_TARGET_${TARGET_IDX}_PROBE}]==])\n")
    string(APPEND CONTENT "set(DEBUG_LOCAL_PORT    ${LOCAL_PORT})\n")
    string(APPEND CONTENT "set(DEBUG_REMOTE_PORT   ${REMOTE_PORT})\n")

    file(WRITE "${VSCODE_DEBUG_TARGET_FILE}" "${CONTENT}")

    Prj_VSCode_PrintOptions("127.0.0.1:${LOCAL_PORT}")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_SerialServe
# Description: Task "EmBi: Serial monitor on board" - the virtual COM port of the picked board of an IT agent
#              on 127.0.0.1:<port> of this machine: the serial server of the agent tools (IT agent interface,
#              embi-agent serial-server) behind ssh -tt -L <port>:127.0.0.1:<port of the agent>, nothing is
#              copied to the agent. The Serial Monitor (ms-vscode.vscode-serial-monitor) connects there in TCP
#              mode; the same board gets the same port. The probe is not locked - the board is debugged and
#              tested meanwhile. The task runs until it is terminated (the serial server of the agent ends with
#              the connection) or ends with an error (port used by another serial monitor, agent not reachable).
#              A board of this machine has its virtual COM port as a serial port of this machine - the Serial
#              Monitor opens it directly.
#
# IN_ID   [in]: ID of the picked board.
# IN_BAUD [in]: Baud rate of the virtual COM port.
# ------------------------------------------------------------------------------
function(Prj_VSCode_SerialServe IN_ID IN_BAUD)

    if(NOT "${IN_BAUD}" MATCHES "^[1-9][0-9]*$")
        message(FATAL_ERROR "Required BAUD '${IN_BAUD}' is not a baud rate.")
    endif()

    Prj_VSCode_GetTarget("${IN_ID}" TARGET_IDX)

    set(HOST "${IT_TARGET_${TARGET_IDX}_HOST}")
    set(TEXT "${IT_TARGET_${TARGET_IDX}_TEXT}")

    if("${HOST}" STREQUAL "${IT_LOCAL_HOST}")
        message(FATAL_ERROR "${TEXT} is a board of this machine - its virtual COM port is a serial port of this "
                            "machine, open it in the Serial Monitor directly.")
    endif()

    Prj_VSCode_GetServerPorts(${TARGET_IDX}
                              ${VSCODE_SERIAL_LOCAL_PORT_BASE}
                              ${VSCODE_SERIAL_REMOTE_PORT_BASE}
                              LOCAL_PORT
                              REMOTE_PORT)

    IntegrationTesting_ReadItHosts(HOSTS "${PROJECT_ROOT_PATH}")
    IntegrationTesting_Get_LockHolder(HOLDER "serial monitor")

    # The local port of the tunnel of the previous serial monitor of a restart may still be closing
    foreach(POLL_IDX RANGE 1 30)
        IntegrationTesting_IsListening(PORT_USED ${LOCAL_PORT})
        if(NOT PORT_USED)
            break()
        endif()
        execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep 0.5)
    endforeach()

    if(PORT_USED)
        message(FATAL_ERROR "Port ${LOCAL_PORT} of 127.0.0.1 is used - the serial monitor of ${TEXT} is open already "
                            "(another task \"EmBi: Serial monitor on board\"), or another program uses the port.")
    endif()

    IntegrationTesting_Get_SshCommand(SSH_COMMAND
                                      "${IT_TARGET_${TARGET_IDX}_TARGET}"
                                      TRUE
                                      -o ExitOnForwardFailure=yes
                                      -L "${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}")

    IntegrationTesting_Get_AgentLine(REMOTE_COMMAND
                                     "${IT_HOST_${HOST}_TOOLS}"
                                     serial-server
                                     --probe
                                     "${IT_TARGET_${TARGET_IDX}_PROBE}"
                                     --port
                                     ${REMOTE_PORT}
                                     --baud
                                     ${IN_BAUD}
                                     --holder
                                     "${HOLDER}")

    message("EmBi: serial monitor of ${TEXT}, ${IN_BAUD} baud")
    message("EmBi: Serial Monitor - Monitor Mode TCP, Host 127.0.0.1, Port ${LOCAL_PORT}, Start Monitoring")
    message("EmBi: the virtual COM port stays open until this task is terminated")

    execute_process(COMMAND ${SSH_COMMAND} "${REMOTE_COMMAND}"
                    RESULT_VARIABLE SERVE_RESULT)

    if(SERVE_RESULT EQUAL IT_AGENT_NOT_INSTALLED)
        message(FATAL_ERROR "embi-agent is not installed on the IT agent ${HOST} (${IT_TARGET_${TARGET_IDX}_TARGET}) "
                            "- the pipeline ItAgentUpdate of EmBi_Tester installs it (or tools of the host in "
                            "ItHosts.json).")
    endif()

    if(NOT SERVE_RESULT EQUAL 0)
        message(FATAL_ERROR "Serial monitor of ${TEXT} ended with ${SERVE_RESULT} - see the output of the agent above.")
    endif()
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_PrintDebugBoard
# Description: Prints a value of the picked board for the debug configurations of a picked board - its
#              probe, the chip, the SVD file, the Debug firmware or the integration test firmwares of its MCU.
#
# IN_ID   [in]: ID of the picked board.
# IN_ITEM [in]: PROBE, CHIP, SVD, FIRMWARE or TESTS.
# ------------------------------------------------------------------------------
function(Prj_VSCode_PrintDebugBoard IN_ID IN_ITEM)

    Prj_VSCode_GetTarget("${IN_ID}" TARGET_IDX)
    set(MCU "${IT_TARGET_${TARGET_IDX}_MCU}")

    if("${IN_ITEM}" STREQUAL "PROBE")
        Prj_VSCode_PrintOptions("${IT_TARGET_${TARGET_IDX}_PROBE}")
    elseif("${IN_ITEM}" STREQUAL "CHIP")
        Prj_VSCode_PrintDebugChip("${MCU}")
    elseif("${IN_ITEM}" STREQUAL "SVD")
        Prj_VSCode_PrintDebugSvd("${MCU}")
    elseif("${IN_ITEM}" STREQUAL "FIRMWARE")
        # The Debug build of the board (its configuration - fixture, own defines), Build_Handler BUILD with BOARD
        Build_Handler_Get_BoardBuild("${IT_TARGET_${TARGET_IDX}_BOARD}" Debug BOARD_MCU BOARD_PRESET BOARD_DIR)
        Prj_VSCode_GetFirmwareName(Debug FIRMWARE)
        Prj_VSCode_PrintOptions("${BOARD_DIR}/${FIRMWARE}")
    elseif("${IN_ITEM}" STREQUAL "TESTS")
        Prj_VSCode_PrintDebugTests(IT "${MCU}")
    else()
        message(FATAL_ERROR "Unknown item '${IN_ITEM}' of the picked board.")
    endif()
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_PrintMcus
# Description: Prints the MCUs of the project presets.
# ------------------------------------------------------------------------------
function(Prj_VSCode_PrintMcus)

    Build_Handler_GetMcuList(MCU_LIST)

    Prj_VSCode_PrintOptions(${MCU_LIST})
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_TestOption
# Description: Option of a test - <file>|<test name>|<module> (<MCU>).
#
# OUT_LINE [out]: Option.
# IN_DIR   [in]:  Folder with the test executables of the build.
# IN_TEST  [in]:  Test (<module path>/Tests/<dir>/<UT|IT>_<NAME><suffix>).
# IN_MCU   [in]:  MCU of the build ("" = not shown).
# ------------------------------------------------------------------------------
function(Prj_VSCode_TestOption OUT_LINE IN_DIR IN_TEST IN_MCU)

    get_filename_component(NAME "${IN_TEST}" NAME_WE)
    get_filename_component(MODULE "${IN_TEST}" DIRECTORY)
    string(REGEX REPLACE "/Tests/(UnitTests|IntegrationTests)$" "" MODULE "${MODULE}")
    # Module of the shared Bsp of the projects of the cores (Prj_VSCode_GetTestFirmwares)
    if(VSCODE_CORE_PROJECT)
        string(REGEX REPLACE "^(External/|(\\.\\./)+)" "" MODULE "${MODULE}")
    endif()

    if(NOT "${IN_MCU}" STREQUAL "")
        set(MODULE "${MODULE} (${IN_MCU})")
    endif()

    set(${OUT_LINE} "${IN_DIR}/${IN_TEST}|${NAME}|${MODULE}" PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_PrintDebugTests
# Description: Prints the test executables to debug - tests registered in the
#              project (Prj_VSCode_GetTestFirmwares, new tests are found without
#              the initialization): integration test firmwares or unit test
#              executables of the MCU.
#
# IN_TEST_TYPE [in]: UT or IT.
# IN_MCU       [in]: MCU.
# ------------------------------------------------------------------------------
function(Prj_VSCode_PrintDebugTests IN_TEST_TYPE IN_MCU)

    set(LINES "")

    if("${IN_TEST_TYPE}" STREQUAL "IT")

        Prj_VSCode_GetTestFirmwares(IntegrationTests TESTS)

        foreach(TEST IN LISTS TESTS)
            Prj_VSCode_TestOption(LINE "${BUILD_HANDLER_BUILD_DIR}/${IN_MCU}_IntegrationTest/IntegrationTests" "${TEST}" "")
            list(APPEND LINES "${LINE}")
        endforeach()

        set(MISSING_TEXT "No integration test is registered in the project (Tests/IntegrationTests/CMakeLists.txt of the modules).")

    elseif("${IN_TEST_TYPE}" STREQUAL "UT")

        Prj_VSCode_GetTestFirmwares(UnitTests TESTS)

        foreach(TEST IN LISTS TESTS)
            Prj_VSCode_TestOption(LINE "${BUILD_HANDLER_BUILD_DIR}/${IN_MCU}_UnitTest/UnitTests" "${TEST}" "")
            list(APPEND LINES "${LINE}")
        endforeach()

        set(MISSING_TEXT "No unit test is registered in the project (Tests/UnitTests/CMakeLists.txt of the modules).")

    else()

        message(FATAL_ERROR "Required TEST_TYPE '${IN_TEST_TYPE}' is not correct (UT, IT).")

    endif()

    if(NOT LINES)
        # No output - the error of the input shows this text
        message("${MISSING_TEXT}")
        return()
    endif()

    Prj_VSCode_PrintOptions(${LINES})
endfunction()


#==============================================================================#
# Main functionality
#
# If the script is executed in script mode ( -P ), execution is started with
# first direct code out of function, thus functions execution has to be
# triggered.
#
# Example:
# cmake -DFUNCTION_ID="MCU_LIST"                                    -P Prj_VSCode_Handler.cmake : List MCUs of the project presets
# cmake -DFUNCTION_ID="FIRMWARE_NAME"                               -P Prj_VSCode_Handler.cmake : Print current firmware name of the root CMakeLists.txt
# cmake -DFUNCTION_ID="INIT"  -DMCU_IDS="1,3" -DFIRMWARE_NAME=Fw    -P Prj_VSCode_Handler.cmake : Generate .vscode, debug configurations of MCUs 1 and 3 (0 = all, empty = connected boards), firmware Fw_<build type>.elf (empty = current name)
# cmake -DFUNCTION_ID="FLASH" -DTARGET=<ID> -DBUILD_TYPE=Debug      -P Prj_VSCode_Handler.cmake : Build for the picked board, flash it and reset its MCU (this machine or IT agent)
# cmake -DFUNCTION_ID="OPTION_BYTES" -DMCU=STM32F407xG | -DTARGET=<ID> -P Prj_VSCode_Handler.cmake : Write the option bytes of the Debug firmware of the MCU (or of the picked board) when the chip has other values (preLaunchTask of the debug configurations)
# cmake -DFUNCTION_ID="OTHER_CORES" -DMCU=STM32H755xI | -DTARGET=<ID> -P Prj_VSCode_Handler.cmake : Build and flash the Debug firmware of the projects of the other cores (preLaunchTask of the debug configurations of the project of a core)
# cmake -DFUNCTION_ID="GDB_SERVER" -DMCU=STM32H755xI                -P Prj_VSCode_Handler.cmake : Print 127.0.0.1:<port> of the GDB server of all cores (input of "EmBi: Debug all cores <MCU>")
# cmake -DFUNCTION_ID="TARGET_GDB" -DMCU=STM32H755xI                -P Prj_VSCode_Handler.cmake : Print arm-none-eabi-gdb of the artifacts of the MCU (input of "EmBi: Debug all cores <MCU>")
# cmake -DFUNCTION_ID="SERVE_ALL_CORES" -DMCU=STM32H755xI           -P Prj_VSCode_Handler.cmake : Build and flash the Debug firmware of all cores, start the GDB server of probe-rs (preLaunchTask of "EmBi: Debug all cores <MCU>")
# cmake -DFUNCTION_ID="EXTENSIONS_CHECK"                            -P Prj_VSCode_Handler.cmake : Print recommended extensions that are not installed
# cmake -DFUNCTION_ID="EXTENSIONS_INSTALL"                          -P Prj_VSCode_Handler.cmake : Install the missing recommended extensions (code command)
# cmake -DFUNCTION_ID="PICK_MCU"                                    -P Prj_VSCode_Handler.cmake : Print MCUs (input of the tasks)
# cmake -DFUNCTION_ID="PICK_BOARD"                                  -P Prj_VSCode_Handler.cmake : Detect and print the boards of this machine and of the IT agents and "All connected boards" (input of the integration test task)
# cmake -DFUNCTION_ID="PICK_TEST_SET" -DTEST_TYPE=UT                -P Prj_VSCode_Handler.cmake : Print test sets of the unit tests (IT = integration tests, input of the tasks)
# cmake -DFUNCTION_ID="DEBUG_CHIP" -DMCU=STM32F407xG                -P Prj_VSCode_Handler.cmake : Print probe-rs chip of the MCU (input of the debug configuration)
# cmake -DFUNCTION_ID="DEBUG_SVD" -DMCU=STM32F407xG                  -P Prj_VSCode_Handler.cmake : Print SVD file of the MCU from the Ral module Svd (input of the debug configuration)
# cmake -DFUNCTION_ID="DEBUG_GDB" -DMCU=STM32F407xG                  -P Prj_VSCode_Handler.cmake : Print host gdb of the unit tests of the MCU (input of the debug configuration)
# cmake -DFUNCTION_ID="DEBUG_FIRMWARE" -DMCU=STM32F407xG -DBUILD_TYPE=Debug -P Prj_VSCode_Handler.cmake : Print firmware file of the MCU (input of the debug configuration)
# cmake -DFUNCTION_ID="DEBUG_TESTS" -DTEST_TYPE=IT -DMCU=STM32F407xG -P Prj_VSCode_Handler.cmake : Print test executables of the MCU (UT or IT - input of the debug configuration)
# cmake -DFUNCTION_ID="PICK_DEBUG_BOARD"                            -P Prj_VSCode_Handler.cmake : Detect and print the boards of this machine and of the IT agents (input debugBoard)
# cmake -DFUNCTION_ID="DEBUG_BOARD_SERVER" -DTARGET=<ID>            -P Prj_VSCode_Handler.cmake : Print 127.0.0.1:<port> of the debug server of the picked board, write Build/DebugTarget.cmake
# cmake -DFUNCTION_ID="DEBUG_BOARD_CHIP" -DTARGET=<ID>              -P Prj_VSCode_Handler.cmake : Print the probe (PROBE), chip (CHIP), SVD file (SVD), Debug firmware (FIRMWARE) or the integration tests (TESTS) of the picked board
# cmake -DFUNCTION_ID="PICK_SERIAL_BOARD"                           -P Prj_VSCode_Handler.cmake : Detect and print the boards of the IT agents (input serialBoard)
# cmake -DFUNCTION_ID="SERIAL_SERVE" -DTARGET=<ID> -DBAUD=115200    -P Prj_VSCode_Handler.cmake : Open the virtual COM port of the picked board of an IT agent on 127.0.0.1:<port> for the Serial Monitor (TCP mode) until terminated
# cmake -DFUNCTION_ID="RUN_CORES" -DCORES="All cores" -DALL_CORES=CM7,CM4 -DCORE_ARGS="-DFUNCTION_ID=BUILD|...|-P|<script>" -P Prj_VSCode_Handler.cmake : Run cmake with CORE_ARGS in the projects of the selected cores of a multi-core MCU one after another (platform root folder, task of the VS Code workspace)
#==============================================================================#
if(CMAKE_SCRIPT_MODE_FILE AND
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)

    if("${FUNCTION_ID}" STREQUAL "MCU_LIST")

        Prj_VSCode_PrintMcuList()

    elseif("${FUNCTION_ID}" STREQUAL "INIT")

        Prj_VSCode_Init("${MCU_IDS}" "${FIRMWARE_NAME}")

    elseif("${FUNCTION_ID}" STREQUAL "FIRMWARE_NAME")

        Prj_VSCode_PrintFirmwareName()

    elseif("${FUNCTION_ID}" STREQUAL "EXTENSIONS_CHECK")

        Prj_VSCode_PrintMissingExtensions()

    elseif("${FUNCTION_ID}" STREQUAL "EXTENSIONS_INSTALL")

        Prj_VSCode_InstallExtensions()

    elseif("${FUNCTION_ID}" STREQUAL "PICK_MCU")

        Prj_VSCode_PrintMcus()

    elseif("${FUNCTION_ID}" STREQUAL "PICK_BOARD")

        Prj_VSCode_PrintTargets(TRUE FALSE)

    elseif("${FUNCTION_ID}" STREQUAL "PICK_DEBUG_BOARD")

        Prj_VSCode_PrintTargets(FALSE FALSE)

    elseif("${FUNCTION_ID}" STREQUAL "PICK_SERIAL_BOARD")

        Prj_VSCode_PrintTargets(FALSE TRUE)

    elseif("${FUNCTION_ID}" STREQUAL "SERIAL_SERVE")

        Prj_VSCode_SerialServe("${TARGET}" "${BAUD}")

    elseif("${FUNCTION_ID}" STREQUAL "RUN_CORES")

        Prj_VSCode_RunCores("${CORES}" "${ALL_CORES}" "${CORE_ARGS}")

    elseif("${FUNCTION_ID}" STREQUAL "DEBUG_BOARD_SERVER")

        Prj_VSCode_PrintDebugBoardServer("${TARGET}")

    elseif("${FUNCTION_ID}" MATCHES "^DEBUG_BOARD_(PROBE|CHIP|SVD|FIRMWARE|TESTS)$")

        Prj_VSCode_PrintDebugBoard("${TARGET}" "${CMAKE_MATCH_1}")

    elseif("${FUNCTION_ID}" STREQUAL "PICK_TEST_SET")

        Prj_VSCode_PrintTestSets("${TEST_TYPE}")

    elseif("${FUNCTION_ID}" STREQUAL "DEBUG_CHIP")

        Prj_VSCode_PrintDebugChip("${MCU}")

    elseif("${FUNCTION_ID}" STREQUAL "DEBUG_SVD")

        Prj_VSCode_PrintDebugSvd("${MCU}")

    elseif("${FUNCTION_ID}" STREQUAL "DEBUG_GDB")

        Prj_VSCode_PrintDebugGdb("${MCU}")

    elseif("${FUNCTION_ID}" STREQUAL "DEBUG_FIRMWARE")

        if(NOT "${BUILD_TYPE}" MATCHES "^(Debug|Release)$")
            message(FATAL_ERROR "Required BUILD_TYPE '${BUILD_TYPE}' is not correct (Debug, Release).")
        endif()

        Prj_VSCode_PrintDebugFirmware("${MCU}" "${BUILD_TYPE}")

    elseif("${FUNCTION_ID}" STREQUAL "DEBUG_TESTS")

        Prj_VSCode_PrintDebugTests("${TEST_TYPE}" "${MCU}")

    elseif("${FUNCTION_ID}" STREQUAL "FLASH")

        if(NOT "${BUILD_TYPE}" MATCHES "^(Debug|Release)$")
            message(FATAL_ERROR "Required BUILD_TYPE '${BUILD_TYPE}' is not correct (Debug, Release).")
        endif()

        # The task of a .vscode of an older platform picks the MCU, not the board
        if("${TARGET}" STREQUAL "")
            message(FATAL_ERROR "Required TARGET (picked board) is missing - the task \"EmBi: Flash\" of this .vscode "
                                "picks the MCU, generate .vscode again (EmBi: Setup, VSCode project initialization).")
        endif()

        Prj_VSCode_Flash("${TARGET}" "${BUILD_TYPE}")

    elseif("${FUNCTION_ID}" STREQUAL "OPTION_BYTES")

        Prj_VSCode_DebugOptionBytes("${MCU}" "${TARGET}")

    elseif("${FUNCTION_ID}" STREQUAL "OTHER_CORES")

        Prj_VSCode_FlashOtherCores("${MCU}" "${TARGET}")

    elseif("${FUNCTION_ID}" STREQUAL "GDB_SERVER")

        Prj_VSCode_GetGdbPort("${MCU}" GDB_PORT)
        Prj_VSCode_PrintOptions("127.0.0.1:${GDB_PORT}")

    elseif("${FUNCTION_ID}" STREQUAL "TARGET_GDB")

        Prj_VSCode_PrintTargetGdb("${MCU}")

    elseif("${FUNCTION_ID}" STREQUAL "SERVE_ALL_CORES")

        Prj_VSCode_ServeAllCores("${MCU}")

    else()

        message(FATAL_ERROR "Unknown FUNCTION_ID '${FUNCTION_ID}'.")

    endif()

endif()
