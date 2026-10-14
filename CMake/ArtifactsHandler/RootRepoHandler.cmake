###############################################################################
# Artifacts Root Repository temporary folder handler functionality
###############################################################################

# List of supported remote repository providers.
set(ROOT_REPO_HANDLER_PROVIDER_GITHUB "GITHUB")
set(ROOT_REPO_HANDLER_PROVIDER_AZURE  "AZURE")
set(ROOT_REPO_HANDLER_PROVIDER_OTHER  "OTHER")

# Global property used to keep GitHub API access state during one run.
set(ROOT_REPO_HANDLER_API_STATE_PROPERTY "ROOT_REPO_HANDLER_API_STATE")


#------------------------------------------------------------------------------#
# Function used to initialize git submodules in artifacts root repository.
#
# ROOT_REPO_PATH_ARG [in]: Path to the artifacts root repository directory
#------------------------------------------------------------------------------#
function(RootRepoHandler_UpdateSubmodules ROOT_REPO_PATH_ARG)

    message(STATUS "Updating artifacts submodules")

    # Get list of all items in folder (artifacts)
    file(GLOB GIT_ROOT_REPO_ITEMS "${ROOT_REPO_PATH_ARG}/*")
    
    set(FAILED_ARTIFACTS "")
    set(FIRST_UPDATE_ERROR "")

    # Initialize all git submodules
    foreach(SUBMODULE_DIR IN LISTS GIT_ROOT_REPO_ITEMS)

        get_filename_component(DIR_NAME "${SUBMODULE_DIR}" NAME)

        if(IS_DIRECTORY "${SUBMODULE_DIR}" AND NOT DIR_NAME STREQUAL ".git")

            if(NOT DIR_NAME MATCHES "^\\.")

                message(DEBUG "Artifact ${DIR_NAME} will be updated.")

                execute_process(COMMAND git submodule update --init --depth=1 --checkout --remote ${DIR_NAME}
                                WORKING_DIRECTORY "${ROOT_REPO_PATH_ARG}"
                                RESULT_VARIABLE UPDATE_RESULT
                                OUTPUT_QUIET
                                ERROR_VARIABLE UPDATE_ERROR)

                if(NOT UPDATE_RESULT EQUAL 0)

                    message(DEBUG "Update of artifact ${DIR_NAME} failed (${UPDATE_RESULT}): ${UPDATE_ERROR}")

                    list(APPEND FAILED_ARTIFACTS "${DIR_NAME}")

                    if("${FIRST_UPDATE_ERROR}" STREQUAL "")
                        set(FIRST_UPDATE_ERROR "${UPDATE_ERROR}")
                    endif()

                endif()

            endif()
        endif()
    endforeach()

    # The failure is not fatal here - the artifacts which are not needed (or
    # which are already available locally) can still be used. The artifact which
    # is needed and not usable is reported when it is accessed.
    if(FAILED_ARTIFACTS)
        string(REPLACE ";" ", " FAILED_ARTIFACTS_TEXT "${FAILED_ARTIFACTS}")
        message(WARNING "Update of the artifact repositories failed: ${FAILED_ARTIFACTS_TEXT}. The local state of the repositories is used.\nFirst git error:\n${FIRST_UPDATE_ERROR}")
    endif()

endfunction(RootRepoHandler_UpdateSubmodules)


#------------------------------------------------------------------------------#
# Function used to check, if the repo was checked today.
#
# REPO_PATH_ARG    [in]: Path to the repository to check fetch date
# FETCH_STATE_ARG [out]: State of fetch. If repo was already fetched within 
#                    timeframe, returns TRUE. Othervise returns FALSE.
#------------------------------------------------------------------------------#
function(RootRepoHandler_CheckLastUpdate REPO_PATH_ARG FETCH_STATE_ARG)

    # Get date of last FETCH_HEAD modification in format YYYY-MM-DD
    set(FETCH_HEAD_FILE "${REPO_PATH_ARG}/.git/FETCH_HEAD")
    set(HEAD_FILE "${REPO_PATH_ARG}/.git/HEAD")
    
    if(EXISTS "${FETCH_HEAD_FILE}")
        file(TIMESTAMP "${FETCH_HEAD_FILE}" LAST_UPDATE_DATE "%Y-%m-%d")
    elseif(EXISTS "${HEAD_FILE}")
        file(TIMESTAMP "${HEAD_FILE}" LAST_UPDATE_DATE "%Y-%m-%d")
    else()
        set(LAST_UPDATE_DATE "")
    endif()
    
    # Get actual date in format YYYY-MM-DD
    string(TIMESTAMP TODAY "%Y-%m-%d")
    
    # Compare dates
    if(NOT LAST_UPDATE_DATE STREQUAL TODAY)    
        set(${FETCH_STATE_ARG} "FALSE" PARENT_SCOPE)
    else()
        set(${FETCH_STATE_ARG} "TRUE" PARENT_SCOPE)
    endif()

endfunction(RootRepoHandler_CheckLastUpdate)


#------------------------------------------------------------------------------#
# Prepare local version of Artifactory Root Repository
#
# OFFLINE_MODE_STATE_ARG [in]: Offline mode (true/false)
# ROOT_REPO_URL_ARG      [in]: Artifacts root repository URL
# ROOT_REPO_PATH_ARG     [in]: Path to the Root repository temp location
#------------------------------------------------------------------------------#
function(RootRepoHandler_Prepare OFFLINE_MODE_STATE_ARG
                                 ROOT_REPO_URL_ARG
                                 ROOT_REPO_PATH_ARG)

    if(NOT EXISTS "${ROOT_REPO_PATH_ARG}/.git")
    
        # Artifacts root repository is not cloned. Clone repo (without submodules)
        message(STATUS "Cloning root repository (without submodules)...")
        execute_process(COMMAND git clone --depth=1 --recurse-submodules=no ${ROOT_REPO_URL_ARG} ${ROOT_REPO_PATH_ARG}
                        RESULT_VARIABLE CLONE_RES
                        OUTPUT_VARIABLE CLONE_OUT
                        ERROR_VARIABLE CLONE_ERR)

        if(NOT CLONE_RES EQUAL 0)
            message(WARNING "Git clone failed:\n${CLONE_OUT}\n${CLONE_ERR}")
        endif()
                        
        if(NOT CLONE_RES EQUAL 0)
            message(FATAL_ERROR "Failed to clone root repository.")
        else()
            RootRepoHandler_UpdateSubmodules(${ROOT_REPO_PATH_ARG})
        endif()
        
    else()
    
        # Chek, if artifact root repository was already updated today
        RootRepoHandler_CheckLastUpdate(${ROOT_REPO_PATH_ARG} UPDATE_STATUS)
        
        if(NOT UPDATE_STATUS)
        
            message(STATUS "Updating artifacts root repository.")
            
            execute_process(COMMAND git fetch --no-recurse-submodules --depth=1 origin
                            WORKING_DIRECTORY "${ROOT_REPO_PATH_ARG}"
                            RESULT_VARIABLE FETCH_RES
                            OUTPUT_VARIABLE FETCH_OUT
                            ERROR_VARIABLE FETCH_ERR)
                            
            if(NOT FETCH_RES EQUAL 0)
                message(WARNING "Git fetch failed:\n${FETCH_OUT}\n${FETCH_ERR}")
            endif()
                            
            execute_process(COMMAND git pull --no-recurse-submodules origin
                            WORKING_DIRECTORY "${ROOT_REPO_PATH_ARG}"
                            RESULT_VARIABLE PULL_RES
                            OUTPUT_VARIABLE PULL_OUT
                            ERROR_VARIABLE PULL_ERR)

            if(NOT PULL_RES EQUAL 0)
                message(WARNING "Git pull failed:\n${PULL_OUT}\n${PULL_ERR}")
            endif()
                            
            RootRepoHandler_UpdateSubmodules(${ROOT_REPO_PATH_ARG})
        
        else()
            message(DEBUG "Artifacts Source Root repository will not be updated.")
        endif() 
        
    endif()

endfunction(RootRepoHandler_Prepare)


