###############################################################################
# Artifacts Configuration file handler functionality
###############################################################################


#------------------------------------------------------------------------------#
# Returns Root repository URL from ArtifactsConfig.txt file.
#
# ARTIFACTS_CONFIG_FILE_PATH_ARG [in]: Path to the ArtifactsConfig.txt file
# ROOT_REPO_URL_ARG             [out]: URL of root repository.
#------------------------------------------------------------------------------#
function(ConfigFileHandler_Get_RootRepoURL ARTIFACTS_CONFIG_FILE_PATH_ARG
                                           ROOT_REPO_URL_ARG)

    if(NOT EXISTS "${ARTIFACTS_CONFIG_FILE_PATH_ARG}")
        message(WARNING "ArtifactsConfig.txt not found!")
        return()
    endif()
    
    file(STRINGS "${ARTIFACTS_CONFIG_FILE_PATH_ARG}" ARTIFACTS_CONFIG_LINES)
    
    set(PARSED_LIST "")

    foreach(LINE IN LISTS ARTIFACTS_CONFIG_LINES)

        # Skip empty lines
        if(LINE STREQUAL "")
            continue()
        endif()

        if(LINE MATCHES "^ARTIFACTS_HANDLER_ROOT_REPO_URL=(.*)$")
        
            set(ROOT_REPO_URL "${CMAKE_MATCH_1}")

            set(${ROOT_REPO_URL_ARG} "${ROOT_REPO_URL}" PARENT_SCOPE)
            
            message(STATUS "Artifacts Root repository URL: ${ROOT_REPO_URL}")

            break()

        endif()

    endforeach()

endfunction(ConfigFileHandler_Get_RootRepoURL)


#------------------------------------------------------------------------------#
# Returns Required Artifacts List from ArtifactsConfig.txt file.
#
# ARTIFACTS_CONFIG_FILE_PATH_ARG [in]: Path to the ArtifactsConfig.txt file
# ARTIFACTS_LIST_ARG            [out]: List of Required Artifacts.
#------------------------------------------------------------------------------#
function(ConfigFileHandler_Get_ArtifactsList ARTIFACTS_CONFIG_FILE_PATH_ARG 
                                             ARTIFACTS_LIST_ARG)

    if(NOT EXISTS "${ARTIFACTS_CONFIG_FILE_PATH_ARG}")
        message(WARNING "ArtifactsConfig.txt not found!")
        return()
    endif()
    
    file(STRINGS "${ARTIFACTS_CONFIG_FILE_PATH_ARG}" ARTIFACTS_CONFIG_LINES)
    
    set(PARSED_LIST "")

    foreach(LINE IN LISTS ARTIFACTS_CONFIG_LINES)
        
        # Skip empty lines
        if(LINE STREQUAL "")
            continue()
        endif()

        # Ignore lines starting with "ARTIFACTS_HANDLER"
        if(LINE MATCHES "^ARTIFACTS_HANDLER")
            continue()
        endif()
        
        # Ignore lines starting with "#"
        if(LINE MATCHES "^#")
            continue()
        endif()

        # Check format: NAME;BINARY_VERSION;HANDLER_VERSION
        if(NOT LINE MATCHES "^([^;]+);([^;]+);([^;]+)$")
            message(FATAL_ERROR "Incorrect line format: '${LINE}'\nRequired format: NAME;BINARY_VERSION;HANDLER_VERSION")
        endif()
        
        string(REPLACE ";" "\;" LINE "${LINE}")
        string(REPLACE "," "\n" LINE "${LINE}")
        string(REPLACE " " "" LINE "${LINE}")
        string(REPLACE "_" "-" LINE "${LINE}")

        list(APPEND PARSED_LIST "${LINE}")
    endforeach()

    set(${ARTIFACTS_LIST_ARG} "${PARSED_LIST}" PARENT_SCOPE)

endfunction(ConfigFileHandler_Get_ArtifactsList)


