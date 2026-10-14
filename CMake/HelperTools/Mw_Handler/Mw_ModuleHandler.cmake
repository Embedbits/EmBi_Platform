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
#   Middlewares/Core/<Name>/   The component's vendor source, added as
#                              a real GIT submodule pointing directly
#                              at its own repository, checked out at
#                              the selected version (a GIT tag, or the
#                              "Latest" sentinel - the newest tag).
#                              Never edited by hand - anything written
#                              here is lost on the next version switch.
#
#   Middlewares/<Name>App/     A project-side handler/wrapper module,
#                              scaffolded once (via the same ModuleInit
#                              used by Setup.bat/sh's "Create module"
#                              option 1 - see SwModule_Handler/ModuleInit.cmake)
#                              and never overwritten afterwards - this
#                              is where the user's own glue/port code
#                              and configuration for the component goes.
#                              Suffixed with MW_APP_SUFFIX ("App") so the
#                              folder, its files and its CMake library
#                              (<Name>App_Lib) never collide with the
#                              vendored component's own names.
#
# Both are wired into the build:
#
#   Middlewares/Middlewares.cmake    add_subdirectory() per handler folder
#                                    (Middlewares/<Name>App) plus exactly one
#                                    add_subdirectory() for Core/.
#
#   Middlewares/Core/CMakeLists.txt  Regenerated from scratch on every
#                                    configuration/update run (same idea as
#                                    Bsp/Mcal/CMakeLists.txt) - one
#                                    add_subdirectory() per vendored
#                                    component that ships its own
#                                    CMakeLists.txt at the checked-out
#                                    version. A component without one is
#                                    listed as a comment only, so the
#                                    project still configures.
#
# A vendored component whose own CMakeLists.txt cannot be used (it needs an
# RTOS port, builds every part of the component, ...) is built by its handler
# module: the file Middlewares/<Name>App/CoreBuild.cmake (created by the user,
# never overwritten) defines the sources, options and libraries of the
# component and is included by the CMakeLists.txt of the handler module.
# Core/CMakeLists.txt lists such a component as a comment only (the CMake
# file of the component is not added).
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
set(MW_CORE_REL_PATH "${MW_REL_PATH}/Core")

# Suffix appended to a component name to form its project-side handler
# module name (folder, files, CMake library) - e.g. "ModBus" -> "ModBusApp".
set(MW_APP_SUFFIX "App")

# Name of the file of a handler module which builds its vendored component
# itself (see the header of this file) - e.g. Middlewares/USBXApp/CoreBuild.cmake.
set(MW_CORE_BUILD_FILE "CoreBuild.cmake")

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
#   │   └── Core*                (Vendored middleware sources, one GIT
#   │       │                     submodule per selected component)
#   │       └── CMakeLists.txt*  (Generated, add_subdirectory() per component)
#   │
#   ├── Bsp                      (Board Support Packages layer module)
#   └── Stm_Template             (Template handler module)
#
# (* - newly created)
# ------------------------------------------------------------------------------
function(Mw_ModuleHandler_FolderStructInit)

    file(MAKE_DIRECTORY "${PROJECT_ROOT_PATH}/${MW_REL_PATH}")
    file(MAKE_DIRECTORY "${PROJECT_ROOT_PATH}/${MW_CORE_REL_PATH}")

    set(OUTPUT_PATH "${PROJECT_ROOT_PATH}/${MW_REL_PATH}/Middlewares.cmake")
    set(CONTENT " ")

    if(NOT EXISTS "${OUTPUT_PATH}")
        file(WRITE "${OUTPUT_PATH}" "${CONTENT}")
    endif()

    # Core/ is always wired exactly once - which vendored components
    # it actually builds is decided by the generated
    # Core/CMakeLists.txt (see Mw_ModuleHandler_CoreCMakeListsGenerate).
    Mw_ModuleHandler_CoreFirst()

endfunction()


