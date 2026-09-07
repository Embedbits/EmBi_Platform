# ==============================================================================
#
# Board Support Packages (BSP) structure initialization CMake script.
#
# The module structure shall have following structure:
#
# Project_root/
# │
# ├── Application                   (Application layer)
# ├── Bsp                           (Board Support Packages)
# │   ├── Hal                       (Hardware Abstraction Layer)
# │   ├── Linker                    (Linker generator module)
# │   ├── Mcal                      (Micro-Controller Abstraction Layer)
# │   ├── Ral                       (Register Abstraction Layer)
# │   └── Startup                   (Startup handler)
# │                                 
# ├── Middlewares                   (Middlewares folder)
# ├── STM_Template                  (Build and miscellaneous tools)
# ├── ArtifactsConfig.txt           (Artifacts configuration file)
# ├── CMakeLists.txt                (Project root CMake file)
# └── README.md                     (Project documentation)
#
# User can execute initialization of this structure through this CMake script.
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

# Set path to CMakeLists.txt handler module
get_filename_component(CMAKELISTS_HANDLER_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/../CMakeLists_Handler/CMakeLists_Handler.cmake" REALPATH)

# Include CMakeLists.txt handler module
include("${CMAKELISTS_HANDLER_FILE_PATH}")

# Read BSP repository URL
SysConfig_Get_BspRepoURL(BSP_REPO_URL)

# Read BSP repository URL
SysConfig_Get_DocsRepoURL(DOCS_REPO_URL)

# Read project root folder path
SysConfig_Get_ProjectRootPath(PROJECT_ROOT_PATH)


# Board Support Packages (BSP) component path relative to project root path.
set(BSP_REL_PATH "Bsp")

# Board Support Packages (BSP) cache path.
set(CACHE_PATH "${CMAKE_CURRENT_LIST_DIR}/Cache")

# Documentation files path.
SysConfig_Get_DocsPath(DOCS_PATH)


# ------------------------------------------------------------------------------
# Function: Bsp_ModuleHandler_CacheInit
# Description: Initialize BSP cache (if needed).
# ------------------------------------------------------------------------------
function(Bsp_ModuleHandler_CacheInit)

    if(EXISTS "${CACHE_PATH}" AND IS_DIRECTORY "${CACHE_PATH}")
    
        file(GLOB DIR_CONTENTS "${CACHE_PATH}/*")
    
        if(DIR_CONTENTS)
            set(BSP_CLONED TRUE)
        else()
            set(BSP_CLONED FALSE)
        endif()
    
    else()
        set(BSP_CLONED FALSE)
    endif()

    if(NOT BSP_CLONED)

        # 1️: Execute initial BSP repository clone without submodules
        GitHandler_CloneMin(${BSP_REPO_URL} ${CACHE_PATH})
        
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: Bsp_ModuleHandler_DocsInit
# Description: Initialize Documentation cache (if needed).
# ------------------------------------------------------------------------------
function(Bsp_ModuleHandler_DocsRepoInit)

    if(EXISTS "${DOCS_PATH}" AND IS_DIRECTORY "${DOCS_PATH}")
    
        file(GLOB DIR_CONTENTS "${DOCS_PATH}/*")
    
        if(DIR_CONTENTS)
            set(BSP_CLONED TRUE)
        else()
            set(BSP_CLONED FALSE)
        endif()
    
    else()
        set(BSP_CLONED FALSE)
    endif()

    if(NOT BSP_CLONED)

        # 1️: Execute initial BSP repository clone without submodules
        GitHandler_CloneMin(${DOCS_REPO_URL} ${DOCS_PATH})
        
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: Bsp_ModuleHandler_FolderStructInit
# Description:
#   Initialization of Bsp module folder structure.
#   The necessary sub-folders and files are created with following structure:
#   Bsp/
#   ├── Hal                  (Hardware Abstraction Layer)
#   │   ├── CMakeLists.txt   (Hal CMake file)
#   │   └── BspMain          (BSP main module)
#   │       ├── BspMain.c     (BSP main source file)
#   │       ├── BspMain.h     (BSP main header file)
#   │       └── CMakeLists.txt (BspMain CMake file)
#   │
#   ├── Mcal                 (Micro-Controller Abstraction Layer)
#   ├── Ral                  (Register Abstraction Layer)
#   ├── Linker               (Linker generator module)
#   └── Startup              (Startup handler)
# ------------------------------------------------------------------------------
function(Bsp_ModuleHandler_FolderStructInit)

    file(MAKE_DIRECTORY "${PROJECT_ROOT_PATH}/${BSP_REL_PATH}")
    file(MAKE_DIRECTORY "${PROJECT_ROOT_PATH}/${BSP_REL_PATH}/Hal")
    file(MAKE_DIRECTORY "${PROJECT_ROOT_PATH}/${BSP_REL_PATH}/Hal/BspMain")
                    
    # Copy necessary .c & .h files
    execute_process(COMMAND git config --global user.name
                    OUTPUT_VARIABLE AUTHOR
                    OUTPUT_STRIP_TRAILING_WHITESPACE)
        
    if(NOT EXISTS "${PROJECT_ROOT_PATH}/${BSP_REL_PATH}/Hal/BspMain/BspMain.c")
        configure_file("${CMAKE_CURRENT_LIST_DIR}/Template_BspMain.c.in"
                       "${PROJECT_ROOT_PATH}/${BSP_REL_PATH}/Hal/BspMain/BspMain.c"
                       @ONLY)
    endif()
           
    if(NOT EXISTS "${PROJECT_ROOT_PATH}/${BSP_REL_PATH}/Hal/BspMain/BspMain.h")
        configure_file("${CMAKE_CURRENT_LIST_DIR}/Template_BspMain.h.in"
                       "${PROJECT_ROOT_PATH}/${BSP_REL_PATH}/Hal/BspMain/BspMain.h"
                       @ONLY)
    endif()
    
    
    set(OUTPUT_PATH "${PROJECT_ROOT_PATH}/${BSP_REL_PATH}/Hal/CMakeLists.txt")
    set(CONTENT "add_subdirectory(\${CMAKE_CURRENT_LIST_DIR}/BspMain)")

    if(NOT EXISTS "${OUTPUT_PATH}")
        file(WRITE "${OUTPUT_PATH}" "${CONTENT}")
    endif()
    
    
    # Set output path for BSP Main module
    set(BSP_MAIN_MODULE_OUTPUT_PATH "${PROJECT_ROOT_PATH}/${BSP_REL_PATH}/Hal/BspMain/")
    
    if(NOT EXISTS "${BSP_MAIN_MODULE_OUTPUT_PATH}/CMakeLists.txt")
        # Generate CMakeLists.txt for BspMain module
        CMakeLists_Handler_Set_PrivateInlcudeDirs("\${CMAKE_CURRENT_SOURCE_DIR}")
        CMakeLists_Handler_Set_PublicInlcudeDirs("")
        CMakeLists_Handler_Set_SourceFiles("BspMain.c")
        CMakeLists_Handler_Set_PublicHeaderFiles("BspMain.h")
        CMakeLists_Handler_Set_PublicDependenLibs("")
        CMakeLists_Handler_Set_PrivateDependentLibs("AppMain_Lib")
        CMakeLists_Handler_Set_ModuleName("BspMain")
        CMakeLists_Handler_Generate_CMakeLists("${BSP_MAIN_MODULE_OUTPUT_PATH}")
    endif()
    
endfunction()


#-------------------------------------------------------------------------------
# Configuration BSP module.
#
# Description: 
# The BSP GIT submodules are initialized if needed, or its commits are switched
# in regards of configuration. The user can easily switch MCU family, or 
# initialize the BSP module. 
#
# IN_BRANCH_ID [in]: Branch numerical identification (e.g. 1 for STM32G4_Dev)
#-------------------------------------------------------------------------------
function(Bsp_ModuleHandler_Config IN_BRANCH_ID)
    
    Bsp_ModuleHandler_CacheInit()
    
    Bsp_ModuleHandler_FolderStructInit()
    
    GitHandler_GetRemoteBranchList(${CACHE_PATH} GIT_BRANCHES)
    
    list(GET GIT_BRANCHES ${IN_BRANCH_ID} BRANCH_NAME)
    
    message(STATUS "Branch ${BRANCH_NAME} selected.")
    
    GitHandler_SwitchBranch(${CACHE_PATH} ${BRANCH_NAME})

    # ----------------------------------------------------------
    # Load .gitmodules and extract submodules + UR's
    # ----------------------------------------------------------
        
    GitHandler_GetSubmoduleList(${CACHE_PATH} 
                                SUBMODULE_PATHS 
                                SUBMODULE_URLS 
                                SUBMODULE_ACTIVES 
                                SUBMODULE_COUNT)
                                
    message(DEBUG "Submodules count returned: ${SUBMODULES_COUNT}")

    # ----------------------------------------------------------
    # 3️: Find commit hash for every submodule in current branch
    # ----------------------------------------------------------
    if(SUBMODULE_COUNT GREATER 0)
        math(EXPR LAST_INDEX "${SUBMODULE_COUNT} - 1")
    
        foreach(idx RANGE 0 ${LAST_INDEX})
            
            message(DEBUG "Processing submodule index: ${idx}")
            list(GET SUBMODULE_PATHS   ${idx} SUB_NAME)
            list(GET SUBMODULE_URLS    ${idx} SUB_URL)
            list(GET SUBMODULE_ACTIVES ${idx} SUB_ACTIVE)
			
			GitHandler_GetCommitId(${CACHE_PATH} ${BRANCH_NAME} ${SUB_NAME} SUB_COMMIT)
        
            message(STATUS "*********************************************************")
            message(STATUS "Processing submodule: ${SUB_NAME}")
            message(DEBUG "  URL:    ${SUB_URL}")
            message(DEBUG "  Commit: ${SUB_COMMIT}")
            message(STATUS "*********************************************************")
            
            if("${SUB_COMMIT}" STREQUAL "")
                message(DEBUG "Submodule ${SUB_NAME} does not exist on branch ${BRANCH_NAME}")
                continue()
            endif()
            
            # ------------------------------------------------------
            # Add git submodule
            # ------------------------------------------------------
            set(LOCAL_SUB_PATH "${PROJECT_ROOT_PATH}/${BSP_REL_PATH}/${SUB_NAME}")
            
            if(EXISTS "${LOCAL_SUB_PATH}/.git")
    
                message(DEBUG "GIT submodule already found in ${LOCAL_SUB_PATH}")
                
            else()
            
                GitHandler_SubmoduleInit(${SUB_URL} "${BSP_REL_PATH}/${SUB_NAME}" ${SUB_ACTIVE})
                
                # Ignore submodule changes in parent directory
                GitHandler_SubmoduleIgnore("${BSP_REL_PATH}/${SUB_NAME}" "dirty")
                
            endif()
        
            # ------------------------------------------------------
            # Commit checkout
            # ------------------------------------------------------
            GitHandler_SwitchBranch(${LOCAL_SUB_PATH} ${SUB_COMMIT})
            
        endforeach()
        
    else()
    
        message(WARNING "No submodules found in branch ${BRANCH_NAME}.")
    
    endif()
    
    # Copy content of BSP module from repository into project
    file(GLOB FILES_ONLY "${CACHE_PATH}/*")
    
    foreach(FILE_NAME ${FILES_ONLY})
        get_filename_component(BASE_NAME "${FILE_NAME}" NAME)
        if(NOT IS_DIRECTORY "${FILE_NAME}" AND NOT ${BASE_NAME} STREQUAL ".gitmodules")
            file(COPY "${FILE_NAME}" DESTINATION "${PROJECT_ROOT_PATH}/${BSP_REL_PATH}")
        endif()
    endforeach()

    message(STATUS "Board Support Packages (BSP) module initialization complete.")

endfunction()


# ------------------------------------------------------------------------------
# Function: Bsp_BranchHandler_PrintBranchList
# Description: Prints all available BSP branches available in repository.
# ------------------------------------------------------------------------------
function(Bsp_ModuleHandler_PrintBranchList)

    Bsp_ModuleHandler_CacheInit()

    GitHandler_GetRemoteBranchList(${CACHE_PATH} GIT_BRANCHES)
    
    # Print to console    
    list(LENGTH GIT_BRANCHES count)
    math(EXPR LIST_SIZE "${count} - 1")
    
    message("[0]: Return back")
    
    foreach(LIST_INDEX RANGE ${LIST_SIZE})

        list(GET GIT_BRANCHES ${LIST_INDEX} BRANCH_NAME)
        math(EXPR DISPLAY_INDEX "${LIST_INDEX} + 1")
        message("[${DISPLAY_INDEX}]: ${BRANCH_NAME}")

    endforeach()
endfunction()


# ------------------------------------------------------------------------------
# Function: Bsp_BranchHandler_PrintBranchList
# Description: Prints all available BSP branches available in repository.
# ------------------------------------------------------------------------------
function(Bsp_ModuleHandler_PrintDocsBranchList)

    Bsp_ModuleHandler_DocsRepoInit()

    GitHandler_GetRemoteBranchList(${DOCS_PATH} GIT_BRANCHES)
    
    # Print to console    
    list(LENGTH GIT_BRANCHES count)
    math(EXPR LIST_SIZE "${count} - 1")
    
    message("[0]: Return back")
    
    foreach(LIST_INDEX RANGE ${LIST_SIZE})

        list(GET GIT_BRANCHES ${LIST_INDEX} BRANCH_NAME)
        math(EXPR DISPLAY_INDEX "${LIST_INDEX} + 1")
        message("[${DISPLAY_INDEX}]: ${BRANCH_NAME}")

    endforeach()
endfunction()


# ------------------------------------------------------------------------------
# Function: Bsp_ModuleHandler_DocsInit
# Description: Downloads Docs submodule.
#
# IN_BRANCH_ID [in]: Branch numerical identification (e.g. 1 for STM32G4_Dev)
# ------------------------------------------------------------------------------
function(Bsp_ModuleHandler_DocsInit IN_BRANCH_ID)
    
    GitHandler_GetRemoteBranchList(${DOCS_PATH} GIT_BRANCHES)
    
    list(GET GIT_BRANCHES ${IN_BRANCH_ID} BRANCH_NAME)
    
    message(STATUS "Branch ${BRANCH_NAME} selected.")
    
    GitHandler_SwitchBranch(${DOCS_PATH} ${BRANCH_NAME})

endfunction()


#==============================================================================#
# Main functionality
# Usage: 
# cmake -P Bsp_ModuleHandler.cmake               : The branch list will be print
# cmake -P -DBRANCH_ID=2 Bsp_ModuleHandler.cmake : The branch with ID 2 will be used
#==============================================================================#
if(CMAKE_SCRIPT_MODE_FILE AND 
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)
   
    if("${FUNCTION_ID}" STREQUAL "BRANCH_LIST")
    
        Bsp_ModuleHandler_PrintBranchList()
        
    elseif("${FUNCTION_ID}" STREQUAL "DOCS_LIST")
    
        Bsp_ModuleHandler_PrintDocsBranchList()
   
    elseif("${FUNCTION_ID}" STREQUAL "BSP_CONFIG")
    
        if(DEFINED BRANCH_ID)
            
            if("${BRANCH_ID}" MATCHES "^[0-9]+$")
            
                if(BRANCH_ID GREATER 0)
            
                    math(EXPR REAL_INDEX "${BRANCH_ID} - 1")
            
                    Bsp_ModuleHandler_Config(${REAL_INDEX})
                    
                else()
                
                    message(STATUS "Returning...")
                    
                endif()
                
            else()
            
                message(FATAL_ERROR "Required BRANCH_ID is not correct.")
                
            endif()
        else()
        
            message(FATAL_ERROR "Required PBRANCH_ID not specified.")
            
        endif()
   
    elseif("${FUNCTION_ID}" STREQUAL "DOCS_INIT")
        
        if(DEFINED BRANCH_ID)
            
            if("${BRANCH_ID}" MATCHES "^[0-9]+$")
                
                if(BRANCH_ID GREATER 0)
            
                    math(EXPR REAL_INDEX "${BRANCH_ID} - 1")
            
                    Bsp_ModuleHandler_DocsInit(${REAL_INDEX})
                    
                else()
                
                    message(STATUS "Returning...")
                    
                endif()
                
            else()
            
                message(FATAL_ERROR "Required BRANCH_ID is not correct.")
                
            endif()
        else()
        
            message(FATAL_ERROR "Required PBRANCH_ID not specified.")
            
        endif()
   
    endif()
    
endif()