#------------------------------------------------------------------------------#
# Checks, if the Bin branch already directly contains the required zip
# archive at the currently checked-out commit (i.e. the archive is committed
# in the repository itself, not only published as a GitHub release asset).
#
# If found, the archive is copied to the Bin temp folder under the same path
# a downloaded release asset would use, so the rest of the flow (Install_Bin)
# does not need to know where the file came from.
#
# SUBMODULE_DIR_ARG    [in]: Path to the checked-out artifact submodule
# ARTIFACT_NAME_ARG    [in]: Name of the artifact being processed
# TEMP_FOLDER_PATH_ARG [in]: Path to the Bin temp folder
# ARTIFACT_OS_ARG      [in]: Required OS type of the artifact binary (used to
#                            select archive if more archives are committed)
# FOUND_LOCAL_ZIP_ARG [out]: TRUE if a local zip archive was found (and
#                            copied), otherwise FALSE
#------------------------------------------------------------------------------#
function(RootRepoHandler_Get_LocalBinZip SUBMODULE_DIR_ARG
                                         ARTIFACT_NAME_ARG
                                         TEMP_FOLDER_PATH_ARG
                                         ARTIFACT_OS_ARG
                                         FOUND_LOCAL_ZIP_ARG)

    set(${FOUND_LOCAL_ZIP_ARG} "FALSE" PARENT_SCOPE)

    # Get list of all archives directly in the checked-out submodule folder
    file(GLOB LOCAL_ZIP_FILES "${SUBMODULE_DIR_ARG}/*.zip")

    if(NOT LOCAL_ZIP_FILES)
        message(DEBUG "Bin branch does not directly contain a zip archive, release asset will be used.")
        return()
    endif()

    list(GET LOCAL_ZIP_FILES 0 LOCAL_ZIP_FILE)

    # More archives committed - prefer the one matching required OS
    list(LENGTH LOCAL_ZIP_FILES LOCAL_ZIP_COUNT)
    if(LOCAL_ZIP_COUNT GREATER 1)
        foreach(ZIP_FILE IN LISTS LOCAL_ZIP_FILES)
            get_filename_component(ZIP_NAME "${ZIP_FILE}" NAME)
            if(ZIP_NAME MATCHES "${ARTIFACT_OS_ARG}")
                set(LOCAL_ZIP_FILE "${ZIP_FILE}")
                break()
            endif()
        endforeach()
    endif()

    get_filename_component(LOCAL_ZIP_NAME "${LOCAL_ZIP_FILE}" NAME)

    set(ARTIFACT_DOWNLOAD_PATH "${TEMP_FOLDER_PATH_ARG}/${ARTIFACT_NAME_ARG}")
    file(MAKE_DIRECTORY "${ARTIFACT_DOWNLOAD_PATH}")

    if(NOT EXISTS "${ARTIFACT_DOWNLOAD_PATH}/${LOCAL_ZIP_NAME}")
        file(COPY "${LOCAL_ZIP_FILE}" DESTINATION "${ARTIFACT_DOWNLOAD_PATH}")
    endif()

    message(STATUS "Zip archive '${LOCAL_ZIP_NAME}' found directly in Bin branch, release asset download skipped.")

    set(${FOUND_LOCAL_ZIP_ARG} "TRUE" PARENT_SCOPE)

endfunction(RootRepoHandler_Get_LocalBinZip)


#------------------------------------------------------------------------------#
# Fetches the branch of the artifact repository with its complete history.
#
# The artifact repositories are initialized and updated with --depth=1 (see
# RootRepoHandler_UpdateSubmodules), so they are shallow. The shallow boundary
# cuts the history of the fetched branch - the versions below the boundary
# (e.g. the Win commit below the Unix / DarwinARM tip of the Bin branch) are
# not visible and the required version would not be found. The history is
# therefore completed with --unshallow. Only commits and trees are transferred
# (--filter=blob:none).
#
# SUBMODULE_DIR_ARG [in]: Path to the artifact repository
# BRANCH_NAME_ARG   [in]: Name of the branch to be fetched (Core or Bin)
# RESULT_ARG       [out]: Result of git fetch (0 if succeeded)
#------------------------------------------------------------------------------#
function(RootRepoHandler_Fetch_Branch SUBMODULE_DIR_ARG
                                      BRANCH_NAME_ARG
                                      RESULT_ARG)

    execute_process(COMMAND git rev-parse --is-shallow-repository
                    WORKING_DIRECTORY "${SUBMODULE_DIR_ARG}"
                    OUTPUT_VARIABLE IS_SHALLOW_REPO
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET)

    set(FETCH_OPTIONS --filter=blob:none)

    if("${IS_SHALLOW_REPO}" STREQUAL "true")
        list(APPEND FETCH_OPTIONS --unshallow)
        message(DEBUG "Artifact repository ${SUBMODULE_DIR_ARG} is shallow, the history of branch ${BRANCH_NAME_ARG} will be completed.")
    endif()

    execute_process(COMMAND git fetch ${FETCH_OPTIONS} origin ${BRANCH_NAME_ARG}
                    WORKING_DIRECTORY "${SUBMODULE_DIR_ARG}"
                    RESULT_VARIABLE GIT_FETCH_RESULT
                    OUTPUT_QUIET
                    ERROR_QUIET)

    set(${RESULT_ARG} "${GIT_FETCH_RESULT}" PARENT_SCOPE)

endfunction(RootRepoHandler_Fetch_Branch)


