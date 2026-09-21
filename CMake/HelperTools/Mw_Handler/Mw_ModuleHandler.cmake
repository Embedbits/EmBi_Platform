# ==============================================================================
#
# Middlewares (MW) module handler CMake script.
#
# The Middlewares catalog repository (see SysConfig_Get_MwRepoURL) only ever
# serves as a CATALOG of available middleware components: it declares one
# GIT submodule per component (e.g. FreeRTOS, u8g2, ...) in its own
# .gitmodules, each pointing at that component's OWN repository. Every
# component versions its own releases with GIT tags on its own repository -
# the catalog repository itself is never version-pinned, it is always
# re-fetched to discover the current list of components.
#
# Selecting a component (Mw_ModuleHandler_Config) results in TWO folders
# being created in the project:
#
#   Middlewares/ThirdParty/<Name>/   The component's vendor source, added as
#                                    a real GIT submodule pointing directly
#                                    at its own repository, checked out at
#                                    the selected version (a GIT tag, or the
#                                    "Latest" sentinel - the newest tag).
#                                    Never edited by hand - anything written
#                                    here is lost on the next version switch.
#
#   Middlewares/<Name>/              A project-side handler/wrapper module,
#                                    scaffolded once (via the same ModuleInit
#                                    used by Setup.bat/sh's "Create module"
#                                    option 1 - see SwModule_Handler/ModuleInit.cmake)
#                                    and never overwritten afterwards - this
#                                    is where the user's own glue/port code
#                                    and configuration for the component goes.
#
# Both are wired into the build via add_subdirectory() entries appended to
# Middlewares/Middlewares.cmake - the handler folder always, the ThirdParty
# folder only once it has its own CMakeLists.txt (most vendored libraries do
# not ship one that fits this project's conventions out of the box).
#
# User can execute configuration of a Middlewares module through this CMake
# script.
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