# ------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_CoreFirst
# Description:
#   Keeps the Core add_subdirectory() entry as the very first entry of
#   the Middlewares root CMakeLists (Middlewares/Middlewares.cmake). Vendored
#   middleware libraries (freertos_kernel, ...) must already exist when the
#   project handler modules linking them are processed. Every existing
#   occurrence of the entry is removed and the entry is prepended, so a file
#   with a different order is fixed on the next configuration run too.
# ------------------------------------------------------------------------------
function(Mw_ModuleHandler_CoreFirst)

    set(MW_CMAKELIST_PATH "${PROJECT_ROOT_PATH}/${MW_REL_PATH}/Middlewares.cmake")
    set(CORE_LINE "add_subdirectory(\${CMAKE_CURRENT_LIST_DIR}/Core)")

    set(EXISTING_CONTENT "")
    if(EXISTS "${MW_CMAKELIST_PATH}")
        file(READ "${MW_CMAKELIST_PATH}" EXISTING_CONTENT)
    endif()

    # Plain string(REPLACE ...) rather than a regex - CORE_LINE contains
    # regex metacharacters ("(", ")", "$"). Matches only the exact Core
    # line, never the legacy per-component "Core/<Name>" ones.
    string(REPLACE "${CORE_LINE}\n" "" NEW_CONTENT "${EXISTING_CONTENT}\n")
    string(STRIP "${NEW_CONTENT}" NEW_CONTENT)

    if(NEW_CONTENT STREQUAL "")
        set(NEW_CONTENT "${CORE_LINE}\n")
    else()
        set(NEW_CONTENT "${CORE_LINE}\n${NEW_CONTENT}\n")
    endif()

    if(NOT "${NEW_CONTENT}" STREQUAL "${EXISTING_CONTENT}")
        file(WRITE "${MW_CMAKELIST_PATH}" "${NEW_CONTENT}")
        message(STATUS "'Core' placed first in Middlewares.cmake")
    endif()

endfunction()


# ------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_UpdateCMakeLists
# Description:
#   Appends an add_subdirectory() entry for IN_REL_SUBDIR into the
#   Middlewares root CMakeLists (Middlewares/Middlewares.cmake), unless that
#   exact entry is already present. IN_REL_SUBDIR is always relative to
#   Middlewares/ itself (e.g. "FreeRTOSApp" for the handler folder, or
#   "Core/FreeRTOS" for the vendored submodule) - matched as the exact
#   generated add_subdirectory() line, rather than a bare name substring, so
#   a handler folder and its Core counterpart sharing the same base
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
        string(STRIP "${EXISTING_CONTENT}" EXISTING_CONTENT)
        string(APPEND EXISTING_CONTENT "\n${NEW_LINE}\n")
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

    # The catalog declares its components relative to itself (e.g.
    # "../ModBus") - resolve them against the catalog URL, otherwise
    # ls-remote / submodule add would resolve them against the current
    # directory or the project's own remote.
    set(ABS_MODULE_URLS "")
    foreach(MODULE_URL ${MODULE_URLS})
        GitHandler_ResolveRelativeUrl(${MW_REPO_URL} ${MODULE_URL} ABS_MODULE_URL)
        list(APPEND ABS_MODULE_URLS "${ABS_MODULE_URL}")
    endforeach()

    set(${OUT_NAMES}   ${MODULE_NAMES}   PARENT_SCOPE)
    set(${OUT_URLS}    ${ABS_MODULE_URLS} PARENT_SCOPE)
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
#   Scaffolds the project-side handler folder Middlewares/<Name>App/ for a
#   middleware component by reusing ModuleInit (SwModule_Handler/ModuleInit.cmake -
#   the exact same generator behind Setup.bat/sh's "Create module" option 1),
#   rather than a Mw-specific template. This produces the standard module
#   shape - <Name>App.c, <Name>App.h, <Name>App_Port.h, <Name>App_Types.h,
#   CMakeLists.txt (library <Name>App_Lib) - directly under
#   Middlewares/<Name>App/. MW_APP_SUFFIX keeps the handler module's names
#   distinct from the vendored component in Core/<Name>.
#
#   ModuleInit only ever creates a file that does not already exist, so this
#   is safe to call again on every Mw_ModuleHandler_Config run - an already
#   existing handler file (the user's own port layer, configuration, glue)
#   is never overwritten by a later re-configuration or version switch.
#
# IN_MODULE_NAME [in]: Middleware component name (e.g. "FreeRTOS").
# ------------------------------------------------------------------------------
function(Mw_ModuleHandler_HandlerFolderInit IN_MODULE_NAME)

    ModuleInit("${MW_REL_PATH}" "${IN_MODULE_NAME}${MW_APP_SUFFIX}")

endfunction()


