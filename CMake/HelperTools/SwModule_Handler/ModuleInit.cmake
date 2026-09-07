################################################################################
#
# Module initialization.
#
# User can generate module from template with specified structure. 
#
# Structure of new module:
#
# Module                (Variable MODULE_NAME_ARG)
# │
# ├── Module.c          (Module core function file)
# ├── Module.h          (Module core header file)
# ├── Module_Port.h     (Public interface header file)
# ├── Module_Types.h    (Public types definitions header file)
# └── CMakeLists.txt    (Module CMake script) 
#
################################################################################
cmake_minimum_required(VERSION 3.21)

#==============================================================================#
# Global variables
#==============================================================================#

# Set path to the CMakeLists.txt handler module
get_filename_component(CMAKELISTS_HANDLER_PATH "${CMAKE_CURRENT_LIST_DIR}/../CMakeLists_Handler/CMakeLists_Handler.cmake" REALPATH)

# Include CMakeLists.txt handler module
include("${CMAKELISTS_HANDLER_PATH}")

# Set path to system configuration file
get_filename_component(SYSTEM_CONFIG_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/../../SysConfig.cmake" REALPATH)

# Include file with system configuration values
include("${SYSTEM_CONFIG_FILE_PATH}")

# Read BSP repository URL
SysConfig_Get_BspRepoURL(BSP_BSP_REPO_URL)

# Read project root folder path
SysConfig_Get_ProjectRootPath(PROJECT_ROOT_PATH)

#------------------------------------------------------------------------------#
# Generation of folder structure and necessary files.
#
# MODULE_PATH_ARG [in]: Path to the required module location (without module name in it)
# MODULE_NAME_ARG [in]: Name of module in location (folder name).
#------------------------------------------------------------------------------#

function(ModuleInit MODULE_PATH_ARG MODULE_NAME_ARG)

    message(STATUS "Initializing module ${MODULE_NAME_ARG} on path ${MODULE_PATH_ARG} ...")
    
    if(NOT IS_DIRECTORY "${PROJECT_ROOT_PATH}/${MODULE_PATH_ARG}/${MODULE_NAME_ARG}")
        file(MAKE_DIRECTORY "${PROJECT_ROOT_PATH}/${MODULE_PATH_ARG}/${MODULE_NAME_ARG}")
    else()
        message(STATUS "Folder ${MODULE_NAME_ARG} already exists in required path.")
    endif()

    string(SUBSTRING "${MODULE_NAME_ARG}" 0 1 first_char)  
    string(TOLOWER "${first_char}" first_char_lower)
    
    string(SUBSTRING "${MODULE_NAME_ARG}" 1 -1 rest)
    # Set typedef name for files generation
    set(TYPE_NAME "${first_char_lower}${rest}")
    
    # Set name for macros in files generation
    set(MACRO_NAME "${MODULE_NAME_ARG}")
    string(TOUPPER "${MACRO_NAME}" MACRO_NAME)
    
    set(MODULE_NAME "${MODULE_NAME_ARG}")

    # Read author name from git global configuration
    execute_process(COMMAND git config --global user.name
                    OUTPUT_VARIABLE AUTHOR
                    OUTPUT_STRIP_TRAILING_WHITESPACE)

    if(EXISTS "${PROJECT_ROOT_PATH}/${MODULE_PATH_ARG}/${MODULE_NAME_ARG}/${MODULE_NAME_ARG}.c")
        message(STATUS "${MODULE_NAME_ARG}.c file already exist in the source directory.")
    else()
        configure_file("${CMAKE_CURRENT_LIST_DIR}/Template.c.in"
                       "${PROJECT_ROOT_PATH}/${MODULE_PATH_ARG}/${MODULE_NAME_ARG}/${MODULE_NAME_ARG}.c"
                       @ONLY)
    endif()
    
    if(EXISTS "${PROJECT_ROOT_PATH}/${MODULE_PATH_ARG}/${MODULE_NAME_ARG}/${MODULE_NAME_ARG}.h")
        message(STATUS "${MODULE_NAME_ARG}.h file already exist in the source directory.")
    else()
        configure_file("${CMAKE_CURRENT_LIST_DIR}/Template.h.in"
                       "${PROJECT_ROOT_PATH}/${MODULE_PATH_ARG}/${MODULE_NAME_ARG}/${MODULE_NAME_ARG}.h"
                       @ONLY)
    endif()
    
    if(EXISTS "${PROJECT_ROOT_PATH}/${MODULE_PATH_ARG}/${MODULE_NAME_ARG}/${MODULE_NAME_ARG}_Port.h")
        message(STATUS "${MODULE_NAME_ARG}_Port.h file already exist in the source directory.")
    else()
        configure_file("${CMAKE_CURRENT_LIST_DIR}/Template_Port.h.in"
                       "${PROJECT_ROOT_PATH}/${MODULE_PATH_ARG}/${MODULE_NAME_ARG}/${MODULE_NAME_ARG}_Port.h"
                       @ONLY)
    endif()
    
    if(EXISTS "${PROJECT_ROOT_PATH}/${MODULE_PATH_ARG}/${MODULE_NAME_ARG}/${MODULE_NAME_ARG}_Types.h")
        message(STATUS "${MODULE_NAME_ARG}_Types.h file already exist in the source directory.")
    else()
        configure_file("${CMAKE_CURRENT_LIST_DIR}/Template_Types.h.in"
                       "${PROJECT_ROOT_PATH}/${MODULE_PATH_ARG}/${MODULE_NAME_ARG}/${MODULE_NAME_ARG}_Types.h"
                       @ONLY)
    endif()
    
    if(EXISTS "${PROJECT_ROOT_PATH}/${MODULE_PATH_ARG}/${MODULE_NAME_ARG}/CMakeLists.txt")
        message(STATUS "CMakeLists.txt file already exist in the source directory.")
    else()
        
        CMakeLists_Handler_Set_PrivateInlcudeDirs("\${CMAKE_CURRENT_SOURCE_DIR}")
        
        CMakeLists_Handler_Set_PublicInlcudeDirs("")
        
        CMakeLists_Handler_Set_SourceFiles("${MODULE_NAME_ARG}.c")
        
        CMakeLists_Handler_Set_PublicHeaderFiles("${MODULE_NAME_ARG}_Types.h;${MODULE_NAME_ARG}_Port.h")
        
        CMakeLists_Handler_Set_ModuleName("${MODULE_NAME_ARG}")
        
        CMakeLists_Handler_Generate_CMakeLists("${PROJECT_ROOT_PATH}/${MODULE_PATH_ARG}/${MODULE_NAME_ARG}/")
        
    endif()
    
    message(STATUS "Module initialization finish.")
    
endfunction()

#==============================================================================#
# Main functionality
#==============================================================================#
# Check if run directly with cmake -P
if(CMAKE_SCRIPT_MODE_FILE AND 
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE AND
   DEFINED MODULE_INIT_MODULE_PATH AND
   DEFINED MODULE_INIT_MODULE_NAME)

    ModuleInit(${MODULE_INIT_MODULE_PATH} 
               ${MODULE_INIT_MODULE_NAME})
    
endif()