#------------------------------------------------------------------------------#
# Returns path to the ArtifactsCache folder from ArtifactsConfig.txt file.
#
# ArtifactsConfig.txt file can contain path, to the Artifacts Cache folder. This
# folder will be used as permanent storage for downloaded artifacts. A path of
# one operating system is not valid on another one, so the path is configured
# per operating system of the host (the file can be shared by all of them):
#
#   ARTIFACTS_HANDLER_CACHE_PATH_WIN=C:\ArtifactsCache         (Windows host)
#   ARTIFACTS_HANDLER_CACHE_PATH_UNIX=/opt/ArtifactsCache      (Linux and other Unix host)
#   ARTIFACTS_HANDLER_CACHE_PATH_MAC=/Users/me/ArtifactsCache  (macOS host)
#
# The line of the host operating system is used first. The generic line
# "ARTIFACTS_HANDLER_CACHE_PATH=" is the fallback for it, but it is ignored,
# when it is a path of another operating system than the host (drive letter or
# UNC path on a Unix host, absolute Unix path on a Windows host). The existence
# of the folder is not checked, the folder is created by the cache handler.
#
# ARTIFACTS_CONFIG_FILE_PATH_ARG [in]: Path to the ArtifactsConfig.txt file
# ARTIFACTS_CACHE_PATH_ARG      [out]: Path to the Artifacts Cache folder. If
#                                      not configured for the host, symbol "-"
#                                      is returned
#------------------------------------------------------------------------------#
function(ConfigFileHandler_Get_CachePath ARTIFACTS_CONFIG_FILE_PATH_ARG 
                                         ARTIFACTS_CACHE_PATH_ARG)

    # The cache path is not configured until its configuration line is found.
    set(${ARTIFACTS_CACHE_PATH_ARG} "-" PARENT_SCOPE)

    if(NOT EXISTS "${ARTIFACTS_CONFIG_FILE_PATH_ARG}")
        message(WARNING "ArtifactsConfig.txt not found!")
        return()
    endif()

    # Configuration line of the host operating system (the system names are the
    # same as in ArtifactsHandler_Get_OsVersion).
    if("${CMAKE_HOST_SYSTEM_NAME}" STREQUAL "Windows")
        set(OS_KEY "ARTIFACTS_HANDLER_CACHE_PATH_WIN")
    elseif("${CMAKE_HOST_SYSTEM_NAME}" STREQUAL "Darwin")
        set(OS_KEY "ARTIFACTS_HANDLER_CACHE_PATH_MAC")
    else()
        set(OS_KEY "ARTIFACTS_HANDLER_CACHE_PATH_UNIX")
    endif()

    file(STRINGS "${ARTIFACTS_CONFIG_FILE_PATH_ARG}" ARTIFACTS_CONFIG_LINES)

    set(OS_PATH      "")
    set(GENERIC_PATH "")

    foreach(LINE IN LISTS ARTIFACTS_CONFIG_LINES)

        if(LINE MATCHES "^${OS_KEY}=(.*)$")

            string(STRIP "${CMAKE_MATCH_1}" OS_PATH)

        elseif(LINE MATCHES "^ARTIFACTS_HANDLER_CACHE_PATH=(.*)$")

            string(STRIP "${CMAKE_MATCH_1}" GENERIC_PATH)

        else()

            # Other line of the configuration file (comment, artifact, URL,
            # path of another operating system)

        endif()

    endforeach()

    # Path of the host operating system.
    if(NOT "${OS_PATH}" STREQUAL "")

        set(${ARTIFACTS_CACHE_PATH_ARG} "${OS_PATH}" PARENT_SCOPE)

        return()

    endif()

    # Generic path (fallback) - only if it is a path of the host operating system.
    if("${GENERIC_PATH}" STREQUAL "")

        return()

    endif()

    set(FOREIGN_PATH FALSE)

    if("${CMAKE_HOST_SYSTEM_NAME}" STREQUAL "Windows")

        # "/opt/ArtifactsCache" - Unix path
        if("${GENERIC_PATH}" MATCHES "^/[^/]")
            set(FOREIGN_PATH TRUE)
        else()
            # Path of the host operating system
        endif()

    else()

        # "C:\ArtifactsCache", "C:/ArtifactsCache", "\\server\share" - Windows path
        if("${GENERIC_PATH}" MATCHES [[^([A-Za-z]:|\\\\)]])
            set(FOREIGN_PATH TRUE)
        else()
            # Path of the host operating system
        endif()

    endif()

    if(FOREIGN_PATH)

        message(STATUS "Cache path '${GENERIC_PATH}' is a path of another operating system, ignored (${OS_KEY} sets the path of this one).")

    else()

        set(${ARTIFACTS_CACHE_PATH_ARG} "${GENERIC_PATH}" PARENT_SCOPE)

    endif()

endfunction(ConfigFileHandler_Get_CachePath)
