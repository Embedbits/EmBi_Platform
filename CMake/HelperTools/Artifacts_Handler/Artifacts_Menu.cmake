# ==============================================================================
#
# Artifacts handler actions of the Setup menu (Setup.bat/sh: Configuration ->
# Artifacts).
#
# The artifacts (build tools such as ninja, gcc-arm-none-eabi, doxygen, probe-rs)
# are installed by the artifacts handler (CMake/ArtifactsHandler) into the
# artifacts cache folder, normally as a part of the configuration of the project.
# This script lets the user use the handler directly:
#
#   INSTALL      - installs the artifacts listed in ArtifactsConfig.txt of the
#                  project (OFFLINE=ON - only the local cache is checked, nothing
#                  is downloaded)
#   INSTALL_ONE  - installs one artifact, which does not need to be listed in
#                  ArtifactsConfig.txt (ARTIFACT_NAME, ARTIFACT_BIN_VERSION and
#                  ARTIFACT_CORE_VERSION, an empty version means "latest")
#   SHOW         - prints the configuration of the handler: configuration file,
#                  root repository, cache folder (and which source it comes from),
#                  required artifacts with the versions installed in the cache
#
# The configuration file is ArtifactsConfig.txt in the root folder of the
# project, created by the project structure initialization (Prj_Handler.cmake).
# The cache folder is resolved by the handler: CMake parameter / environment
# variable ARTIFACTS_HANDLER_CACHE_PATH, path of the host operating system in
# ArtifactsConfig.txt (ARTIFACTS_HANDLER_CACHE_PATH_WIN / _UNIX / _MAC), default
# cache folder of the handler (see CMake/ArtifactsHandler/README.md).
#
# ==============================================================================


#===============================================================================
# Global variables
#===============================================================================

