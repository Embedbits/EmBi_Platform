# ==============================================================================
#
# Generic GIT helper functions used by the module handler scripts (Bsp, Ral,
# Mw, ...).
#
# Provides low level wrappers around GIT operations needed to manage
# repositories and their submodules:
#   - Reading a repository's declared submodules (name / URL / active state)
#     directly from its .gitmodules file.
#   - Resolving a submodule's pinned commit for a given branch of its parent
#     repository.
#   - Cloning a repository without submodules (used to seed local caches).
#   - Adding a new GIT submodule at a given path.
#   - Listing a repository's remote branches, and checking whether a specific
#     branch exists on a remote (without requiring a local clone).
#   - Switching a repository (or submodule) to a given branch/commit, doing a
#     hard reset + clean, and recursively updating any nested submodules.
#   - Configuring how a submodule's local modifications are reported by its
#     parent repository (the "ignore" setting).
#
# All functions in this file operate purely on GIT (no Azure DevOps / GitHub
# REST API calls) and are shared across the *_Handler.cmake scripts.
#
# ==============================================================================


# ------------------------------------------------------------------------------
# Function: GitHandler_GetSubmoduleList
# Description: Returns lists of submodules and its URL's in parent directory.
#
# IN_SOURCE_PATH             [in]: Source directory with GIT submodules to be found. 
# OUT_SUBMODULE_NAME_LIST   [out]: List of found GIT submodules.
# OUT_SUBMODULE_URL_LIST    [out]: List of GIT submodules URL's.
# OUT_SUBMODULE_ACTIVE_LIST [out]: Active state of GIT submodules.
# OUT_SUBMODULES_COUNT      [out]: Count of found GIT submodules.
# ------------------------------------------------------------------------------
function(GitHandler_GetSubmoduleList IN_SOURCE_PATH
                                     OUT_SUBMODULE_NAME_LIST
                                     OUT_SUBMODULE_URL_LIST
                                     OUT_SUBMODULE_ACTIVE_LIST
                                     OUT_SUBMODULES_COUNT)

    set(GITMODULES_FILE "${IN_SOURCE_PATH}/.gitmodules")
    if(NOT EXISTS "${GITMODULES_FILE}")
        message(FATAL_ERROR "No .gitmodules file found in ${IN_SOURCE_PATH}")
    endif()

    file(READ "${GITMODULES_FILE}" GITMODULES_CONTENTS)

    # Extract list of submodule names
    string(REGEX MATCHALL "\\[submodule \"([^\"]+)\"\\]" SUBMODULE_HEADERS "${GITMODULES_CONTENTS}")
    
    set(SUBMODULE_NAMES   "")
    set(SUBMODULE_PATHS   "")
    set(SUBMODULE_URLS    "")
    set(SUBMODULE_ACTIVES "")

    foreach(HEADER ${SUBMODULE_HEADERS})
    
        # Extract submodule name
        string(REGEX MATCH "\\[submodule \"([^\"]+)\"\\]" _ "${HEADER}")
        set(SUBMODULE_NAME "${CMAKE_MATCH_1}")
        
        message(DEBUG "Processing: ${SUBMODULE_NAME}")
        
        # Get path
        execute_process(COMMAND git config -f "${GITMODULES_FILE}" submodule.${SUBMODULE_NAME}.path
                        OUTPUT_VARIABLE SUB_PATH
                        OUTPUT_STRIP_TRAILING_WHITESPACE
                        ERROR_QUIET)
                        
        message(DEBUG "Path: ${SUB_PATH}")
        
        # Get URL
        execute_process(COMMAND git config -f "${GITMODULES_FILE}" submodule.${SUBMODULE_NAME}.url
                        OUTPUT_VARIABLE SUB_URL
                        OUTPUT_STRIP_TRAILING_WHITESPACE
                        ERROR_QUIET)
        
        message(DEBUG "URL: ${SUB_URL}")
        
        # Get "active" state
        execute_process(COMMAND git config -f "${GITMODULES_FILE}" submodule.${SUBMODULE_NAME}.active
                        OUTPUT_VARIABLE SUB_ACTIVE
                        OUTPUT_STRIP_TRAILING_WHITESPACE
                        ERROR_QUIET)

        if(NOT SUB_ACTIVE STREQUAL "false")
            set(SUB_ACTIVE "true")
        endif()
        
        message(DEBUG "Active state: ${SUB_ACTIVE}")
        
        list(APPEND SUBMODULE_NAMES "${SUBMODULE_NAME}")
        list(APPEND SUBMODULE_PATHS "${SUB_PATH}")
        list(APPEND SUBMODULE_URLS "${SUB_URL}")
        list(APPEND SUBMODULE_ACTIVES "${SUB_ACTIVE}")
        
    endforeach()

    list(LENGTH SUBMODULE_NAMES SUBMODULE_COUNT)
    if(SUBMODULE_COUNT EQUAL 0)
        message(WARNING "No submodules found in .gitmodules")
        set(${OUT_SUBMODULES_COUNT} 0 PARENT_SCOPE)
        return()
    endif()

    message(DEBUG "Submodules count: ${SUBMODULE_COUNT}")
    
    set(${OUT_SUBMODULE_NAME_LIST} ${SUBMODULE_NAMES} PARENT_SCOPE)
    set(${OUT_SUBMODULE_URL_LIST} ${SUBMODULE_URLS} PARENT_SCOPE)
    set(${OUT_SUBMODULE_ACTIVE_LIST} ${SUBMODULE_ACTIVES} PARENT_SCOPE)
    set(${OUT_SUBMODULES_COUNT} ${SUBMODULE_COUNT} PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: GitHandler_GetCommitId
# Description: Returns GIT submodule's commit ID to which is submodules parent 
#              repository pointing.
#
# IN_SOURCE_PATH    [in]: Path to the submodules parent repository.
# IN_BRANCH_NAME    [in]: Branch name of the submodules parent repository.
# IN_SUBMODULE_NAME [in]: Name of GIT submodule.
# OUT_COMMIT_ID    [out]: Commit ID of GIT submodule.
# ------------------------------------------------------------------------------
function(GitHandler_GetCommitId IN_SOURCE_PATH IN_BRANCH_NAME IN_SUBMODULE_NAME OUT_COMMIT_ID)

    execute_process(COMMAND git fetch --depth=0
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET)

    execute_process(COMMAND git -C "${IN_SOURCE_PATH}" ls-tree origin/${IN_BRANCH_NAME} ${IN_SUBMODULE_NAME}
                    OUTPUT_VARIABLE SUBTREE_INFO
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET)
        
    if("${SUBTREE_INFO}" STREQUAL "")
        message(DEBUG "Submodule '${IN_SUBMODULE_NAME}' not found on branch ${IN_BRANCH_NAME}")
        set(${OUT_COMMIT_ID} "" PARENT_SCOPE)
        return()
    endif()
    
    
    string(REPLACE "\r" "" SUBTREE_INFO "${SUBTREE_INFO}")
    
    # Split text to list of tags
    separate_arguments(SUBTREE_TOKENS NATIVE_COMMAND "${SUBTREE_INFO}")
    
    # First tokens: [0]=160000 [1]=commit [2]=hash
    list(LENGTH SUBTREE_TOKENS COUNT)
    if(COUNT GREATER 2)
        list(GET SUBTREE_TOKENS 2 SUB_COMMIT)
    else()
        set(SUB_COMMIT "")
    endif()
    
    if(SUB_COMMIT STREQUAL "")
        message(DEBUG "Failed to parse commit for ${IN_SUBMODULE_NAME}. Raw: '${SUBTREE_INFO}'")
        set(${OUT_COMMIT_ID} "" PARENT_SCOPE)
    else()
        set(${OUT_COMMIT_ID} ${SUB_COMMIT} PARENT_SCOPE)
    endif()
            
endfunction()


# ------------------------------------------------------------------------------
# Function: GitHandler_CloneMin
# Description: Clone required repository without any submodules.
#
# IN_REPO_URL    [in]: Repository URL link
# IN_TARGET_PATH [in]: Destination path for repository clone
# ------------------------------------------------------------------------------
function(GitHandler_CloneMin IN_REPO_URL IN_TARGET_PATH)

    # 1️: Execute initial BSP repository clone without submodules
    execute_process(COMMAND git clone --recurse-submodules=no ${IN_REPO_URL} ${IN_TARGET_PATH}
                    RESULT_VARIABLE GIT_CLONE_RESULT
                    OUTPUT_QUIET
                    ERROR_QUIET)
                 
    if(NOT GIT_CLONE_RESULT EQUAL 0)
        message(FATAL_ERROR "Failed to clone repository: ${IN_REPO_URL} into ${IN_TARGET_PATH}.")
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: GitHandler_SubmoduleInit
# Description: Add new GIT submodule into specified path with specified URL.
#
# IN_REPO_URL     [in]: GIT submodule repository URL path
# IN_TARGET_PATH  [in]: Destination path for GIT submodule
# IN_ACTIVE_STATE [in]: Submodule active state (if the module shall be 
#                      initialized during clone or neither)
# ------------------------------------------------------------------------------
function(GitHandler_SubmoduleInit IN_REPO_URL IN_TARGET_PATH IN_ACTIVE_STATE)

    message(DEBUG "Function 'GitHandler_SubmoduleInit' executed with parameters:")
    message(DEBUG "  IN_REPO_URL:     ${IN_REPO_URL}")
    message(DEBUG "  IN_TARGET_PATH:  ${IN_TARGET_PATH}")
    message(DEBUG "  IN_ACTIVE_STATE: ${IN_ACTIVE_STATE}")
    
    execute_process(COMMAND git submodule add ${IN_REPO_URL} ${IN_TARGET_PATH}
                    WORKING_DIRECTORY "${PROJECT_ROOT_PATH}"
                    RESULT_VARIABLE ADD_RESULT
                    OUTPUT_QUIET
                    ERROR_QUIET
                    )
                    
    if(NOT ADD_RESULT EQUAL 0)
    
        message(WARNING "Failed to add submodule.")
        return()
        
    endif()
                    
    if(${IN_ACTIVE_STATE} STREQUAL "false")
    
        execute_process(COMMAND git config -f .gitmodules submodule.${IN_TARGET_PATH}.active false
                        WORKING_DIRECTORY "${PROJECT_ROOT_PATH}"
                        RESULT_VARIABLE ADD_RESULT
                        OUTPUT_QUIET
                        ERROR_QUIET)
                            
    endif()
    
endfunction()


# ------------------------------------------------------------------------------
# Function: GitHandler_GetRemoteBranchList
# Description: Returns the remote branch list from cloned repository. 
#
# IN_TARGET_PATH   [in]: GIT repository path.
# OUT_BRANCH_LIST [out]: List of remote branches.
# ------------------------------------------------------------------------------
function(GitHandler_GetRemoteBranchList IN_TARGET_PATH OUT_BRANCH_LIST)

    # Fetch only branch list (no data)
    execute_process(COMMAND git ls-remote --heads origin
                    WORKING_DIRECTORY "${IN_TARGET_PATH}"
                    OUTPUT_VARIABLE BRANCH_LIST
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET)
    
    # Filter branch list
    string(REGEX MATCHALL "refs/heads/[^\n\r]+" GIT_HEADS "${BRANCH_LIST}")
    string(REPLACE "refs/heads/" "" BRANCH_LIST "${GIT_HEADS}")
    
    # Format to list
    string(REPLACE "\n" ";" BRANCH_LIST "${BRANCH_LIST}")
    list(REMOVE_DUPLICATES BRANCH_LIST)
    
    set(${OUT_BRANCH_LIST} ${BRANCH_LIST} PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: GitHandler_RemoteBranchExists
# Description: Checks whether a branch exists on a remote repository, without
#              requiring a local clone of that repository.
#
# IN_REPO_URL    [in]: GIT repository URL to query.
# IN_BRANCH_NAME [in]: Branch name to look for.
# OUT_EXISTS    [out]: TRUE if the branch exists on the remote, FALSE otherwise.
# ------------------------------------------------------------------------------
function(GitHandler_RemoteBranchExists IN_REPO_URL IN_BRANCH_NAME OUT_EXISTS)

    execute_process(COMMAND git ls-remote --heads ${IN_REPO_URL} ${IN_BRANCH_NAME}
                    OUTPUT_VARIABLE BRANCH_REF
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET)

    if("${BRANCH_REF}" STREQUAL "")
        message(DEBUG "Branch '${IN_BRANCH_NAME}' not found on remote '${IN_REPO_URL}'")
        set(${OUT_EXISTS} FALSE PARENT_SCOPE)
    else()
        set(${OUT_EXISTS} TRUE PARENT_SCOPE)
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: GitHandler_SwitchBranch
# Description: Switch to required branch and fetch data with only ONE commit.
#
# IN_TARGET_PATH [in]: GIT repository path.
# IN_COMMIT_ID   [in]: Target commit ID to be switched to.
# ------------------------------------------------------------------------------
function(GitHandler_SwitchBranch IN_TARGET_PATH IN_COMMIT_ID)

    message(DEBUG "Function 'GitHandler_SwitchBranch' executed with parameters:")
    message(DEBUG "  IN_TARGET_PATH: ${IN_TARGET_PATH}")
    message(DEBUG "  IN_COMMIT_ID: ${IN_COMMIT_ID}")
    
    # 1. Fetch the commit(only one)
    execute_process(COMMAND git fetch origin ${IN_COMMIT_ID}
                    WORKING_DIRECTORY "${IN_TARGET_PATH}"
                    RESULT_VARIABLE FETCH_RESULT
                    OUTPUT_QUIET
                    ERROR_QUIET)
    
    if(NOT FETCH_RESULT EQUAL 0)
        message(WARNING "Failed to fetch commit ${IN_COMMIT_ID} in '${IN_TARGET_PATH}' ")
        return()
    endif()
    
    # 1. Checkout to commit
    execute_process(COMMAND git checkout ${IN_COMMIT_ID}
                    WORKING_DIRECTORY "${IN_TARGET_PATH}"
                    RESULT_VARIABLE CHK_RESULT
                    OUTPUT_QUIET
                    ERROR_QUIET)
    
    if(NOT CHK_RESULT EQUAL 0)
        message(WARNING "Failed to checkout '${IN_TARGET_PATH}' to commit ${IN_COMMIT_ID}")
        return()
    endif()
    
    # 2. Hard reset (overwrite tracked files)
    execute_process(COMMAND git reset --hard
                    WORKING_DIRECTORY "${IN_TARGET_PATH}"
                    OUTPUT_QUIET 
                    ERROR_QUIET)
    
    # 3. Clean (remove untracked files)
    execute_process(COMMAND git clean -fdx
                    WORKING_DIRECTORY "${IN_TARGET_PATH}"
                    OUTPUT_QUIET 
                    ERROR_QUIET)
    
    # 4. Update internal submodules (if submodule has own submodules)
    if(EXISTS "${IN_TARGET_PATH}/.gitmodules")
        message(DEBUG "Updating nested submodules in ${IN_TARGET_PATH}")
        
        execute_process(COMMAND git submodule update --init --recursive --force
                        WORKING_DIRECTORY "${IN_TARGET_PATH}"
                        RESULT_VARIABLE UPDATE_RESULT
                        OUTPUT_QUIET 
                        ERROR_QUIET)
        
        if(NOT UPDATE_RESULT EQUAL 0)
            message(WARNING "Failed to update nested submodules in ${IN_TARGET_PATH}")
        endif()
    endif()
    
    message(DEBUG "Successfully switched ${IN_TARGET_PATH} to ${IN_COMMIT_ID}")
endfunction()


# ------------------------------------------------------------------------------
# Function: GitHandler_SubmoduleUpdate
# Description: Updates and downloads GIT submodule content.
#
# IN_TARGET_PATH [in]: GIT repository path.
# ------------------------------------------------------------------------------
function(GitHandler_SubmoduleUpdate IN_TARGET_PATH)

    if(NOT EXISTS "${PROJECT_ROOT_PATH}/${IN_TARGET_PATH}/.git")
        message(STATUS "Initializing inactive submodule: ${IN_TARGET_PATH}")
        
        execute_process(COMMAND git submodule update --init --recursive ${IN_TARGET_PATH}
                        WORKING_DIRECTORY "${PROJECT_ROOT_PATH}"
                        RESULT_VARIABLE INIT_RESULT
                        OUTPUT_QUIET)
        
        if(NOT INIT_RESULT EQUAL 0)
            message(FATAL_ERROR "Failed to initialize submodule ${IN_TARGET_PATH}")
        endif()
        
        message(STATUS "Submodule ${IN_TARGET_PATH} initialized")
    else()
        message(STATUS "Submodule ${IN_TARGET_PATH} already initialized")
    endif()
    
endfunction()


# ------------------------------------------------------------------------------ 
# Function: GitHandler_SubmoduleIgnore
# Description: Configures visibility of submodule modifications in parent 
#              repository.
# 
# IN_SUBMODULE_PATH [in]: Path to the submodule
# IN_IGNORE_TYPE    [in]: Type of modification level visibility:
#  --------------------------------------------------------------------
# | Ignore Type    | Modified Files | Untracked Files | Commit Changes |
# |----------------|----------------|-----------------|----------------|
# | none (default) | Shows          | Shows           | Shows          |
# | untracked      | Shows          | Ignore          | Shows          |
# | dirty          | Ignore         | Ignore          | Shows          |
# | all            | Ignore         | Ignore          | Ignore         |
#  --------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
function(GitHandler_SubmoduleIgnore IN_SUBMODULE_PATH IN_IGNORE_TYPE)

    execute_process(COMMAND git config -f .gitmodules submodule.${IN_SUBMODULE_PATH}.ignore ${IN_IGNORE_TYPE}
                    WORKING_DIRECTORY "${PROJECT_ROOT_PATH}"
                    OUTPUT_QUIET
                    ERROR_QUIET)
    
    message(DEBUG "Set ${IN_SUBMODULE_PATH} ignore to ${IN_IGNORE_TYPE}")
    
endfunction()
