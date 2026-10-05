# ==============================================================================
# Platform updates handler.
#
# User shall place their updates in folder "Updates" and then create folder for
# every version. The version folder can contain multiple .cmake files for
# separate update stages/steps. Its execution will be in alphabetical order.
#
# Update steps are applied to modules of the project - folders with
# CMakeLists.txt generated from the template (header "# Template version:") in
# Application, Bsp and Middlewares, test sets in Tests/ are not modules. Every
# step is executed once for every selected module with variables:
#   UPDATER_MODULE_DIR - absolute path of the module folder
#   VERSION_ID         - version of the executed update
# A step shall change only files of the module and shall be idempotent (second
# execution changes nothing), steps are executed again for every selected
# branch of the module repository.
# ==============================================================================

#===============================================================================
# Global variables
#===============================================================================

# Path to the project configuration files
get_filename_component(VERSION_HANDLER_PATH "${CMAKE_CURRENT_LIST_DIR}/../HelperTools/Prj_Handler/Platform_VersionHandler.cmake" REALPATH)

# Include platform version handler functionality
include(${VERSION_HANDLER_PATH})

# Path to the update scripts
set(UPDATE_VERSIONS_DIR "${CMAKE_CURRENT_LIST_DIR}/Updates/")

# Set path to system configuration file
get_filename_component(SYSTEM_CONFIG_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/../SysConfig.cmake" REALPATH)

# Include file with system configuration values
include("${SYSTEM_CONFIG_FILE_PATH}")

# Folders of the project searched for modules
set(UPDATER_MODULE_SEARCH_DIRS  "Application" "Bsp" "Middlewares")

# Header line of module CMakeLists.txt generated from the template
set(UPDATER_MODULE_HEADER_PATTERN "^# Template version:[ \t]*[0-9]+\\.[0-9]+\\.[0-9]+")

# Default commit message of module updates
set(UPDATER_DEFAULT_COMMIT_MESSAGE "Module updated by EmBi_Platform Updater")

# ------------------------------------------------------------------------------
# Function: Updater_Get_UpdatesVersionList
# Description: Returns all available version for update process.
# ------------------------------------------------------------------------------
function(Updater_Get_UpdatesVersionList OUT_VERSIONS_LIST)

    file(GLOB DIR_LIST RELATIVE ${UPDATE_VERSIONS_DIR}/ "${UPDATE_VERSIONS_DIR}/*")

    set(VERSION_LIST "")

    foreach(DIR_NAME ${DIR_LIST})
        if(IS_DIRECTORY "${UPDATE_VERSIONS_DIR}/${DIR_NAME}")
            list(APPEND VERSION_LIST ${DIR_NAME})
        endif()
    endforeach()

    list(SORT VERSION_LIST COMPARE NATURAL ORDER ASCENDING)

    message(DEBUG "List of available version: ${VERSION_LIST}")

    set(${OUT_VERSIONS_LIST} ${VERSION_LIST} PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Updater_Get_UpdateStepsList
# Description: Returns all steps in update to required version.
# ------------------------------------------------------------------------------
function(Updater_Get_UpdateStepsList IN_VERSION OUT_STEP_LIST)

    file(GLOB STEP_LIST_RAW RELATIVE ${UPDATE_VERSIONS_DIR}/${IN_VERSION} "${UPDATE_VERSIONS_DIR}/${IN_VERSION}/*.cmake")

    set(STEP_LIST "")

    foreach(STEP_NAME ${STEP_LIST_RAW})
        if(NOT IS_DIRECTORY "${UPDATE_VERSIONS_DIR}/${STEP_NAME}")
            list(APPEND STEP_LIST ${STEP_NAME})
        endif()
    endforeach()

    list(SORT STEP_LIST COMPARE NATURAL ORDER ASCENDING)

    set(${OUT_STEP_LIST} ${STEP_LIST} PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Updater_Get_ProjectRoot
# Description: Returns project root folder (UPDATE_PROJECT_ROOT overrides the
#              project of this EmBi_Platform).
# ------------------------------------------------------------------------------
function(Updater_Get_ProjectRoot OUT_ROOT)

    if(DEFINED UPDATE_PROJECT_ROOT AND NOT "${UPDATE_PROJECT_ROOT}" STREQUAL "")
        get_filename_component(ROOT "${UPDATE_PROJECT_ROOT}" REALPATH)
    else()
        SysConfig_Get_ProjectRootPath(ROOT)
        get_filename_component(ROOT "${ROOT}" REALPATH)
    endif()

    set(${OUT_ROOT} "${ROOT}" PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Updater_Get_ModuleList
# Description: Returns modules of the project (folders relative to the project
#              root with CMakeLists.txt generated from the template, test sets
#              excluded).
# ------------------------------------------------------------------------------
function(Updater_Get_ModuleList IN_PROJECT_ROOT OUT_MODULE_LIST)

    set(MODULE_LIST "")

    foreach(SEARCH_DIR IN LISTS UPDATER_MODULE_SEARCH_DIRS)

        if(NOT IS_DIRECTORY "${IN_PROJECT_ROOT}/${SEARCH_DIR}")
            continue()
        endif()

        file(GLOB_RECURSE CMAKELISTS_FILES RELATIVE "${IN_PROJECT_ROOT}"
             "${IN_PROJECT_ROOT}/${SEARCH_DIR}/*/CMakeLists.txt")

        foreach(CMAKELISTS_FILE IN LISTS CMAKELISTS_FILES)

            if(CMAKELISTS_FILE MATCHES "(^|/)(Tests|Build[^/]*|\\.git)/")
                continue()
            endif()

            file(READ "${IN_PROJECT_ROOT}/${CMAKELISTS_FILE}" HEADER LIMIT 64)

            if(HEADER MATCHES "${UPDATER_MODULE_HEADER_PATTERN}")
                get_filename_component(MODULE_DIR "${CMAKELISTS_FILE}" DIRECTORY)
                list(APPEND MODULE_LIST "${MODULE_DIR}")
            endif()

        endforeach()

    endforeach()

    list(SORT MODULE_LIST)

    set(${OUT_MODULE_LIST} ${MODULE_LIST} PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Updater_Git
# Description: Executes GIT command in repository, fails on error if required.
# ------------------------------------------------------------------------------
function(Updater_Git IN_REPO OUT_RESULT OUT_OUTPUT)

    execute_process(COMMAND git ${ARGN}
                    WORKING_DIRECTORY "${IN_REPO}"
                    RESULT_VARIABLE GIT_RESULT
                    OUTPUT_VARIABLE GIT_OUTPUT
                    ERROR_VARIABLE  GIT_ERROR
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_STRIP_TRAILING_WHITESPACE)

    if(NOT GIT_RESULT EQUAL 0)
        message(DEBUG "git ${ARGN} failed in ${IN_REPO}: ${GIT_ERROR}")
        set(GIT_OUTPUT "${GIT_ERROR}")
    endif()

    set(${OUT_RESULT} ${GIT_RESULT}    PARENT_SCOPE)
    set(${OUT_OUTPUT} "${GIT_OUTPUT}"  PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Updater_Get_RepoRoot
# Description: Returns root folder of GIT repository containing the folder
#              (empty if the folder is not in a GIT repository).
# ------------------------------------------------------------------------------
function(Updater_Get_RepoRoot IN_DIR OUT_REPO_ROOT)

    Updater_Git("${IN_DIR}" GIT_RESULT GIT_OUTPUT rev-parse --show-toplevel)

    if(GIT_RESULT EQUAL 0)
        get_filename_component(REPO_ROOT "${GIT_OUTPUT}" REALPATH)
    else()
        set(REPO_ROOT "")
    endif()

    set(${OUT_REPO_ROOT} "${REPO_ROOT}" PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Updater_Get_CurrentRef
# Description: Returns checked out branch of the repository, or commit ID for
#              detached HEAD. OUT_IS_BRANCH signals a branch.
# ------------------------------------------------------------------------------
function(Updater_Get_CurrentRef IN_REPO OUT_REF OUT_IS_BRANCH)

    Updater_Git("${IN_REPO}" GIT_RESULT GIT_OUTPUT symbolic-ref -q --short HEAD)

    if(GIT_RESULT EQUAL 0 AND NOT "${GIT_OUTPUT}" STREQUAL "")
        set(${OUT_REF} "${GIT_OUTPUT}" PARENT_SCOPE)
        set(${OUT_IS_BRANCH} TRUE PARENT_SCOPE)
    else()
        Updater_Git("${IN_REPO}" GIT_RESULT GIT_OUTPUT rev-parse HEAD)
        set(${OUT_REF} "${GIT_OUTPUT}" PARENT_SCOPE)
        set(${OUT_IS_BRANCH} FALSE PARENT_SCOPE)
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: Updater_Get_BranchList
# Description: Returns local branches and branches of remote "origin" (without
#              "origin/" prefix) of the repository.
# ------------------------------------------------------------------------------
function(Updater_Get_BranchList IN_REPO OUT_BRANCH_LIST)

    Updater_Git("${IN_REPO}" GIT_RESULT GIT_OUTPUT
                for-each-ref "--format=%(refname)" refs/heads refs/remotes/origin)

    set(BRANCH_LIST "")

    if(GIT_RESULT EQUAL 0)
        string(REPLACE "\n" ";" REF_LIST "${GIT_OUTPUT}")

        foreach(REF_NAME IN LISTS REF_LIST)
            string(REGEX REPLACE "^refs/(heads|remotes/origin)/" "" BRANCH_NAME "${REF_NAME}")
            if(NOT "${BRANCH_NAME}" STREQUAL "HEAD" AND NOT "${BRANCH_NAME}" STREQUAL "")
                list(APPEND BRANCH_LIST "${BRANCH_NAME}")
            endif()
        endforeach()
    endif()

    list(REMOVE_DUPLICATES BRANCH_LIST)
    list(SORT BRANCH_LIST)

    set(${OUT_BRANCH_LIST} ${BRANCH_LIST} PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Updater_Match_Branches
# Description: Returns branches matching names or patterns ("*" any characters,
#              "?" one character), e.g. "Dev/STM32F4/*".
# ------------------------------------------------------------------------------
function(Updater_Match_Branches IN_BRANCH_LIST IN_PATTERN_LIST OUT_MATCHED)

    set(MATCHED_LIST "")

    foreach(PATTERN IN LISTS IN_PATTERN_LIST)

        set(REGEX "${PATTERN}")
        foreach(SPECIAL_CHAR "\\" "." "+" "(" ")" "[" "]" "{" "}" "^" "$" "|")
            string(REPLACE "${SPECIAL_CHAR}" "\\${SPECIAL_CHAR}" REGEX "${REGEX}")
        endforeach()
        string(REPLACE "*" ".*" REGEX "${REGEX}")
        string(REPLACE "?" "." REGEX "${REGEX}")

        foreach(BRANCH_NAME IN LISTS IN_BRANCH_LIST)
            if(BRANCH_NAME MATCHES "^${REGEX}$")
                list(APPEND MATCHED_LIST "${BRANCH_NAME}")
            endif()
        endforeach()

    endforeach()

    list(REMOVE_DUPLICATES MATCHED_LIST)

    set(${OUT_MATCHED} ${MATCHED_LIST} PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Updater_Checkout
# Description: Checks out branch of the repository, local tracking branch is
#              created for a branch existing only in remote "origin".
# ------------------------------------------------------------------------------
function(Updater_Checkout IN_REPO IN_BRANCH OUT_RESULT OUT_OUTPUT)

    Updater_Git("${IN_REPO}" GIT_RESULT GIT_OUTPUT show-ref --verify --quiet "refs/heads/${IN_BRANCH}")

    if(GIT_RESULT EQUAL 0)
        Updater_Git("${IN_REPO}" GIT_RESULT GIT_OUTPUT checkout -q "${IN_BRANCH}")
    else()
        Updater_Git("${IN_REPO}" GIT_RESULT GIT_OUTPUT checkout -q --track "origin/${IN_BRANCH}")
    endif()

    set(${OUT_RESULT} ${GIT_RESULT}   PARENT_SCOPE)
    set(${OUT_OUTPUT} "${GIT_OUTPUT}" PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Updater_Run_ModuleSteps
# Description: Executes all steps of required versions for one module.
# ------------------------------------------------------------------------------
function(Updater_Run_ModuleSteps IN_MODULE_DIR IN_VERSION_LIST)

    foreach(VERSION_ID IN LISTS IN_VERSION_LIST)

        Updater_Get_UpdateStepsList(${VERSION_ID} STEP_LIST)

        foreach(UPDATE_STEP IN LISTS STEP_LIST)

            set(UPDATER_MODULE_DIR "${IN_MODULE_DIR}")

            message(STATUS "  ${VERSION_ID}/${UPDATE_STEP}")

            # Execute update step
            include("${UPDATE_VERSIONS_DIR}/${VERSION_ID}/${UPDATE_STEP}")

        endforeach()

    endforeach()

endfunction()


# ------------------------------------------------------------------------------
# Function: Updater_RunVersionUpdate
# Description: Executes all necessary steps in update for required version for
#              all modules of the project (checked out branches) and updates
#              actual platform version.
# ------------------------------------------------------------------------------
function(Updater_RunVersionUpdate IN_TARGET_VERSION)

    Updater_Get_ProjectRoot(PROJECT_ROOT)
    Updater_Get_ModuleList("${PROJECT_ROOT}" MODULE_LIST)

    foreach(MODULE_REL_DIR IN LISTS MODULE_LIST)
        message(STATUS "Module ${MODULE_REL_DIR}:")
        Updater_Run_ModuleSteps("${PROJECT_ROOT}/${MODULE_REL_DIR}" "${IN_TARGET_VERSION}")
    endforeach()

    # Update actual version
    Platform_VersionHandler_Set_Version(${IN_TARGET_VERSION})

endfunction()


# ------------------------------------------------------------------------------
# Function: Updater_Print_VersionList
# Description: Prints available update versions with their steps.
# ------------------------------------------------------------------------------
function(Updater_Print_VersionList)

    Updater_Get_UpdatesVersionList(VERSION_LIST)

    message("Available updates:")
    message("[0]: Latest")

    set(VERSION_IDX 0)
    foreach(VERSION_NAME IN LISTS VERSION_LIST)
        math(EXPR VERSION_IDX "${VERSION_IDX} + 1")
        Updater_Get_UpdateStepsList(${VERSION_NAME} STEP_LIST)
        string(REPLACE ";" ", " STEP_TEXT "${STEP_LIST}")
        message("[${VERSION_IDX}]: ${VERSION_NAME} (${STEP_TEXT})")
    endforeach()

endfunction()


# ------------------------------------------------------------------------------
# Function: Updater_Print_ModuleList
# Description: Prints modules of the project with repository branch.
# ------------------------------------------------------------------------------
function(Updater_Print_ModuleList)

    Updater_Get_ProjectRoot(PROJECT_ROOT)
    Updater_Get_ModuleList("${PROJECT_ROOT}" MODULE_LIST)

    message("Modules of the project:")
    message("[0]: All modules")

    set(MODULE_IDX 0)
    foreach(MODULE_REL_DIR IN LISTS MODULE_LIST)
        math(EXPR MODULE_IDX "${MODULE_IDX} + 1")
        Updater_Get_RepoRoot("${PROJECT_ROOT}/${MODULE_REL_DIR}" REPO_ROOT)
        if("${REPO_ROOT}" STREQUAL "")
            set(REF_TEXT "no GIT repository")
        else()
            Updater_Get_CurrentRef("${REPO_ROOT}" CURRENT_REF IS_BRANCH)
            set(REF_TEXT "${CURRENT_REF}")
        endif()
        message("[${MODULE_IDX}]: ${MODULE_REL_DIR} (${REF_TEXT})")
    endforeach()

endfunction()


# ------------------------------------------------------------------------------
# Function: Updater_Select_Versions
# Description: Returns versions in range FROM - TO (both included). Range is
#              given by versions (UPDATE_FROM_VERSION, UPDATE_TO_VERSION) or by
#              IDs of the printed list (FROM_VERSION_ID, TO_VERSION_ID, 0 or
#              empty = first / latest).
# ------------------------------------------------------------------------------
function(Updater_Select_Versions OUT_VERSION_LIST)

    Updater_Get_UpdatesVersionList(ALL_VERSIONS)
    list(LENGTH ALL_VERSIONS VERSION_CNT)

    if(VERSION_CNT EQUAL 0)
        message(FATAL_ERROR "No update available.")
    endif()

    list(GET ALL_VERSIONS 0 FIRST_VERSION)
    math(EXPR LAST_IDX "${VERSION_CNT} - 1")
    list(GET ALL_VERSIONS ${LAST_IDX} LAST_VERSION)

    foreach(LIMIT FROM TO)

        if(DEFINED UPDATE_${LIMIT}_VERSION AND NOT "${UPDATE_${LIMIT}_VERSION}" STREQUAL "")
            set(${LIMIT}_VERSION "${UPDATE_${LIMIT}_VERSION}")
        elseif(DEFINED ${LIMIT}_VERSION_ID AND "${${LIMIT}_VERSION_ID}" MATCHES "^[1-9][0-9]*$")
            if(${LIMIT}_VERSION_ID GREATER VERSION_CNT)
                message(FATAL_ERROR "Version ID ${${LIMIT}_VERSION_ID} is not correct.")
            endif()
            math(EXPR VERSION_IDX "${${LIMIT}_VERSION_ID} - 1")
            list(GET ALL_VERSIONS ${VERSION_IDX} ${LIMIT}_VERSION)
        elseif("${LIMIT}" STREQUAL "FROM")
            set(FROM_VERSION "${FIRST_VERSION}")
        else()
            set(TO_VERSION "${LAST_VERSION}")
        endif()

    endforeach()

    set(VERSION_LIST "")
    foreach(VERSION_NAME IN LISTS ALL_VERSIONS)
        if(NOT VERSION_NAME VERSION_LESS FROM_VERSION AND NOT VERSION_NAME VERSION_GREATER TO_VERSION)
            list(APPEND VERSION_LIST "${VERSION_NAME}")
        endif()
    endforeach()

    if("${VERSION_LIST}" STREQUAL "")
        message(FATAL_ERROR "No update in range ${FROM_VERSION} - ${TO_VERSION}.")
    endif()

    set(${OUT_VERSION_LIST} ${VERSION_LIST} PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Updater_Select_Modules
# Description: Returns selected modules (MODULE_IDS - IDs of the printed list
#              separated by comma, 0 or empty = all; or UPDATE_MODULES - module
#              folders relative to the project root).
# ------------------------------------------------------------------------------
function(Updater_Select_Modules IN_PROJECT_ROOT OUT_MODULE_LIST)

    Updater_Get_ModuleList("${IN_PROJECT_ROOT}" ALL_MODULES)
    list(LENGTH ALL_MODULES MODULE_CNT)

    set(MODULE_LIST "")

    if(DEFINED UPDATE_MODULES AND NOT "${UPDATE_MODULES}" STREQUAL "")

        string(REPLACE "," ";" REQ_MODULES "${UPDATE_MODULES}")
        foreach(REQ_MODULE IN LISTS REQ_MODULES)
            string(STRIP "${REQ_MODULE}" REQ_MODULE)
            string(REGEX REPLACE "/+$" "" REQ_MODULE "${REQ_MODULE}")
            if(NOT "${REQ_MODULE}" IN_LIST ALL_MODULES)
                message(FATAL_ERROR "Module '${REQ_MODULE}' is not a module of the project.")
            endif()
            list(APPEND MODULE_LIST "${REQ_MODULE}")
        endforeach()

    elseif(DEFINED MODULE_IDS AND NOT "${MODULE_IDS}" STREQUAL "" AND NOT "${MODULE_IDS}" STREQUAL "0")

        string(REPLACE "," ";" REQ_IDS "${MODULE_IDS}")
        foreach(REQ_ID IN LISTS REQ_IDS)
            string(STRIP "${REQ_ID}" REQ_ID)
            if(NOT "${REQ_ID}" MATCHES "^[1-9][0-9]*$" OR REQ_ID GREATER MODULE_CNT)
                message(FATAL_ERROR "Module ID '${REQ_ID}' is not correct.")
            endif()
            math(EXPR MODULE_IDX "${REQ_ID} - 1")
            list(GET ALL_MODULES ${MODULE_IDX} REQ_MODULE)
            list(APPEND MODULE_LIST "${REQ_MODULE}")
        endforeach()

    else()
        set(MODULE_LIST ${ALL_MODULES})
    endif()

    list(REMOVE_DUPLICATES MODULE_LIST)

    set(${OUT_MODULE_LIST} ${MODULE_LIST} PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Updater_Update_Repo
# Description: Updates modules of one repository on all required branches.
#
# IN_REPO_ROOT    [in]: Repository root folder (empty = not a GIT repository)
# IN_MODULE_DIRS  [in]: Absolute folders of the modules in the repository
# IN_VERSION_LIST [in]: Versions of the update
# OUT_RESULTS    [out]: Result lines appended to the list
# ------------------------------------------------------------------------------
function(Updater_Update_Repo IN_REPO_ROOT IN_MODULE_DIRS IN_VERSION_LIST IN_PROJECT_ROOT OUT_RESULTS)

    set(RESULTS ${${OUT_RESULTS}})

    if("${IN_REPO_ROOT}" STREQUAL "")
        set(REPO_NAME "(no GIT repository)")
    else()
        file(RELATIVE_PATH REPO_NAME "${IN_PROJECT_ROOT}" "${IN_REPO_ROOT}")
        if("${REPO_NAME}" STREQUAL "")
            set(REPO_NAME "(project)")
        endif()
    endif()

    message(STATUS "================================================================================")
    message(STATUS "Repository ${REPO_NAME}")
    message(STATUS "================================================================================")

    #------------------------------ Branches ---------------------------------#
    set(CURRENT_REF "")
    set(BRANCH_LIST "")

    if(NOT "${IN_REPO_ROOT}" STREQUAL "")
        Updater_Get_CurrentRef("${IN_REPO_ROOT}" CURRENT_REF CURRENT_IS_BRANCH)
    endif()

    if("${UPDATE_BRANCH_PATTERNS}" STREQUAL "")
        # Checked out state only
        set(BRANCH_LIST "<current>")
    elseif("${IN_REPO_ROOT}" STREQUAL "")
        list(APPEND RESULTS "${REPO_NAME}: skipped - branches required, not a GIT repository")
        set(${OUT_RESULTS} ${RESULTS} PARENT_SCOPE)
        return()
    elseif("${IN_REPO_ROOT}" STREQUAL "${IN_PROJECT_ROOT}")
        # Branch switch of the project repository would change the whole project
        message(STATUS "Project repository - only checked out branch '${CURRENT_REF}' is updated")
        set(BRANCH_LIST "<current>")
    else()
        Updater_Get_BranchList("${IN_REPO_ROOT}" ALL_BRANCHES)
        Updater_Match_Branches("${ALL_BRANCHES}" "${UPDATE_BRANCH_PATTERNS}" BRANCH_LIST)
        if("${BRANCH_LIST}" STREQUAL "")
            list(APPEND RESULTS "${REPO_NAME}: skipped - no branch matches '${UPDATE_BRANCHES}'")
            set(${OUT_RESULTS} ${RESULTS} PARENT_SCOPE)
            return()
        endif()
    endif()

    #------------------------- Local changes check ---------------------------#
    if(NOT "${IN_REPO_ROOT}" STREQUAL "" AND NOT "${UPDATE_MODE}" STREQUAL "APPLY")
        Updater_Git("${IN_REPO_ROOT}" GIT_RESULT GIT_STATUS status --porcelain --untracked-files=no)
        if(NOT "${GIT_STATUS}" STREQUAL "")
            list(APPEND RESULTS "${REPO_NAME}: skipped - local changes (commit or stash them first)")
            set(${OUT_RESULTS} ${RESULTS} PARENT_SCOPE)
            return()
        endif()
    endif()

    # Module folders relative to the repository (GIT pathspec)
    set(MODULE_PATHSPECS "")
    foreach(MODULE_DIR IN LISTS IN_MODULE_DIRS)
        if(NOT "${IN_REPO_ROOT}" STREQUAL "")
            file(RELATIVE_PATH MODULE_PATHSPEC "${IN_REPO_ROOT}" "${MODULE_DIR}")
            if("${MODULE_PATHSPEC}" STREQUAL "")
                set(MODULE_PATHSPEC ".")
            endif()
            list(APPEND MODULE_PATHSPECS "${MODULE_PATHSPEC}")
        endif()
    endforeach()

    #------------------------------ Update -----------------------------------#
    foreach(BRANCH_NAME IN LISTS BRANCH_LIST)

        if("${BRANCH_NAME}" STREQUAL "<current>")
            set(BRANCH_TEXT "${CURRENT_REF}")
        else()
            set(BRANCH_TEXT "${BRANCH_NAME}")
            Updater_Checkout("${IN_REPO_ROOT}" "${BRANCH_NAME}" GIT_RESULT GIT_OUTPUT)
            if(NOT GIT_RESULT EQUAL 0)
                list(APPEND RESULTS "${REPO_NAME} @ ${BRANCH_TEXT}: checkout failed - ${GIT_OUTPUT}")
                continue()
            endif()
        endif()

        message(STATUS "Branch ${BRANCH_TEXT}")

        set(UPDATED_CNT 0)
        foreach(MODULE_DIR IN LISTS IN_MODULE_DIRS)
            file(RELATIVE_PATH MODULE_REL_DIR "${IN_PROJECT_ROOT}" "${MODULE_DIR}")
            if(EXISTS "${MODULE_DIR}/CMakeLists.txt")
                message(STATUS " Module ${MODULE_REL_DIR}")
                Updater_Run_ModuleSteps("${MODULE_DIR}" "${IN_VERSION_LIST}")
                math(EXPR UPDATED_CNT "${UPDATED_CNT} + 1")
            else()
                message(STATUS " Module ${MODULE_REL_DIR} does not exist on this branch")
            endif()
        endforeach()

        if("${IN_REPO_ROOT}" STREQUAL "")
            list(APPEND RESULTS "${REPO_NAME}: ${UPDATED_CNT} module(s) processed")
            continue()
        elseif(UPDATED_CNT EQUAL 0)
            list(APPEND RESULTS "${REPO_NAME} @ ${BRANCH_TEXT}: no selected module on this branch")
            continue()
        endif()

        # Changes of the modules
        Updater_Git("${IN_REPO_ROOT}" GIT_RESULT CHANGED_FILES diff --name-only -- ${MODULE_PATHSPECS})

        if("${CHANGED_FILES}" STREQUAL "")
            list(APPEND RESULTS "${REPO_NAME} @ ${BRANCH_TEXT}: up to date")
        else()
            string(REPLACE "\n" ";" CHANGED_LIST "${CHANGED_FILES}")
            list(LENGTH CHANGED_LIST CHANGED_CNT)

            Updater_Git("${IN_REPO_ROOT}" GIT_RESULT CHANGES_DIFF diff -- ${MODULE_PATHSPECS})
            message("${CHANGES_DIFF}")

            if("${UPDATE_MODE}" STREQUAL "DRY_RUN")

                Updater_Git("${IN_REPO_ROOT}" GIT_RESULT GIT_OUTPUT checkout -- ${MODULE_PATHSPECS})
                list(APPEND RESULTS "${REPO_NAME} @ ${BRANCH_TEXT}: ${CHANGED_CNT} file(s) would change (dry run, nothing written)")

            elseif("${UPDATE_MODE}" STREQUAL "COMMIT")

                Updater_Git("${IN_REPO_ROOT}" GIT_RESULT GIT_OUTPUT add -u -- ${MODULE_PATHSPECS})
                Updater_Git("${IN_REPO_ROOT}" GIT_RESULT GIT_OUTPUT commit -q -m "${UPDATE_COMMIT_MESSAGE}")

                if(NOT GIT_RESULT EQUAL 0)
                    Updater_Git("${IN_REPO_ROOT}" RESET_RESULT RESET_OUTPUT reset -q)
                    Updater_Git("${IN_REPO_ROOT}" RESET_RESULT RESET_OUTPUT checkout -- ${MODULE_PATHSPECS})
                    list(APPEND RESULTS "${REPO_NAME} @ ${BRANCH_TEXT}: commit failed, changes reverted - ${GIT_OUTPUT}")
                    continue()
                endif()

                Updater_Git("${IN_REPO_ROOT}" GIT_RESULT COMMIT_ID rev-parse --short HEAD)
                set(RESULT_TEXT "${REPO_NAME} @ ${BRANCH_TEXT}: ${CHANGED_CNT} file(s) committed ${COMMIT_ID}")

                if(UPDATE_PUSH AND NOT "${BRANCH_NAME}" STREQUAL "<current>")
                    set(PUSH_BRANCH "${BRANCH_NAME}")
                elseif(UPDATE_PUSH AND CURRENT_IS_BRANCH)
                    set(PUSH_BRANCH "${CURRENT_REF}")
                else()
                    set(PUSH_BRANCH "")
                endif()

                if(NOT "${PUSH_BRANCH}" STREQUAL "")
                    Updater_Git("${IN_REPO_ROOT}" GIT_RESULT GIT_OUTPUT push -q origin "${PUSH_BRANCH}")
                    if(GIT_RESULT EQUAL 0)
                        string(APPEND RESULT_TEXT ", pushed")
                    else()
                        string(APPEND RESULT_TEXT ", push failed - ${GIT_OUTPUT}")
                    endif()
                endif()

                list(APPEND RESULTS "${RESULT_TEXT}")

            else()
                list(APPEND RESULTS "${REPO_NAME} @ ${BRANCH_TEXT}: ${CHANGED_CNT} file(s) changed (not committed)")
            endif()
        endif()

    endforeach()

    #------------------------ Restore checked out ref -------------------------#
    if(NOT "${IN_REPO_ROOT}" STREQUAL "" AND NOT "${BRANCH_LIST}" STREQUAL "<current>")
        Updater_Git("${IN_REPO_ROOT}" GIT_RESULT GIT_OUTPUT checkout -q "${CURRENT_REF}")
        if(NOT GIT_RESULT EQUAL 0)
            list(APPEND RESULTS "${REPO_NAME}: restore of '${CURRENT_REF}' failed - ${GIT_OUTPUT}")
        endif()
    endif()

    set(${OUT_RESULTS} ${RESULTS} PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Updater_Update_Modules
# Description: Updates selected modules on selected branches of their
#              repositories (see Main functionality for parameters).
# ------------------------------------------------------------------------------
function(Updater_Update_Modules)

    # Mode of the update
    if("${UPDATE_MODE}" STREQUAL "")
        set(UPDATE_MODE "DRY_RUN")
    endif()

    if(NOT "${UPDATE_MODE}" MATCHES "^(DRY_RUN|APPLY|COMMIT)$")
        message(FATAL_ERROR "UPDATE_MODE '${UPDATE_MODE}' is not correct (DRY_RUN, APPLY, COMMIT).")
    endif()

    # Branch names / patterns
    string(REPLACE "," ";" UPDATE_BRANCH_PATTERNS "${UPDATE_BRANCHES}")
    set(BRANCH_PATTERNS "")
    foreach(PATTERN IN LISTS UPDATE_BRANCH_PATTERNS)
        string(STRIP "${PATTERN}" PATTERN)
        if(NOT "${PATTERN}" STREQUAL "")
            list(APPEND BRANCH_PATTERNS "${PATTERN}")
        endif()
    endforeach()
    set(UPDATE_BRANCH_PATTERNS ${BRANCH_PATTERNS})

    if(NOT "${UPDATE_BRANCH_PATTERNS}" STREQUAL "" AND "${UPDATE_MODE}" STREQUAL "APPLY")
        message(FATAL_ERROR "Changes of other branches can not be kept without commit - use DRY_RUN or COMMIT mode, or update the checked out branches only.")
    endif()

    if("${UPDATE_COMMIT_MESSAGE}" STREQUAL "")
        set(UPDATE_COMMIT_MESSAGE "${UPDATER_DEFAULT_COMMIT_MESSAGE}")
    endif()

    Updater_Get_ProjectRoot(PROJECT_ROOT)
    Updater_Select_Versions(VERSION_LIST)
    Updater_Select_Modules("${PROJECT_ROOT}" MODULE_LIST)

    if("${MODULE_LIST}" STREQUAL "")
        message(FATAL_ERROR "No module selected.")
    endif()

    string(REPLACE ";" ", " VERSION_TEXT "${VERSION_LIST}")
    if("${UPDATE_BRANCH_PATTERNS}" STREQUAL "")
        set(BRANCH_TEXT "checked out")
    else()
        string(REPLACE ";" ", " BRANCH_TEXT "${UPDATE_BRANCH_PATTERNS}")
    endif()
    list(LENGTH MODULE_LIST MODULE_CNT)

    message(STATUS "Updates:  ${VERSION_TEXT}")
    message(STATUS "Modules:  ${MODULE_CNT}")
    message(STATUS "Branches: ${BRANCH_TEXT}")
    message(STATUS "Mode:     ${UPDATE_MODE}")

    # Modules grouped by GIT repository
    set(REPO_LIST "")
    foreach(MODULE_REL_DIR IN LISTS MODULE_LIST)
        set(MODULE_DIR "${PROJECT_ROOT}/${MODULE_REL_DIR}")
        Updater_Get_RepoRoot("${MODULE_DIR}" REPO_ROOT)
        if("${REPO_ROOT}" STREQUAL "")
            set(REPO_KEY "NO_REPO")
        else()
            string(MAKE_C_IDENTIFIER "${REPO_ROOT}" REPO_KEY)
        endif()
        if(NOT "${REPO_KEY}" IN_LIST REPO_LIST)
            list(APPEND REPO_LIST "${REPO_KEY}")
            set(REPO_ROOT_${REPO_KEY} "${REPO_ROOT}")
            set(REPO_MODULES_${REPO_KEY} "")
        endif()
        list(APPEND REPO_MODULES_${REPO_KEY} "${MODULE_DIR}")
    endforeach()

    set(RESULTS "")
    foreach(REPO_KEY IN LISTS REPO_LIST)
        Updater_Update_Repo("${REPO_ROOT_${REPO_KEY}}" "${REPO_MODULES_${REPO_KEY}}" "${VERSION_LIST}" "${PROJECT_ROOT}" RESULTS)
    endforeach()

    message(STATUS "================================================================================")
    message(STATUS "Update summary")
    message(STATUS "================================================================================")
    foreach(RESULT_LINE IN LISTS RESULTS)
        message(STATUS "${RESULT_LINE}")
    endforeach()

endfunction()


#==============================================================================#
# Main functionality
# Usage:
# cmake -DFUNCTION_ID="VERSION_LIST" -P Updater.cmake : List available updates
# cmake -DFUNCTION_ID="MODULE_LIST"  -P Updater.cmake : List modules of the project
# cmake -DFUNCTION_ID="UPDATE" [options] -P Updater.cmake : Update modules
#   FROM_VERSION_ID / TO_VERSION_ID   - range of updates by IDs of the list
#                                       (empty or 0 = first / latest)
#   UPDATE_FROM_VERSION / UPDATE_TO_VERSION - range of updates by versions
#   MODULE_IDS     - module IDs of the list separated by comma (empty or 0 = all)
#   UPDATE_MODULES - module folders relative to the project root separated by comma
#   UPDATE_BRANCHES - branches of the module repositories separated by comma,
#                    "*" and "?" patterns allowed (e.g. "Dev/STM32F4/*"),
#                    local and "origin" branches; empty = checked out branches
#   UPDATE_MODE    - DRY_RUN (default, changes shown and reverted), APPLY (checked
#                    out branches only, changes kept), COMMIT (changes committed)
#   UPDATE_COMMIT_MESSAGE - commit message of COMMIT mode
#   UPDATE_PUSH    - ON: committed branches are pushed to "origin"
#   UPDATE_PROJECT_ROOT - project root (default: project of this EmBi_Platform)
# cmake -DTARGET_VERSION="1.0.3" -P Updater.cmake : Update all modules (checked
#   out branches) from actual platform version to required one
#==============================================================================#
if(CMAKE_SCRIPT_MODE_FILE AND
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)

    if("${FUNCTION_ID}" STREQUAL "VERSION_LIST")

        Updater_Print_VersionList()

    elseif("${FUNCTION_ID}" STREQUAL "MODULE_LIST")

        Updater_Print_ModuleList()

    elseif("${FUNCTION_ID}" STREQUAL "UPDATE")

        Updater_Update_Modules()

    elseif(DEFINED TARGET_VERSION)

        # Read list of available updates
        Updater_Get_UpdatesVersionList(VERSIONS_LIST)

        # Read actual version of project
        Platform_VersionHandler_Get_Version(PROJECT_VERSION)

        # Filter applicable updates for project
        foreach(VERSION_ID IN LISTS VERSIONS_LIST)

            if(((TARGET_VERSION VERSION_GREATER VERSION_ID) OR
                (TARGET_VERSION VERSION_EQUAL VERSION_ID  )    ) AND
                (PROJECT_VERSION VERSION_LESS VERSION_ID       )     )

                message(DEBUG "Processing update to version: ${VERSION_ID}")

                # Version to be processed.
                Updater_RunVersionUpdate(${VERSION_ID})

            endif()

        endforeach()

    else()

        message(FATAL_ERROR "FUNCTION_ID (VERSION_LIST, MODULE_LIST, UPDATE) or TARGET_VERSION is required.")

    endif()

endif()
