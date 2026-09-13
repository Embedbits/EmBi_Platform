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
# │   ├── Mcal                      (Micro-Controller Abstraction Layer -
# │   │   NOT a single submodule; composed of the
# │   │   individual peripheral repositories Mcal
# │   │   itself declares, e.g. Rcc, Nvic, Gpio,
# │   │   Exti, ... - see
# │   │   Bsp_ModuleHandler_McalPeripheralsInit)
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
# Function: Bsp_ModuleHandler_DocsBranchList
# Description:
#   Returns the list of Docs repository branches WITHOUT cloning it - the
#   Docs repository is large, so listing its branches must never trigger a
#   full clone (a plain `git ls-remote` against the URL is used instead, see
#   GitHandler_ListRemoteBranches). The "main"/"master" branch is filtered
#   out of the result, since Docs content is only ever selected per-topic/
#   per-family branch, never from the default branch.
#
# OUT_BRANCH_LIST [out]: Filtered list of Docs repository branch names.
# ------------------------------------------------------------------------------
function(Bsp_ModuleHandler_DocsBranchList OUT_BRANCH_LIST)

    GitHandler_ListRemoteBranches(${DOCS_REPO_URL} BRANCH_LIST)

    list(REMOVE_ITEM BRANCH_LIST "main")
    list(REMOVE_ITEM BRANCH_LIST "master")

    set(${OUT_BRANCH_LIST} ${BRANCH_LIST} PARENT_SCOPE)

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
#   ├── Mcal                 (Micro-Controller Abstraction Layer - populated
#   │   with Mcal's own peripheral submodules, see
#   │   Bsp_ModuleHandler_McalPeripheralsInit)
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


# ------------------------------------------------------------------------------
# Function: Bsp_ModuleHandler_McalCMakeListsGenerate
# Description:
#   (Re)generates the Bsp/Mcal/CMakeLists.txt file so it add_subdirectory()'s
#   every peripheral submodule that was composed into Bsp/Mcal. Always
#   overwrites the file from scratch, so it stays in sync with whichever
#   peripheral repositories were actually added on the current run.
#
# IN_MODULE_NAMES [in]: List of peripheral module folder names (e.g. Rcc,
#                        Nvic) that were added under Bsp/Mcal and need to be
#                        built.
# ------------------------------------------------------------------------------
function(Bsp_ModuleHandler_McalCMakeListsGenerate IN_MODULE_NAMES)

    file(MAKE_DIRECTORY "${PROJECT_ROOT_PATH}/${BSP_REL_PATH}/Mcal")

    set(MCAL_CMAKE_PATH "${PROJECT_ROOT_PATH}/${BSP_REL_PATH}/Mcal/CMakeLists.txt")

    if(IN_MODULE_NAMES)

        set(CONTENT "")

        foreach(MODULE_NAME ${IN_MODULE_NAMES})
            string(APPEND CONTENT "add_subdirectory(\${CMAKE_CURRENT_LIST_DIR}/${MODULE_NAME})\n")
        endforeach()

    else()

        set(CONTENT "# No Mcal peripheral submodules matched the selected branch.\n")

    endif()

    file(WRITE "${MCAL_CMAKE_PATH}" "${CONTENT}")

endfunction()


