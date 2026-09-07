################################################################################
#
# Project structure initialization CMake script.
#
# The project structure shall have following structure:
#
# Project_root/
# │
# ...
# └── STM32CubeIDE                  (STM32CubeIDE project folder)
#     ├── .cproject                 (STM32CubeIDE C project file)
#     ├── .project                  (STM32CubeIDE project file)
#     ├── Debug                     (Build output folder)
#     └── ...
#
# User can execute initialization of this structure through this CMake script.
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


# ------------------------------------------------------------------------------
# Function: Prj_CubeIDE_Init
# Description: Copy STM32CubeIDE project files into project and sets the project
# name.
# ------------------------------------------------------------------------------
function(Prj_CubeIDE_Init IN_PROJECT_NAME)

    set(CUBE_IDE_PATH "${PROJECT_ROOT_PATH}/STM32CubeIDE/")

    if(IN_PROJECT_NAME STREQUAL "")
        set(PROJECT_NAME "STM_Template")
    else()
        set(PROJECT_NAME ${IN_PROJECT_NAME})
    endif()

    if(NOT EXISTS "${CUBE_IDE_PATH}/.cproject")
        configure_file("${CMAKE_CURRENT_LIST_DIR}/Template.cproject.in"
                       "${CUBE_IDE_PATH}/.cproject"
                       @ONLY)
    endif()

    if(NOT EXISTS "${CUBE_IDE_PATH}/.project")
        configure_file("${CMAKE_CURRENT_LIST_DIR}/Template.project.in"
                       "${CUBE_IDE_PATH}/.project"
                       @ONLY)
    endif()

endfunction()


#==============================================================================#
# Main functionality
# 
# If the script is executed in script mode ( -P ), execution is started with 
# first direct code out of function, thus functions execution has to be 
# triggered.
#
# Example:
# cmake -DPROJECT_NAME="TestProject" -P Prj_CubeIDE_Handler.cmake
#==============================================================================#
if(CMAKE_SCRIPT_MODE_FILE AND 
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)
   
   set(PROJECT_DEFAULT_NAME "STM_Template")

    if(NOT DEFINED PROJECT_NAME OR PROJECT_NAME STREQUAL "")
        message(STATUS "Using default project name '${PROJECT_DEFAULT_NAME}'")
        Prj_CubeIDE_Init("${PROJECT_DEFAULT_NAME}")
    else()
        Prj_CubeIDE_Init(${PROJECT_NAME})
    endif()
    
endif()

