# ==============================================================================
# Platform version CMake handler functionality 
#
# To read and update actual platform version (stored in Platform.c file) can be 
# used this functionality script. 
#
# Example usage:
# To get actual platform version:
# cmake -P Platform_VersionHandler.cmake
#
# To configure new platform version:
# cmake -DPLATFORM_VERSION=1.0.1 -P Platform_VersionHandler.cmake
# ==============================================================================

#===============================================================================
# Global variables
#===============================================================================

# Project configuration function file name
set(PROJECT_CONFIG_FUNCTION_FILE "Platform.c")

# Project configuration header file name
set(PROJECT_CONFIG_HEADER_FILE "Platform.h")

# Path to the project configuration files
get_filename_component(PROJECT_CONFIG_FUNCTION_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/../../${PROJECT_CONFIG_FUNCTION_FILE}" REALPATH)
get_filename_component(PROJECT_CONFIG_HEADER_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/../../${PROJECT_CONFIG_HEADER_FILE}" REALPATH)

# Set path to system configuration file
get_filename_component(SYSTEM_CONFIG_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/../../SysConfig.cmake" REALPATH)

# ------------------------------------------------------------------------------
# Function: Platform_VersionHandler_Get_DefineValue
# Description: finds and returns value of "#define" string from input string 
# array. User specify "#define" name by "DEFINE_NAME".
#
# IN_STRING_ARRAY [in]: String array to be used for searching
# IN_DEFINE_NAME  [in]: Name of "#define" to be found
# OUT_VALUE      [out]: Value of found "#define"
# ------------------------------------------------------------------------------
function(Platform_VersionHandler_Get_DefineValue IN_STRING_ARRAY IN_DEFINE_NAME OUT_VALUE)

    # Pattern: #define NAME (value) alebo #define NAME value
    string(REGEX MATCH "#define[ \t]+${IN_DEFINE_NAME}[ \t]+\\(?([0-9]+)u?\\)?" _ "${IN_STRING_ARRAY}")
    
    if(DEFINED CMAKE_MATCH_1)
        set(${OUT_VALUE} ${CMAKE_MATCH_1} PARENT_SCOPE)
    else()
        set(${OUT_VALUE} "" PARENT_SCOPE)
    endif()
    
endfunction()


# ------------------------------------------------------------------------------
# Function: Platform_VersionHandler_Get_Version
# Description: Returns actual project version.
#
# OUT_VERSION [out]: Actual project version in format X.Y.Z
# ------------------------------------------------------------------------------
function(Platform_VersionHandler_Get_Version OUT_VERSION)

    file(READ "${PROJECT_CONFIG_FUNCTION_FILE_PATH}" CONTENT)
    
    # Extract MAJOR
    Platform_VersionHandler_Get_DefineValue("${CONTENT}" "PLATFORM_MAJOR_VERSION" MAJOR)
    
    # Extract MINOR
    Platform_VersionHandler_Get_DefineValue("${CONTENT}" "PLATFORM_MINOR_VERSION" MINOR)
    
    # Extract PATCH
    Platform_VersionHandler_Get_DefineValue("${CONTENT}" "PLATFORM_PATCH_VERSION" PATCH)
    
    message(DEBUG "Extracted project version: ${MAJOR}.${MINOR}.${PATCH}")
    
    set(${OUT_VERSION} "${MAJOR}.${MINOR}.${PATCH}" PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Platform_VersionHandler_Set_Version
# Description: Updates project version.
#
# IN_VERSION [in]: Required project version in format X.Y.Z
# ------------------------------------------------------------------------------
function(Platform_VersionHandler_Set_Version IN_VERSION)

    string(REPLACE "." ";" VERSION_LIST "${IN_VERSION}")
    
    list(LENGTH VERSION_LIST VERSION_PARTS)
    if(NOT VERSION_PARTS EQUAL 3)
        message(FATAL_ERROR "Invalid version format: ${IN_VERSION}. Expected X.Y.Z")
    endif()
    
    list(GET VERSION_LIST 0 NEW_MAJOR)
    list(GET VERSION_LIST 1 NEW_MINOR)
    list(GET VERSION_LIST 2 NEW_PATCH)
    
    # Check if all values are numbers.
    if(NOT NEW_MAJOR MATCHES "^[0-9]+$" OR 
       NOT NEW_MINOR MATCHES "^[0-9]+$" OR 
       NOT NEW_PATCH MATCHES "^[0-9]+$")
        message(FATAL_ERROR "Version must contain only numbers: ${IN_VERSION}")
    endif()

    file(READ "${PROJECT_CONFIG_FUNCTION_FILE_PATH}" CONTENT)
    
    # Replace MAJOR value
    string(REGEX REPLACE 
           "(#define[ \t]+PLATFORM_MAJOR_VERSION[ \t]+\\()([0-9]+)(u?\\))"
           "\\1${NEW_MAJOR}\\3"
           CONTENT 
           "${CONTENT}")
    
    # Replace MINOR value
    string(REGEX REPLACE 
           "(#define[ \t]+PLATFORM_MINOR_VERSION[ \t]+\\()([0-9]+)(u?\\))"
           "\\1${NEW_MINOR}\\3"
           CONTENT 
           "${CONTENT}")
    
    # Replace PATCH value
    string(REGEX REPLACE 
           "(#define[ \t]+PLATFORM_PATCH_VERSION[ \t]+\\()([0-9]+)(u?\\))"
           "\\1${NEW_PATCH}\\3"
           CONTENT 
           "${CONTENT}")
    
    # Write changes
    file(WRITE "${PROJECT_CONFIG_FUNCTION_FILE_PATH}" "${CONTENT}")
    
    message(STATUS "Updated version to ${NEW_MAJOR}.${NEW_MINOR}.${NEW_PATCH}")
    
endfunction()


#==============================================================================#
# Main functionality
# Usage: cmake -DTARGET_VERSION="1.0.3" -P Updater.cmake
#==============================================================================#
if(CMAKE_SCRIPT_MODE_FILE AND 
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)
   
    if(DEFINED PLATFORM_VERSION)
        Platform_VersionHandler_Set_Version(${PLATFORM_VERSION})
    else()
        Platform_VersionHandler_Get_Version(ACTUAL_VERSION)
        message(STATUS "Actual platform version: ${ACTUAL_VERSION}")
    endif()
    
endif()