#------------------------------------------------------------------------------#
# The binary part of the artifact shall be downloaded to the temporary location.
#
# ROOT_REPO_PATH_ARG                [in]: Path to the Root repository temp location
# ARTIFACT_NAME_ARG                 [in]: Name of the artifact to be processed
# ARTIFACT_BIN_VERSION_ARG          [in]: Required version of artifact binary
# ARTIFACT_OS_ARG                   [in]: Required OS type of the artifact binary
# TEMP_FOLDER_PATH_ARG              [in]: Path to the temporary folder
# ARTIFACT_CORE_VERSION_ACTIVE_ARG [out]: Found the artifact core version
#------------------------------------------------------------------------------#
function(RootRepoHandler_DownloadArtifact_Bin ROOT_REPO_PATH_ARG
                                              ARTIFACT_NAME_ARG
                                              ARTIFACT_BIN_VERSION_ARG
                                              ARTIFACT_OS_ARG
                                              TEMP_FOLDER_PATH_ARG
                                              ARTIFACT_BIN_VERSION_ACTIVE_ARG)

    set(BRANCH_NAME "Bin")
    
    RootRepoHandler_Get_ArtifactDir(${ROOT_REPO_PATH_ARG}
                                    ${ARTIFACT_NAME_ARG}
                                    SUBMODULE_DIR)

    set(REQUIRED_VERSION "${ARTIFACT_BIN_VERSION_ARG}")

    RootRepoHandler_Fetch_Branch("${SUBMODULE_DIR}"
                                 ${BRANCH_NAME}
                                 GIT_FETCH_RESULT)

    if(NOT GIT_FETCH_RESULT EQUAL 0)
        message(FATAL_ERROR "Git fetch failed on branch ${BRANCH_NAME}")
    endif()
                    
    execute_process(COMMAND git log FETCH_HEAD --pretty=format:%H||%s
                    OUTPUT_VARIABLE GIT_LOG_OUTPUT
                    RESULT_VARIABLE GIT_LOG_RESULT
                    WORKING_DIRECTORY "${SUBMODULE_DIR}"
                    ERROR_QUIET)
                    
    if(NOT GIT_LOG_RESULT EQUAL 0)
        message(FATAL_ERROR "Command Git log failed.")
    endif()
    
    # Separate list to rows
    string(REPLACE "\n" ";" COMMIT_LINES "${GIT_LOG_OUTPUT}")

    # Prvy prechod: zisti, ci nejaky commit na tomto branchi vobec spomina OS.
    # Ak ano, artefakt je OS-dependent a OS filter sa vynuti. Ak nie, artefakt
    # je OS-independent a filter sa preskoci uplne.
    set(BIN_IS_OS_DEPENDENT FALSE)
    foreach(LINE ${COMMIT_LINES})
        string(REPLACE "||" ";" LINE_PARTS "${LINE}")
        list(GET LINE_PARTS 1 COMMIT_MESSAGE)
        if(COMMIT_MESSAGE MATCHES "(${ARTIFACTS_HANDLER_OS_WIN}|${ARTIFACTS_HANDLER_OS_UNIX}|${ARTIFACTS_HANDLER_OS_MAC})")
            set(BIN_IS_OS_DEPENDENT TRUE)
            break()
        endif()
    endforeach()

    set(MATCHING_COMMITS "")
    
    foreach(LINE ${COMMIT_LINES})
        # Separate hash and commit message by "||"
        string(REPLACE "||" ";" LINE_PARTS "${LINE}")
        list(GET LINE_PARTS 0 COMMIT_HASH)
        list(GET LINE_PARTS 1 COMMIT_MESSAGE)
    
        # OS filter - vynuti sa len pre artefakty, ktore OS naozaj rozlisuju
        if(BIN_IS_OS_DEPENDENT AND NOT COMMIT_MESSAGE MATCHES "${ARTIFACT_OS_ARG}")
            continue()
        endif()
    
        if(NOT COMMIT_MESSAGE MATCHES "([0-9]+\\.[0-9]+\\.[0-9]+)")
            continue()
        endif()
        set(COMMIT_VERSION "${CMAKE_MATCH_1}")
        
        message(DEBUG "Adding version ${COMMIT_VERSION} to the available list.")
    
        list(APPEND MATCHING_COMMITS "${COMMIT_HASH}|${COMMIT_VERSION}")
    endforeach()
    
    # The list is checked as a value - an undefined list in unquoted if()
    # would be compared as a text and the check would never be true.
    if("${MATCHING_COMMITS}" STREQUAL "")

        if(BIN_IS_OS_DEPENDENT)

            # Report the OS which is really required and the OS versions which
            # are published, so the missing one is clear (e.g. Unix is missing
            # on Windows only artifact).
            set(AVAILABLE_OS_LIST "")

            foreach(OS_NAME ${ARTIFACTS_HANDLER_OS_WIN} ${ARTIFACTS_HANDLER_OS_UNIX} ${ARTIFACTS_HANDLER_OS_MAC})
                foreach(LINE ${COMMIT_LINES})
                    if(LINE MATCHES "${OS_NAME}")
                        list(APPEND AVAILABLE_OS_LIST "${OS_NAME}")
                        break()
                    endif()
                endforeach()
            endforeach()

            string(REPLACE ";" ", " AVAILABLE_OS_TEXT "${AVAILABLE_OS_LIST}")

            message(FATAL_ERROR "No Bin version of artifact '${ARTIFACT_NAME_ARG}' found for OS '${ARTIFACT_OS_ARG}' in branch ${BRANCH_NAME} (published OS: ${AVAILABLE_OS_TEXT}).")

        else()

            message(FATAL_ERROR "No Bin version of artifact '${ARTIFACT_NAME_ARG}' found in branch ${BRANCH_NAME}.")

        endif()

    endif()


    set(TARGET_HASH "")
    set(TARGET_VERSION "")

    # Process releases to find latest version
    if("${ARTIFACT_BIN_VERSION_ARG}" STREQUAL "latest")

        set(BEST_HASH "")
        set(BEST_VERSION "")
        
        foreach(ENTRY ${MATCHING_COMMITS})
            string(REPLACE "|" ";" ENTRY_PARTS "${ENTRY}")
            list(GET ENTRY_PARTS 0 ENTRY_HASH)
            list(GET ENTRY_PARTS 1 ENTRY_VERSION)
        
            if(BEST_VERSION STREQUAL "" OR ENTRY_VERSION VERSION_GREATER BEST_VERSION)
                set(BEST_VERSION "${ENTRY_VERSION}")
                set(BEST_HASH "${ENTRY_HASH}")
            endif()
        endforeach()
        
        set(TARGET_HASH ${BEST_HASH})
        set(TARGET_VERSION ${BEST_VERSION})
        
    else()
        # User selected exact version
        foreach(ENTRY ${MATCHING_COMMITS})
            string(REPLACE "|" ";" ENTRY_PARTS "${ENTRY}")
            list(GET ENTRY_PARTS 0 ENTRY_HASH)
            list(GET ENTRY_PARTS 1 ENTRY_VERSION)
        
            if(ENTRY_VERSION VERSION_EQUAL ARTIFACT_BIN_VERSION_ARG)
                set(TARGET_HASH "${ENTRY_HASH}")
                set(TARGET_VERSION "${ENTRY_VERSION}")
                break()
            endif()
        endforeach()

        if(TARGET_HASH STREQUAL "")

            set(AVAILABLE_VERSIONS "")

            foreach(ENTRY ${MATCHING_COMMITS})
                string(REPLACE "|" ";" ENTRY_PARTS "${ENTRY}")
                list(GET ENTRY_PARTS 1 ENTRY_VERSION)
                list(APPEND AVAILABLE_VERSIONS "${ENTRY_VERSION}")
            endforeach()

            string(REPLACE ";" ", " AVAILABLE_VERSIONS_TEXT "${AVAILABLE_VERSIONS}")

            if(BIN_IS_OS_DEPENDENT)
                message(FATAL_ERROR "Bin version ${ARTIFACT_BIN_VERSION_ARG} of artifact '${ARTIFACT_NAME_ARG}' not found for OS '${ARTIFACT_OS_ARG}' in branch ${BRANCH_NAME} (available: ${AVAILABLE_VERSIONS_TEXT}).")
            else()
                message(FATAL_ERROR "Bin version ${ARTIFACT_BIN_VERSION_ARG} of artifact '${ARTIFACT_NAME_ARG}' not found in branch ${BRANCH_NAME} (available: ${AVAILABLE_VERSIONS_TEXT}).")
            endif()

        endif()
    endif()
    
    message(STATUS "The version ${TARGET_VERSION} of artifacts Bin part will be used.")

    # Checkout na nájdený commit
    execute_process(COMMAND git checkout ${TARGET_HASH}
                    WORKING_DIRECTORY "${SUBMODULE_DIR}"
                    RESULT_VARIABLE GIT_CHECKOUT_RESULT
                    OUTPUT_QUIET
                    ERROR_QUIET)
                    
    if(NOT GIT_CHECKOUT_RESULT EQUAL 0)
        message(FATAL_ERROR "Checkout to commit ${TARGET_HASH} (version ${TARGET_VERSION}) of artifact '${ARTIFACT_NAME_ARG}' failed.")
    else()
        set(${ARTIFACT_BIN_VERSION_ACTIVE_ARG} ${TARGET_VERSION} PARENT_SCOPE)
        message(DEBUG "Switched to artifact Bin version ${TARGET_VERSION}")
    endif()

    # Remove archives of previously processed versions, so only the required
    # archive is available for installation.
    file(GLOB OLD_ZIP_FILES "${TEMP_FOLDER_PATH_ARG}/${ARTIFACT_NAME_ARG}/*.zip")
    if(OLD_ZIP_FILES)
        file(REMOVE ${OLD_ZIP_FILES})
    endif()

    # Archive committed directly in Bin branch - no remote API is needed
    RootRepoHandler_Get_LocalBinZip("${SUBMODULE_DIR}"
                                    ${ARTIFACT_NAME_ARG}
                                    ${TEMP_FOLDER_PATH_ARG}
                                    ${ARTIFACT_OS_ARG}
                                    FOUND_LOCAL_ZIP)

    if(FOUND_LOCAL_ZIP)
        return()
    endif()

    # Archive is available only as release asset - depends on remote provider
    RootRepoHandler_Get_RemoteProvider("${SUBMODULE_DIR}" REMOTE_PROVIDER)

    if(REMOTE_PROVIDER STREQUAL "${ROOT_REPO_HANDLER_PROVIDER_GITHUB}")

        # The availability of the GitHub API is checked only when a list of
        # releases / tags has to be downloaded (RootRepoHandler_Get_PaginatedGithubList),
        # valid cached lists are used without the API.
        RootRepoHandler_DownloadBin(${ROOT_REPO_PATH_ARG}
                                    ${ARTIFACT_NAME_ARG}
                                    ${TARGET_HASH}
                                    ${TEMP_FOLDER_PATH_ARG}
                                    ${ARTIFACT_OS_ARG}
                                    ${TARGET_VERSION})
    else()
        message(FATAL_ERROR "Bin part of ${ARTIFACT_NAME_ARG} version ${TARGET_VERSION} is not committed in ${BRANCH_NAME} branch "
                            "and release download is not supported for provider ${REMOTE_PROVIDER}.")
    endif()

endfunction(RootRepoHandler_DownloadArtifact_Bin)


