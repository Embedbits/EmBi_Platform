# ==============================================================================
# ==================== CMakeLists.txt file helper functions ====================
# ==============================================================================
#
# Usage: cmake -P CMakeLists_Handler.cmake --log-level=DEBUG 
#
# Description:
#   This module provides helper functions to handle CMakeLists.txt files. 
#   Configuration can be parsed from existing CMakeLists.txt files and used
#   to set up new modules or update existing ones.
#
# Functions Provided:
#  - CMakeLists_Handler_Get_Version( MODULE_PATH OUT_VERSION )
#  - CMakeLists_Handler_Set_Version( NEW_VERSION )
#
#  - CMakeLists_Handler_Get_PrivateIncludeDirs( MODULE_PATH OUT_INCLUDE_DIRS )
#  - CMakeLists_Handler_Set_PrivateInlcudeDirs( INCLUDE_DIRS )
#
#  - CMakeLists_Handler_Get_PublicIncludeDirs( MODULE_PATH OUT_INCLUDE_DIRS )
#  - CMakeLists_Handler_Set_PublicInlcudeDirs( INCLUDE_DIRS )
#
#  - CMakeLists_Handler_Get_SourceFiles( MODULE_PATH OUT_SOURCE_FILES )
#  - CMakeLists_Handler_Set_SourceFiles( SOURCE_FILES )
#
#  - CMakeLists_Handler_Get_PublicHeaderFiles( MODULE_PATH OUT_PUBLIC_HEADER_FILES )
#  - CMakeLists_Handler_Set_PublicHeaderFiles( PUBLIC_HEADER_FILES )
#
#  - CMakeLists_Handler_Get_PublicDependenLibs( MODULE_PATH OUT_PUBLIC_DEPENDENT_LIBS )
#  - CMakeLists_Handler_Set_PublicDependenLibs( PUBLIC_DEPENDENT_LIBS )
#
#  - CMakeLists_Handler_Get_PrivateDependentLibs( MODULE_PATH OUT_PRIVATE_DEPENDENT_LIBS )
#  - CMakeLists_Handler_Set_PrivateDependentLibs( PRIVATE_DEPENDENT_LIBS )
#
#  - CMakeLists_Handler_Get_ModuleName( MODULE_PATH OUT_MODULE_NAME )
#  - CMakeLists_Handler_Set_ModuleName( MODULE_NAME )
#
#  - CMakeLists_Handler_Generate_CMakeLists( MODULE_PATH )
#
#
# Example Usage:
#   
#   CMakeLists_Handler_Set_Version("2.0.0")
#   
#   CMakeLists_Handler_Set_PrivateInlcudeDirs("\${CMAKE_CURRENT_SOURCE_DIR}")
#   
#   CMakeLists_Handler_Set_PublicInlcudeDirs("")
#   
#   CMakeLists_Handler_Set_SourceFiles("Module.c;Module_Core.c")
#   
#   CMakeLists_Handler_Set_PublicHeaderFiles("Port.h;Types.h")
#   
#   CMakeLists_Handler_Set_PublicDependenLibs("PublicLib1;PublicLib2")
#   
#   CMakeLists_Handler_Set_PrivateDependentLibs("PrivateLib1;PrivateLib2")
#   
#   CMakeLists_Handler_Set_ModuleName("TestModule")
#   
#   CMakeLists_Handler_Generate_CMakeLists("${CMAKE_CURRENT_LIST_DIR}")
#
# ==============================================================================


