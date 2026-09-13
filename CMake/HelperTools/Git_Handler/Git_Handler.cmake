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
# Function: GitHandler_IsGitRepo
# Description: Checks whether a given path is located inside a GIT repository
#              (i.e. `git` commands such as `git submodule add` can be used
#              there). Used to detect the case where the EmBi platform itself
#              was not cloned/initialized as a GIT repository - in that case
#              submodule-based operations are not possible at all.
#
# IN_PATH     [in]: Path to check.
# OUT_IS_REPO [out]: TRUE if IN_PATH is inside a working GIT repository,
#                     FALSE otherwise.
# ------------------------------------------------------------------------------
function(GitHandler_IsGitRepo IN_PATH OUT_IS_REPO)

    execute_process(COMMAND git rev-parse --is-inside-work-tree
                    WORKING_DIRECTORY "${IN_PATH}"
                    RESULT_VARIABLE REV_PARSE_RESULT
                    OUTPUT_QUIET
                    ERROR_QUIET)

    if(REV_PARSE_RESULT EQUAL 0)
        set(${OUT_IS_REPO} TRUE PARENT_SCOPE)
    else()
        set(${OUT_IS_REPO} FALSE PARENT_SCOPE)
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: GitHandler_SubmoduleInit
# Description: Add new GIT submodule into specified path with specified URL.
#              If the EmBi platform itself is NOT located inside a GIT
#              repository, `git submodule add` would fail outright - in that
#              case, this function falls back to just plainly cloning the
#              repository into the target path instead (no submodule entry
#              is created, since none can be).
#
# IN_REPO_URL       [in]: GIT submodule repository URL path
# IN_TARGET_PATH    [in]: Destination path for GIT submodule
# IN_ACTIVE_STATE   [in]: Submodule active state (if the module shall be
#                        initialized during clone or neither)
# OUT_IS_SUBMODULE [out]: TRUE if a real GIT submodule was added, FALSE if a
#                         plain clone fallback was used instead (the parent
#                         project is not itself a GIT repository).
# ------------------------------------------------------------------------------
function(GitHandler_SubmoduleInit IN_REPO_URL IN_TARGET_PATH IN_ACTIVE_STATE OUT_IS_SUBMODULE)

    message(DEBUG "Function 'GitHandler_SubmoduleInit' executed with parameters:")
    message(DEBUG "  IN_REPO_URL:     ${IN_REPO_URL}")
    message(DEBUG "  IN_TARGET_PATH:  ${IN_TARGET_PATH}")
    message(DEBUG "  IN_ACTIVE_STATE: ${IN_ACTIVE_STATE}")

    GitHandler_IsGitRepo("${PROJECT_ROOT_PATH}" PROJECT_IS_GIT_REPO)

    if(NOT PROJECT_IS_GIT_REPO)

        message(STATUS "'${PROJECT_ROOT_PATH}' is not a GIT repository - cloning '${IN_TARGET_PATH}' directly instead of adding it as a submodule.")

        GitHandler_CloneMin(${IN_REPO_URL} "${PROJECT_ROOT_PATH}/${IN_TARGET_PATH}")

        set(${OUT_IS_SUBMODULE} FALSE PARENT_SCOPE)
        return()

    endif()

    execute_process(COMMAND git submodule add ${IN_REPO_URL} ${IN_TARGET_PATH}
                    WORKING_DIRECTORY "${PROJECT_ROOT_PATH}"
                    RESULT_VARIABLE ADD_RESULT
                    OUTPUT_QUIET
                    ERROR_QUIET
                    )

    if(NOT ADD_RESULT EQUAL 0)

        message(WARNING "Failed to add submodule.")
        set(${OUT_IS_SUBMODULE} FALSE PARENT_SCOPE)
        return()

    endif()

    if(${IN_ACTIVE_STATE} STREQUAL "false")

        execute_process(COMMAND git config -f .gitmodules submodule.${IN_TARGET_PATH}.active false
                        WORKING_DIRECTORY "${PROJECT_ROOT_PATH}"
                        RESULT_VARIABLE ADD_RESULT
                        OUTPUT_QUIET
                        ERROR_QUIET)

    endif()

    set(${OUT_IS_SUBMODULE} TRUE PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: GitHandler_SubmoduleRemove
# Description: Cleanly removes a GIT submodule from the parent repository -
#              deinitializes it, removes its .gitmodules/.git entry and
#              working tree, and deletes its internal GIT metadata.
#              If the EmBi platform itself is NOT located inside a GIT
#              repository, the folder was never a real submodule (it was
#              plainly cloned by GitHandler_SubmoduleInit's fallback) - in
#              that case, this function just deletes the folder directly.
#
# IN_SUBMODULE_PATH [in]: Path to the submodule, relative to PROJECT_ROOT_PATH.
# ------------------------------------------------------------------------------
function(GitHandler_SubmoduleRemove IN_SUBMODULE_PATH)

    GitHandler_IsGitRepo("${PROJECT_ROOT_PATH}" PROJECT_IS_GIT_REPO)

    if(NOT PROJECT_IS_GIT_REPO)

        file(REMOVE_RECURSE "${PROJECT_ROOT_PATH}/${IN_SUBMODULE_PATH}")
        message(STATUS "Removed stale directory '${IN_SUBMODULE_PATH}' (plain clone - '${PROJECT_ROOT_PATH}' is not a GIT repository).")
        return()

    endif()

    execute_process(COMMAND git submodule deinit -f -- ${IN_SUBMODULE_PATH}
                    WORKING_DIRECTORY "${PROJECT_ROOT_PATH}"
                    RESULT_VARIABLE DEINIT_RESULT
                    OUTPUT_QUIET
                    ERROR_QUIET)

    if(NOT DEINIT_RESULT EQUAL 0)
        message(WARNING "Failed to deinit submodule '${IN_SUBMODULE_PATH}' - attempting removal anyway.")
    endif()

    execute_process(COMMAND git rm -f -- ${IN_SUBMODULE_PATH}
                    WORKING_DIRECTORY "${PROJECT_ROOT_PATH}"
                    RESULT_VARIABLE RM_RESULT
                    OUTPUT_QUIET
                    ERROR_QUIET)

    if(NOT RM_RESULT EQUAL 0)
        message(WARNING "Failed to 'git rm' submodule '${IN_SUBMODULE_PATH}'.")
    endif()

    file(REMOVE_RECURSE "${PROJECT_ROOT_PATH}/.git/modules/${IN_SUBMODULE_PATH}")

    message(STATUS "Removed stale submodule '${IN_SUBMODULE_PATH}'.")

endfunction()


# ------------------------------------------------------------------------------
# Function: GitHandler_PruneStaleSubmodules
# Description:
#   Removes any GIT submodule checkout found directly under a parent folder
#   that is NOT in the given "keep" list - used after switching BSP family/
#   branch, so a submodule that belonged to the PREVIOUS selection (and is no
#   longer declared for the newly selected one) doesn't linger on disk.
#   Only folders that actually look like a submodule checkout (contain a
#   .git file/dir) are considered - anything else under the parent folder is
#   left untouched.
#
# IN_PARENT_REL_PATH [in]: Parent folder to scan, relative to PROJECT_ROOT_PATH
#                           (e.g. "Bsp" or "Bsp/Mcal").
# IN_KEEP_NAMES       [in]: List of child folder names that must be kept
#                           (the submodules actually valid for the currently
#                           selected branch/family).
# ------------------------------------------------------------------------------
function(GitHandler_PruneStaleSubmodules IN_PARENT_REL_PATH IN_KEEP_NAMES)

    set(PARENT_ABS_PATH "${PROJECT_ROOT_PATH}/${IN_PARENT_REL_PATH}")

    if(NOT EXISTS "${PARENT_ABS_PATH}")
        return()
    endif()

    file(GLOB CHILD_ENTRIES RELATIVE "${PARENT_ABS_PATH}" "${PARENT_ABS_PATH}/*")

    foreach(CHILD_NAME ${CHILD_ENTRIES})

        set(CHILD_PATH "${PARENT_ABS_PATH}/${CHILD_NAME}")

        if(NOT IS_DIRECTORY "${CHILD_PATH}" OR NOT EXISTS "${CHILD_PATH}/.git")
            continue()  # Not a submodule checkout - leave it alone.
        endif()

        list(FIND IN_KEEP_NAMES "${CHILD_NAME}" KEEP_INDEX)

        if(KEEP_INDEX EQUAL -1)
            message(STATUS "Pruning stale submodule '${IN_PARENT_REL_PATH}/${CHILD_NAME}' - not part of the currently selected branch/family.")
            GitHandler_SubmoduleRemove("${IN_PARENT_REL_PATH}/${CHILD_NAME}")
        endif()

    endforeach()

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

# ------------------------------------------------------------------------------
# Function: GitHandler_ListRemoteBranches
# Description: Lists a repository's branches directly from its URL, WITHOUT
#              cloning it - a plain `git ls-remote`, safe to call even for a
#              large repository that should never be fully cloned just to
#              see what branches exist.
#
# IN_REPO_URL     [in]: GIT repository URL to query.
# OUT_BRANCH_LIST [out]: List of remote branch names.
# ------------------------------------------------------------------------------
function(GitHandler_ListRemoteBranches IN_REPO_URL OUT_BRANCH_LIST)

    execute_process(COMMAND git ls-remote --heads ${IN_REPO_URL}
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
# Function: GitHandler_CloneSingleBranch
# Description: Clones a repository with ONLY the requested branch - none of
#              its other branches are downloaded. Use for large repositories
#              where a full multi-branch clone (GitHandler_CloneMin) would be
#              wasteful.
#
# IN_REPO_URL    [in]: Repository URL link.
# IN_BRANCH_NAME [in]: Name of the single branch to clone.
# IN_TARGET_PATH [in]: Destination path for the clone.
# ------------------------------------------------------------------------------
function(GitHandler_CloneSingleBranch IN_REPO_URL IN_BRANCH_NAME IN_TARGET_PATH)

    execute_process(COMMAND git clone --single-branch --branch ${IN_BRANCH_NAME} --recurse-submodules=no ${IN_REPO_URL} ${IN_TARGET_PATH}
                    RESULT_VARIABLE GIT_CLONE_RESULT
                    OUTPUT_QUIET
                    ERROR_QUIET)

    if(NOT GIT_CLONE_RESULT EQUAL 0)
        message(FATAL_ERROR "Failed to clone branch '${IN_BRANCH_NAME}' of repository: ${IN_REPO_URL} into ${IN_TARGET_PATH}.")
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: GitHandler_FetchAndTrackBranch
# Description: Makes an additional branch fetchable/checkout-able on a
#              repository that was cloned with only ONE branch
#              (GitHandler_CloneSingleBranch) - widens the remote's tracked
#              branch list to also include this branch, then fetches just
#              that branch, WITHOUT downloading every other branch.
#
# IN_TARGET_PATH [in]: GIT repository path (an existing clone).
# IN_BRANCH_NAME [in]: Branch to add and fetch.
# ------------------------------------------------------------------------------
function(GitHandler_FetchAndTrackBranch IN_TARGET_PATH IN_BRANCH_NAME)

    execute_process(COMMAND git remote set-branches --add origin ${IN_BRANCH_NAME}
                    WORKING_DIRECTORY "${IN_TARGET_PATH}"
                    OUTPUT_QUIET
                    ERROR_QUIET)

    execute_process(COMMAND git fetch origin ${IN_BRANCH_NAME}
                    WORKING_DIRECTORY "${IN_TARGET_PATH}"
                    RESULT_VARIABLE FETCH_RESULT
                    OUTPUT_QUIET
                    ERROR_QUIET)

    if(NOT FETCH_RESULT EQUAL 0)
        message(WARNING "Failed to fetch branch '${IN_BRANCH_NAME}' in '${IN_TARGET_PATH}'")
    endif()

endfunction()