#------------------------------------------------------------------------------#
# The binary part of the artifact shall be downloaded to the temporary location.
#
# ROOT_REPO_PATH_ARG                [in]: Path to the Root repository temp location
# ARTIFACT_NAME_ARG                 [in]: Name of the artifact to be processed
# ARTIFACT_CORE_VERSION_ARG         [in]: Required version of artifact core
# ARTIFACT_CORE_VERSION_ACTIVE_ARG [out]: Found the artifact core version
#------------------------------------------------------------------------------#
function(RootRepoHandler_DownloadArtifact_Core ROOT_REPO_PATH_ARG 
                                               ARTIFACT_NAME_ARG
                                               ARTIFACT_CORE_VERSION_ARG
                                               ARTIFACT_CORE_VERSION_ACTIVE_ARG)

    set(BRANCH_NAME "Core")
    
    RootRepoHandler_Get_ArtifactDir(${ROOT_REPO_PATH_ARG}
                                    ${ARTIFACT_NAME_ARG}
                                    SUBMODULE_DIR)

    set(REQUIRED_VERSION "${ARTIFACT_CORE_VERSION_ARG}")

    RootRepoHandler_Fetch_Branch("${SUBMODULE_DIR}"
                                 ${BRANCH_NAME}
                                 GIT_FETCH_RESULT)

    if(NOT GIT_FETCH_RESULT EQUAL 0)
        message(FATAL_ERROR "Git fetch failed on branch ${BRANCH_NAME} in ${SUBMODULE_DIR}.")
    endif()
                    
    execute_process(COMMAND git log FETCH_HEAD --pretty=format:%H||%s
                    OUTPUT_VARIABLE GIT_LOG_OUTPUT
                    RESULT_VARIABLE GIT_LOG_RESULT
                    WORKING_DIRECTORY "${SUBMODULE_DIR}"
                    ERROR_QUIET)
                    
    if(NOT GIT_LOG_RESULT EQUAL 0)
        message(FATAL_ERROR "Command Git log failed.")
    endif()
    
    # Separate list to rows
    string(REPLACE "\n" ";" COMMIT_LINES "${GIT_LOG_OUTPUT}")
    
    set(MATCHING_COMMITS "")
    
    foreach(LINE ${COMMIT_LINES})
        # Separate hash and commit message by "||"
        string(REPLACE "||" ";" LINE_PARTS "${LINE}")
        list(GET LINE_PARTS 0 COMMIT_HASH)
        list(GET LINE_PARTS 1 COMMIT_MESSAGE)
    
        if(NOT COMMIT_MESSAGE MATCHES "([0-9]+\\.[0-9]+\\.[0-9]+)")
            continue()
        endif()
        set(COMMIT_VERSION "${CMAKE_MATCH_1}")
        
        message(DEBUG "Adding version ${COMMIT_VERSION} to the available list.")
    
        list(APPEND MATCHING_COMMITS "${COMMIT_HASH}|${COMMIT_VERSION}")
    endforeach()
    
    # The list is checked as a value - an undefined list in unquoted if()
    # would be compared as a text and the check would never be true.
    if("${MATCHING_COMMITS}" STREQUAL "")
        message(FATAL_ERROR "No Core version of artifact '${ARTIFACT_NAME_ARG}' found in branch ${BRANCH_NAME}.")
    endif()


    set(TARGET_HASH "")
    set(TARGET_VERSION "")

    # Process releases to find latest version
    if("${ARTIFACT_CORE_VERSION_ARG}" STREQUAL "latest")

        set(BEST_HASH "")
        set(BEST_VERSION "")
        
        foreach(ENTRY ${MATCHING_COMMITS})
            string(REPLACE "|" ";" ENTRY_PARTS "${ENTRY}")
            list(GET ENTRY_PARTS 0 ENTRY_HASH)
            list(GET ENTRY_PARTS 1 ENTRY_VERSION)
        
            if(BEST_VERSION STREQUAL "" OR ENTRY_VERSION VERSION_GREATER BEST_VERSION)
                set(BEST_VERSION "${ENTRY_VERSION}")
                set(BEST_HASH "${ENTRY_HASH}")
            endif()
        endforeach()
        
        set(TARGET_HASH ${BEST_HASH})
        set(TARGET_VERSION ${BEST_VERSION})
        
    else()
        # User selected exact version
        foreach(ENTRY ${MATCHING_COMMITS})
            string(REPLACE "|" ";" ENTRY_PARTS "${ENTRY}")
            list(GET ENTRY_PARTS 0 ENTRY_HASH)
            list(GET ENTRY_PARTS 1 ENTRY_VERSION)
        
            if(ENTRY_VERSION VERSION_EQUAL ARTIFACT_CORE_VERSION_ARG)
                set(TARGET_HASH "${ENTRY_HASH}")
                set(TARGET_VERSION ${ENTRY_VERSION})
                break()
            endif()
        endforeach()

        if(TARGET_HASH STREQUAL "")

            set(AVAILABLE_VERSIONS "")

            foreach(ENTRY ${MATCHING_COMMITS})
                string(REPLACE "|" ";" ENTRY_PARTS "${ENTRY}")
                list(GET ENTRY_PARTS 1 ENTRY_VERSION)
                list(APPEND AVAILABLE_VERSIONS "${ENTRY_VERSION}")
            endforeach()

            string(REPLACE ";" ", " AVAILABLE_VERSIONS_TEXT "${AVAILABLE_VERSIONS}")

            message(FATAL_ERROR "Core version ${ARTIFACT_CORE_VERSION_ARG} of artifact '${ARTIFACT_NAME_ARG}' not found in branch ${BRANCH_NAME} (available: ${AVAILABLE_VERSIONS_TEXT}).")

        endif()
    endif()
    
    message(STATUS "The version ${TARGET_VERSION} of artifacts Core part will be used.")

    # Checkout to found commit
    execute_process(COMMAND git checkout ${TARGET_HASH}
                    WORKING_DIRECTORY "${SUBMODULE_DIR}"
                    RESULT_VARIABLE GIT_CHECKOUT_RESULT
                    OUTPUT_QUIET
                    ERROR_QUIET)
                    
    if(NOT GIT_CHECKOUT_RESULT EQUAL 0)
        message(FATAL_ERROR "Checkout to commit ${TARGET_HASH} (version ${TARGET_VERSION}) of artifact '${ARTIFACT_NAME_ARG}' failed.")
    else()
        set(${ARTIFACT_CORE_VERSION_ACTIVE_ARG} ${TARGET_VERSION} PARENT_SCOPE)
        message(DEBUG "Switched to artifact Core version: ${TARGET_VERSION}")
    endif()

endfunction(RootRepoHandler_DownloadArtifact_Core)


#------------------------------------------------------------------------------#
# Returns the latest version of artifact part available on remote.
#
# The artifact branch is fetched and the highest version found in commit
# messages is returned. Nothing is checked out or downloaded. In case of any
# failure (e.g. remote is not reachable) empty version is returned, so the
# caller can continue with the cached version.
#
# ROOT_REPO_PATH_ARG    [in]: Path to the Root repository temp location
# ARTIFACT_NAME_ARG     [in]: Name of the artifact to be processed
# BRANCH_NAME_ARG       [in]: Artifact branch (Core or Bin)
# ARTIFACT_OS_ARG       [in]: Required OS type of the artifact binary (used for
#                             Bin branch of OS dependent artifacts only)
# LATEST_VERSION_ARG   [out]: Latest version in format X.Y.Z or empty string
#------------------------------------------------------------------------------#
function(RootRepoHandler_Get_LatestVersion ROOT_REPO_PATH_ARG
                                           ARTIFACT_NAME_ARG
                                           BRANCH_NAME_ARG
                                           ARTIFACT_OS_ARG
                                           LATEST_VERSION_ARG)

    set(${LATEST_VERSION_ARG} "" PARENT_SCOPE)

    set(ARTIFACT_FOUND_NAME "")

    RootRepoHandler_Get_ArtifactFolderName(${ROOT_REPO_PATH_ARG}
                                           ${ARTIFACT_NAME_ARG}
                                           ARTIFACT_FOUND_NAME)

    if("${ARTIFACT_FOUND_NAME}" STREQUAL "")
        return()
    endif()

    set(SUBMODULE_DIR "${ROOT_REPO_PATH_ARG}/${ARTIFACT_FOUND_NAME}")

    RootRepoHandler_Fetch_Branch("${SUBMODULE_DIR}"
                                 ${BRANCH_NAME_ARG}
                                 GIT_FETCH_RESULT)

    if(NOT GIT_FETCH_RESULT EQUAL 0)
        message(WARNING "Git fetch failed on branch ${BRANCH_NAME_ARG} in ${SUBMODULE_DIR}, latest version cannot be checked.")
        return()
    endif()

    execute_process(COMMAND git log FETCH_HEAD --pretty=format:%s
                    OUTPUT_VARIABLE GIT_LOG_OUTPUT
                    RESULT_VARIABLE GIT_LOG_RESULT
                    WORKING_DIRECTORY "${SUBMODULE_DIR}"
                    ERROR_QUIET)

    if(NOT GIT_LOG_RESULT EQUAL 0)
        message(WARNING "Command Git log failed in ${SUBMODULE_DIR}, latest version cannot be checked.")
        return()
    endif()

    # Separate list to rows
    string(REPLACE "\n" ";" COMMIT_MESSAGES "${GIT_LOG_OUTPUT}")

    # OS filter is used only for Bin branch of artifacts which distinguish OS
    # (same rule as in RootRepoHandler_DownloadArtifact_Bin)
    set(IS_OS_DEPENDENT FALSE)

    if("${BRANCH_NAME_ARG}" STREQUAL "Bin")
        foreach(COMMIT_MESSAGE ${COMMIT_MESSAGES})
            if(COMMIT_MESSAGE MATCHES "(${ARTIFACTS_HANDLER_OS_WIN}|${ARTIFACTS_HANDLER_OS_UNIX}|${ARTIFACTS_HANDLER_OS_MAC})")
                set(IS_OS_DEPENDENT TRUE)
                break()
            endif()
        endforeach()
    endif()

    set(BEST_VERSION "")

    foreach(COMMIT_MESSAGE ${COMMIT_MESSAGES})

        if(IS_OS_DEPENDENT AND NOT COMMIT_MESSAGE MATCHES "${ARTIFACT_OS_ARG}")
            continue()
        endif()

        if(NOT COMMIT_MESSAGE MATCHES "([0-9]+\\.[0-9]+\\.[0-9]+)")
            continue()
        endif()

        if(BEST_VERSION STREQUAL "" OR CMAKE_MATCH_1 VERSION_GREATER BEST_VERSION)
            set(BEST_VERSION "${CMAKE_MATCH_1}")
        endif()
    endforeach()

    message(DEBUG "Latest remote version of ${ARTIFACT_NAME_ARG} ${BRANCH_NAME_ARG} part: ${BEST_VERSION}")

    set(${LATEST_VERSION_ARG} "${BEST_VERSION}" PARENT_SCOPE)

