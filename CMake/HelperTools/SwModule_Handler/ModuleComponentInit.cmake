################################################################################
#
# Module component initialization.
#
# User can add component into existing module from template. 
# 
#
# Module                (Variable MODULE_NAME_ARG)
# │
# ├── Module.c          (Module core function file)
# ├── Module.h          (Module core header file)
# ├── Module_Port.h     (Public interface header file)
# ├── Module_Types.h    (Public types definitions header file)
# ├── ...
# ├── Component.c       (New component function file)
# └── Component.h       (New component header file) 
#
#
################################################################################
cmake_minimum_required(VERSION 3.21)

#==============================================================================#
# Global variables
#==============================================================================#

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
# MODULE_PATH_ARG    [in]: Path to the required module location (without module name in it)
# MODULE_NAME_ARG    [in]: Name of module in location (folder name).
# COMPONENT_NAME_ARG [in]: Name of component to be added into module.
#------------------------------------------------------------------------------#
function(ModuleComponentInit MODULE_PATH_ARG MODULE_NAME_ARG COMPONENT_NAME_ARG)
    message(STATUS "Adding module component...")

    string(SUBSTRING "${MODULE_NAME_ARG}" 0 1 first_char)
    string(TOLOWER "${first_char}" first_char_lower)
    
    string(SUBSTRING "${MODULE_NAME_ARG}" 1 -1 rest)
    # Set typedef name for files generation
    set(TYPE_NAME "${first_char_lower}${rest}")
    
    # Set name for macros in files generation
    set(MACRO_MODULE_NAME "${MODULE_NAME_ARG}_${COMPONENT_NAME_ARG}")
    string(TOUPPER "${MACRO_MODULE_NAME}" MACRO_MODULE_NAME)
    
    set(MACRO_COMPONENT_NAME "${COMPONENT_NAME_ARG}")
    string(TOUPPER "${MACRO_COMPONENT_NAME}" MACRO_COMPONENT_NAME)
    
    set(MODULE_NAME "${MODULE_NAME_ARG}")
    
    set(COMPONENT_NAME "${COMPONENT_NAME_ARG}")
    
    set(FILE_NAME "${MODULE_NAME_ARG}_${COMPONENT_NAME_ARG}")

    # Template.c.in also references @MACRO_NAME@ (module-level version-macro
    # prefix, e.g. FREERTOS_MAJOR_VERSION) which was never set here, leaving
    # those macro names blank in generated component .c files - reuse the
    # already-combined module+component macro prefix for it.
    set(MACRO_NAME "${MACRO_MODULE_NAME}")
    
    set(FUNCTION_PREFIX "${MODULE_NAME_ARG}_${COMPONENT_NAME_ARG}")
    
    # Read author name from git global configuration
    execute_process(COMMAND git config --global user.name
                    OUTPUT_VARIABLE AUTHOR
                    OUTPUT_STRIP_TRAILING_WHITESPACE)

    if(EXISTS "${PROJECT_ROOT_PATH}/${MODULE_PATH_ARG}/${MODULE_NAME_ARG}/${COMPONENT_NAME_ARG}.c")
        message(STATUS "${COMPONENT_NAME_ARG}.c file already exist in the source directory.")
    else()
        configure_file("${CMAKE_CURRENT_LIST_DIR}/Template.c.in"
                       "${PROJECT_ROOT_PATH}/${MODULE_PATH_ARG}/${MODULE_NAME_ARG}/${MODULE_NAME_ARG}_${COMPONENT_NAME_ARG}.c"
                       @ONLY)
    endif()
    
    if(EXISTS "${PROJECT_ROOT_PATH}/${MODULE_PATH_ARG}/${MODULE_NAME_ARG}/${COMPONENT_NAME_ARG}.h")
        message(STATUS "${COMPONENT_NAME_ARG}.h file already exist in the source directory.")
    else()
        configure_file("${CMAKE_CURRENT_LIST_DIR}/Template.h.in"
                       "${PROJECT_ROOT_PATH}/${MODULE_PATH_ARG}/${MODULE_NAME_ARG}/${MODULE_NAME_ARG}_${COMPONENT_NAME_ARG}.h"
                       @ONLY)
    endif()
endfunction(ModuleComponentInit)

#==============================================================================#
# Main functionality
#==============================================================================#
# Check if run directly with cmake -P
if(CMAKE_SCRIPT_MODE_FILE AND 
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE AND
   DEFINED COMPONENT_INIT_MODULE_PATH AND
   DEFINED COMPONENT_INIT_MODULE_NAME AND 
   DEFINED COMPONENT_INIT_COMPONENT_NAME)

    message(STATUS "Script executed directly")
    ModuleComponentInit(${COMPONENT_INIT_MODULE_PATH}
                        ${COMPONENT_INIT_MODULE_NAME}
                        ${COMPONENT_INIT_COMPONENT_NAME})
    
endif()