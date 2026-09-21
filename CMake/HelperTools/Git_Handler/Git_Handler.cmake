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
#   - Listing a repository's tags, and resolving its default branch, directly
#     from its URL (without requiring a local clone) - used to discover a
#     middleware component's own available versions (see Mw_ModuleHandler.cmake).
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
        # No .gitmodules at all is a valid state (e.g. Mcal declaring zero
        # peripherals for a given family branch) - treat it the same as a
        # .gitmodules file with zero [submodule] entries below, instead of
        # aborting the whole script with a FATAL_ERROR.
        message(WARNING "No .gitmodules file found in ${IN_SOURCE_PATH} - treating as zero submodules.")
        set(${OUT_SUBMODULE_NAME_LIST} "" PARENT_SCOPE)
        set(${OUT_SUBMODULE_URL_LIST} "" PARENT_SCOPE)
        set(${OUT_SUBMODULE_ACTIVE_LIST} "" PARENT_SCOPE)
        set(${OUT_SUBMODULES_COUNT} 0 PARENT_SCOPE)
        return()
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
# Function: GitHandler_GetSubmoduleBranch
# Description:
#   Returns the branch a GIT submodule is declared to track, as recorded by
#   its parent repository's .gitmodules (the standard
#   `submodule.<name>.branch` config field), IF that field is set.
#
#   NOTE: EmBi's BSP repository does not actually use this field on any of
#   its submodules (verified empirically) - GitHandler_ResolveBranchFromCommit
#   is what Bsp_ModuleHandler_Config actually uses instead (derives the
#   branch from the submodule's currently pinned commit). Kept as a general-
#   purpose GIT helper in case some OTHER repository/handler does declare it.
#
# IN_SOURCE_PATH    [in]: Path to the submodule's parent repository (the one
#                          containing the .gitmodules file to read from).
# IN_SUBMODULE_NAME [in]: Name of the GIT submodule (its .gitmodules section).
# OUT_BRANCH       [out]: Declared branch name, or an empty string if the
#                          submodule does not declare one in .gitmodules.
# ------------------------------------------------------------------------------
function(GitHandler_GetSubmoduleBranch IN_SOURCE_PATH IN_SUBMODULE_NAME OUT_BRANCH)

    set(GITMODULES_FILE "${IN_SOURCE_PATH}/.gitmodules")

    execute_process(COMMAND git config -f "${GITMODULES_FILE}" submodule.${IN_SUBMODULE_NAME}.branch
                    OUTPUT_VARIABLE SUB_BRANCH
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET)

    if("${SUB_BRANCH}" STREQUAL "")
        message(DEBUG "Submodule '${IN_SUBMODULE_NAME}' declares no branch in ${GITMODULES_FILE}")
    endif()

    set(${OUT_BRANCH} "${SUB_BRANCH}" PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: GitHandler_GetCommitId
# Description: Returns GIT submodule's PINNED commit ID, i.e. the exact commit
#              the submodule's parent repository records for it on a given
#              branch (via `git ls-tree`).
#
#              Used by Bsp_ModuleHandler_Config purely as a STARTING POINT to
#              discover which of the submodule's OWN branches it belongs to
#              (see GitHandler_ResolveBranchFromCommit) - the submodule is
#              then switched to the LATEST commit of that discovered branch,
#              never left pinned at this exact commit.
#
# IN_SOURCE_PATH    [in]: Path to the submodules parent repository.
# IN_BRANCH_NAME    [in]: Branch name of the submodules parent repository.
# IN_SUBMODULE_NAME [in]: Name of GIT submodule.
# OUT_COMMIT_ID    [out]: Commit ID of GIT submodule.
# ------------------------------------------------------------------------------
function(GitHandler_GetCommitId IN_SOURCE_PATH IN_BRANCH_NAME IN_SUBMODULE_NAME OUT_COMMIT_ID)

    execute_process(COMMAND git fetch --depth=0
                    WORKING_DIRECTORY "${IN_SOURCE_PATH}"
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
# Function: GitHandler_ResolveBranchFromCommit
# Description:
#   Determines which of a (already cloned) repository's OWN remote branches
#   a given commit belongs to (`git branch -r --contains`) - this is how a
#   BSP submodule's tracked branch is discovered when .gitmodules declares
#   no explicit `branch` field for it: BSP only pins the submodule at a
#   specific COMMIT for the selected family (see GitHandler_GetCommitId);
#   that commit's OWN branch is then resolved here, so the submodule can be
#   switched to the LATEST commit of that branch instead of staying pinned.
#
#   If several remote branches contain the commit, the first one reported
#   by `git branch -r --contains` is used (excluding the `origin/HEAD -> ...`
#   alias line, which is not a real branch).
#
# IN_TARGET_PATH [in]: Path to the (already cloned) submodule repository.
# IN_COMMIT_ID   [in]: Commit to resolve the owning branch of.
# OUT_BRANCH    [out]: Resolved branch name (without the "origin/" prefix),
#                       or an empty string if no remote branch contains it.
# ------------------------------------------------------------------------------
function(GitHandler_ResolveBranchFromCommit IN_TARGET_PATH IN_COMMIT_ID OUT_BRANCH)

    # Make sure the commit (and the history of every remote branch) is
    # actually present locally - a fresh/partial clone could otherwise make
    # the --contains lookup below silently find nothing.
    execute_process(COMMAND git fetch origin
                    WORKING_DIRECTORY "${IN_TARGET_PATH}"
                    OUTPUT_QUIET
                    ERROR_QUIET)

    execute_process(COMMAND git branch -r --contains ${IN_COMMIT_ID}
                    WORKING_DIRECTORY "${IN_TARGET_PATH}"
                    OUTPUT_VARIABLE BRANCH_OUTPUT
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET)

    if("${BRANCH_OUTPUT}" STREQUAL "")
        message(DEBUG "No remote branch in '${IN_TARGET_PATH}' contains commit ${IN_COMMIT_ID}")
        set(${OUT_BRANCH} "" PARENT_SCOPE)
        return()
    endif()

    string(REPLACE "\r" "" BRANCH_OUTPUT "${BRANCH_OUTPUT}")
    string(REPLACE "\n" ";" BRANCH_LINES "${BRANCH_OUTPUT}")

    set(RESOLVED_BRANCH "")

    foreach(LINE ${BRANCH_LINES})

        string(STRIP "${LINE}" LINE)

        # Skip the "origin/HEAD -> origin/<default>" alias line - not a
        # real branch.
        if(LINE MATCHES " -> ")
            continue()
        endif()

        if(LINE MATCHES "^origin/(.+)$")
            set(RESOLVED_BRANCH "${CMAKE_MATCH_1}")
            break()
        endif()

    endforeach()

    set(${OUT_BRANCH} "${RESOLVED_BRANCH}" PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: GitHandler_GetHeadCommit
# Description:
#   Returns the commit a submodule/repository is CURRENTLY checked out at
#   (a plain `git rev-parse HEAD`) - used by the lightweight BSP update path
#   (Bsp_ModuleHandler_Update) to discover which branch an already-composed
#   submodule is on (fed into GitHandler_ResolveBranchFromCommit instead of
#   a BSP-pinned commit), without needing BSP's own cache/pinned commit at
#   all.
#
# IN_TARGET_PATH [in]: Path to the (already cloned) repository/submodule.
# OUT_COMMIT_ID [out]: Current HEAD commit hash, or an empty string if it
#                       could not be determined (e.g. not a GIT repository).
# ------------------------------------------------------------------------------
function(GitHandler_GetHeadCommit IN_TARGET_PATH OUT_COMMIT_ID)

    execute_process(COMMAND git rev-parse HEAD
                    WORKING_DIRECTORY "${IN_TARGET_PATH}"
                    OUTPUT_VARIABLE HEAD_COMMIT
                    RESULT_VARIABLE RESULT_CODE
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET)

    if(NOT RESULT_CODE EQUAL 0)
        message(DEBUG "Failed to resolve current HEAD commit in '${IN_TARGET_PATH}'")
        set(${OUT_COMMIT_ID} "" PARENT_SCOPE)
        return()
    endif()

    set(${OUT_COMMIT_ID} "${HEAD_COMMIT}" PARENT_SCOPE)

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
                    ERROR_VARIABLE ADD_ERROR
                    )

    if(NOT ADD_RESULT EQUAL 0)

        # A very common cause here is a LEFTOVER .gitmodules/index entry for
        # this exact path from an earlier, incompletely-removed submodule
        # (see GitHandler_SubmoduleRemove) - git then refuses to add it again
        # even though the working tree folder looks empty/gone. Surfacing
        # git's own message (instead of a generic warning) makes that
        # distinguishable from a real network/URL failure.
        message(WARNING "Failed to add submodule '${IN_TARGET_PATH}'. Git said: ${ADD_ERROR}")
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
                    ERROR_VARIABLE DEINIT_ERROR)

    if(NOT DEINIT_RESULT EQUAL 0)
        message(WARNING "Failed to deinit submodule '${IN_SUBMODULE_PATH}' - attempting removal anyway. Git said: ${DEINIT_ERROR}")
    endif()

    execute_process(COMMAND git rm -f -- ${IN_SUBMODULE_PATH}
                    WORKING_DIRECTORY "${PROJECT_ROOT_PATH}"
                    RESULT_VARIABLE RM_RESULT
                    OUTPUT_QUIET
                    ERROR_VARIABLE RM_ERROR)

    if(NOT RM_RESULT EQUAL 0)

        # A failed 'git rm' here used to be logged and then silently ignored,
        # while the function went on to report success anyway. That left the
        # index entry AND the .gitmodules section for this path in place -
        # which then makes a FUTURE 'git submodule add' for this exact same
        # path fail too (git refuses to add a path/section that already
        # exists), even though the working tree looks empty/gone. Fall back
        # to stripping the index entry and the .gitmodules section by hand so
        # the state doesn't stay stuck for the next run.
        message(WARNING "Failed to 'git rm' submodule '${IN_SUBMODULE_PATH}' - Git said: ${RM_ERROR}. Falling back to a manual index/.gitmodules cleanup.")

        # 'git rm --cached' is itself just as likely to hit the exact same
        # "please stage your changes to .gitmodules" refusal as the plain
        # 'git rm' above did (it also needs to edit .gitmodules as part of
        # removing a submodule) - so it is NOT a safe fallback on its own,
        # and its own failure must not be swallowed silently: a first
        # real-world test of this fallback (2026-09-18) DID hit exactly that,
        # leaving the path stuck in the index for good (a LATER re-add of the
        # same path then failed with "already exists in the index", even
        # though this function had already logged "Removed stale submodule").
        # Stage whatever .gitmodules currently holds FIRST, so the 'git rm
        # --cached' below no longer has anything unstaged to trip over.
        execute_process(COMMAND git add .gitmodules
                        WORKING_DIRECTORY "${PROJECT_ROOT_PATH}"
                        OUTPUT_QUIET
                        ERROR_QUIET)

        execute_process(COMMAND git rm -f --cached -- ${IN_SUBMODULE_PATH}
                        WORKING_DIRECTORY "${PROJECT_ROOT_PATH}"
                        RESULT_VARIABLE CACHED_RM_RESULT
                        OUTPUT_QUIET
                        ERROR_VARIABLE CACHED_RM_ERROR)

        if(NOT CACHED_RM_RESULT EQUAL 0)
            # Last resort: drop the path straight from the index, bypassing
            # git's submodule/.gitmodules bookkeeping entirely - this is the
            # one operation that cannot refuse over a dirty .gitmodules,
            # since it never touches that file.
            message(WARNING "'git rm --cached' also failed for '${IN_SUBMODULE_PATH}' - Git said: ${CACHED_RM_ERROR}. Forcing it out of the index directly.")

            execute_process(COMMAND git update-index --force-remove -- ${IN_SUBMODULE_PATH}
                            WORKING_DIRECTORY "${PROJECT_ROOT_PATH}"
                            OUTPUT_QUIET
                            ERROR_QUIET)
        endif()

        execute_process(COMMAND git config -f .gitmodules --remove-section submodule.${IN_SUBMODULE_PATH}
                        WORKING_DIRECTORY "${PROJECT_ROOT_PATH}"
                        OUTPUT_QUIET
                        ERROR_QUIET)

        execute_process(COMMAND git add .gitmodules
                        WORKING_DIRECTORY "${PROJECT_ROOT_PATH}"
                        OUTPUT_QUIET
                        ERROR_QUIET)

    endif()

    file(REMOVE_RECURSE "${PROJECT_ROOT_PATH}/.git/modules/${IN_SUBMODULE_PATH}")

    # Always make sure the working tree folder itself is actually gone too -
    # 'git rm' normally does this, but the manual fallback above only touches
    # the index/.gitmodules, not the checked-out files.
    file(REMOVE_RECURSE "${PROJECT_ROOT_PATH}/${IN_SUBMODULE_PATH}")

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
#              Always lands on the LATEST commit that was just fetched for
#              IN_COMMIT_ID - it checks out FETCH_HEAD (detached), rather than
#              IN_COMMIT_ID itself. This matters because IN_COMMIT_ID is very
#              often a branch name (e.g. a selected MCU family branch): a
#              plain `git checkout <branch>` re-uses a local branch of that
#              name if one already exists from a PREVIOUS run of this script
#              (its tip does not move on its own just because the remote
#              advanced), silently leaving the checkout on a stale commit even
#              though the fetch above did pull the newest one. Checking out
#              FETCH_HEAD instead guarantees the working tree always matches
#              exactly what was just fetched, whether IN_COMMIT_ID is a branch
#              name or a specific commit hash.
#
# IN_TARGET_PATH [in]: GIT repository path.
# IN_COMMIT_ID   [in]: Target branch name or commit ID to be switched to.
# ------------------------------------------------------------------------------
function(GitHandler_SwitchBranch IN_TARGET_PATH IN_COMMIT_ID)

    message(DEBUG "Function 'GitHandler_SwitchBranch' executed with parameters:")
    message(DEBUG "  IN_TARGET_PATH: ${IN_TARGET_PATH}")
    message(DEBUG "  IN_COMMIT_ID: ${IN_COMMIT_ID}")

    # 1. Fetch the commit (only one)
    execute_process(COMMAND git fetch origin ${IN_COMMIT_ID}
                    WORKING_DIRECTORY "${IN_TARGET_PATH}"
                    RESULT_VARIABLE FETCH_RESULT
                    OUTPUT_QUIET
                    ERROR_VARIABLE FETCH_ERROR)

    if(NOT FETCH_RESULT EQUAL 0)
        # Note: this working directory itself not being a valid GIT checkout
        # (e.g. a preceding 'git submodule add' failed and left an empty/
        # missing folder here) fails at this exact step too, with a generic
        # "not a git repository" from git - not just a real network/branch
        # problem. Check the warning right above this one for that case.
        message(WARNING "Failed to fetch commit ${IN_COMMIT_ID} in '${IN_TARGET_PATH}'. Git said: ${FETCH_ERROR}")
        return()
    endif()

    # 2. Checkout the just-fetched commit directly (detached HEAD), instead
    #    of checking out IN_COMMIT_ID by name - see function description for
    #    why (avoids reusing a stale pre-existing local branch of that name).
    execute_process(COMMAND git checkout --detach FETCH_HEAD
                    WORKING_DIRECTORY "${IN_TARGET_PATH}"
                    RESULT_VARIABLE CHK_RESULT
                    OUTPUT_QUIET
                    ERROR_VARIABLE CHK_ERROR)

    if(NOT CHK_RESULT EQUAL 0)
        message(WARNING "Failed to checkout '${IN_TARGET_PATH}' to fetched ref '${IN_COMMIT_ID}'. Git said: ${CHK_ERROR}")
        return()
    endif()

    # 3. Hard reset (overwrite tracked files)
    execute_process(COMMAND git reset --hard
                    WORKING_DIRECTORY "${IN_TARGET_PATH}"
                    OUTPUT_QUIET 
                    ERROR_QUIET)
    
    # 4. Clean (remove untracked files)
    execute_process(COMMAND git clean -fdx
                    WORKING_DIRECTORY "${IN_TARGET_PATH}"
                    OUTPUT_QUIET
                    ERROR_QUIET)

    # 5. Update internal submodules (if submodule has own submodules)
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

    # `git config -f .gitmodules` above edits .gitmodules directly on disk,
    # OUTSIDE git's staging area - it does not stage that edit the way
    # `git submodule add` stages its own .gitmodules change. Left unstaged,
    # this is exactly what caused a real failure (2026-09-18, confirmed via
    # the ERROR_VARIABLE added to GitHandler_SubmoduleRemove): a LATER
    # `git rm -f` on some other submodule refused with "fatal: please stage
    # your changes to .gitmodules or stash them to proceed", because git
    # itself also needs to edit .gitmodules for that removal and won't do so
    # on top of an already-dirty (unstaged) working tree copy. Staging this
    # edit immediately avoids leaving that trap for whatever git command
    # touches .gitmodules next.
    execute_process(COMMAND git add .gitmodules
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


# ------------------------------------------------------------------------------
# Function: GitHandler_ListRemoteTags
# Description: Lists a repository's tags directly from its URL, WITHOUT
#              cloning it (a plain `git ls-remote --tags --refs`, the same
#              "no clone needed" approach as GitHandler_ListRemoteBranches).
#              `--refs` excludes the dereferenced "^{}" peeled entries an
#              annotated tag would otherwise also produce.
#
#              Used to discover the available VERSIONS of a middleware
#              component (see Mw_ModuleHandler.cmake) - each middleware
#              component versions its own releases via GIT tags on its own
#              repository (the Middlewares catalog repository itself is
#              never version-pinned).
#
# IN_REPO_URL  [in]: GIT repository URL to query.
# OUT_TAG_LIST [out]: List of remote tag names, in whatever order
#                      `git ls-remote` reported them - NOT sorted. Callers
#                      that need them in semantic-version order must sort
#                      the result themselves, e.g.
#                      `list(SORT OUT_TAG_LIST COMPARE NATURAL)`.
# ------------------------------------------------------------------------------
function(GitHandler_ListRemoteTags IN_REPO_URL OUT_TAG_LIST)

    execute_process(COMMAND git ls-remote --tags --refs ${IN_REPO_URL}
                    OUTPUT_VARIABLE TAG_LIST
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET)

    # Filter tag list
    string(REGEX MATCHALL "refs/tags/[^\n\r]+" GIT_TAGS "${TAG_LIST}")
    string(REPLACE "refs/tags/" "" TAG_LIST "${GIT_TAGS}")

    # Format to list
    string(REPLACE "\n" ";" TAG_LIST "${TAG_LIST}")
    list(REMOVE_DUPLICATES TAG_LIST)

    set(${OUT_TAG_LIST} ${TAG_LIST} PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: GitHandler_GetDefaultBranch
# Description: Resolves a repository's default branch (the one its remote
#              HEAD points at, e.g. "main"/"master") directly from its URL,
#              WITHOUT cloning it (`git ls-remote --symref <url> HEAD`).
#
#              Used as a fallback "latest version" for a middleware
#              component that does not (yet) have any GIT tags - see
#              Mw_ModuleHandler.cmake.
#
# IN_REPO_URL [in]: GIT repository URL to query.
# OUT_BRANCH [out]: Default branch name, or an empty string if it could not
#                    be resolved.
# ------------------------------------------------------------------------------
function(GitHandler_GetDefaultBranch IN_REPO_URL OUT_BRANCH)

    execute_process(COMMAND git ls-remote --symref ${IN_REPO_URL} HEAD
                    OUTPUT_VARIABLE SYMREF_OUTPUT
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET)

    string(REGEX MATCH "ref:[ \t]*refs/heads/([^ \t\r\n]+)" _ "${SYMREF_OUTPUT}")

    if(NOT CMAKE_MATCH_1)
        message(DEBUG "Could not resolve default branch for '${IN_REPO_URL}'")
        set(${OUT_BRANCH} "" PARENT_SCOPE)
        return()
    endif()

    set(${OUT_BRANCH} "${CMAKE_MATCH_1}" PARENT_SCOPE)

endfunction()

