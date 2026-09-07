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
# ├── CMakeLists.txt                (Project root CMake file)
# └── README.md                     (Project documentation)
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
# Function: ProjectStructureInit_ProjectRootInit
# Description:
#   Initialization of Project root folder structure.
#   The necessary files are created with following structure:
#   Project_Root/
#   ├── ArtifactsConfig.txt      (Artifacts configuration file)
#   └── CMakeLists.txt           (Project root CMake file)
# ------------------------------------------------------------------------------
function(ProjectStructureInit_ProjectRootInit)

    if(NOT EXISTS "${PROJECT_ROOT_PATH}/CMakeLists.txt")
        file(COPY_FILE "${CMAKE_CURRENT_LIST_DIR}/Template_CMakeLists.txt.in"
            "${PROJECT_ROOT_PATH}/CMakeLists.txt"
            ONLY_IF_DIFFERENT)
    endif()
        
    if(NOT EXISTS "${PROJECT_ROOT_PATH}/ArtifactsConfig.txt")
        file(COPY_FILE "${CMAKE_CURRENT_LIST_DIR}/Template_ArtifactsConfig.txt.in"
            "${PROJECT_ROOT_PATH}/ArtifactsConfig.txt"
            ONLY_IF_DIFFERENT)
    endif()
    
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
   
    ProjectStructureInit_ProjectRootInit()
    
endif()

