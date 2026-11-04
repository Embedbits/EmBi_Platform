################################################################################
#
# Project structure initialization CMake script.
#
# The project structure shall have following structure:
#
# Project_root/
# │
# ...
# ├── ArtifactsConfig.txt           (Artifacts configuration file)
# ├── CMakePresets.json             (Project CMake presets)
# ├── CMakeLists.txt                (Project root CMake file)
# └── README.md                     (Project documentation)
#
# User can execute initialization of this structure through this CMake script.
#
# A multi-core MCU (STM32H745 / H747 / H755 / H757) has one project per core,
# the projects of the cores share EmBi_Platform and Bsp in the project root:
#
# Project_root/
# ├── EmBi_Platform/, Bsp/          (shared by the projects of the cores)
# ├── CM7/                          (project of the core: CMakeLists.txt with
# ├── CM4/                           TARGET_CORE, CMakePresets.json,
# │                                  ArtifactsConfig.txt, Application/, ...)
# └── <Project_root>.code-workspace (VS Code workspace of the projects)
#
#   cmake -DFUNCTION_ID=CORE_PROJECTS -DMCU=STM32H755xI [-DMCU_IDS=0] [-DFIRMWARE_NAME=Fw] -P Prj_Handler.cmake
#
# The VSCode project initialization of a project with a multi-core MCU runs it
# (Prj_VSCode_Handler.cmake INIT).
#
################################################################################

# Set path to the CMakeLists.txt handler module
get_filename_component(CMAKELISTS_HANDLER_PATH "${CMAKE_CURRENT_LIST_DIR}/../CMakeLists_Handler/CMakeLists_Handler.cmake" REALPATH)

# Include CMakeLists.txt handler module
include("${CMAKELISTS_HANDLER_PATH}")