# ------------------------------------------------------------------------------
# Function: Bsp_ModuleHandler_McalPeripheralsInit
# Description:
#   Composes the Bsp/Mcal folder out of Mcal's OWN peripheral repositories,
#   instead of adding the Mcal repository itself as a single GIT submodule.
#
#   Mcal's repository is cloned into a scratch cache (never committed as a
#   project submodule) and switched to the selected family branch. Its
#   .gitmodules is then read to discover every peripheral repository it
#   currently declares (e.g. Rcc, Nvic, Gpio, Exti, ...). Each peripheral
#   repository that also has the selected family branch available is added
#   as its own GIT submodule directly under Bsp/Mcal and checked out at the
#   LATEST commit of that branch (not a pinned commit) - a peripheral
#   repository missing the branch is soft-skipped with a warning, it does not
#   abort the rest. Finally, Bsp/Mcal/CMakeLists.txt is regenerated to build
#   every module that was added.
#
# IN_MCAL_REPO_URL [in]: URL of Mcal's own GIT repository (as declared in the
#                         BSP repository's .gitmodules).
# IN_BRANCH_NAME   [in]: Selected family branch name (e.g. "STM32G4"), used
#                         both to select Mcal's own peripheral list and to
#                         checkout each peripheral repository's latest commit.
# ------------------------------------------------------------------------------
function(Bsp_ModuleHandler_McalPeripheralsInit IN_MCAL_REPO_URL IN_BRANCH_NAME)

    # ----------------------------------------------------------
    # Clone (or reuse) a scratch copy of Mcal itself, purely to
    # read its .gitmodules - Mcal is never added as a submodule.
    # ----------------------------------------------------------
    set(MCAL_CACHE_PATH "${CACHE_PATH}/Mcal")

    if(NOT EXISTS "${MCAL_CACHE_PATH}/.git")
        GitHandler_CloneMin(${IN_MCAL_REPO_URL} ${MCAL_CACHE_PATH})
    endif()

    GitHandler_SwitchBranch(${MCAL_CACHE_PATH} ${IN_BRANCH_NAME})

    GitHandler_GetSubmoduleList(${MCAL_CACHE_PATH}
                                MCAL_SUB_PATHS
                                MCAL_SUB_URLS
                                MCAL_SUB_ACTIVES
                                MCAL_SUB_COUNT)

    set(MCAL_REL_PATH "${BSP_REL_PATH}/Mcal")
    set(MCAL_ADDED_MODULES "")

    if(MCAL_SUB_COUNT GREATER 0)

        math(EXPR MCAL_LAST_INDEX "${MCAL_SUB_COUNT} - 1")

        foreach(idx RANGE 0 ${MCAL_LAST_INDEX})

            list(GET MCAL_SUB_PATHS   ${idx} MCAL_SUB_NAME)
            list(GET MCAL_SUB_URLS    ${idx} MCAL_SUB_URL)
            list(GET MCAL_SUB_ACTIVES ${idx} MCAL_SUB_ACTIVE)

            message(STATUS "*********************************************************")
            message(STATUS "Processing Mcal peripheral: ${MCAL_SUB_NAME}")
            message(DEBUG "  URL: ${MCAL_SUB_URL}")
            message(STATUS "*********************************************************")

            # --------------------------------------------------
            # Only compose peripherals that actually have the
            # selected family branch available.
            # --------------------------------------------------
            GitHandler_RemoteBranchExists(${MCAL_SUB_URL} ${IN_BRANCH_NAME} MCAL_SUB_BRANCH_EXISTS)

            if(NOT MCAL_SUB_BRANCH_EXISTS)
                message(WARNING "Mcal peripheral '${MCAL_SUB_NAME}' has no branch '${IN_BRANCH_NAME}' - skipping.")
                continue()
            endif()

            set(LOCAL_MCAL_SUB_PATH "${PROJECT_ROOT_PATH}/${MCAL_REL_PATH}/${MCAL_SUB_NAME}")

            if(EXISTS "${LOCAL_MCAL_SUB_PATH}/.git")

                message(DEBUG "GIT submodule already found in ${LOCAL_MCAL_SUB_PATH}")

            else()

                GitHandler_SubmoduleInit(${MCAL_SUB_URL} "${MCAL_REL_PATH}/${MCAL_SUB_NAME}" ${MCAL_SUB_ACTIVE} MCAL_SUB_IS_SUBMODULE)

                # Ignore submodule changes in parent directory (meaningless for a
                # plain clone fallback - EmBi platform is not itself a GIT repo)
                if(MCAL_SUB_IS_SUBMODULE)
                    GitHandler_SubmoduleIgnore("${MCAL_REL_PATH}/${MCAL_SUB_NAME}" "dirty")
                endif()

            endif()

            # --------------------------------------------------
            # Always checkout the LATEST commit of the family
            # branch (never a pinned commit) for each peripheral.
            # --------------------------------------------------
            GitHandler_SwitchBranch(${LOCAL_MCAL_SUB_PATH} ${IN_BRANCH_NAME})

            list(APPEND MCAL_ADDED_MODULES "${MCAL_SUB_NAME}")

        endforeach()

    else()

        message(WARNING "No peripheral repositories declared in Mcal's .gitmodules on branch ${IN_BRANCH_NAME}.")

    endif()

    # ----------------------------------------------------------
    # Remove any Bsp/Mcal/<X> peripheral submodule left over from a
    # PREVIOUS family/branch that the currently selected one doesn't
    # declare anymore.
    # ----------------------------------------------------------
    GitHandler_PruneStaleSubmodules("${MCAL_REL_PATH}" "${MCAL_ADDED_MODULES}")

    Bsp_ModuleHandler_McalCMakeListsGenerate("${MCAL_ADDED_MODULES}")

    message(STATUS "Mcal peripheral composition complete (${MCAL_ADDED_MODULES}).")

endfunction()


