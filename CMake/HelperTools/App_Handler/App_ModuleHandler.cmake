################################################################################
#
# Application layer structure initialization CMake script.
#
# The project structure shall have following structure:
#
# Project_root/
# │
# ├── Application
# │   ├── AppCom                    (Application communication interface)
# │   ├── AppComp                   (Application components)
# │   ├── AppCore                   (Application core handler)
# │   ├── AppFun                    (Application functionality)
# │   └── AppMain                   (Application main function)
# │                                 
# ├── Bsp                           (Board Support Packages)
# ├── Middlewares                   (Middlewares folder)
# ├── STM_Template                  (Build and miscellaneous tools)
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

# Application (App) component path relative to project root path.
set(APP_REL_PATH "Application")

# ------------------------------------------------------------------------------
# Function: App_ModuleHandler_Init
# Description:
#   Initialization of Application module folder structure.
#   The necessary sub-folders and files are created with following structure:
#   Application/
#   ├── AppMain              (Application main function)
#   │   ├── AppMain.c          (Application main source file)
#   │   ├── AppMain.h          (Application main header file)
#   │   └── CMakeLists.txt     (AppMain CMake file)
#   │
#   ├── AppCore              (Application core handler)
#   ├── AppComp              (Application components)
#   ├── AppFun               (Application functionality)
#   └── App.cmake            (Application module CMake file)
# ------------------------------------------------------------------------------
function(App_ModuleHandler_Init)

    file(MAKE_DIRECTORY "${PROJECT_ROOT_PATH}/${APP_REL_PATH}")
    file(MAKE_DIRECTORY "${PROJECT_ROOT_PATH}/${APP_REL_PATH}/AppMain")
    file(MAKE_DIRECTORY "${PROJECT_ROOT_PATH}/${APP_REL_PATH}/AppCore")
    file(MAKE_DIRECTORY "${PROJECT_ROOT_PATH}/${APP_REL_PATH}/AppComp")
    file(MAKE_DIRECTORY "${PROJECT_ROOT_PATH}/${APP_REL_PATH}/AppFun")
    
    # Read author name from git global configuration
    execute_process(COMMAND git config --global user.name
                    OUTPUT_VARIABLE AUTHOR
                    OUTPUT_STRIP_TRAILING_WHITESPACE)
    
    # Copy necessary .c & .h files
    if(NOT EXISTS "${PROJECT_ROOT_PATH}/${APP_REL_PATH}/AppMain/AppMain.c")
        configure_file("${CMAKE_CURRENT_LIST_DIR}/Template_AppMain.c.in"
                       "${PROJECT_ROOT_PATH}/${APP_REL_PATH}/AppMain/AppMain.c"
                       @ONLY)
    endif()
        
    if(NOT EXISTS "${PROJECT_ROOT_PATH}/${APP_REL_PATH}/AppMain/AppMain.h")
        configure_file("${CMAKE_CURRENT_LIST_DIR}/Template_AppMain.h.in"
                       "${PROJECT_ROOT_PATH}/${APP_REL_PATH}/AppMain/AppMain.h"
                       @ONLY)
    endif()

    # Set output path for AppMain module
    set(APP_MAIN_MODULE_OUTPUT_PATH "${PROJECT_ROOT_PATH}/${APP_REL_PATH}/AppMain/")
    
    # Generate CMakeLists.txt for AppMain module
    CMakeLists_Handler_Set_PrivateInlcudeDirs("\${CMAKE_CURRENT_SOURCE_DIR}")
    CMakeLists_Handler_Set_PublicInlcudeDirs("")
    CMakeLists_Handler_Set_SourceFiles("AppMain.c")
    CMakeLists_Handler_Set_PublicHeaderFiles("AppMain.h")
    CMakeLists_Handler_Set_PublicDependenLibs("")
    CMakeLists_Handler_Set_PrivateDependentLibs("")
    CMakeLists_Handler_Set_ModuleName("AppMain")
    CMakeLists_Handler_Generate_CMakeLists("${APP_MAIN_MODULE_OUTPUT_PATH}")
    
    
    set(OUTPUT_PATH "${PROJECT_ROOT_PATH}/${APP_REL_PATH}/App.cmake")
    set(CONTENT "add_subdirectory(\${CMAKE_CURRENT_LIST_DIR}/AppMain)")

    if(NOT EXISTS "${OUTPUT_PATH}")
        file(WRITE "${OUTPUT_PATH}" "${CONTENT}")
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
   
    App_ModuleHandler_Init()
    
endif()