# ------------------------------------------------------------------------------
# Function: Mw_ModuleHandler_CoreCMakeListsGenerate
# Description:
#   (Re)generates Middlewares/Core/CMakeLists.txt from scratch, so it
#   add_subdirectory()'s every vendored middleware component currently
#   present under Middlewares/Core/ (a child folder counts only if it
#   contains a real checkout - its own ".git" file/folder). Mirrors
#   Bsp_ModuleHandler_McalCMakeListsGenerate for Bsp/Mcal.
#
#   Only a component that ships its own CMakeLists.txt at the currently
#   checked-out version gets a real add_subdirectory() line - add_subdirectory()
#   on a folder without one is a hard configure error. Such a component is
#   written as a commented-out line instead (with a note), and a WARNING is
#   printed, so the user sees it and the project still configures.
#
#   Also removes any legacy per-component "Core/<Name>" entry from
#   Middlewares/Middlewares.cmake (written by older versions of this script),
#   which would otherwise add the same folder twice now that Core/ is
#   wired as a whole.
#
#   Always regenerated (never appended), so it stays in sync with whatever
#   components/versions are actually checked out - including after a
#   version switch that adds or drops a component's CMakeLists.txt.
# ------------------------------------------------------------------------------
function(Mw_ModuleHandler_CoreCMakeListsGenerate)

    set(CORE_ROOT "${PROJECT_ROOT_PATH}/${MW_CORE_REL_PATH}")
    set(CORE_CMAKE_PATH "${CORE_ROOT}/CMakeLists.txt")

    file(MAKE_DIRECTORY "${CORE_ROOT}")

    # Collect vendored component folders (sorted for a stable output)
    file(GLOB CORE_CHILDREN LIST_DIRECTORIES true "${CORE_ROOT}/*")
    list(SORT CORE_CHILDREN)

    set(CONTENT "# Generated by Mw_ModuleHandler.cmake - DO NOT EDIT, regenerated on every\n")
    string(APPEND CONTENT "# Middleware configuration/update run.\n")

    set(WIRED_COUNT 0)
    set(HANDLER_BUILT_COUNT 0)

    foreach(CHILD_PATH ${CORE_CHILDREN})

        if(NOT IS_DIRECTORY "${CHILD_PATH}" OR NOT EXISTS "${CHILD_PATH}/.git")
            continue()
        endif()

        get_filename_component(CHILD_NAME "${CHILD_PATH}" NAME)

        # Component built by its handler module: the handler folder holds
        # CoreBuild.cmake (included by the handler's CMakeLists.txt) which
        # defines the sources, options and library of the component. The
        # CMakeLists.txt of the component is not used (e.g. it requires an RTOS
        # port or builds every part of the component).
        set(HANDLER_BUILD_PATH "${PROJECT_ROOT_PATH}/${MW_REL_PATH}/${CHILD_NAME}${MW_APP_SUFFIX}/${MW_CORE_BUILD_FILE}")

        if(EXISTS "${HANDLER_BUILD_PATH}")
            string(APPEND CONTENT "# ${CHILD_NAME} is built by its handler module (${CHILD_NAME}${MW_APP_SUFFIX}/${MW_CORE_BUILD_FILE}) - the CMakeLists.txt of the component is not used\n")
            math(EXPR HANDLER_BUILT_COUNT "${HANDLER_BUILT_COUNT} + 1")
            continue()
        endif()

        if(EXISTS "${CHILD_PATH}/CMakeLists.txt")
            string(APPEND CONTENT "add_subdirectory(\${CMAKE_CURRENT_LIST_DIR}/${CHILD_NAME})\n")
            math(EXPR WIRED_COUNT "${WIRED_COUNT} + 1")
        else()
            string(APPEND CONTENT "# add_subdirectory(\${CMAKE_CURRENT_LIST_DIR}/${CHILD_NAME}) - no CMakeLists.txt at the checked-out version\n")
            message(WARNING "Middleware '${CHILD_NAME}' has no CMakeLists.txt at its checked-out version - it is NOT built from Core/ (listed as a comment in Core/CMakeLists.txt).")
        endif()

    endforeach()

    if(WIRED_COUNT EQUAL 0 AND HANDLER_BUILT_COUNT EQUAL 0)
        string(APPEND CONTENT "# No vendored middleware component with its own CMakeLists.txt found.\n")
    endif()

    file(WRITE "${CORE_CMAKE_PATH}" "${CONTENT}")

    message(STATUS "Generated '${MW_CORE_REL_PATH}/CMakeLists.txt' (${WIRED_COUNT} component(s) wired, ${HANDLER_BUILT_COUNT} built by the handler).")

    # --------------------------------------------------
    # Remove legacy per-component Core/<Name> lines
    # from Middlewares.cmake (Core/ itself stays).
    # --------------------------------------------------
    set(MW_CMAKELIST_PATH "${PROJECT_ROOT_PATH}/${MW_REL_PATH}/Middlewares.cmake")

    if(EXISTS "${MW_CMAKELIST_PATH}")

        file(READ "${MW_CMAKELIST_PATH}" MW_CONTENT)

        # "[$]" and "[(]"/"[)]" match those characters literally without
        # relying on backslash escapes inside a quoted CMake string.
        string(REGEX REPLACE "\n?add_subdirectory[(][$][{]CMAKE_CURRENT_LIST_DIR[}]/Core/[^)\n]+[)]" "" MW_NEW_CONTENT "${MW_CONTENT}")

        if(NOT "${MW_NEW_CONTENT}" STREQUAL "${MW_CONTENT}")
            file(WRITE "${MW_CMAKELIST_PATH}" "${MW_NEW_CONTENT}")
            message(STATUS "Removed legacy 'Core/<Name>' entries from Middlewares.cmake (Core/ is now wired as a whole).")
        endif()

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
#      Middlewares/Core/<Name> (first time only) and switched to the
#      resolved version (every time - this is also how an already-added
#      component's version is CHANGED: run this again with a different
#      IN_VERSION_ID).
#   4. The project-side handler folder Middlewares/<Name>App is scaffolded
#      (first time only, never overwritten afterwards).
#   5. The handler folder and Core/ are wired into
#      Middlewares/Middlewares.cmake, and Middlewares/Core/CMakeLists.txt
#      is regenerated (see Mw_ModuleHandler_CoreCMakeListsGenerate).
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
    # Add git submodule under Middlewares/Core/<Name>
    # ------------------------------------------------------
    set(LOCAL_SUB_PATH "${PROJECT_ROOT_PATH}/${MW_CORE_REL_PATH}/${SUB_NAME}")

    if(EXISTS "${LOCAL_SUB_PATH}/.git")

        message(DEBUG "Module already found in ${LOCAL_SUB_PATH}")

    else()

        GitHandler_SubmoduleInit(${SUB_URL} "${MW_CORE_REL_PATH}/${SUB_NAME}" ${SUB_ACTIVE} SUB_IS_SUBMODULE)

        # Ignore submodule changes in parent directory (meaningless for a
        # plain clone fallback - EmBi platform is not itself a GIT repo)
        if(SUB_IS_SUBMODULE)
            GitHandler_SubmoduleIgnore("${MW_CORE_REL_PATH}/${SUB_NAME}" "dirty")
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

    Mw_ModuleHandler_UpdateCMakeLists("${SUB_NAME}${MW_APP_SUFFIX}")

    Mw_ModuleHandler_CoreCMakeListsGenerate()

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
#   (Middlewares/Core/<Name>) to the LATEST GIT tag available on its
#   own repository (or the latest commit of its default branch, if it still
#   has no tags). Unlike Mw_ModuleHandler_Config, this never touches the
#   handler folder - only the vendored submodule's checked-out version, after
#   which Middlewares/Core/CMakeLists.txt is regenerated (the new
#   version may add or drop the component's own CMakeLists.txt).
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

    set(LOCAL_SUB_PATH "${PROJECT_ROOT_PATH}/${MW_CORE_REL_PATH}/${SUB_NAME}")

    if(NOT EXISTS "${LOCAL_SUB_PATH}/.git")
        message(WARNING "Middleware '${SUB_NAME}' is not initialized yet under '${MW_CORE_REL_PATH}' - run 'Configure Middleware module' first.")
        return()
    endif()

    Mw_ModuleHandler_ResolveVersionRef(${SUB_URL} 0 LATEST_VERSION_REF)

    message(STATUS "Updating '${SUB_NAME}' to latest version '${LATEST_VERSION_REF}'...")

    GitHandler_SwitchBranch(${LOCAL_SUB_PATH} ${LATEST_VERSION_REF})

    Mw_ModuleHandler_CoreCMakeListsGenerate()

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