# Set path to the module-init handler module (the same "Create module"
# generator Setup.bat/sh's option 1 uses - Module.c/.h/_Port.h/_Types.h +
# CMakeLists.txt) - reused here to scaffold the project-side handler folder,
# instead of a Mw-specific template.
get_filename_component(MODULE_INIT_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/../SwModule_Handler/ModuleInit.cmake" REALPATH)

# Include module-init handler module
include("${MODULE_INIT_FILE_PATH}")

# Read MW repository URL
SysConfig_Get_MwRepoURL(MW_REPO_URL)

# Read project root folder path
SysConfig_Get_ProjectRootPath(PROJECT_ROOT_PATH)


# Middlewares (MW) component path relative to project root path.
set(MW_REL_PATH "Middlewares")

# Vendored (GIT submodule) middleware sources path, relative to project root.
set(MW_THIRDPARTY_REL_PATH "${MW_REL_PATH}/ThirdParty")

# Middlewares (MW) catalog cache path - a clone of the MW_REPO_URL catalog
# repository itself, NOT where the selected components end up.
set(CACHE_PATH "${CMAKE_CURRENT_LIST_DIR}/Cache")


# ------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_CacheInit
# Description:
#   Initializes the MW catalog cache (if needed). If the cache already
#   exists, it is refreshed to the latest commit of the catalog's default
#   branch every time, so a middleware component newly registered (or
#   removed) in the catalog shows up without the user having to delete the
#   Cache/ folder by hand - the catalog itself carries no version to pin.
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

        # 1️: Execute initial MW catalog repository clone without submodules
        GitHandler_CloneMin(${MW_REPO_URL} ${CACHE_PATH})

    else()

        # Catalog already cloned - always advance it to the latest commit of
        # its default branch (GitHandler_SwitchBranch checks out FETCH_HEAD,
        # so a local branch left over from a previous run is never silently
        # reused).
        GitHandler_GetDefaultBranch(${MW_REPO_URL} MW_DEFAULT_BRANCH)

        if(NOT "${MW_DEFAULT_BRANCH}" STREQUAL "")
            GitHandler_SwitchBranch(${CACHE_PATH} ${MW_DEFAULT_BRANCH})
        else()
            message(WARNING "Could not resolve the Middlewares catalog's default branch - using whatever is currently cached.")
        endif()

    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_FolderStructInit
# Description:
#   Initialization of Mw module folder structure.
#   The necessary sub-folders and files are created with following structure:
#   Project root/
#   ├── Application              (Application layer module)
#   ├── Middlewares*             (Middlewares layer module)
#   │   ├── Middlewares.cmake*   (Middlewares root CMakeList file)
#   │   └── ThirdParty*          (Vendored middleware sources, one GIT
#   │                             submodule per selected component)
#   │
#   ├── Bsp                      (Board Support Packages layer module)
#   └── Stm_Template             (Template handler module)
#
# (* - newly created)
# ------------------------------------------------------------------------------
function(Mw_ModuleHandler_FolderStructInit)

    file(MAKE_DIRECTORY "${PROJECT_ROOT_PATH}/${MW_REL_PATH}")
    file(MAKE_DIRECTORY "${PROJECT_ROOT_PATH}/${MW_THIRDPARTY_REL_PATH}")

    set(OUTPUT_PATH "${PROJECT_ROOT_PATH}/${MW_REL_PATH}/Middlewares.cmake")
    set(CONTENT " ")

    if(NOT EXISTS "${OUTPUT_PATH}")
        file(WRITE "${OUTPUT_PATH}" "${CONTENT}")
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_UpdateCMakeLists
# Description:
#   Appends an add_subdirectory() entry for IN_REL_SUBDIR into the
#   Middlewares root CMakeLists (Middlewares/Middlewares.cmake), unless that
#   exact entry is already present. IN_REL_SUBDIR is always relative to
#   Middlewares/ itself (e.g. "FreeRTOS" for the handler folder, or
#   "ThirdParty/FreeRTOS" for the vendored submodule) - matched as the exact
#   generated add_subdirectory() line, rather than a bare name substring, so
#   a handler folder and its ThirdParty counterpart sharing the same base
#   name never false-positive against each other.
#
# IN_REL_SUBDIR [in]: Sub-folder to add, relative to Middlewares/.
# ------------------------------------------------------------------------------
function(Mw_ModuleHandler_UpdateCMakeLists IN_REL_SUBDIR)

    set(MW_CMAKELIST_PATH "${PROJECT_ROOT_PATH}/${MW_REL_PATH}/Middlewares.cmake")
    set(NEW_LINE "add_subdirectory(\${CMAKE_CURRENT_LIST_DIR}/${IN_REL_SUBDIR})")

    if(EXISTS "${MW_CMAKELIST_PATH}")
        file(READ "${MW_CMAKELIST_PATH}" EXISTING_CONTENT)

        # Check if this exact add_subdirectory() line already exists - a
        # plain substring search (string(FIND ...)) rather than MATCHES,
        # since NEW_LINE contains "(", ")" and "$" which are regex
        # metacharacters (a "$" in particular would anchor to end-of-string
        # mid-pattern and make MATCHES never find a real match at all).
        string(FIND "${EXISTING_CONTENT}" "${NEW_LINE}" LINE_FOUND_INDEX)
        if(NOT LINE_FOUND_INDEX EQUAL -1)
            message(STATUS "'${IN_REL_SUBDIR}' already in Middlewares.cmake")
            return()
        endif()

        # Append to the end
        string(APPEND EXISTING_CONTENT "\n${NEW_LINE}")
        file(WRITE "${MW_CMAKELIST_PATH}" "${EXISTING_CONTENT}")
    else()
        # Create new file
        file(WRITE "${MW_CMAKELIST_PATH}" "${NEW_LINE}\n")
    endif()

    message(STATUS "Added '${IN_REL_SUBDIR}' to Middlewares.cmake")
endfunction()


# ------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_GetModuleList
# Description:
#   Refreshes the MW catalog cache and returns the list of available
#   middleware components declared in its .gitmodules (name/URL/active).
#
# OUT_NAMES   [out]: List of middleware component names.
# OUT_URLS    [out]: List of middleware component repository URLs.
# OUT_ACTIVES [out]: List of middleware component active states.
# OUT_COUNT   [out]: Count of available middleware components.
# ------------------------------------------------------------------------------
function(Mw_ModuleHandler_GetModuleList OUT_NAMES OUT_URLS OUT_ACTIVES OUT_COUNT)

    Mw_ModuleHandler_CacheInit()

    GitHandler_GetSubmoduleList(${CACHE_PATH}
                                MODULE_NAMES
                                MODULE_URLS
                                MODULE_ACTIVES
                                MODULE_COUNT)

    set(${OUT_NAMES}   ${MODULE_NAMES}   PARENT_SCOPE)
    set(${OUT_URLS}    ${MODULE_URLS}    PARENT_SCOPE)
    set(${OUT_ACTIVES} ${MODULE_ACTIVES} PARENT_SCOPE)
    set(${OUT_COUNT}   ${MODULE_COUNT}   PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_GetVersionList
# Description:
#   Returns the sorted (oldest -> newest, natural/semver order) list of GIT
#   tags available on the given middleware component's OWN repository - each
#   component versions itself this way, the catalog repository carries no
#   version information at all. If the component has no tags yet,
#   OUT_TAG_LIST comes back empty and OUT_FALLBACK_BRANCH is set to its
#   default branch instead, so callers can still offer a "latest commit of
#   the default branch" option rather than failing outright.
#
# IN_REPO_URL          [in]: Middleware component repository URL.
# OUT_TAG_LIST        [out]: Sorted list of GIT tags (may be empty).
# OUT_FALLBACK_BRANCH [out]: Default branch name - only meaningful/non-empty
#                             when OUT_TAG_LIST came back empty.
# ------------------------------------------------------------------------------
function(Mw_ModuleHandler_GetVersionList IN_REPO_URL OUT_TAG_LIST OUT_FALLBACK_BRANCH)

    GitHandler_ListRemoteTags(${IN_REPO_URL} TAG_LIST)

    if(TAG_LIST)
        list(SORT TAG_LIST COMPARE NATURAL)
        set(${OUT_TAG_LIST} ${TAG_LIST} PARENT_SCOPE)
        set(${OUT_FALLBACK_BRANCH} "" PARENT_SCOPE)
    else()
        message(WARNING "Component at '${IN_REPO_URL}' has no GIT tags yet - falling back to its default branch.")
        GitHandler_GetDefaultBranch(${IN_REPO_URL} DEFAULT_BRANCH)
        set(${OUT_TAG_LIST} "" PARENT_SCOPE)
        set(${OUT_FALLBACK_BRANCH} "${DEFAULT_BRANCH}" PARENT_SCOPE)
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_ResolveVersionRef
# Description:
#   Resolves a numerical IN_VERSION_ID (as printed by
#   Mw_ModuleHandler_PrintVersionList) into an actual GIT ref (a tag name, or
#   the fallback default branch name) to check the component out at.
#
#   IN_VERSION_ID = 0 always means "Latest" - the newest tag (last entry
#   after the natural sort), or the fallback default branch if the
#   component has no tags yet. Any other value selects that exact tag from
#   the sorted list (1 = oldest tag, highest number = newest tag).
#
#   NOTE this "0" convention differs from the "0 = Return back / cancel"
#   convention used for IN_MODULE_ID elsewhere in this file - by the time a
#   version is being resolved, the user has already committed to a
#   component and there is nothing left to cancel; "0" here is a real,
#   actionable selection ("Latest"), not a no-op.
#
# IN_REPO_URL      [in]: Middleware component repository URL.
# IN_VERSION_ID    [in]: Numerical version selection (0 = Latest).
# OUT_VERSION_REF [out]: Resolved GIT ref (tag or branch name) to check out.
# ------------------------------------------------------------------------------
function(Mw_ModuleHandler_ResolveVersionRef IN_REPO_URL IN_VERSION_ID OUT_VERSION_REF)

    Mw_ModuleHandler_GetVersionList(${IN_REPO_URL} TAG_LIST FALLBACK_BRANCH)

    if(NOT TAG_LIST)

        if("${FALLBACK_BRANCH}" STREQUAL "")
            message(FATAL_ERROR "Could not resolve any version (no tags, no default branch) for '${IN_REPO_URL}'.")
        endif()

        message(STATUS "No tags available yet - using latest commit of default branch '${FALLBACK_BRANCH}'.")
        set(${OUT_VERSION_REF} "${FALLBACK_BRANCH}" PARENT_SCOPE)
        return()

    endif()

    if(IN_VERSION_ID EQUAL 0)
        list(GET TAG_LIST -1 LATEST_TAG)
        set(${OUT_VERSION_REF} "${LATEST_TAG}" PARENT_SCOPE)
        return()
    endif()

    math(EXPR TAG_INDEX "${IN_VERSION_ID} - 1")
    list(GET TAG_LIST ${TAG_INDEX} SELECTED_TAG)
    set(${OUT_VERSION_REF} "${SELECTED_TAG}" PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_HandlerFolderInit
# Description:
#   Scaffolds the project-side handler folder Middlewares/<Name>/ for a
#   middleware component by reusing ModuleInit (SwModule_Handler/ModuleInit.cmake -
#   the exact same generator behind Setup.bat/sh's "Create module" option 1),
#   rather than a Mw-specific template. This produces the standard module
#   shape - <Name>.c, <Name>.h, <Name>_Port.h, <Name>_Types.h, CMakeLists.txt -
#   directly under Middlewares/<Name>/.
#
#   ModuleInit only ever creates a file that does not already exist, so this
#   is safe to call again on every Mw_ModuleHandler_Config run - an already
#   existing handler file (the user's own port layer, configuration, glue)
#   is never overwritten by a later re-configuration or version switch.
#
# IN_MODULE_NAME [in]: Middleware component name (e.g. "FreeRTOS").
# ------------------------------------------------------------------------------
function(Mw_ModuleHandler_HandlerFolderInit IN_MODULE_NAME)

    ModuleInit("${MW_REL_PATH}" "${IN_MODULE_NAME}")

endfunction()


# ------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_ThirdPartyWireBuild
# Description:
#   Adds an add_subdirectory() entry for Middlewares/ThirdParty/<Name> ONLY
#   if that vendored folder actually contains its own CMakeLists.txt - most
#   third-party libraries do not ship one that fits this project's build
#   conventions out of the box, in which case the handler folder
#   (Middlewares/<Name>/, see Mw_ModuleHandler_HandlerFolderInit) is the only
#   thing wired into the build, and the user is expected to reference the
#   vendored sources directly from there instead.
#
# IN_MODULE_NAME [in]: Middleware component name (e.g. "FreeRTOS").
# ------------------------------------------------------------------------------
function(Mw_ModuleHandler_ThirdPartyWireBuild IN_MODULE_NAME)

    set(THIRDPARTY_PATH "${PROJECT_ROOT_PATH}/${MW_THIRDPARTY_REL_PATH}/${IN_MODULE_NAME}")

    if(EXISTS "${THIRDPARTY_PATH}/CMakeLists.txt")
        Mw_ModuleHandler_UpdateCMakeLists("ThirdParty/${IN_MODULE_NAME}")
    else()
        message(STATUS "'${IN_MODULE_NAME}' has no CMakeLists.txt of its own under ThirdParty/ - only the handler folder was wired into the build.")
    endif()

endfunction()


#-------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_Config
#
# Description:
# Adds (or switches the version of) a single middleware component:
#   1. The component is resolved from the catalog by IN_MODULE_ID.
#   2. IN_VERSION_ID is resolved into an actual GIT tag (or fallback branch)
#      on the component's OWN repository - see
#      Mw_ModuleHandler_ResolveVersionRef.
#   3. The component is added as a GIT submodule under
#      Middlewares/ThirdParty/<Name> (first time only) and switched to the
#      resolved version (every time - this is also how an already-added
#      component's version is CHANGED: run this again with a different
#      IN_VERSION_ID).
#   4. The project-side handler folder Middlewares/<Name> is scaffolded
#      (first time only, never overwritten afterwards).
#   5. Both folders are wired into Middlewares/Middlewares.cmake.
#
# IN_MODULE_ID  [in]: Middleware component numerical identification (e.g. 1
#                      for the first component in the catalog).
# IN_VERSION_ID [in]: Version numerical identification (0 = Latest tag, see
#                      Mw_ModuleHandler_ResolveVersionRef).
#-------------------------------------------------------------------------------
function(Mw_ModuleHandler_Config IN_MODULE_ID IN_VERSION_ID)

    Mw_ModuleHandler_GetModuleList(MODULE_NAMES MODULE_URLS MODULE_ACTIVES MODULE_COUNT)

    list(GET MODULE_NAMES ${IN_MODULE_ID} SUB_NAME)
    list(GET MODULE_URLS ${IN_MODULE_ID} SUB_URL)
    list(GET MODULE_ACTIVES ${IN_MODULE_ID} SUB_ACTIVE)

    message(STATUS "*********************************************************")
    message(STATUS "Processing middleware: ${SUB_NAME}")
    message(DEBUG "  URL: ${SUB_URL}")
    message(STATUS "*********************************************************")

    Mw_ModuleHandler_FolderStructInit()

    Mw_ModuleHandler_ResolveVersionRef(${SUB_URL} ${IN_VERSION_ID} VERSION_REF)

    message(STATUS "Version '${VERSION_REF}' selected for '${SUB_NAME}'.")

    # ------------------------------------------------------
    # Add git submodule under Middlewares/ThirdParty/<Name>
    # ------------------------------------------------------
    set(LOCAL_SUB_PATH "${PROJECT_ROOT_PATH}/${MW_THIRDPARTY_REL_PATH}/${SUB_NAME}")

    if(EXISTS "${LOCAL_SUB_PATH}/.git")

        message(DEBUG "Module already found in ${LOCAL_SUB_PATH}")

    else()

        GitHandler_SubmoduleInit(${SUB_URL} "${MW_THIRDPARTY_REL_PATH}/${SUB_NAME}" ${SUB_ACTIVE} SUB_IS_SUBMODULE)

        # Ignore submodule changes in parent directory (meaningless for a
        # plain clone fallback - EmBi platform is not itself a GIT repo)
        if(SUB_IS_SUBMODULE)
            GitHandler_SubmoduleIgnore("${MW_THIRDPARTY_REL_PATH}/${SUB_NAME}" "dirty")
        endif()

    endif()

    # Always (re-)switch to the resolved version - this is what actually
    # changes the version of an already-added component too.
    GitHandler_SwitchBranch(${LOCAL_SUB_PATH} ${VERSION_REF})

    # ------------------------------------------------------
    # Scaffold the project-side handler folder and wire both
    # folders into the build.
    # ------------------------------------------------------
    Mw_ModuleHandler_HandlerFolderInit(${SUB_NAME})

    Mw_ModuleHandler_UpdateCMakeLists("${SUB_NAME}")

    Mw_ModuleHandler_ThirdPartyWireBuild(${SUB_NAME})

    # Copy the catalog repository's own root files (README.md, LICENSE.md,
    # ...) into the project's Middlewares/ folder, same as the BSP module
    # does for Bsp/ - .gitmodules is skipped, it is meaningless outside the
    # catalog clone itself.
    file(GLOB CATALOG_ROOT_FILES "${CACHE_PATH}/*")

    foreach(FILE_NAME ${CATALOG_ROOT_FILES})
        get_filename_component(BASE_NAME "${FILE_NAME}" NAME)
        if(NOT IS_DIRECTORY "${FILE_NAME}" AND NOT "${BASE_NAME}" STREQUAL ".gitmodules")
            file(COPY "${FILE_NAME}" DESTINATION "${PROJECT_ROOT_PATH}/${MW_REL_PATH}")
        endif()
    endforeach()

    message(STATUS "Middlewares (MW) module '${SUB_NAME}' initialization complete (version '${VERSION_REF}').")

endfunction()


# ------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_Update
# Description:
#   Updates a single, already-added middleware component
#   (Middlewares/ThirdParty/<Name>) to the LATEST GIT tag available on its
#   own repository (or the latest commit of its default branch, if it still
#   has no tags). Unlike Mw_ModuleHandler_Config, this never touches the
#   handler folder or Middlewares.cmake - only the vendored submodule's
#   checked-out version.
#
#   If the component was never added yet, nothing is updated - run
#   "Configure Middleware module" first.
#
# IN_MODULE_ID [in]: Middleware component numerical identification, same
#                     indexing as Mw_ModuleHandler_Config.
# ------------------------------------------------------------------------------
function(Mw_ModuleHandler_Update IN_MODULE_ID)

    Mw_ModuleHandler_GetModuleList(MODULE_NAMES MODULE_URLS MODULE_ACTIVES MODULE_COUNT)

    list(GET MODULE_NAMES ${IN_MODULE_ID} SUB_NAME)
    list(GET MODULE_URLS ${IN_MODULE_ID} SUB_URL)

    set(LOCAL_SUB_PATH "${PROJECT_ROOT_PATH}/${MW_THIRDPARTY_REL_PATH}/${SUB_NAME}")

    if(NOT EXISTS "${LOCAL_SUB_PATH}/.git")
        message(WARNING "Middleware '${SUB_NAME}' is not initialized yet under '${MW_THIRDPARTY_REL_PATH}' - run 'Configure Middleware module' first.")
        return()
    endif()

    Mw_ModuleHandler_ResolveVersionRef(${SUB_URL} 0 LATEST_VERSION_REF)

    message(STATUS "Updating '${SUB_NAME}' to latest version '${LATEST_VERSION_REF}'...")

    GitHandler_SwitchBranch(${LOCAL_SUB_PATH} ${LATEST_VERSION_REF})

    message(STATUS "Middleware '${SUB_NAME}' update complete (version '${LATEST_VERSION_REF}').")

endfunction()


# ------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_PrintModuleList
# Description: Prints all available middleware components found in the
#              catalog repository.
# ------------------------------------------------------------------------------
function(Mw_ModuleHandler_PrintModuleList)

    Mw_ModuleHandler_GetModuleList(MODULE_NAMES MODULE_URLS MODULE_ACTIVES MODULE_COUNT)

    math(EXPR LIST_SIZE "${MODULE_COUNT} - 1")

    message("[0]: Return back")

    foreach(LIST_INDEX RANGE ${LIST_SIZE})

        list(GET MODULE_NAMES ${LIST_INDEX} MODULE_NAME)
        math(EXPR DISPLAY_INDEX "${LIST_INDEX} + 1")
        message("[${DISPLAY_INDEX}]: ${MODULE_NAME}")

    endforeach()
endfunction()


# ------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_PrintVersionList
# Description:
#   Prints all available versions (GIT tags) for the middleware component
#   selected by IN_MODULE_ID, plus a "[0]: Latest" entry that always selects
#   the newest one - see Mw_ModuleHandler_ResolveVersionRef for how
#   IN_VERSION_ID maps back to an actual GIT ref.
#
# IN_MODULE_ID [in]: Middleware component numerical identification.
# ------------------------------------------------------------------------------
function(Mw_ModuleHandler_PrintVersionList IN_MODULE_ID)

    Mw_ModuleHandler_GetModuleList(MODULE_NAMES MODULE_URLS MODULE_ACTIVES MODULE_COUNT)

    list(GET MODULE_NAMES ${IN_MODULE_ID} SUB_NAME)
    list(GET MODULE_URLS ${IN_MODULE_ID} SUB_URL)

    Mw_ModuleHandler_GetVersionList(${SUB_URL} TAG_LIST FALLBACK_BRANCH)

    message("Available versions for '${SUB_NAME}':")

    if(NOT TAG_LIST)
        message("[0]: Latest (no tags yet - latest commit of '${FALLBACK_BRANCH}')")
        return()
    endif()

    list(LENGTH TAG_LIST TAG_COUNT)
    math(EXPR LIST_SIZE "${TAG_COUNT} - 1")

    list(GET TAG_LIST -1 NEWEST_TAG)
    message("[0]: Latest (${NEWEST_TAG})")

    foreach(LIST_INDEX RANGE ${LIST_SIZE})

        list(GET TAG_LIST ${LIST_INDEX} TAG_NAME)
        math(EXPR DISPLAY_INDEX "${LIST_INDEX} + 1")
        message("[${DISPLAY_INDEX}]: ${TAG_NAME}")

    endforeach()
endfunction()


#==============================================================================#
# Main functionality
# Usage:
# cmake -DFUNCTION_ID="MODULE_LIST"                               -P Mw_ModuleHandler.cmake : List available middleware components
# cmake -DFUNCTION_ID="VERSION_LIST" -DMODULE_ID=2                -P Mw_ModuleHandler.cmake : List available versions of component 2
# cmake -DFUNCTION_ID="MW_CONFIG"    -DMODULE_ID=2 -DVERSION_ID=0  -P Mw_ModuleHandler.cmake : Add/switch component 2 to its latest version
# cmake -DFUNCTION_ID="MW_UPDATE"    -DMODULE_ID=2                 -P Mw_ModuleHandler.cmake : Update already-added component 2 to its latest version
#==============================================================================#
if(CMAKE_SCRIPT_MODE_FILE AND
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)

    if("${FUNCTION_ID}" STREQUAL "MODULE_LIST")

        Mw_ModuleHandler_PrintModuleList()

    elseif("${FUNCTION_ID}" STREQUAL "VERSION_LIST")

        if(DEFINED MODULE_ID AND "${MODULE_ID}" MATCHES "^[0-9]+$" AND MODULE_ID GREATER 0)

            math(EXPR REAL_MODULE_INDEX "${MODULE_ID} - 1")
            Mw_ModuleHandler_PrintVersionList(${REAL_MODULE_INDEX})

        else()

            message(FATAL_ERROR "Required MODULE_ID is not correct.")

        endif()

    elseif("${FUNCTION_ID}" STREQUAL "MW_CONFIG")

        if(DEFINED MODULE_ID AND "${MODULE_ID}" MATCHES "^[0-9]+$" AND MODULE_ID GREATER 0 AND
           DEFINED VERSION_ID AND "${VERSION_ID}" MATCHES "^[0-9]+$")

            math(EXPR REAL_MODULE_INDEX "${MODULE_ID} - 1")
            Mw_ModuleHandler_Config(${REAL_MODULE_INDEX} ${VERSION_ID})

        else()

            message(FATAL_ERROR "Required MODULE_ID and/or VERSION_ID is not correct.")

        endif()

    elseif("${FUNCTION_ID}" STREQUAL "MW_UPDATE")

        if(DEFINED MODULE_ID AND "${MODULE_ID}" MATCHES "^[0-9]+$" AND MODULE_ID GREATER 0)

            math(EXPR REAL_MODULE_INDEX "${MODULE_ID} - 1")
            Mw_ModuleHandler_Update(${REAL_MODULE_INDEX})

        else()

            message(FATAL_ERROR "Required MODULE_ID is not correct.")

        endif()

    else()

        Mw_ModuleHandler_PrintModuleList()

    endif()

endif()