# Set path to system configuration file
get_filename_component(SYSTEM_CONFIG_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/../../SysConfig.cmake" REALPATH)

# Include file with system configuration values
include("${SYSTEM_CONFIG_FILE_PATH}")

# Path to the project root folder
SysConfig_Get_ProjectRootPath(ARTIFACTS_MENU_PROJECT_ROOT)

# Configuration file of the artifacts handler
set(ARTIFACTS_MENU_CONFIG_FILE "${ARTIFACTS_MENU_PROJECT_ROOT}/ArtifactsConfig.txt")

# Functions of the artifacts handler - the handler is started explicitly by the
# actions below, the include only defines the functions.
set(ARTIFACTS_HANDLER_NO_RUN TRUE)
include("${CMAKE_CURRENT_LIST_DIR}/../../ArtifactsHandler/ArtifactsHandler.cmake")
unset(ARTIFACTS_HANDLER_NO_RUN)


# ------------------------------------------------------------------------------
# Function: Artifacts_Menu_CheckConfigFile
# Description: Ends with an error if the project has no ArtifactsConfig.txt.
# ------------------------------------------------------------------------------
function(Artifacts_Menu_CheckConfigFile)

    if(NOT EXISTS "${ARTIFACTS_MENU_CONFIG_FILE}")
        message(FATAL_ERROR "ArtifactsConfig.txt not found in the project root folder ${ARTIFACTS_MENU_PROJECT_ROOT}. "
                            "Run the project structure initialization first (Configuration -> Project structure initialization).")
    endif()

endfunction(Artifacts_Menu_CheckConfigFile)


# ------------------------------------------------------------------------------
# Function: Artifacts_Menu_Install
# Description: Installs the artifacts of ArtifactsConfig.txt of the project.
#
# IN_OFFLINE [in]: ON / TRUE - only the local cache is checked, nothing is
#                  downloaded.
# ------------------------------------------------------------------------------
function(Artifacts_Menu_Install IN_OFFLINE)

    Artifacts_Menu_CheckConfigFile()

    # Parameters of the handler (read by ArtifactsHandler_Main from this scope)
    set(CONFIG_FILE_PATH "${ARTIFACTS_MENU_PROJECT_ROOT}")

    if(IN_OFFLINE)
        set(ARTIFACTS_HANDLER_OFFLINE_MODE TRUE)
        message(STATUS "Offline mode - only the local cache is checked.")
    else()
        # Missing artifacts are downloaded
    endif()

    ArtifactsHandler_Main()

endfunction(Artifacts_Menu_Install)


# ------------------------------------------------------------------------------
# Function: Artifacts_Menu_InstallOne
# Description: Installs one artifact (the configuration file of the project is
#              still needed for the root repository and the cache folder).
#
# IN_NAME         [in]: Name of the artifact (e.g. ninja).
# IN_BIN_VERSION  [in]: Version of the Bin part, empty = latest.
# IN_CORE_VERSION [in]: Version of the Core part, empty = latest.
# ------------------------------------------------------------------------------
function(Artifacts_Menu_InstallOne IN_NAME IN_BIN_VERSION IN_CORE_VERSION)

    Artifacts_Menu_CheckConfigFile()

    if(NOT "${IN_NAME}" MATCHES "^[A-Za-z0-9._-]+$")
        message(FATAL_ERROR "Artifact name '${IN_NAME}' is not correct (letters, digits, '.', '_' and '-').")
    endif()

    set(BIN_VERSION  "${IN_BIN_VERSION}")
    set(CORE_VERSION "${IN_CORE_VERSION}")

    if("${BIN_VERSION}" STREQUAL "")
        set(BIN_VERSION "latest")
    endif()

    if("${CORE_VERSION}" STREQUAL "")
        set(CORE_VERSION "latest")
    endif()

    if(NOT "${BIN_VERSION}" MATCHES "^[A-Za-z0-9._-]+$")
        message(FATAL_ERROR "Bin version '${BIN_VERSION}' is not correct (X.Y.Z or latest).")
    endif()

    if(NOT "${CORE_VERSION}" MATCHES "^[A-Za-z0-9._-]+$")
        message(FATAL_ERROR "Core version '${CORE_VERSION}' is not correct (X.Y.Z or latest).")
    endif()

    # Parameters of the handler (read by ArtifactsHandler_Main from this scope)
    set(CONFIG_FILE_PATH "${ARTIFACTS_MENU_PROJECT_ROOT}")
    set(ARTIFACTS_HANDLER_REQ_LIST "${IN_NAME};${BIN_VERSION};${CORE_VERSION}")

    message(STATUS "Installing the artifact ${IN_NAME} (Bin ${BIN_VERSION}, Core ${CORE_VERSION}).")

    ArtifactsHandler_Main()

endfunction(Artifacts_Menu_InstallOne)


# ------------------------------------------------------------------------------
# Function: Artifacts_Menu_ListVersions
# Description: Returns versions of an artifact part installed in the cache.
#
# IN_PART_DIR      [in]: Folder of the part (<cache>/<artifact>/Bin or Core).
# OUT_VERSIONS_STR [out]: Installed versions separated by ", ", "-" if none.
#                         Staging folders of an interrupted installation (their
#                         names begin with '.') are not versions.
# ------------------------------------------------------------------------------
function(Artifacts_Menu_ListVersions IN_PART_DIR OUT_VERSIONS_STR)

    set(VERSIONS "")

    if(IS_DIRECTORY "${IN_PART_DIR}")

        file(GLOB ENTRIES LIST_DIRECTORIES true RELATIVE "${IN_PART_DIR}" "${IN_PART_DIR}/*")

        foreach(ENTRY IN LISTS ENTRIES)
            if(IS_DIRECTORY "${IN_PART_DIR}/${ENTRY}")
                list(APPEND VERSIONS "${ENTRY}")
            endif()
        endforeach()

        list(SORT VERSIONS COMPARE NATURAL)

    else()

        # Part is not installed

    endif()

    if("${VERSIONS}" STREQUAL "")
        set(${OUT_VERSIONS_STR} "-" PARENT_SCOPE)
    else()
        string(REPLACE ";" ", " VERSIONS_STR "${VERSIONS}")
        set(${OUT_VERSIONS_STR} "${VERSIONS_STR}" PARENT_SCOPE)
    endif()

endfunction(Artifacts_Menu_ListVersions)


# ------------------------------------------------------------------------------
# Function: Artifacts_Menu_Show
# Description: Prints the configuration of the artifacts handler and the
#              required artifacts with the versions installed in the cache.
# ------------------------------------------------------------------------------
function(Artifacts_Menu_Show)

    message(STATUS "Project root          : ${ARTIFACTS_MENU_PROJECT_ROOT}")

    if(EXISTS "${ARTIFACTS_MENU_CONFIG_FILE}")
        message(STATUS "Configuration file    : ${ARTIFACTS_MENU_CONFIG_FILE}")
    else()
        message(STATUS "Configuration file    : ${ARTIFACTS_MENU_CONFIG_FILE} - NOT FOUND")
    endif()

    Artifacts_Menu_CheckConfigFile()

    # Root repository (the handler prints the URL)
    ArtifactsHandler_Get_RootRepoURL("${ARTIFACTS_MENU_CONFIG_FILE}" ROOT_REPO_URL)

    # Cache folder
    ArtifactsHandler_Get_ArtifactsCachePath("${ARTIFACTS_MENU_CONFIG_FILE}" CACHE_PATH CACHE_PATH_SOURCE)
    message(STATUS "Cache folder          : ${CACHE_PATH} (${CACHE_PATH_SOURCE})")

    if(IS_DIRECTORY "${CACHE_PATH}")
        message(STATUS "Cache folder exists   : yes")
    else()
        message(STATUS "Cache folder exists   : no (created by the first installation)")
    endif()

    # Offline mode
    ArtifactsHandler_Get_OfflineModeState(OFFLINE_MODE_STATE)
    message(STATUS "Offline mode          : ${OFFLINE_MODE_STATE}")

    # Required artifacts
    ArtifactsHandler_Get_RequiredArtifactsList_Source(LIST_SOURCE)

    if("${LIST_SOURCE}" STREQUAL "${ARTIFACTS_HANDLER_ARTIFACT_LIST_SRC_FILE}")
        set(LIST_SOURCE_TEXT "ArtifactsConfig.txt")
    elseif("${LIST_SOURCE}" STREQUAL "${ARTIFACTS_HANDLER_ARTIFACT_LIST_SRC_PARAM}")
        set(LIST_SOURCE_TEXT "CMake parameter ARTIFACTS_HANDLER_REQ_LIST")
    else()
        set(LIST_SOURCE_TEXT "environment variable ARTIFACTS_HANDLER_REQ_LIST")
    endif()

    ArtifactsHandler_Get_RequiredArtifactsList("${ARTIFACTS_MENU_CONFIG_FILE}" REQUIRED_ARTIFACTS_LIST)

    message(STATUS "Required artifacts    : (${LIST_SOURCE_TEXT})")

    foreach(ARTIFACT_RECORD IN LISTS REQUIRED_ARTIFACTS_LIST)

        list(GET ARTIFACT_RECORD 0 ARTIFACT_NAME)
        list(GET ARTIFACT_RECORD 1 ARTIFACT_BIN_VERSION)
        list(GET ARTIFACT_RECORD 2 ARTIFACT_CORE_VERSION)

        Artifacts_Menu_ListVersions("${CACHE_PATH}/${ARTIFACT_NAME}/Bin"  INSTALLED_BIN)
        Artifacts_Menu_ListVersions("${CACHE_PATH}/${ARTIFACT_NAME}/Core" INSTALLED_CORE)

        message(STATUS "  ${ARTIFACT_NAME}")
        message(STATUS "      required  : Bin ${ARTIFACT_BIN_VERSION}, Core ${ARTIFACT_CORE_VERSION}")
        message(STATUS "      installed : Bin ${INSTALLED_BIN}; Core ${INSTALLED_CORE}")

    endforeach()

endfunction(Artifacts_Menu_Show)


#===============================================================================
# Main functionality
#===============================================================================
# cmake -DFUNCTION_ID="INSTALL"                                                    -P Artifacts_Menu.cmake : Install the artifacts of ArtifactsConfig.txt
# cmake -DFUNCTION_ID="INSTALL" -DOFFLINE=ON                                       -P Artifacts_Menu.cmake : Check the local cache only
# cmake -DFUNCTION_ID="INSTALL_ONE" -DARTIFACT_NAME=ninja -DARTIFACT_BIN_VERSION=1.12.0 -DARTIFACT_CORE_VERSION=latest -P Artifacts_Menu.cmake : Install one artifact
# cmake -DFUNCTION_ID="SHOW"                                                       -P Artifacts_Menu.cmake : Show the configuration and the installed versions

if(CMAKE_SCRIPT_MODE_FILE AND
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)

    if("${FUNCTION_ID}" STREQUAL "INSTALL")

        Artifacts_Menu_Install("${OFFLINE}")

    elseif("${FUNCTION_ID}" STREQUAL "INSTALL_ONE")

        Artifacts_Menu_InstallOne("${ARTIFACT_NAME}" "${ARTIFACT_BIN_VERSION}" "${ARTIFACT_CORE_VERSION}")

    elseif("${FUNCTION_ID}" STREQUAL "SHOW")

        Artifacts_Menu_Show()

    else()

        message(FATAL_ERROR "Unknown FUNCTION_ID '${FUNCTION_ID}'.")

    endif()

endif()