endfunction(RootRepoHandler_Get_LatestVersion)


#------------------------------------------------------------------------------#
# Returns provider of the remote repository based on submodule remote URL.
#
# SUBMODULE_DIR_ARG [in]: Path to the git submodule
# OUT_PROVIDER_ARG [out]: One of ROOT_REPO_HANDLER_PROVIDER_* values
#------------------------------------------------------------------------------#
function(RootRepoHandler_Get_RemoteProvider SUBMODULE_DIR_ARG
                                            OUT_PROVIDER_ARG)

    execute_process(COMMAND git config --get remote.origin.url
                    WORKING_DIRECTORY "${SUBMODULE_DIR_ARG}"
                    OUTPUT_VARIABLE REMOTE_URL
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    RESULT_VARIABLE GIT_RESULT)

    if(NOT GIT_RESULT EQUAL 0)
        message(FATAL_ERROR "The URL in ${SUBMODULE_DIR_ARG} submodule not found.")
    endif()

    if(REMOTE_URL MATCHES "github\\.com[:/]")
        set(PROVIDER "${ROOT_REPO_HANDLER_PROVIDER_GITHUB}")
    elseif(REMOTE_URL MATCHES "(dev\\.azure\\.com|visualstudio\\.com)")
        set(PROVIDER "${ROOT_REPO_HANDLER_PROVIDER_AZURE}")
    else()
        set(PROVIDER "${ROOT_REPO_HANDLER_PROVIDER_OTHER}")
    endif()

    message(DEBUG "Remote ${REMOTE_URL} detected as provider ${PROVIDER}.")

    set(${OUT_PROVIDER_ARG} "${PROVIDER}" PARENT_SCOPE)

endfunction(RootRepoHandler_Get_RemoteProvider)


#------------------------------------------------------------------------------#
# Check, if the Github API is available or neither.
#
# The check is executed only once per run, the result is kept in global
# property and reused for next artifacts.
#
# TEMP_FOLDER_PATH_ARG [in]: Path to the temporary folder
# OUT_ACCESSIBLE_ARG  [out]: FALSE if the API is not accessible, otherwise TRUE
#------------------------------------------------------------------------------#
function(RootRepoHandler_Get_ApiAccess TEMP_FOLDER_PATH_ARG
                                       OUT_ACCESSIBLE_ARG)

    get_property(API_STATE_CACHED GLOBAL PROPERTY ${ROOT_REPO_HANDLER_API_STATE_PROPERTY})

    if(NOT "${API_STATE_CACHED}" STREQUAL "")
        set(${OUT_ACCESSIBLE_ARG} "${API_STATE_CACHED}" PARENT_SCOPE)
        return()
    endif()

    RootRepoHandler_Check_ApiAccess(${TEMP_FOLDER_PATH_ARG} API_STATE)

    set_property(GLOBAL PROPERTY ${ROOT_REPO_HANDLER_API_STATE_PROPERTY} "${API_STATE}")
    set(${OUT_ACCESSIBLE_ARG} "${API_STATE}" PARENT_SCOPE)

endfunction(RootRepoHandler_Get_ApiAccess)


#------------------------------------------------------------------------------#
# Request actual Github API rate limit state.
#
# TEMP_FOLDER_PATH_ARG [in]: Path to the temporary folder
# OUT_ACCESSIBLE_ARG  [out]: FALSE if the API is not accessible, otherwise TRUE
#------------------------------------------------------------------------------#
function(RootRepoHandler_Check_ApiAccess TEMP_FOLDER_PATH_ARG
                                         OUT_ACCESSIBLE_ARG)

    set(RATE_LIMIT_FILE "${TEMP_FOLDER_PATH_ARG}/rate_limit.json")

    file(DOWNLOAD "https://api.github.com/rate_limit" "${RATE_LIMIT_FILE}"
        HTTPHEADER "Accept: application/vnd.github+json"
        STATUS DOWNLOAD_STATUS)
        
    list(GET DOWNLOAD_STATUS 0 STATUS_CODE)
    
    if(NOT STATUS_CODE EQUAL 0)
        list(GET DOWNLOAD_STATUS 1 STATUS_MESSAGE)
        message(WARNING "Failed to check GitHub API rate limit: ${STATUS_MESSAGE}")
        set(${OUT_ACCESSIBLE_ARG} "FALSE" PARENT_SCOPE)
        return()
    endif()

    file(READ "${RATE_LIMIT_FILE}" RATE_LIMIT_JSON)
    string(JSON REMAINING GET "${RATE_LIMIT_JSON}" "resources" "core" "remaining")
    string(JSON RESET_EPOCH GET "${RATE_LIMIT_JSON}" "resources" "core" "reset")

    if(REMAINING GREATER 0)
        message(DEBUG "GitHub API is available, there is ${REMAINING} remaining requests")
        set(${OUT_ACCESSIBLE_ARG} "TRUE" PARENT_SCOPE)
        return()
    endif()

    # There is no free limit - calculate timestamp to real time format
    string(TIMESTAMP CURRENT_EPOCH "%s" UTC)
    math(EXPR SECONDS_REMAINING "${RESET_EPOCH} - ${CURRENT_EPOCH}")
    math(EXPR MINUTES_REMAINING "${SECONDS_REMAINING} / 60")

    
    message(WARNING "GitHub API rate limit is done. It will be reset in ${MINUTES_REMAINING} min")

    set(${OUT_ACCESSIBLE_ARG} "FALSE" PARENT_SCOPE)

endfunction(RootRepoHandler_Check_ApiAccess)


