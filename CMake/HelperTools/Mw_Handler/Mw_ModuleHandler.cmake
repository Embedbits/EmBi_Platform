# ==============================================================================
#
# Middlewares (MW) module handler CMake script.
#
# User can execute configure Middlewares module through this CMake script.
# 
# ==============================================================================


#===============================================================================
# Global variables
#===============================================================================

# Set path to system configuration file
get_filename_component(SYSTEM_CONFIG_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/../../SysConfig.cmake" REALPATH)

# Include file with system configuration values
include("${SYSTEM_CONFIG_FILE_PATH}")

# Set path to GIT handler module
get_filename_component(GIT_HANDLER_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/../Git_Handler/Git_Handler.cmake" REALPATH)

# Include GIT handler module
include("${GIT_HANDLER_FILE_PATH}")

# Read MW repository URL
SysConfig_Get_MwRepoURL(MW_REPO_URL)

# Read project root folder path
SysConfig_Get_ProjectRootPath(PROJECT_ROOT_PATH)


# Middlewares (MW) component path relative to project root path.
set(MW_REL_PATH "Middlewares")

# Board Support Packages (MW) cache path.
set(CACHE_PATH "${CMAKE_CURRENT_LIST_DIR}/Cache")


# ------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_CacheInit
# Description: Initialize MW cache (if needed).
# ------------------------------------------------------------------------------
function(Mw_ModuleHandler_CacheInit)

    if(EXISTS "${CACHE_PATH}" AND IS_DIRECTORY "${CACHE_PATH}")
    
        file(GLOB DIR_CONTENTS "${CACHE_PATH}/*")
    
        if(DIR_CONTENTS)
            set(MW_CLONED TRUE)
        else()
            set(MW_CLONED FALSE)
        endif()
    
    else()
        set(MW_CLONED FALSE)
    endif()

    if(NOT MW_CLONED)

        # 1️: Execute initial MW repository clone without submodules
        GitHandler_CloneMin(${MW_REPO_URL} ${CACHE_PATH})
        
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_UpdateCMakeLists
# Description: Append new module into Middlewares root CMakeLists.txt
# ------------------------------------------------------------------------------
function(Mw_ModuleHandler_UpdateCMakeLists IN_MODULE_NAME)

    set(MW_CMAKELIST_PATH "${PROJECT_ROOT_PATH}/${MW_REL_PATH}/Middlewares.cmake")
    set(NEW_LINE "add_subdirectory(\${CMAKE_CURRENT_LIST_DIR}/${IN_MODULE_NAME})")

    if(EXISTS "${MW_CMAKELIST_PATH}")
        file(READ "${MW_CMAKELIST_PATH}" EXISTING_CONTENT)
        
        # Check if already exists
        if(EXISTING_CONTENT MATCHES "${IN_MODULE_NAME}")
            message(STATUS "Module ${IN_MODULE_NAME} already in Middlewares.cmake")
            return()
        endif()
        
        # Append to the end
        string(APPEND EXISTING_CONTENT "\n${NEW_LINE}")
        file(WRITE "${MW_CMAKELIST_PATH}" "${EXISTING_CONTENT}")
    else()
        # Create new file
        file(WRITE "${MW_CMAKELIST_PATH}" "${NEW_LINE}\n")
    endif()
    
    message(STATUS "Added ${IN_MODULE_NAME} to Middlewares.cmake")
endfunction()


# ------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_FolderStructInit
# Description:
#   Initialization of Mw module folder structure.
#   The necessary sub-folders and files are created with following structure:
#   Project root/
#   ├── Application          (Application layer module)
#   ├── Middlewares*         (Middlewares layer module)
#   │   └── CMakeLists.txt*  (Middlewares root CMakeList file)
#   │
#   ├── Bsp                  (Board Support Packages layer module)
#   └── Stm_Template         (Template handler module)
#
# (* - newly created)
# ------------------------------------------------------------------------------
function(Mw_ModuleHandler_FolderStructInit)

    file(MAKE_DIRECTORY "${PROJECT_ROOT_PATH}/${MW_REL_PATH}")
    
    set(OUTPUT_PATH "${PROJECT_ROOT_PATH}/${MW_REL_PATH}/Middlewares.cmake")
    set(CONTENT " ")
    
    if(NOT EXISTS "${OUTPUT_PATH}")
        file(WRITE "${OUTPUT_PATH}" "${CONTENT}")
    endif()
    
endfunction()


#-------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_Config
#
# Description: 
# The MW GIT submodules are initialized if needed, or its commits are switched
# in regards of configuration. The user can easily switch MCU family, or 
# initialize the MW module. 
#
# IN_MODULE_ID [in]: Middleware module numerical identification (e.g. 1 for FreeRTOS)
#-------------------------------------------------------------------------------
function(Mw_ModuleHandler_Config IN_MODULE_ID)
    
    Mw_ModuleHandler_CacheInit()
    
    Mw_ModuleHandler_FolderStructInit()
    
    GitHandler_GetSubmoduleList(${CACHE_PATH} 
                                SUBMODULE_PATHS 
                                SUBMODULE_URLS 
                                SUBMODULE_ACTIVES 
                                SUBMODULES_COUNT)
    
    list(GET SUBMODULE_PATHS ${IN_MODULE_ID} SUBMODULE_NAME)
    
    message(STATUS "Submodule ${SUBMODULE_NAME} selected.")

            
    message(DEBUG "Processing submodule index: ${IN_MODULE_ID}")
    list(GET SUBMODULE_PATHS ${IN_MODULE_ID} SUB_NAME)
    list(GET SUBMODULE_URLS  ${IN_MODULE_ID} SUB_URL)
    list(GET SUBMODULE_ACTIVES ${IN_MODULE_ID} SUB_ACTIVE)
    
    message(STATUS "*********************************************************")
    message(STATUS "Processing submodule: ${SUB_NAME}")
    message(DEBUG "  URL:    ${SUB_URL}")
    message(STATUS "*********************************************************")
    
    # ------------------------------------------------------
    # Add git submodule
    # ------------------------------------------------------
    set(LOCAL_SUB_PATH "${PROJECT_ROOT_PATH}/${MW_REL_PATH}/${SUB_NAME}")
    
    if(EXISTS "${LOCAL_SUB_PATH}/.git")
    
        message(DEBUG "Module already found in ${LOCAL_SUB_PATH}")
        
    else()
    
        GitHandler_SubmoduleInit(${SUB_URL} "${MW_REL_PATH}/${SUB_NAME}" ${SUB_ACTIVE})
        
        # Ignore submodule changes in parent directory
        GitHandler_SubmoduleIgnore("${MW_REL_PATH}/${SUB_NAME}" "dirty")
        
    endif()    
    
    Mw_ModuleHandler_UpdateCMakeLists(${SUB_NAME})        

    message(STATUS "Middlewares (MW) module ${SUB_NAME} initialization complete.")

endfunction()


# ------------------------------------------------------------------------------
# Function: Mw_BranchHandler_PrintBranchList
# Description: Prints all available MW branches available in repository.
# ------------------------------------------------------------------------------
function(Mw_ModuleHandler_PrintBranchList)

    Mw_ModuleHandler_CacheInit()

    GitHandler_GetSubmoduleList(${CACHE_PATH}
                                SUBMODULE_PATHS 
                                SUBMODULE_URLS 
                                SUBMODULE_ACTIVES 
                                SUBMODULES_COUNT)
    
    # Print to console
    math(EXPR LIST_SIZE "${SUBMODULES_COUNT} - 1")
    
    message("[0]: Return back")
    
    foreach(LIST_INDEX RANGE ${LIST_SIZE})
    
        list(GET SUBMODULE_PATHS ${LIST_INDEX} SUBMODULE_NAME)
        math(EXPR DISPLAY_INDEX "${LIST_INDEX} + 1")
        message("[${DISPLAY_INDEX}]: ${SUBMODULE_NAME}")
        
    endforeach()
endfunction()


#==============================================================================#
# Main functionality
# Usage: 
# cmake -P Mw_ModuleHandler.cmake               : The module list will be print
# cmake -P -DMODULE_ID=2 Mw_ModuleHandler.cmake : The module with ID 2 will be used
#==============================================================================#
if(CMAKE_SCRIPT_MODE_FILE AND 
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)
   
    if(DEFINED MODULE_ID)
    
        if(BRANCH_ID GREATER 0)
        
            math(EXPR REAL_INDEX "${MODULE_ID} - 1")
            
            Mw_ModuleHandler_Config(${REAL_INDEX})
            
        else()
                
            message(STATUS "Returning...")
                    
        endif()
            
    else()
        Mw_ModuleHandler_PrintBranchList()
    endif()
    
endif()