# Set path to system configuration file
get_filename_component(SYSTEM_CONFIG_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/../../SysConfig.cmake" REALPATH)

# Include file with system configuration values
include("${SYSTEM_CONFIG_FILE_PATH}")

#==============================================================================#
# Global variables
#==============================================================================#

# Read project root folder path
SysConfig_Get_ProjectRootPath(PROJECT_ROOT_PATH)

# Folder of the templates (CMAKE_CURRENT_LIST_DIR inside of a function is the
# folder of the file, which calls it - the function can be called from other handlers)
set(PRJ_HANDLER_TEMPLATES_PATH "${CMAKE_CURRENT_LIST_DIR}")


# ------------------------------------------------------------------------------
# Function: ProjectStructureInit_ProjectRootInit
# Description:
#   Initialization of Project root folder structure.
#   The necessary files are created with following structure:
#   Project_Root/
#   ├── ArtifactsConfig.txt      (Artifacts configuration file)
#   ├── CMakePresets.json        (Project CMake presets)
#   └── CMakeLists.txt           (Project root CMake file)
# ------------------------------------------------------------------------------
function(ProjectStructureInit_ProjectRootInit)

    if(NOT EXISTS "${PROJECT_ROOT_PATH}/CMakeLists.txt")
        file(COPY_FILE "${PRJ_HANDLER_TEMPLATES_PATH}/Template_CMakeLists.txt.in"
            "${PROJECT_ROOT_PATH}/CMakeLists.txt"
            ONLY_IF_DIFFERENT)
    endif()
        
    if(NOT EXISTS "${PROJECT_ROOT_PATH}/ArtifactsConfig.txt")
        file(COPY_FILE "${PRJ_HANDLER_TEMPLATES_PATH}/Template_ArtifactsConfig.txt.in"
            "${PROJECT_ROOT_PATH}/ArtifactsConfig.txt"
            ONLY_IF_DIFFERENT)
    endif()

    # Presets of MCU targets are added by BSP configuration (Prj_PresetsHandler)
    if(NOT EXISTS "${PROJECT_ROOT_PATH}/CMakePresets.json")
        file(COPY_FILE "${PRJ_HANDLER_TEMPLATES_PATH}/Template_CMakePresets.json.in"
            "${PROJECT_ROOT_PATH}/CMakePresets.json"
            ONLY_IF_DIFFERENT)
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: ProjectStructureInit_CoreProjectsInit
# Description:
#   Creates the project of every core of a multi-core MCU in a subfolder of the
#   platform root folder named by the core (CM7, CM4 - "cores" of the
#   identification of the Ral preset of the MCU, ral-presets.sh): CMakeLists.txt
#   of the template with TARGET_CORE (core of the project), TARGET_CORES (all
#   cores of the MCU) and PLATFORM_ROOT_PATH (parent folder), ArtifactsConfig.txt,
#   CMakePresets.json with the MCUs of the core, Application layer, the board
#   files of the platform root (ItBoards.json, ItHosts.json) and the VS Code
#   configuration of the project and the workspace of the projects
#   (Prj_VSCode_Handler INIT, started by the VSCode project initialization of a
#   project with a multi-core MCU). Files which already exist are kept.
#
# IN_MCU           [in]: MCU preset (e.g. STM32H755xI).
# IN_MCU_IDS       [in]: MCUs of the debug configurations (IDs or names separated by comma, empty or 0 = all MCUs of
#                        the core).
# IN_FIRMWARE_NAME [in]: Firmware name, the project of a core gets <name>_<core> (empty = current name is kept).
# ------------------------------------------------------------------------------
function(ProjectStructureInit_CoreProjectsInit IN_MCU IN_MCU_IDS IN_FIRMWARE_NAME)

    SysConfig_Get_PlatformRootPath(PLATFORM_ROOT_PATH)

    set(RAL_PRESETS_FILE "${PLATFORM_ROOT_PATH}/Bsp/Ral/RalPresets.json")

    if(NOT EXISTS "${RAL_PRESETS_FILE}")
        message(FATAL_ERROR "${RAL_PRESETS_FILE} not found - run \"BSP module - Configuration\" first.")
    endif()

    file(READ "${RAL_PRESETS_FILE}" RAL_JSON)

    # Cores of the MCU - identification of its Ral preset
    set(CORES "")
    string(JSON PRESET_COUNT LENGTH "${RAL_JSON}" configurePresets)
    math(EXPR LAST_PRESET_INDEX "${PRESET_COUNT} - 1")

    foreach(PRESET_INDEX RANGE ${LAST_PRESET_INDEX})

        string(JSON PRESET_NAME GET "${RAL_JSON}" configurePresets ${PRESET_INDEX} name)

        if(PRESET_NAME STREQUAL IN_MCU)
            string(JSON CORE_COUNT ERROR_VARIABLE JSON_ERROR
                   LENGTH "${RAL_JSON}" configurePresets ${PRESET_INDEX} vendor "embedbits.com/EmBi" identification cores)
            if(NOT JSON_ERROR AND CORE_COUNT GREATER 0)
                math(EXPR LAST_CORE_INDEX "${CORE_COUNT} - 1")
                foreach(CORE_INDEX RANGE ${LAST_CORE_INDEX})
                    string(JSON CORE_NAME
                           GET "${RAL_JSON}" configurePresets ${PRESET_INDEX} vendor "embedbits.com/EmBi" identification cores ${CORE_INDEX} name)
                    list(APPEND CORES "${CORE_NAME}")
                endforeach()
            endif()
        endif()

    endforeach()

    list(LENGTH CORES CORE_COUNT)

    if(CORE_COUNT LESS 2)
        message(FATAL_ERROR "${IN_MCU} is not a multi-core MCU (no cores in the identification of its preset in ${RAL_PRESETS_FILE}).")
    endif()

    message(STATUS "Cores of ${IN_MCU}: ${CORES}")

    # Project CMakeLists.txt of a core - the template with the core, the cores of the MCU and the platform root in
    # the parent folder (every line has to be found in the template)
    file(READ "${PRJ_HANDLER_TEMPLATES_PATH}/Template_CMakeLists.txt.in" TEMPLATE_CONTENT)

    set(TEMPLATE_LINES "(set\\(PROJECT_NAME[ \t]+\")Project_Template_"
                       "(set\\(TARGET_CORE[ \t]+)\"\""
                       "(set\\(TARGET_CORES[ \t]+)\"\""
                       "()set\\(PLATFORM_ROOT_PATH[ \t]+\"\\\${CMAKE_SOURCE_DIR}\"\\)")

    foreach(TEMPLATE_LINE IN LISTS TEMPLATE_LINES)
        if(NOT TEMPLATE_CONTENT MATCHES "${TEMPLATE_LINE}")
            message(FATAL_ERROR "${TEMPLATE_LINE} not found in Template_CMakeLists.txt.in - projects of the cores cannot be created.")
        endif()
    endforeach()

    foreach(CORE IN LISTS CORES)

        set(CORE_PATH "${PLATFORM_ROOT_PATH}/${CORE}")
        file(MAKE_DIRECTORY "${CORE_PATH}")

        if(NOT EXISTS "${CORE_PATH}/CMakeLists.txt")
            list(GET TEMPLATE_LINES 0 NAME_LINE)
            list(GET TEMPLATE_LINES 1 CORE_LINE)
            list(GET TEMPLATE_LINES 2 CORES_LINE)
            list(GET TEMPLATE_LINES 3 ROOT_LINE)
            string(REGEX REPLACE "${NAME_LINE}"  "\\1Project_Template_${CORE}_" CORE_CONTENT "${TEMPLATE_CONTENT}")
            string(REGEX REPLACE "${CORE_LINE}"  "\\1\"${CORE}\""               CORE_CONTENT "${CORE_CONTENT}")
            string(REGEX REPLACE "${CORES_LINE}" "\\1\"${CORES}\""              CORE_CONTENT "${CORE_CONTENT}")
            string(REGEX REPLACE "${ROOT_LINE}"  "cmake_path(GET CMAKE_SOURCE_DIR PARENT_PATH PLATFORM_ROOT_PATH)"
                   CORE_CONTENT "${CORE_CONTENT}")
            file(WRITE "${CORE_PATH}/CMakeLists.txt" "${CORE_CONTENT}")
        endif()

        # Artifacts configuration of the platform root (cache, sources) if it has one
        if(NOT EXISTS "${CORE_PATH}/ArtifactsConfig.txt")
            if(EXISTS "${PLATFORM_ROOT_PATH}/ArtifactsConfig.txt")
                file(COPY_FILE "${PLATFORM_ROOT_PATH}/ArtifactsConfig.txt" "${CORE_PATH}/ArtifactsConfig.txt")
            else()
                file(COPY_FILE "${PRJ_HANDLER_TEMPLATES_PATH}/Template_ArtifactsConfig.txt.in"
                     "${CORE_PATH}/ArtifactsConfig.txt")
            endif()
        endif()

        if(NOT EXISTS "${CORE_PATH}/CMakePresets.json")
            file(COPY_FILE "${PRJ_HANDLER_TEMPLATES_PATH}/Template_CMakePresets.json.in"
                 "${CORE_PATH}/CMakePresets.json")
        endif()

        # Boards of the integration tests and the debugging (configuration of the platform root)
        foreach(BOARDS_FILE IN ITEMS "ItBoards.json" "ItHosts.json")
            if(NOT EXISTS "${CORE_PATH}/${BOARDS_FILE}" AND EXISTS "${PLATFORM_ROOT_PATH}/${BOARDS_FILE}")
                file(COPY_FILE "${PLATFORM_ROOT_PATH}/${BOARDS_FILE}" "${CORE_PATH}/${BOARDS_FILE}")
            endif()
        endforeach()

        # Presets and Application layer - the handlers take the project of the core from the working folder
        foreach(HANDLER IN ITEMS "${PRJ_HANDLER_TEMPLATES_PATH}/Prj_PresetsHandler.cmake"
                                 "${PRJ_HANDLER_TEMPLATES_PATH}/../App_Handler/App_ModuleHandler.cmake")
            execute_process(COMMAND "${CMAKE_COMMAND}" -P "${HANDLER}"
                            WORKING_DIRECTORY "${CORE_PATH}"
                            RESULT_VARIABLE HANDLER_RESULT)
            if(NOT HANDLER_RESULT EQUAL 0)
                message(FATAL_ERROR "${HANDLER} failed for the project of the core ${CORE}.")
            endif()
        endforeach()

        message(STATUS "Project of the core ${CORE}: ${CORE_PATH}")

    endforeach()

    # VS Code configuration of every project (debug configurations of the MCUs, firmware name with the core) and the
    # workspace of the projects
    set(MCU_IDS "${IN_MCU_IDS}")
    if("${MCU_IDS}" STREQUAL "")
        set(MCU_IDS 0)
    endif()

    foreach(CORE IN LISTS CORES)
        set(CORE_FIRMWARE_NAME "")
        if(NOT "${IN_FIRMWARE_NAME}" STREQUAL "")
            set(CORE_FIRMWARE_NAME "${IN_FIRMWARE_NAME}_${CORE}")
        endif()
        execute_process(COMMAND "${CMAKE_COMMAND}" -DFUNCTION_ID=INIT
                                                   "-DMCU_IDS=${MCU_IDS}"
                                                   "-DFIRMWARE_NAME=${CORE_FIRMWARE_NAME}"
                                                   -P "${PRJ_HANDLER_TEMPLATES_PATH}/Prj_VSCode_Handler.cmake"
                        WORKING_DIRECTORY "${PLATFORM_ROOT_PATH}/${CORE}"
                        RESULT_VARIABLE HANDLER_RESULT)
        if(NOT HANDLER_RESULT EQUAL 0)
            message(FATAL_ERROR "VS Code initialization failed for the project of the core ${CORE}.")
        endif()
    endforeach()

endfunction()


#==============================================================================#
# Main functionality
# 
# If the script is executed in script mode ( -P ), no functions are called, thus 
# direct execution has to be triggered.
#
# Example:
# cmake -P PrjStructure_Handler.cmake
#==============================================================================#
if(CMAKE_SCRIPT_MODE_FILE AND 
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)
   
    if("${FUNCTION_ID}" STREQUAL "CORE_PROJECTS")
        ProjectStructureInit_CoreProjectsInit("${MCU}" "${MCU_IDS}" "${FIRMWARE_NAME}")
    else()
        ProjectStructureInit_ProjectRootInit()
    endif()
    
endif()