#------------------------------------------------------------------------------#
# The binary part of the artifact shall be downloaded to the temporary location.
#
# ROOT_REPO_PATH_ARG   [in]: Path to the Root repository temp location
# ARTIFACT_NAME_ARG    [in]: Name of the artifact to be processed
# COMMIT_HASH_ARG      [in]: Hash of commit connected to the release
# TEMP_FOLDER_PATH_ARG [in]: Path to the temporary folder
# ARTIFACT_OS_ARG      [in]: Required OS type of the artifact binary
# REQUIRED_VERSION_ARG [in]: Resolved artifact Bin version (X.Y.Z)
#------------------------------------------------------------------------------#
function(RootRepoHandler_DownloadBin ROOT_REPO_PATH_ARG
                                     ARTIFACT_NAME_ARG
                                     COMMIT_HASH_ARG
                                     TEMP_FOLDER_PATH_ARG
                                     ARTIFACT_OS_ARG
                                     REQUIRED_VERSION_ARG)
                                     
    set(ARTIFACT_DOWNLOAD_PATH "${TEMP_FOLDER_PATH_ARG}/${ARTIFACT_NAME_ARG}")
    
    set(ASSET_PATTERN ".zip")
                                     
    RootRepoHandler_Get_ArtifactFolderName(${ROOT_REPO_PATH_ARG}
                                           ${ARTIFACT_NAME_ARG}
                                           ARTIFACT_FOUND_NAME)
    
    # Get Github repository and owner
    RootRepoHandler_Get_GithubOwnerRepo("${ROOT_REPO_PATH_ARG}/${ARTIFACT_FOUND_NAME}" 
                                        GITHUB_OWNER
                                        GITHUB_REPO)
                                        
    message(DEBUG "Owner: ${GITHUB_OWNER}, Repo: ${GITHUB_REPO}")
    
    set(RELEASES_CACHE_FILE_PATH "${TEMP_FOLDER_PATH_ARG}/${ARTIFACT_NAME_ARG}/releases.json")
    set(TAGS_CACHE_FILE_PATH "${TEMP_FOLDER_PATH_ARG}/${ARTIFACT_NAME_ARG}/tags.json")
    
    # The lists of releases and tags are kept in the cache for one hour (rate
    # limit of the GitHub API). A version published after the lists were
    # downloaded is not in them, so when the required tag or its release is not
    # found, the lists are refreshed once and the lookup is repeated.
    set(FORCE_REFRESH FALSE)

    foreach(LOOKUP_ATTEMPT RANGE 1 2)

        RootRepoHandler_Get_PaginatedGithubList("${GITHUB_OWNER}"
                                                "${GITHUB_REPO}"
                                                "releases"
                                                "${TEMP_FOLDER_PATH_ARG}"
                                                "${RELEASES_CACHE_FILE_PATH}"
                                                ${FORCE_REFRESH}
                                                RELEASES_FROM_CACHE)

        RootRepoHandler_Get_PaginatedGithubList("${GITHUB_OWNER}"
                                                "${GITHUB_REPO}"
                                                "tags"
                                                "${TEMP_FOLDER_PATH_ARG}"
                                                "${TAGS_CACHE_FILE_PATH}"
                                                ${FORCE_REFRESH}
                                                TAGS_FROM_CACHE)

        RootRepoHandler_Get_VersionTag("${TAGS_CACHE_FILE_PATH}"
                                       "${REQUIRED_VERSION_ARG}"
                                       "${ARTIFACT_OS_ARG}"
                                       FOUND_TAG_NAME
                                       FOUND_TAG_NAME_SHA)

        set(RELEASE_INDEX -1)
        set(FOUND_ASSET_NAME "")

        if(NOT "${FOUND_TAG_NAME}" STREQUAL "")
            RootRepoHandler_Get_ReleaseIndexTag("${RELEASES_CACHE_FILE_PATH}"
                                                "${FOUND_TAG_NAME}"
                                                "${ASSET_PATTERN}"
                                                RELEASE_INDEX
                                                FOUND_ASSET_NAME)
        endif()

        # The tag and its release were found
        if(NOT RELEASE_INDEX EQUAL -1)
            break()
        endif()

        # The lists were downloaded just now - refresh would not bring anything new
        if(NOT RELEASES_FROM_CACHE)
            if(NOT TAGS_FROM_CACHE)
                break()
            endif()
        endif()

        message(STATUS "Tag or release of Bin version ${REQUIRED_VERSION_ARG} of artifact '${ARTIFACT_NAME_ARG}' not found in the cached lists, the lists are refreshed from GitHub.")

        set(FORCE_REFRESH TRUE)

    endforeach()

    if(FOUND_TAG_NAME STREQUAL "")
        message(FATAL_ERROR "No tag found for Bin version ${REQUIRED_VERSION_ARG} of artifact '${ARTIFACT_NAME_ARG}' (required OS: ${ARTIFACT_OS_ARG}) in ${GITHUB_OWNER}/${GITHUB_REPO}.")
    else()
        message(DEBUG "Tag found: ${FOUND_TAG_NAME}")
    endif()
    
    
    if(RELEASE_INDEX EQUAL -1)
        message(FATAL_ERROR "No release found for tag ${FOUND_TAG_NAME}")
    endif()
    
    message(DEBUG "Release found on index: ${RELEASE_INDEX}")

    # Release without the archive (e.g. failed upload of the asset) - the empty
    # name would make the path of the download folder itself, which exists, and
    # the archive would be taken as already downloaded.
    if("${FOUND_ASSET_NAME}" STREQUAL "")
        message(FATAL_ERROR "Release ${FOUND_TAG_NAME} of artifact '${ARTIFACT_NAME_ARG}' has no archive (asset matching '${ASSET_PATTERN}') to download.")
    endif()

    set(ASSET_PATH "${ARTIFACT_DOWNLOAD_PATH}/${FOUND_ASSET_NAME}")
    
    if(NOT EXISTS "${ASSET_PATH}")
    
        RootRepoHandler_Download_ReleaseAsset("${RELEASES_CACHE_FILE_PATH}" 
                                              "${RELEASE_INDEX}"
                                              "${ASSET_PATTERN}" 
                                              "${ARTIFACT_DOWNLOAD_PATH}/" 
                                              DOWNLOADED_ASSET_PATH)
    
        message(DEBUG "File downloaded to: ${DOWNLOADED_ASSET_PATH}")
        
    else()
        message(DEBUG "File ${FOUND_ASSET_NAME} already downloaded.")
    endif()
    
endfunction()


# ==============================================================================
# Returns github owner and repository from submodule remote URL 
#
# SUBMODULE_DIR_ARG [in]: Path to the git submodule
# OUT_OWNER_ARG    [out]: Owner name
# OUT_REPO_ARG     [out]: Repository name
# ==============================================================================
function(RootRepoHandler_Get_GithubOwnerRepo SUBMODULE_DIR_ARG 
                                             OUT_OWNER_ARG
                                             OUT_REPO_ARG)
                                             
    execute_process(COMMAND git config --get remote.origin.url
                    WORKING_DIRECTORY "${SUBMODULE_DIR_ARG}"
                    OUTPUT_VARIABLE REMOTE_URL
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    RESULT_VARIABLE GIT_RESULT)
                    
    if(NOT GIT_RESULT EQUAL 0)
        message(FATAL_ERROR "The URL in ${SUBMODULE_DIR_ARG} submodule not found.")
    endif()

    if(REMOTE_URL MATCHES "github\\.com[:/]([^/]+)/([^/.]+)(\\.git)?$")
        set(${OUT_OWNER_ARG} "${CMAKE_MATCH_1}" PARENT_SCOPE)
        set(${OUT_REPO_ARG} "${CMAKE_MATCH_2}" PARENT_SCOPE)
    else()
        message(FATAL_ERROR "Parsing owner/repo from URL: ${REMOTE_URL} failed")
    endif()
endfunction()


# ==============================================================================
# Download paging list from GitHub API to single file
#
# The downloaded file is used as a cache for one hour (rate limit of the
# GitHub API), unless the refresh is forced.
#
# REPO_OWNER_ARG    [in]: Owner of the GitHub repository
# REPO_NAME_ARG     [in]: Name of the GitHub repository
# API_PATH          [in]: Listed API path (releases or tags)
# BIN_TEMP_PATH_ARG [in]: Path to the temporary folder
# OUTPUT_FILE_ARG   [in]: File with the list (cache file)
# FORCE_REFRESH_ARG [in]: TRUE if the list shall be downloaded even if the cache
#                         file is not older than one hour
# FROM_CACHE_ARG   [out]: TRUE if the list was taken from the cache file, FALSE
#                         if it was downloaded
# ==============================================================================
function(RootRepoHandler_Get_PaginatedGithubList REPO_OWNER_ARG
                                                 REPO_NAME_ARG
                                                 API_PATH
                                                 BIN_TEMP_PATH_ARG
                                                 OUTPUT_FILE_ARG
                                                 FORCE_REFRESH_ARG
                                                 FROM_CACHE_ARG)

    set(${FROM_CACHE_ARG} "FALSE" PARENT_SCOPE)

    file(MAKE_DIRECTORY "${BIN_TEMP_PATH_ARG}")

    if(EXISTS "${OUTPUT_FILE_ARG}")
        file(TIMESTAMP "${OUTPUT_FILE_ARG}" FILE_MODIFIED_EPOCH "%s")
        string(TIMESTAMP CURRENT_EPOCH "%s" UTC)

        math(EXPR FILE_AGE_SECONDS "${CURRENT_EPOCH} - ${FILE_MODIFIED_EPOCH}")
        set(CACHE_MAX_AGE_SECONDS 3600)

        if(FORCE_REFRESH_ARG)
            message(STATUS "Cache file is refreshed (${FILE_AGE_SECONDS}s old): ${OUTPUT_FILE_ARG}")
        elseif(FILE_AGE_SECONDS LESS CACHE_MAX_AGE_SECONDS)
            message(STATUS "Cache file already exist, no new download will be executed: ${OUTPUT_FILE_ARG}")
            set(${FROM_CACHE_ARG} "TRUE" PARENT_SCOPE)
            return()
        else()
            message(STATUS "Cache file is older than 1 hour (${FILE_AGE_SECONDS}s), refreshing: ${OUTPUT_FILE_ARG}")
        endif()
    endif()

    # The list has to be downloaded - the GitHub API is needed (rate limit). The
    # outdated cache file stays untouched until the new list is downloaded (it is
    # overwritten at the end).
    RootRepoHandler_Get_ApiAccess("${BIN_TEMP_PATH_ARG}" API_STATE)

    if(NOT API_STATE STREQUAL "TRUE")
        message(FATAL_ERROR "GitHub API is not available, the list of ${API_PATH} of ${REPO_OWNER_ARG}/${REPO_NAME_ARG} cannot be downloaded (no valid cached list with the required version is available).")
    endif()

    set(COMBINED_JSON "[]")
    set(COMBINED_LENGTH 0)
    set(PAGE 1)

    while(TRUE)
        set(PAGE_FILE "${BIN_TEMP_PATH_ARG}/page_${PAGE}.json")

        file(DOWNLOAD "https://api.github.com/repos/${REPO_OWNER_ARG}/${REPO_NAME_ARG}/${API_PATH}?per_page=10000&page=${PAGE}" "${PAGE_FILE}"
             HTTPHEADER "Accept: application/vnd.github+json"
             STATUS DOWNLOAD_STATUS)

        list(GET DOWNLOAD_STATUS 0 STATUS_CODE)

        if(NOT STATUS_CODE EQUAL 0)
            list(GET DOWNLOAD_STATUS 1 STATUS_MESSAGE)
            message(FATAL_ERROR "Downloading ${API_PATH} (page ${PAGE}) failed: ${STATUS_MESSAGE}")
        endif()

        file(READ "${PAGE_FILE}" PAGE_JSON)

        string(JSON PAGE_COUNT LENGTH "${PAGE_JSON}")

        file(REMOVE "${PAGE_FILE}")

        if(PAGE_COUNT EQUAL 0)
            break()
        endif()

        math(EXPR PAGE_LAST_INDEX "${PAGE_COUNT} - 1")
        foreach(I RANGE ${PAGE_LAST_INDEX})
            string(JSON ITEM GET "${PAGE_JSON}" ${I})
            string(JSON COMBINED_JSON SET "${COMBINED_JSON}" ${COMBINED_LENGTH} "${ITEM}")
            math(EXPR COMBINED_LENGTH "${COMBINED_LENGTH} + 1")
        endforeach()

        if(PAGE_COUNT LESS 100)
            break()
        endif()
        math(EXPR PAGE "${PAGE} + 1")
    endwhile()

    file(WRITE "${OUTPUT_FILE_ARG}" "${COMBINED_JSON}")
    message(DEBUG "Stored: ${OUTPUT_FILE_ARG} (${COMBINED_LENGTH} records)")