#-------------------------------------------------------------------------------
# Configuration BSP module.
#
# Description: 
# The BSP GIT submodules are initialized if needed, or its commits are switched
# in regards of configuration. The user can easily switch MCU family, or 
# initialize the BSP module. 
#
# Special case - Mcal: Mcal itself is NEVER added as a GIT submodule. Instead,
# its repository is inspected (see Bsp_ModuleHandler_McalPeripheralsInit) and
# every peripheral repository it currently declares (Rcc, Nvic, Gpio, ...) is
# added as an individual submodule directly under Bsp/Mcal, each checked out
# at the LATEST commit of the selected family branch (never a pinned commit).
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
    # Names of submodules actually valid for the selected branch -
    # used afterwards to prune anything left over from a PREVIOUS
    # family/branch selection that no longer applies.
    # ----------------------------------------------------------
    set(PROCESSED_SUB_NAMES "")

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

            # This submodule IS valid for the selected branch - keep it.
            list(APPEND PROCESSED_SUB_NAMES "${SUB_NAME}")

            # ------------------------------------------------------
            # Mcal special case: never add Mcal itself as a submodule -
            # compose Bsp/Mcal from its own peripheral repositories
            # instead (see Bsp_ModuleHandler_McalPeripheralsInit).
            # ------------------------------------------------------
            if("${SUB_NAME}" STREQUAL "Mcal")

                Bsp_ModuleHandler_McalPeripheralsInit(${SUB_URL} ${BRANCH_NAME})

                continue()

            endif()
            
            # ------------------------------------------------------
            # Add git submodule
            # ------------------------------------------------------
            set(LOCAL_SUB_PATH "${PROJECT_ROOT_PATH}/${BSP_REL_PATH}/${SUB_NAME}")
            
            if(EXISTS "${LOCAL_SUB_PATH}/.git")
    
                message(DEBUG "GIT submodule already found in ${LOCAL_SUB_PATH}")
                
            else()

                GitHandler_SubmoduleInit(${SUB_URL} "${BSP_REL_PATH}/${SUB_NAME}" ${SUB_ACTIVE} SUB_IS_SUBMODULE)

                # Ignore submodule changes in parent directory (meaningless for a
                # plain clone fallback - EmBi platform is not itself a GIT repo)
                if(SUB_IS_SUBMODULE)
                    GitHandler_SubmoduleIgnore("${BSP_REL_PATH}/${SUB_NAME}" "dirty")
                endif()

            endif()
        
            # ------------------------------------------------------
            # Commit checkout
            # ------------------------------------------------------
            GitHandler_SwitchBranch(${LOCAL_SUB_PATH} ${SUB_COMMIT})
            
        endforeach()
        
    else()
    
        message(WARNING "No submodules found in branch ${BRANCH_NAME}.")
    
    endif()

    # ----------------------------------------------------------
    # Remove any Bsp/<X> submodule left over from a PREVIOUS family/
    # branch selection that isn't valid for the one just selected.
    # ----------------------------------------------------------
    GitHandler_PruneStaleSubmodules("${BSP_REL_PATH}" "${PROCESSED_SUB_NAMES}")
    
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
# Function: Bsp_ModuleHandler_PrintDocsBranchList
# Description: Prints all available Docs branches (main/master filtered out),
#              WITHOUT cloning the Docs repository (it is large) - see
#              Bsp_ModuleHandler_DocsBranchList.
# ------------------------------------------------------------------------------
function(Bsp_ModuleHandler_PrintDocsBranchList)

    Bsp_ModuleHandler_DocsBranchList(GIT_BRANCHES)
    
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
# Description:
#   Downloads Docs content for the selected branch. Only that ONE branch is
#   ever downloaded - a fresh clone uses GitHandler_CloneSingleBranch (never
#   the full Docs repository), and if a Docs clone already exists from a
#   previous run (possibly on a different branch), only the newly selected
#   branch is additionally fetched (GitHandler_FetchAndTrackBranch) instead
#   of re-cloning everything.
#
# IN_BRANCH_ID [in]: Branch numerical identification (e.g. 1 for STM32G4_Dev)
# ------------------------------------------------------------------------------
function(Bsp_ModuleHandler_DocsInit IN_BRANCH_ID)

    Bsp_ModuleHandler_DocsBranchList(GIT_BRANCHES)
    
    list(GET GIT_BRANCHES ${IN_BRANCH_ID} BRANCH_NAME)
    
    message(STATUS "Branch ${BRANCH_NAME} selected.")

    if(EXISTS "${DOCS_PATH}/.git")

        # A Docs clone already exists (possibly on a different branch) -
        # just make this branch fetchable on it, instead of re-cloning.
        GitHandler_FetchAndTrackBranch(${DOCS_PATH} ${BRANCH_NAME})

    else()

        # Fresh clone - only the selected branch is downloaded, never the
        # full Docs repository (it is large).
        GitHandler_CloneSingleBranch(${DOCS_REPO_URL} ${BRANCH_NAME} ${DOCS_PATH})

    endif()
    
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