# Set path to system configuration file
get_filename_component(SYSTEM_CONFIG_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/../../SysConfig.cmake" REALPATH)

# Include file with system configuration values
include("${SYSTEM_CONFIG_FILE_PATH}")

# Read project root folder path
SysConfig_Get_ProjectRootPath(PROJECT_ROOT_PATH)


# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------
# Template path for generating CMakeLists.txt files
set(CMAKE_LISTS_HANDLER_TEMPLATE_PATH "${CMAKE_CURRENT_LIST_DIR}/Template_CMakeLists.txt.in")

# Internal buffer variables
set(CMAKE_LISTS_HANDLER_MODULE_NAME             "")
set(CMAKE_LISTS_HANDLER_FILE_PATH               "")
set(CMAKE_LISTS_HANDLER_MODULE_VERSION          "0.0.0")
set(CMAKE_LISTS_HANDLER_PRIVATE_INCLUDE_DIRS    "")
set(CMAKE_LISTS_HANDLER_PUBLIC_INCLUDE_DIRS     "")
set(CMAKE_LISTS_HANDLER_SOURCE_FILES            "")
set(CMAKE_LISTS_HANDLER_PUBLIC_HEADER_FILES     "")
set(CMAKE_LISTS_HANDLER_PUBLIC_DEPENDENCIES     "")
set(CMAKE_LISTS_HANDLER_PRIVATE_DEPENDENCIES    "")


# ------------------------------------------------------------------------------
# Function: CMakeLists_Handler_ResetVariables
# Description:
#   Resets global variables used in CMakeLists handling.
# ------------------------------------------------------------------------------
function(CMakeLists_Handler_ResetVariables)
    set(CMAKE_LISTS_HANDLER_MODULE_NAME             ""      PARENT_SCOPE)
    set(CMAKE_LISTS_HANDLER_FILE_PATH               ""      PARENT_SCOPE)
    set(CMAKE_LISTS_HANDLER_MODULE_VERSION          "0.0.0" PARENT_SCOPE)
    set(CMAKE_LISTS_HANDLER_PRIVATE_INCLUDE_DIRS    ""      PARENT_SCOPE)
    set(CMAKE_LISTS_HANDLER_PUBLIC_INCLUDE_DIRS     ""      PARENT_SCOPE)
    set(CMAKE_LISTS_HANDLER_SOURCE_FILES            ""      PARENT_SCOPE)
    set(CMAKE_LISTS_HANDLER_PUBLIC_HEADER_FILES     ""      PARENT_SCOPE)
    set(CMAKE_LISTS_HANDLER_PUBLIC_DEPENDENCIES     ""      PARENT_SCOPE)
    set(CMAKE_LISTS_HANDLER_PRIVATE_DEPENDENCIES    ""      PARENT_SCOPE)
endfunction()


# ------------------------------------------------------------------------------
# Function: CMakeLists_Handler_Get_Version
# Description:
#   Extracts the MODULE_VERSION from a CMakeLists.txt file located in the 
#   specified module path.
# Parameters:
#   MODULE_PATH [in]: Path to the module directory containing CMakeLists.txt
#   OUT_VERSION [out]: Extracted version in format X.Y.Z
# ------------------------------------------------------------------------------
function(CMakeLists_Handler_Get_Version MODULE_PATH OUT_VERSION)

    set(CMAKE_LISTS_FILE_PATH "${MODULE_PATH}/CMakeLists.txt")

    if(EXISTS "${CMAKE_LISTS_FILE_PATH}")

        file(READ "${CMAKE_LISTS_FILE_PATH}" CMAKE_LISTS_CONTENTS)

        string(
            REGEX MATCH 
            "Template version:[ \t]*([0-9]+\\.[0-9]+\\.[0-9]+)" 
            VERSION_LINE 
            "${CMAKE_LISTS_CONTENTS}"
        )

        if(VERSION_LINE)
            string(REGEX MATCH "[0-9]+\\.[0-9]+\\.[0-9]+" EXTRACTED_VERSION "${VERSION_LINE}")
            message(DEBUG "Extracted module version: ${EXTRACTED_VERSION}")
            set(${OUT_VERSION} "${EXTRACTED_VERSION}" PARENT_SCOPE)
        else()
            message(STATUS "WARNING --- Module version not found. ---")
            set(${OUT_VERSION} "0.0.0" PARENT_SCOPE)
        endif()

    else()
    
        message(STATUS "WARNING --- CMakeLists.txt not found in ${MODULE_PATH}. ---")
        set(${OUT_VERSION} "0.0.0" PARENT_SCOPE)
        
    endif()
    
endfunction()


# ------------------------------------------------------------------------------
# Function: CMakeLists_Handler_Set_Version
# Description:
#   Sets the module version into internal buffer for later use.
# Parameters:
#   NEW_VERSION [in]: New version to set in format X.Y.Z
# ------------------------------------------------------------------------------
function(CMakeLists_Handler_Set_Version NEW_VERSION)

    set(CMAKE_LISTS_HANDLER_MODULE_VERSION ${NEW_VERSION} PARENT_SCOPE)
    
endfunction()


# ------------------------------------------------------------------------------
# Function: CMakeLists_Handler_Get_PrivateIncludeDirs
# Description:
#   Extracts the include directories from a CMakeLists.txt file located in the
#   specified module path.
# Parameters:
#   MODULE_PATH [in]: Path to the module directory containing CMakeLists.txt
#   OUT_INCLUDE_DIRS [out]: Extracted private include directories as a 
#                           semicolon-separated list
# ------------------------------------------------------------------------------
function(CMakeLists_Handler_Get_PrivateIncludeDirs MODULE_PATH OUT_INCLUDE_DIRS)

    set(CMAKE_LISTS_FILE_PATH "${MODULE_PATH}/CMakeLists.txt")

    if(EXISTS "${CMAKE_LISTS_FILE_PATH}")
    
        file(READ "${CMAKE_LISTS_FILE_PATH}" CMAKE_LISTS_CONTENTS)
        
        set(PRIVATE_INCLUDE_DIRS_PATTERN "_PrivateIncludeDirs|_IncludeDirs")
    
        string(
            REGEX MATCH
             "set[ \t\r\n]*\\([ \t\r\n]*([A-Za-z0-9_]+(${PRIVATE_INCLUDE_DIRS_PATTERN}))[ \t\r\n]*([^\\)]*)\\)"
            _MATCH
            "${CMAKE_LISTS_CONTENTS}"
        )
        
        if (NOT _MATCH)
            message(STATUS "WARNING --- Private include directory list  not found. ---")
        endif()
        
        set(_RAW_LIST "${CMAKE_MATCH_3}")
        
        string(REGEX REPLACE "[\r\n]" " " _RAW_LIST "${_RAW_LIST}")
        string(REGEX REPLACE "[ \t]+" ";" _RAW_LIST "${_RAW_LIST}")
        
        set(INCLUDE_DIRS_LIST ${_RAW_LIST})
        
        message(DEBUG "Extracted include directories: ${INCLUDE_DIRS_LIST}")

        set(${OUT_INCLUDE_DIRS} "${INCLUDE_DIRS_LIST}" PARENT_SCOPE)

    else()
    
        message(STATUS "WARNING --- CMakeLists.txt not found in ${MODULE_PATH}. ---")
        set(${OUT_INCLUDE_DIRS} "" PARENT_SCOPE)
        
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: CMakeLists_Handler_Set_PrivateInlcudeDirs
# Description:
#   Sets the include directories into internal buffer for later use.
# Parameters:
#   OUT_INCLUDE_DIRS [in]: Private include directories as a semicolon-separated list
# ------------------------------------------------------------------------------
function(CMakeLists_Handler_Set_PrivateInlcudeDirs INCLUDE_DIRS)
    
    set(CMAKE_LISTS_HANDLER_PRIVATE_INCLUDE_DIRS ${INCLUDE_DIRS} PARENT_SCOPE)
    
endfunction()


# ------------------------------------------------------------------------------
# Function: CMakeLists_Handler_Get_PublicIncludeDirs
# Description:
#   Extracts the public include directories from a CMakeLists.txt file located 
#   in the specified module path.
# Parameters:
#   MODULE_PATH [in]: Path to the module directory containing CMakeLists.txt
#   OUT_INCLUDE_DIRS [out]: Extracted public include directories as a 
#                           semicolon-separated list
# ------------------------------------------------------------------------------
function(CMakeLists_Handler_Get_PublicIncludeDirs MODULE_PATH OUT_INCLUDE_DIRS)

    set(CMAKE_LISTS_FILE_PATH "${MODULE_PATH}/CMakeLists.txt")

    if(EXISTS "${CMAKE_LISTS_FILE_PATH}")    
    
        file(READ "${CMAKE_LISTS_FILE_PATH}" CMAKE_LISTS_CONTENTS)
        
        set(PUBLIC_INCLUDE_DIRS_PATTERN "_PublicIncludeDirs")
    
        string(
            REGEX MATCH
             "set[ \t\r\n]*\\([ \t\r\n]*([A-Za-z0-9_]+(${PUBLIC_INCLUDE_DIRS_PATTERN}))[ \t\r\n]*([^\\)]*)\\)"
            _MATCH
            "${CMAKE_LISTS_CONTENTS}"
        )
        
        if (NOT _MATCH)
            message(STATUS "WARNING --- Public include directory list not found. ---")
        endif()
        
        set(_RAW_LIST "${CMAKE_MATCH_3}")
        
        string(REGEX REPLACE "[\r\n]" " " _RAW_LIST "${_RAW_LIST}")
        string(REGEX REPLACE "[ \t]+" ";" _RAW_LIST "${_RAW_LIST}")
        
        set(INCLUDE_DIRS_LIST ${_RAW_LIST})
        
        message(DEBUG "Extracted include directories: ${INCLUDE_DIRS_LIST}")

        set(${OUT_INCLUDE_DIRS} "${INCLUDE_DIRS_LIST}" PARENT_SCOPE)

    else()
    
        message(STATUS "WARNING --- CMakeLists.txt not found in ${MODULE_PATH}. ---")
        set(${OUT_INCLUDE_DIRS} "" PARENT_SCOPE)
        
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: CMakeLists_Handler_Set_PublicInlcudeDirs
# Description:
#   Sets the public include directories list into internal buffer for later use.
# Parameters:
#   INCLUDE_DIRS [in]: Public include directories as a semicolon-separated list
# ------------------------------------------------------------------------------
function(CMakeLists_Handler_Set_PublicInlcudeDirs INCLUDE_DIRS)
    
    set(CMAKE_LISTS_HANDLER_PUBLIC_INCLUDE_DIRS ${INCLUDE_DIRS} PARENT_SCOPE)
    
endfunction()


# ------------------------------------------------------------------------------
# Function: CMakeLists_Handler_Get_SourceFiles
# Description:
#   Extracts the source files list from a CMakeLists.txt file located in the 
#   specified module path.
# Parameters:
#   MODULE_PATH [in]: Path to the module directory containing CMakeLists.txt
#   OUT_SOURCE_FILES [out]: Extracted source files as a semicolon-separated list
# ------------------------------------------------------------------------------
function(CMakeLists_Handler_Get_SourceFiles MODULE_PATH OUT_SOURCE_FILES)

    set(CMAKE_LISTS_FILE_PATH "${MODULE_PATH}/CMakeLists.txt")

    if(EXISTS "${CMAKE_LISTS_FILE_PATH}")    
    
        file(READ "${CMAKE_LISTS_FILE_PATH}" CMAKE_LISTS_CONTENTS)
        
        set(SOURCE_PATTERN "_SourceFiles|_LibSrcs")
        
        string(
            REGEX MATCH
            "set[ \t\r\n]*\\([ \t\r\n]*([A-Za-z0-9_]*(${SOURCE_PATTERN}))[ \t\r\n]*([^)]*)"
            _MATCH
            "${CMAKE_LISTS_CONTENTS}"
        )
        
        if (NOT _MATCH)
            message(STATUS "WARNING --- Source file list not found. ---")
        endif()
        
        set(_RAW_LIST "${CMAKE_MATCH_3}")
        
        string(REGEX REPLACE "[\r\n]" " " _RAW_LIST "${_RAW_LIST}")
        string(REGEX REPLACE "[ \t]+" ";" _RAW_LIST "${_RAW_LIST}")
        
        set(SOURCE_FILES_LIST ${_RAW_LIST})
        
        message(DEBUG "Extracted source files: ${SOURCE_FILES_LIST}")

        set(${OUT_SOURCE_FILES} "${SOURCE_FILES_LIST}" PARENT_SCOPE)

    else()
    
        message(STATUS "WARNING --- CMakeLists.txt not found in ${MODULE_PATH}. ---")
        set(${OUT_SOURCE_FILES} "" PARENT_SCOPE)
        
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: CMakeLists_Handler_Set_SourceFiles
# Description:
#   Sets the source files list into internal buffer for later use.
# Parameters:
#   SOURCE_FILES [in]: Source files as a semicolon-separated list
# ------------------------------------------------------------------------------
function(CMakeLists_Handler_Set_SourceFiles SOURCE_FILES)
    
    set(CMAKE_LISTS_HANDLER_SOURCE_FILES ${SOURCE_FILES} PARENT_SCOPE)
    
endfunction()


# ------------------------------------------------------------------------------
# Function: CMakeLists_Handler_Get_PublicHeaderFiles
# Description:
#   Extracts the public header files list from a CMakeLists.txt file located in  
#   the specified module path.
# Parameters:
#   MODULE_PATH [in]: Path to the module directory containing CMakeLists.txt
#   OUT_PUBLIC_HEADER_FILES [out]: Extracted public header files as a 
#                                  semicolon-separated list
# ------------------------------------------------------------------------------
function(CMakeLists_Handler_Get_PublicHeaderFiles MODULE_PATH OUT_PUBLIC_HEADER_FILES)

    set(CMAKE_LISTS_FILE_PATH "${MODULE_PATH}/CMakeLists.txt")

    if(EXISTS "${CMAKE_LISTS_FILE_PATH}")    
    
        file(READ "${CMAKE_LISTS_FILE_PATH}" CMAKE_LISTS_CONTENTS)
        
        set(PUBLIC_HEADERS_PATTERN "_PublicHeaders")
    
        string(
            REGEX MATCH
             "set[ \t\r\n]*\\([ \t\r\n]*([A-Za-z0-9_]+(${PUBLIC_HEADERS_PATTERN}))[ \t\r\n]*([^\\)]*)\\)"
            _MATCH
            "${CMAKE_LISTS_CONTENTS}"
        )
        
        if (NOT _MATCH)
            message(STATUS "WARNING --- Public header list not found. ---")
        endif()
        
        set(_RAW_LIST "${CMAKE_MATCH_3}")
        
        string(REGEX REPLACE "[\r\n]" " " _RAW_LIST "${_RAW_LIST}")
        string(REGEX REPLACE "[ \t]+" ";" _RAW_LIST "${_RAW_LIST}")
        
        set(PUBLIC_HEADER_FILES_LIST ${_RAW_LIST})
        
        message(DEBUG "Extracted public header files: ${PUBLIC_HEADER_FILES_LIST}")

        set(${OUT_PUBLIC_HEADER_FILES} "${PUBLIC_HEADER_FILES_LIST}" PARENT_SCOPE)

    else()
    
        message(STATUS "WARNING --- CMakeLists.txt not found in ${MODULE_PATH}. ---")
        set(${OUT_SOURCE_FILES} "" PARENT_SCOPE)
        
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: CMakeLists_Handler_Set_PublicHeaderFiles
# Description:
#   Sets the public header files list into internal buffer for later use.
# Parameters:
#   PUBLIC_HEADER_FILES [in]: Public header files as a semicolon-separated list
# ------------------------------------------------------------------------------
function(CMakeLists_Handler_Set_PublicHeaderFiles PUBLIC_HEADER_FILES)
    
    set(CMAKE_LISTS_HANDLER_PUBLIC_HEADER_FILES ${PUBLIC_HEADER_FILES} PARENT_SCOPE)
    
endfunction()



# ------------------------------------------------------------------------------
# Function: CMakeLists_Handler_Get_PublicDependenLibs
# Description:
#   Extracts the public dependent libraries list from a CMakeLists.txt file   
#   located in the specified module path.
# Parameters:
#   MODULE_PATH [in]: Path to the module directory containing CMakeLists.txt
#   OUT_PUBLIC_DEPENDENT_LIBS [out]: Extracted public dependent libraries as a 
#                                    semicolon-separated list
# ------------------------------------------------------------------------------
function(CMakeLists_Handler_Get_PublicDependenLibs MODULE_PATH OUT_PUBLIC_DEPENDENT_LIBS)

    set(CMAKE_LISTS_FILE_PATH "${MODULE_PATH}/CMakeLists.txt")

    if(EXISTS "${CMAKE_LISTS_FILE_PATH}")
    
        file(READ "${CMAKE_LISTS_FILE_PATH}" CMAKE_LISTS_CONTENTS)
        
        set(PUBLIC_DEPENDENT_LIBS_PATTERN "_PublicDependentLibs|_DependentLibs")
    
        string(
            REGEX MATCH
             "set[ \t\r\n]*\\([ \t\r\n]*([A-Za-z0-9_]+(${PUBLIC_DEPENDENT_LIBS_PATTERN}))[ \t\r\n]*([^\\)]*)\\)"
            _MATCH
            "${CMAKE_LISTS_CONTENTS}"
        )
        
        if (NOT _MATCH)
            message(STATUS "WARNING --- Public dependent library list not found. ---")
        endif()
        
        set(_RAW_LIST "${CMAKE_MATCH_3}")
        
        string(REGEX REPLACE "[\r\n]" " " _RAW_LIST "${_RAW_LIST}")
        string(REGEX REPLACE "[ \t]+" ";" _RAW_LIST "${_RAW_LIST}")
        
        set(PUBLIC_DEPENDENT_LIBS_LIST ${_RAW_LIST})
        
        message(DEBUG "Extracted public dependent libraries: ${PUBLIC_DEPENDENT_LIBS_LIST}")

        set(${OUT_PUBLIC_DEPENDENT_LIBS} "${PUBLIC_DEPENDENT_LIBS_LIST}" PARENT_SCOPE)

    else()
    
        message(STATUS "WARNING --- CMakeLists.txt not found in ${MODULE_PATH}. ---")
        set(${OUT_SOURCE_FILES} "" PARENT_SCOPE)
        
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: CMakeLists_Handler_Set_PublicDependenLibs
# Description:
#   Sets the public dependent libraries list into internal buffer for later use.
# Parameters:
#   PUBLIC_DEPENDENT_LIBS [in]: Public dependent libraries as a semicolon-separated list
# ------------------------------------------------------------------------------
function(CMakeLists_Handler_Set_PublicDependenLibs PUBLIC_DEPENDENT_LIBS)
    
    set(CMAKE_LISTS_HANDLER_PUBLIC_DEPENDENCIES ${PUBLIC_DEPENDENT_LIBS} PARENT_SCOPE)
    
endfunction()


# ------------------------------------------------------------------------------
# Function: CMakeLists_Handler_Get_PrivateDependentLibs
# Description:
#   Extracts the public dependent libraries list from a CMakeLists.txt file   
#   located in the specified module path.
# Parameters:
#   MODULE_PATH [in]: Path to the module directory containing CMakeLists.txt
#   OUT_PRIVATE_DEPENDENT_LIBS [out]: Extracted private dependent libraries as a 
#                                     semicolon-separated list
# ------------------------------------------------------------------------------
function(CMakeLists_Handler_Get_PrivateDependentLibs MODULE_PATH OUT_PRIVATE_DEPENDENT_LIBS)

    set(CMAKE_LISTS_FILE_PATH "${MODULE_PATH}/CMakeLists.txt")

    if(EXISTS "${CMAKE_LISTS_FILE_PATH}")
    
        file(READ "${CMAKE_LISTS_FILE_PATH}" CMAKE_LISTS_CONTENTS)
        
        set(PRIVATE_DEPENDENT_LIBS_PATTERN "_PrivateDependentLibs")
    
        string(
            REGEX MATCH
             "set[ \t\r\n]*\\([ \t\r\n]*([A-Za-z0-9_]+(${PRIVATE_DEPENDENT_LIBS_PATTERN}))[ \t\r\n]*([^\\)]*)\\)"
            _MATCH
            "${CMAKE_LISTS_CONTENTS}"
        )
        
        if (NOT _MATCH)
            message(STATUS "WARNING --- Private dependent library list not found. ---")
        endif()
        
        set(_RAW_LIST "${CMAKE_MATCH_3}")
        
        string(REGEX REPLACE "[\r\n]" " " _RAW_LIST "${_RAW_LIST}")
        string(REGEX REPLACE "[ \t]+" ";" _RAW_LIST "${_RAW_LIST}")
        
        set(PRIVATE_DEPENDENT_LIBS_LIST ${_RAW_LIST})
        
        message(DEBUG "Extracted public dependent libraries: ${PRIVATE_DEPENDENT_LIBS_LIST}")

        set(${OUT_PRIVATE_DEPENDENT_LIBS} "${PRIVATE_DEPENDENT_LIBS_LIST}" PARENT_SCOPE)

    else()
    
        message(STATUS "WARNING --- CMakeLists.txt not found in ${MODULE_PATH}. ---")
        set(${OUT_SOURCE_FILES} "" PARENT_SCOPE)
        
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: CMakeLists_Handler_Set_PrivateDependentLibs
# Description:
#   Sets the public dependent libraries list into internal buffer for later use.
# Parameters:
#   PRIVATE_DEPENDENT_LIBS [in]: Private dependent libraries as a semicolon-separated list
# ------------------------------------------------------------------------------
function(CMakeLists_Handler_Set_PrivateDependentLibs PRIVATE_DEPENDENT_LIBS)
    
    set(CMAKE_LISTS_HANDLER_PRIVATE_DEPENDENCIES ${PRIVATE_DEPENDENT_LIBS} PARENT_SCOPE)
    
endfunction()


# ------------------------------------------------------------------------------
# Function: CMakeLists_Handler_Get_ModuleName
# Description:
#   Extracts the module name from a CMakeLists.txt file located in the specified 
#   module path.
# Parameters:
#   MODULE_PATH [in]: Path to the module directory containing CMakeLists.txt
#   OUT_MODULE_NAME [out]: Extracted module name
# ------------------------------------------------------------------------------
function(CMakeLists_Handler_Get_ModuleName MODULE_PATH OUT_MODULE_NAME)

    set(CMAKE_LISTS_FILE_PATH "${MODULE_PATH}/CMakeLists.txt")

    if(EXISTS "${CMAKE_LISTS_FILE_PATH}")
    
        file(READ "${CMAKE_LISTS_FILE_PATH}" CMAKE_LISTS_CONTENTS)
        
        string(
            REGEX MATCH
            "add_library[ \t\r\n]*\\([ \t\r\n]*([A-Za-z0-9_]+)(_Lib|_Library|_library)"
            _MATCH
            "${CMAKE_LISTS_CONTENTS}"
        )
        
        if (NOT _MATCH)
            message(STATUS "WARNING --- Library name not found. ---")
        endif()
        
        set(LIB_NAME "${CMAKE_MATCH_1}")
        
        message(DEBUG "Library name: ${LIB_NAME}")

        set(${OUT_MODULE_NAME} "${LIB_NAME}" PARENT_SCOPE)

    else()
    
        message(STATUS "WARNING --- CMakeLists.txt not found in ${MODULE_PATH}. ---")
        set(${OUT_SOURCE_FILES} "" PARENT_SCOPE)
        
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: CMakeLists_Handler_Set_ModuleName
# Description:
#   Sets the module name into internal buffer for later use.
# Parameters:
#   MODULE_NAME [in]: Module name to set
# ------------------------------------------------------------------------------
function(CMakeLists_Handler_Set_ModuleName MODULE_NAME)
    
    set(CMAKE_LISTS_HANDLER_MODULE_NAME ${MODULE_NAME} PARENT_SCOPE)
    
endfunction()


# ------------------------------------------------------------------------------
# Function: CMakeLists_Handler_Generate_CMakeLists
# Description:
#   Generates a CMakeLists.txt file in the specified module path using the
#   internal buffer variables and a predefined template.
# Parameters:
#   MODULE_PATH [in]: Path to the module directory where CMakeLists.txt will be 
#                     generated
# ------------------------------------------------------------------------------
function(CMakeLists_Handler_Generate_CMakeLists MODULE_PATH)

    get_filename_component(MODULE_PATH "${MODULE_PATH}" REALPATH)
    
    set(TEMPLATE_FILE_MODULE_NAME                   "${CMAKE_LISTS_HANDLER_MODULE_NAME}")
    set(TEMPLATE_FILE_MODULE_VERSION                "${CMAKE_LISTS_HANDLER_MODULE_VERSION}")
    set(TEMPLATE_FILE_PUBLIC_INCLUDE_DIRS_LIST      "${CMAKE_LISTS_HANDLER_PUBLIC_INCLUDE_DIRS}")
    set(TEMPLATE_FILE_PRIVATE_INCLUDE_DIRS_LIST     "${CMAKE_LISTS_HANDLER_PRIVATE_INCLUDE_DIRS}")
    set(TEMPLATE_FILE_SOURCE_FILE_LIST              "${CMAKE_LISTS_HANDLER_SOURCE_FILES}")
    set(TEMPLATE_FILE_PUBLIC_HEADER_LIST            "${CMAKE_LISTS_HANDLER_PUBLIC_HEADER_FILES}")
    set(TEMPLATE_FILE_PUBLIC_DEPENDENT_LIBS_LIST    "${CMAKE_LISTS_HANDLER_PUBLIC_DEPENDENCIES}")
    set(TEMPLATE_FILE_PRIVATE_DEPENDENT_LIBS_LIST   "${CMAKE_LISTS_HANDLER_PRIVATE_DEPENDENCIES}")  
    
    string(REGEX REPLACE ";" "\n" TEMPLATE_FILE_MODULE_NAME                 "${TEMPLATE_FILE_MODULE_NAME}")  
    string(REGEX REPLACE ";" "\n" TEMPLATE_FILE_MODULE_VERSION              "${TEMPLATE_FILE_MODULE_VERSION}")             
    string(REGEX REPLACE ";" "\n" TEMPLATE_FILE_PUBLIC_INCLUDE_DIRS_LIST    "${TEMPLATE_FILE_PUBLIC_INCLUDE_DIRS_LIST}")   
    string(REGEX REPLACE ";" "\n" TEMPLATE_FILE_PRIVATE_INCLUDE_DIRS_LIST   "${TEMPLATE_FILE_PRIVATE_INCLUDE_DIRS_LIST}")  
    string(REGEX REPLACE ";" "\n" TEMPLATE_FILE_SOURCE_FILE_LIST            "${TEMPLATE_FILE_SOURCE_FILE_LIST}")           
    string(REGEX REPLACE ";" "\n" TEMPLATE_FILE_PUBLIC_HEADER_LIST          "${TEMPLATE_FILE_PUBLIC_HEADER_LIST}")        
    string(REGEX REPLACE ";" "\n" TEMPLATE_FILE_PUBLIC_DEPENDENT_LIBS_LIST  "${TEMPLATE_FILE_PUBLIC_DEPENDENT_LIBS_LIST}") 
    string(REGEX REPLACE ";" "\n" TEMPLATE_FILE_PRIVATE_DEPENDENT_LIBS_LIST "${TEMPLATE_FILE_PRIVATE_DEPENDENT_LIBS_LIST}")
    
    message(DEBUG "Generating CMakeLists.txt file with TEMPLATE_FILE_MODULE_NAME                 set to : ${CMAKE_LISTS_HANDLER_MODULE_NAME}")
    message(DEBUG "Generating CMakeLists.txt file with TEMPLATE_FILE_MODULE_VERSION              set to : ${CMAKE_LISTS_HANDLER_MODULE_VERSION}")
    message(DEBUG "Generating CMakeLists.txt file with TEMPLATE_FILE_PUBLIC_INCLUDE_DIRS_LIST    set to : ${CMAKE_LISTS_HANDLER_PUBLIC_INCLUDE_DIRS}")
    message(DEBUG "Generating CMakeLists.txt file with TEMPLATE_FILE_PRIVATE_INCLUDE_DIRS_LIST   set to : ${CMAKE_LISTS_HANDLER_PRIVATE_INCLUDE_DIRS}")
    message(DEBUG "Generating CMakeLists.txt file with TEMPLATE_FILE_SOURCE_FILE_LIST            set to : ${CMAKE_LISTS_HANDLER_SOURCE_FILES}")
    message(DEBUG "Generating CMakeLists.txt file with TEMPLATE_FILE_PUBLIC_HEADER_LIST          set to : ${CMAKE_LISTS_HANDLER_PUBLIC_HEADER_FILES}")
    message(DEBUG "Generating CMakeLists.txt file with TEMPLATE_FILE_PUBLIC_DEPENDENT_LIBS_LIST  set to : ${CMAKE_LISTS_HANDLER_PUBLIC_DEPENDENCIES}")
    message(DEBUG "Generating CMakeLists.txt file with TEMPLATE_FILE_PRIVATE_DEPENDENT_LIBS_LIST set to : ${CMAKE_LISTS_HANDLER_PRIVATE_DEPENDENCIES}")

    configure_file("${CMAKE_LISTS_HANDLER_TEMPLATE_PATH}"
                   "${MODULE_PATH}/CMakeLists.txt"
                   @ONLY)
    
endfunction()


#==============================================================================#
# Script mode execution main functionality
#
# If the script is executed in script mode ( -P ), no functions are called, thus 
# direct execution has to be triggered.
#
# Example:
# cmake -DCMAKE_INIT_MODULE_PATH="App" -DCMAKE_INIT_MODULE_NAME="Application" -P CMakeLists_Handler.cmake
# 
# Applicable arguments:
#  - CMAKE_INIT_MODULE_NAME                 : Name of module to be used in CMakeLists.txt (CMake library name)                 
#  - CMAKE_INIT_MODULE_VERSION              : Version of CMakeLists.txt (in X.Y.Z)
#  - CMAKE_INIT_PUBLIC_INCLUDE_DIRS_LIST    : Publicly available directories
#  - CMAKE_INIT_PRIVATE_INCLUDE_DIRS_LIST   : Privately available directories
#  - CMAKE_INIT_SOURCE_FILE_LIST            : List of source files
#  - CMAKE_INIT_PUBLIC_HEADER_LIST          : List of public header files
#  - CMAKE_INIT_PUBLIC_DEPENDENT_LIBS_LIST  : List of public dependent CMake libraries
#  - CMAKE_INIT_PRIVATE_DEPENDENT_LIBS_LIST : List of private dependent CMake libraries
#
# Note: List records are separated by ';' symbol.
#==============================================================================#
if(CMAKE_SCRIPT_MODE_FILE AND 
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE AND 
   DEFINED CMAKE_INIT_MODULE_PATH AND
   DEFINED CMAKE_INIT_MODULE_NAME)
    
    message(DEBUG "Script CMakeLists_Handler executed in script mode.")
    
    set(CMAKE_LISTS_HANDLER_MODULE_NAME "${CMAKE_INIT_MODULE_NAME}")
    
    
    if(NOT DEFINED CMAKE_INIT_MODULE_VERSION)
        set(CMAKE_LISTS_HANDLER_MODULE_VERSION "1.0.0")
    else()
        set(CMAKE_LISTS_HANDLER_MODULE_VERSION "${CMAKE_INIT_MODULE_VERSION}")    
    endif()
    
    
    if(NOT DEFINED CMAKE_INIT_PUBLIC_INCLUDE_DIRS_LIST)
        set(CMAKE_LISTS_HANDLER_PUBLIC_INCLUDE_DIRS "")
    else()
        set(CMAKE_LISTS_HANDLER_PUBLIC_INCLUDE_DIRS "${CMAKE_INIT_PUBLIC_INCLUDE_DIRS_LIST}")     
    endif()
    
    
    if(NOT DEFINED CMAKE_INIT_PRIVATE_INCLUDE_DIRS_LIST)
        set(CMAKE_LISTS_HANDLER_PRIVATE_INCLUDE_DIRS "")
    else()
        set(CMAKE_LISTS_HANDLER_PRIVATE_INCLUDE_DIRS "${CMAKE_INIT_PRIVATE_INCLUDE_DIRS_LIST}")     
    endif()
                
         
    if(NOT DEFINED CMAKE_INIT_SOURCE_FILE_LIST)
        set(CMAKE_LISTS_HANDLER_SOURCE_FILES "")
    else()
        set(CMAKE_LISTS_HANDLER_SOURCE_FILES "${CMAKE_INIT_SOURCE_FILE_LIST}")     
    endif()
    
    
    if(NOT DEFINED CMAKE_INIT_PUBLIC_HEADER_LIST)
        set(CMAKE_LISTS_HANDLER_PUBLIC_HEADER_FILES "")
    else()
        set(CMAKE_LISTS_HANDLER_PUBLIC_HEADER_FILES "${CMAKE_INIT_PUBLIC_HEADER_LIST}")     
    endif()
    

    if(NOT DEFINED CMAKE_INIT_PUBLIC_DEPENDENT_LIBS_LIST)
        set(CMAKE_LISTS_HANDLER_PUBLIC_DEPENDENCIES "")
    else()
        set(CMAKE_LISTS_HANDLER_PUBLIC_DEPENDENCIES "${CMAKE_INIT_PUBLIC_DEPENDENT_LIBS_LIST}")     
    endif()
    
    
    if(NOT DEFINED CMAKE_INIT_PRIVATE_DEPENDENT_LIBS_LIST)
        set(CMAKE_LISTS_HANDLER_PRIVATE_DEPENDENCIES "")
    else()
        set(CMAKE_LISTS_HANDLER_PRIVATE_DEPENDENCIES "${CMAKE_INIT_PRIVATE_DEPENDENT_LIBS_LIST}")     
    endif()
    
    if(DEFINED PROJECT_ROOT_PATH AND DEFINED CMAKE_INIT_MODULE_PATH)
    
        set(MODULE_PATH "${PROJECT_ROOT_PATH}/${CMAKE_INIT_MODULE_PATH}")
    
        CMakeLists_Handler_Generate_CMakeLists(${MODULE_PATH})
        
    endif()
    
endif()