endfunction()


# ==============================================================================
# 4. Nájdenie tagu, ktorý ukazuje na daný commit (z lokálneho tags cache súboru)
# ==============================================================================
function(RootRepoHandler_Get_TagForCommit TAGS_FILE 
                                          COMMIT_HASH 
                                          OUT_TAG)
                                          
    file(READ "${TAGS_FILE}" TAGS_JSON)
    string(JSON TAG_COUNT LENGTH "${TAGS_JSON}")

    set(${OUT_TAG} "" PARENT_SCOPE)
    if(TAG_COUNT EQUAL 0)
        return()
    endif()

    math(EXPR LAST_INDEX "${TAG_COUNT} - 1")
    foreach(I RANGE ${LAST_INDEX})
        string(JSON TAG_SHA GET "${TAGS_JSON}" ${I} "commit" "sha")
        if(TAG_SHA STREQUAL COMMIT_HASH)
            string(JSON TAG_NAME GET "${TAGS_JSON}" ${I} "name")
            set(${OUT_TAG} "${TAG_NAME}" PARENT_SCOPE)
            return()
        endif()
    endforeach()
endfunction()


#------------------------------------------------------------------------------#
# Finds Release index for given tag, and locates a matching asset within it.
#
# RELEASES_FILE_PATH      [in]: Path to cached releases.json.
# TAG_NAME_ARG            [in]: Tag name to search for.
# ASSET_NAME_PATTERN_ARG  [in]: Regex pattern to match against asset names.
# OUT_RELEASE_INDEX_ARG  [out]: Index of the found release (-1 if not found).
# OUT_ASSET_NAME_ARG     [out]: Name of the matching asset file (empty if not found).
#------------------------------------------------------------------------------#
function(RootRepoHandler_Get_ReleaseIndexTag RELEASES_FILE_PATH
                                             TAG_NAME_ARG
                                             ASSET_NAME_PATTERN_ARG
                                             OUT_RELEASE_INDEX_ARG
                                             OUT_ASSET_NAME_ARG)

    file(READ "${RELEASES_FILE_PATH}" RELEASES_JSON)
    string(JSON RELEASE_COUNT LENGTH "${RELEASES_JSON}")

    set(${OUT_RELEASE_INDEX_ARG} -1 PARENT_SCOPE)
    set(${OUT_ASSET_NAME_ARG} "" PARENT_SCOPE)

    if(RELEASE_COUNT EQUAL 0)
        return()
    endif()

    math(EXPR LAST_INDEX "${RELEASE_COUNT} - 1")
    foreach(I RANGE ${LAST_INDEX})
        string(JSON RELEASE_TAG GET "${RELEASES_JSON}" ${I} "tag_name")
        if(RELEASE_TAG STREQUAL TAG_NAME_ARG)
            set(${OUT_RELEASE_INDEX_ARG} ${I} PARENT_SCOPE)

            # Prehľadaj assets tohto release-u a nájdi ten, ktorý zodpovedá vzoru
            string(JSON ASSET_COUNT LENGTH "${RELEASES_JSON}" ${I} "assets")
            if(ASSET_COUNT GREATER 0)
                math(EXPR ASSET_LAST_INDEX "${ASSET_COUNT} - 1")
                foreach(J RANGE ${ASSET_LAST_INDEX})
                    string(JSON ASSET_NAME GET "${RELEASES_JSON}" ${I} "assets" ${J} "name")
                    if(ASSET_NAME MATCHES "${ASSET_NAME_PATTERN_ARG}")
                        set(${OUT_ASSET_NAME_ARG} "${ASSET_NAME}" PARENT_SCOPE)
                        return()
                    endif()
                endforeach()
            endif()

            return()
        endif()
    endforeach()

endfunction()


#------------------------------------------------------------------------------#
# Finds Git Tag for required version and OS
#
# TAGS_FILE_PATH_ARG        [in]: Path to the JSON file with tag list
# REQUIRED_VERSION_ARG      [in]: Required artifact version ("latest" or exact version)
# ARTIFACT_OS_ARG           [in]: OS/platform suffix to filter tags by (e.g. Unix, Win, DarwinARM)
# OUT_TAG_NAME_ARG         [out]: Name of the found tag
# OUT_TAG_SHA_ARG          [out]: Commit SHA of the found tag
#------------------------------------------------------------------------------#
function(RootRepoHandler_Get_VersionTag TAGS_FILE_PATH_ARG
                                         REQUIRED_VERSION_ARG
                                         ARTIFACT_OS_ARG
                                         OUT_TAG_NAME_ARG
                                         OUT_TAG_SHA_ARG)

    file(READ "${TAGS_FILE_PATH_ARG}" TAGS_JSON)
    string(JSON TAG_COUNT LENGTH "${TAGS_JSON}")

    set(${OUT_TAG_NAME_ARG} "" PARENT_SCOPE)
    set(${OUT_TAG_SHA_ARG} "" PARENT_SCOPE)

    if(TAG_COUNT EQUAL 0)
        message(DEBUG "No tags found in ${TAGS_FILE_PATH_ARG}")
        return()
    endif()

    math(EXPR LAST_INDEX "${TAG_COUNT} - 1")

    # Zisti, ci je artefakt OS-dependent vobec - ak ma HOCIJEDEN tag OS suffix,
    # berieme cely artefakt ako OS-dependent a vyzadujeme presnu zhodu OS.
    # Len ak ZIADEN tag OS suffix nema, akceptujeme "holé" X.Y.Z tagy.
    set(ARTIFACT_IS_OS_DEPENDENT FALSE)
    foreach(I RANGE ${LAST_INDEX})
        string(JSON T_NAME GET "${TAGS_JSON}" ${I} "name")
        if(T_NAME MATCHES "[0-9]+\\.[0-9]+\\.[0-9]+-(${ARTIFACTS_HANDLER_OS_WIN}|${ARTIFACTS_HANDLER_OS_UNIX}|${ARTIFACTS_HANDLER_OS_MAC})$")
            set(ARTIFACT_IS_OS_DEPENDENT TRUE)
            break()
        endif()
    endforeach()

    if(ARTIFACT_IS_OS_DEPENDENT)
        set(VERSION_PATTERN "([0-9]+\\.[0-9]+\\.[0-9]+)-${ARTIFACT_OS_ARG}$")
    else()
        set(VERSION_PATTERN "([0-9]+\\.[0-9]+\\.[0-9]+)$")
    endif()

    if(REQUIRED_VERSION_ARG STREQUAL "latest")
        set(BEST_VERSION "")
        set(BEST_NAME "")
        set(BEST_SHA "")

        foreach(I RANGE ${LAST_INDEX})
            string(JSON T_NAME GET "${TAGS_JSON}" ${I} "name")

            if(T_NAME MATCHES "${VERSION_PATTERN}")
                set(T_VERSION "${CMAKE_MATCH_1}")

                if(BEST_VERSION STREQUAL "" OR T_VERSION VERSION_GREATER BEST_VERSION)
                    set(BEST_VERSION "${T_VERSION}")
                    set(BEST_NAME "${T_NAME}")
                    string(JSON BEST_SHA GET "${TAGS_JSON}" ${I} "commit" "sha")
                endif()
            endif()
        endforeach()

        if(NOT BEST_NAME STREQUAL "")
            set(${OUT_TAG_NAME_ARG} "${BEST_NAME}" PARENT_SCOPE)
            set(${OUT_TAG_SHA_ARG} "${BEST_SHA}" PARENT_SCOPE)
        endif()
        return()
    endif()

    foreach(I RANGE ${LAST_INDEX})
        string(JSON T_NAME GET "${TAGS_JSON}" ${I} "name")

        if(T_NAME MATCHES "${VERSION_PATTERN}")
            set(T_VERSION "${CMAKE_MATCH_1}")
            if(T_VERSION VERSION_EQUAL REQUIRED_VERSION_ARG)
                string(JSON T_SHA GET "${TAGS_JSON}" ${I} "commit" "sha")
                set(${OUT_TAG_NAME_ARG} "${T_NAME}" PARENT_SCOPE)
                set(${OUT_TAG_SHA_ARG} "${T_SHA}" PARENT_SCOPE)
                return()
            endif()
        endif()
    endforeach()

endfunction()


# ==============================================================================
# 6. Stiahnutie jedného assetu (podľa regex vzoru) z release-u na danom indexe
# ==============================================================================
function(RootRepoHandler_Download_ReleaseAsset RELEASES_FILE_ARG 
                                               RELEASE_INDEX_ARG 
                                               ASSET_NAME_PATTERN_ARG 
                                               OUTPUT_DIR_ARG 
                                               OUT_DOWNLOADED_PATH_ARG)
                                               
    file(READ "${RELEASES_FILE_ARG}" RELEASES_JSON)
    
    string(JSON ASSET_COUNT LENGTH "${RELEASES_JSON}" ${RELEASE_INDEX_ARG} "assets")

    set(${OUT_DOWNLOADED_PATH_ARG} "" PARENT_SCOPE)
    
    if(ASSET_COUNT EQUAL 0)
        message(FATAL_ERROR "No assets found for release with index ${RELEASE_INDEX_ARG}")
    endif()

    file(MAKE_DIRECTORY "${OUTPUT_DIR_ARG}")

    math(EXPR LAST_INDEX "${ASSET_COUNT} - 1")
    
    foreach(I RANGE ${LAST_INDEX})
        string(JSON ASSET_NAME GET "${RELEASES_JSON}" ${RELEASE_INDEX_ARG} "assets" ${I} "name")

        if(ASSET_NAME MATCHES "${ASSET_NAME_PATTERN_ARG}")
        
            string(JSON ASSET_URL GET "${RELEASES_JSON}" ${RELEASE_INDEX_ARG} "assets" ${I} "browser_download_url")
            
            set(DEST_PATH "${OUTPUT_DIR_ARG}/${ASSET_NAME}")
            
            string(TOUPPER "${CMAKE_MESSAGE_LOG_LEVEL}" LOG_LEVEL_UPPER)
            
            if(LOG_LEVEL_UPPER STREQUAL "DEBUG")
            
                file(DOWNLOAD "${ASSET_URL}" "${DEST_PATH}"
                     STATUS DOWNLOAD_STATUS
                     SHOW_PROGRESS)
                     
            else()
            
                file(DOWNLOAD "${ASSET_URL}" "${DEST_PATH}"
                     STATUS DOWNLOAD_STATUS)
                     
            endif()


                
            list(GET DOWNLOAD_STATUS 0 STATUS_CODE)
            
            if(NOT STATUS_CODE EQUAL 0)
                list(GET DOWNLOAD_STATUS 1 STATUS_MESSAGE)
                message(FATAL_ERROR "Downloading ${ASSET_NAME} failed: ${STATUS_MESSAGE}")
            endif()

            set(${OUT_DOWNLOADED_PATH_ARG} "${DEST_PATH}" PARENT_SCOPE)
            return()
        endif()
    endforeach()

    message(FATAL_ERROR "No asset '${ASSET_NAME_PATTERN_ARG}' found in release.")
    
endfunction()


#------------------------------------------------------------------------------#
# Returns the real name of artifact folder from selected folder.
#
# This function can be used to check real folder name in case, the artifact 
# uses '_' instead of '-'
#
# ARTIFACTS_PATH_ARG       [in]: Path to the repository folder.
# ARTIFACT_NAME_ARG        [in]: Name of artifact.
# ARTIFACT_FOUND_NAME_ARG [out]: Name of the found folder
#------------------------------------------------------------------------------#
function(RootRepoHandler_Get_ArtifactFolderName ARTIFACTS_PATH_ARG 
                                                ARTIFACT_NAME_ARG
                                                ARTIFACT_FOUND_NAME_ARG)
                                                
    set(ARTIFACT_NAME_UNDERSCORE "${ARTIFACT_NAME_ARG}")
    string(REPLACE "-" "_" ARTIFACT_NAME_UNDERSCORE "${ARTIFACT_NAME_UNDERSCORE}")
    
    set(ARTIFACT_NAME_ORIGINAL "${ARTIFACT_NAME_ARG}")

    
    if(IS_DIRECTORY "${ARTIFACTS_PATH_ARG}/${ARTIFACT_NAME_UNDERSCORE}")
    
        set(${ARTIFACT_FOUND_NAME_ARG} "${ARTIFACT_NAME_UNDERSCORE}" PARENT_SCOPE)
        
        message(DEBUG "Artifact folder name found: ${ARTIFACT_NAME_UNDERSCORE}")
    
    elseif(IS_DIRECTORY "${ARTIFACTS_PATH_ARG}/${ARTIFACT_NAME_ORIGINAL}")
    
        set(${ARTIFACT_FOUND_NAME_ARG} "${ARTIFACT_NAME_ORIGINAL}" PARENT_SCOPE)
        
        message(DEBUG "Artifact folder name found: ${ARTIFACT_NAME_ORIGINAL}")
    
    else()
        message(WARNING "No folder of artifact '${ARTIFACT_NAME_ARG}' found in ${ARTIFACTS_PATH_ARG}!")
    endif()

endfunction(RootRepoHandler_Get_ArtifactFolderName)


#------------------------------------------------------------------------------#
# Returns the path to the folder (git repository) of the artifact in the Root
# repository. The artifact which is not in the Root repository can not be
# downloaded, so it is reported here by FATAL_ERROR, including the list of the
# artifacts which are available (otherwise the git command would be executed in
# the Root repository itself and fail with a misleading message).
#
# ROOT_REPO_PATH_ARG [in]: Path to the Root repository temp location
# ARTIFACT_NAME_ARG  [in]: Name of the artifact
# ARTIFACT_DIR_ARG  [out]: Path to the folder of the artifact
#------------------------------------------------------------------------------#
function(RootRepoHandler_Get_ArtifactDir ROOT_REPO_PATH_ARG
                                         ARTIFACT_NAME_ARG
                                         ARTIFACT_DIR_ARG)

    set(ARTIFACT_FOUND_NAME "")

    RootRepoHandler_Get_ArtifactFolderName("${ROOT_REPO_PATH_ARG}"
                                           "${ARTIFACT_NAME_ARG}"
                                           ARTIFACT_FOUND_NAME)

    if("${ARTIFACT_FOUND_NAME}" STREQUAL "")

        set(AVAILABLE_ARTIFACTS "")

        file(GLOB ROOT_REPO_ITEMS LIST_DIRECTORIES true "${ROOT_REPO_PATH_ARG}/*")

        foreach(ROOT_REPO_ITEM IN LISTS ROOT_REPO_ITEMS)

            get_filename_component(ITEM_NAME "${ROOT_REPO_ITEM}" NAME)

            # Hidden folders (e.g. .git) are not artifacts
            if(ITEM_NAME MATCHES "^\\.")
                continue()
            endif()

            if(IS_DIRECTORY "${ROOT_REPO_ITEM}")
                string(REPLACE "_" "-" ITEM_NAME "${ITEM_NAME}")
                list(APPEND AVAILABLE_ARTIFACTS "${ITEM_NAME}")
            endif()

        endforeach()

        string(REPLACE ";" ", " AVAILABLE_ARTIFACTS_TEXT "${AVAILABLE_ARTIFACTS}")

        message(FATAL_ERROR "Artifact '${ARTIFACT_NAME_ARG}' not found in the root repository (available artifacts: ${AVAILABLE_ARTIFACTS_TEXT}).")

    endif()

    # The folder of the submodule which was not initialized (failed update, see
    # RootRepoHandler_UpdateSubmodules) is empty and git commands executed in it
    # would work with the Root repository.
    if(NOT EXISTS "${ROOT_REPO_PATH_ARG}/${ARTIFACT_FOUND_NAME}/.git")
        message(FATAL_ERROR "Repository of artifact '${ARTIFACT_NAME_ARG}' is not initialized in ${ROOT_REPO_PATH_ARG}/${ARTIFACT_FOUND_NAME} (see the warning about the failed update of the artifact repositories).")
    endif()

    set(${ARTIFACT_DIR_ARG} "${ROOT_REPO_PATH_ARG}/${ARTIFACT_FOUND_NAME}" PARENT_SCOPE)

endfunction(RootRepoHandler_Get_ArtifactDir)