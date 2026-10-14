###############################################################################
# Artifacts Cache folder handler functionality
#
# Artifacts cache folder is location, where the artifacts are stored to be used 
# during build. This folder can be shared between different projects and 
# different builds.
###############################################################################

# Name of cmake file used for artifacts configuration
set(CACHE_HANDLER_CONFIG_FILE_NAME "ArtifactConfig.cmake")

# Name of file keeping date of the last remote check of the latest version
set(CACHE_HANDLER_LATEST_CHECK_FILE ".LatestCheck")

# Infix of staging folder name - artifact part is installed into folder
# .<version><infix><random> and renamed to <version> when complete
set(CACHE_HANDLER_STAGING_INFIX ".partial-")


#------------------------------------------------------------------------------#
# Checks, if Binary artifact with required version is cached or not.
#
# CACHED_ARTIFACTS_PATH_ARG  [in]: Path to the Artifacts Cache folder
# ARTIFACT_NAME_ARG          [in]: Name of artifact.
# ARTIFACT_BIN_VERSION_ARG   [in]: Required version of Binary artifact part
# CACHED_ARTIFACT_STATE_ARG [out]: State, if artifact exist
# CACHED_VERSION_ARG        [out]: Found version in format X.Y.Z
#------------------------------------------------------------------------------#
function(CacheHandler_Check_CachedArtifact_Bin CACHED_ARTIFACTS_PATH_ARG 
                                               ARTIFACT_NAME_ARG 
                                               ARTIFACT_BIN_VERSION_ARG 
                                               CACHED_ARTIFACT_STATE_ARG
                                               CACHED_VERSION_ARG)

    set(TARGET_VERSION "")
    set(ARTIFACT_PATH "${CACHED_ARTIFACTS_PATH_ARG}/${ARTIFACT_NAME_ARG}/Bin")

    if(NOT EXISTS "${ARTIFACT_PATH}" OR NOT IS_DIRECTORY "${ARTIFACT_PATH}")
        set(${CACHED_ARTIFACT_STATE_ARG} "FALSE" PARENT_SCOPE)
        message(DEBUG "Binary part of artifact ${ARTIFACT_NAME_ARG} is not cached.")
        return()
    endif()


    if(ARTIFACT_BIN_VERSION_ARG STREQUAL "latest")

        file(GLOB FOLDERS_LIST "${ARTIFACT_PATH}/*")
        
        if(NOT FOLDERS_LIST)
            set(${CACHED_ARTIFACT_STATE_ARG} "FALSE" PARENT_SCOPE)
            message(DEBUG "Artifact folder is empty.")
            return()
        endif()

        foreach(FOLDER_NAME IN LISTS FOLDERS_LIST)
            get_filename_component(ARTIFACT_VERSION "${FOLDER_NAME}" NAME)
            if(ARTIFACT_VERSION MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$" AND IS_DIRECTORY "${FOLDER_NAME}")
                list(APPEND VERSION_LIST "${ARTIFACT_VERSION}")
            endif()
        endforeach()
        
        list(SORT VERSION_LIST COMPARE NATURAL ORDER DESCENDING)
        
        if(VERSION_LIST)
        
            list(GET VERSION_LIST 0 LATEST_VERSION)
        
            set(TARGET_VERSION ${LATEST_VERSION})
            
        else()
        
            set(TARGET_VERSION ${ARTIFACT_BIN_VERSION_ARG})
            
        endif()

    else()
    
        set(TARGET_VERSION ${ARTIFACT_BIN_VERSION_ARG})
        
    endif()
    
    set(${CACHED_VERSION_ARG} "${TARGET_VERSION}" PARENT_SCOPE)


    if(IS_DIRECTORY "${ARTIFACT_PATH}/${TARGET_VERSION}" AND NOT "${TARGET_VERSION}" STREQUAL "latest")

        set(${CACHED_ARTIFACT_STATE_ARG} "TRUE" PARENT_SCOPE)
        
        message(DEBUG "Artifacts Bin is already cached.")

    else()

        set(${CACHED_ARTIFACT_STATE_ARG} "FALSE" PARENT_SCOPE)
        
        message(DEBUG "Artifacts Bin is not cached.")

    endif()
    
endfunction(CacheHandler_Check_CachedArtifact_Bin)


#------------------------------------------------------------------------------#
# Checks, if Core artifact with required version is cached or not.
#
# CACHED_ARTIFACTS_PATH_ARG  [in]: Path to the Artifacts Cache folder
# ARTIFACT_NAME_ARG          [in]: Name of artifact.
# ARTIFACT_CORE_VERSION_ARG  [in]: Required version of Core artifact part
# CACHED_ARTIFACT_STATE_ARG [out]: State, if artifact exist
# CACHED_VERSION_ARG        [out]: Found version in format X.Y.Z
#------------------------------------------------------------------------------#
function(ArtifactsHandler_Check_CachedArtifact_Core CACHED_ARTIFACTS_PATH_ARG 
                                                    ARTIFACT_NAME_ARG 
                                                    ARTIFACT_CORE_VERSION_ARG 
                                                    CACHED_ARTIFACT_STATE_ARG
                                                    CACHED_VERSION_ARG)

    set(TARGET_VERSION "")
    set(ARTIFACT_PATH "${CACHED_ARTIFACTS_PATH_ARG}/${ARTIFACT_NAME_ARG}/Core")

    if(NOT EXISTS "${ARTIFACT_PATH}" OR NOT IS_DIRECTORY "${ARTIFACT_PATH}")
        set(${CACHED_ARTIFACT_STATE_ARG} "FALSE" PARENT_SCOPE)
        message(DEBUG "Artifact cached folder ${ARTIFACT_NAME_ARG} does not exist on ${ARTIFACT_PATH}.")
        return()
    endif()


    if(ARTIFACT_CORE_VERSION_ARG STREQUAL "latest")

        file(GLOB FOLDERS_LIST "${ARTIFACT_PATH}/*")
        
        if(NOT FOLDERS_LIST)
            set(${CACHED_ARTIFACT_STATE_ARG} "FALSE" PARENT_SCOPE)
            message(DEBUG "Artifact folder is empty.")
            return()
        endif()

        foreach(FOLDER_NAME IN LISTS FOLDERS_LIST)
            get_filename_component(ARTIFACT_VERSION "${FOLDER_NAME}" NAME)
            
            if(ARTIFACT_VERSION MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$" AND IS_DIRECTORY "${FOLDER_NAME}")
                list(APPEND VERSION_LIST "${ARTIFACT_VERSION}")
            endif()
        endforeach()
        
        list(SORT VERSION_LIST COMPARE NATURAL ORDER DESCENDING)
        
        if(VERSION_LIST)
        
            list(GET VERSION_LIST 0 LATEST_VERSION)
        
            set(TARGET_VERSION ${LATEST_VERSION})
            
        else()
        
            set(TARGET_VERSION ${ARTIFACT_CORE_VERSION_ARG})
            
        endif()

    else()
    
        set(TARGET_VERSION ${ARTIFACT_CORE_VERSION_ARG})
        
    endif()
    
    set(${CACHED_VERSION_ARG} "${TARGET_VERSION}" PARENT_SCOPE)


    if(IS_DIRECTORY "${ARTIFACT_PATH}/${TARGET_VERSION}" AND NOT "${TARGET_VERSION}" STREQUAL "latest")

        set(${CACHED_ARTIFACT_STATE_ARG} "TRUE" PARENT_SCOPE)
        
        message(DEBUG "Artifacts Core is already cached.")

    else()

        set(${CACHED_ARTIFACT_STATE_ARG} "FALSE" PARENT_SCOPE)
        
        message(DEBUG "Artifacts Core is not cached.")

    endif()
    
endfunction(ArtifactsHandler_Check_CachedArtifact_Core)


#------------------------------------------------------------------------------#
# Checks, if the latest version of artifact part was already checked on remote
# today.
#
# The date of the last check is stored in file CACHE_HANDLER_LATEST_CHECK_FILE
# in artifact part folder of the Artifacts Cache, so the check is shared by
# all projects using the same cache.
#
# CACHED_ARTIFACTS_PATH_ARG  [in]: Path to the Artifacts Cache folder
# ARTIFACT_NAME_ARG          [in]: Name of artifact.
# ARTIFACT_PART_ARG          [in]: Artifact part (Core or Bin)
# CHECK_STATE_ARG           [out]: TRUE if latest version was checked today,
#                                  otherwise FALSE
#------------------------------------------------------------------------------#
function(CacheHandler_Check_LatestCheckDate CACHED_ARTIFACTS_PATH_ARG
                                            ARTIFACT_NAME_ARG
                                            ARTIFACT_PART_ARG
                                            CHECK_STATE_ARG)

    set(CHECK_FILE "${CACHED_ARTIFACTS_PATH_ARG}/${ARTIFACT_NAME_ARG}/${ARTIFACT_PART_ARG}/${CACHE_HANDLER_LATEST_CHECK_FILE}")

    set(LAST_CHECK_DATE "")

    if(EXISTS "${CHECK_FILE}")
        file(STRINGS "${CHECK_FILE}" LAST_CHECK_DATE LIMIT_COUNT 1)
    endif()

    string(TIMESTAMP TODAY "%Y-%m-%d")

    if("${LAST_CHECK_DATE}" STREQUAL "${TODAY}")
        set(${CHECK_STATE_ARG} "TRUE" PARENT_SCOPE)
    else()
        set(${CHECK_STATE_ARG} "FALSE" PARENT_SCOPE)
    endif()

endfunction(CacheHandler_Check_LatestCheckDate)


#------------------------------------------------------------------------------#
# Stores today as the date of the last remote check of the latest version of
# artifact part.
#
# CACHED_ARTIFACTS_PATH_ARG  [in]: Path to the Artifacts Cache folder
# ARTIFACT_NAME_ARG          [in]: Name of artifact.
# ARTIFACT_PART_ARG          [in]: Artifact part (Core or Bin)
#------------------------------------------------------------------------------#
function(CacheHandler_Set_LatestCheckDate CACHED_ARTIFACTS_PATH_ARG
                                          ARTIFACT_NAME_ARG
                                          ARTIFACT_PART_ARG)

    set(CHECK_FILE "${CACHED_ARTIFACTS_PATH_ARG}/${ARTIFACT_NAME_ARG}/${ARTIFACT_PART_ARG}/${CACHE_HANDLER_LATEST_CHECK_FILE}")

    string(TIMESTAMP TODAY "%Y-%m-%d")

    file(WRITE "${CHECK_FILE}" "${TODAY}\n")

endfunction(CacheHandler_Set_LatestCheckDate)


#------------------------------------------------------------------------------#
# Prepares staging folder for installation of artifact part into cache.
#
# Artifact part is never installed directly into its version folder - the
# version folder is taken as installed artifact as soon as it exists, so an
# interrupted installation (killed configure, crash, full disk) would leave a
# broken artifact in cache forever. The part is installed into the staging
# folder .<version>.partial-<random> instead (not a version folder, so it is
# skipped when cached versions are listed) and moved to the version folder by
# CacheHandler_Commit_Staging when complete.
#
# Staging folders of the same version left by interrupted installations are
# removed.
#
# TARGET_PATH_ARG   [in]: Version folder of artifact part in cache
# STAGING_PATH_ARG [out]: Empty staging folder to install the part into
#------------------------------------------------------------------------------#
function(CacheHandler_Prepare_Staging TARGET_PATH_ARG
                                      STAGING_PATH_ARG)

    get_filename_component(PARENT_DIR "${TARGET_PATH_ARG}" DIRECTORY)
    get_filename_component(VERSION_NAME "${TARGET_PATH_ARG}" NAME)

    file(GLOB LEFTOVER_STAGING_DIRS LIST_DIRECTORIES true
         "${PARENT_DIR}/.${VERSION_NAME}${CACHE_HANDLER_STAGING_INFIX}*")

    foreach(LEFTOVER_DIR IN LISTS LEFTOVER_STAGING_DIRS)
        message(STATUS "Removing incomplete installation: ${LEFTOVER_DIR}")
        file(REMOVE_RECURSE "${LEFTOVER_DIR}")
    endforeach()

    string(RANDOM LENGTH 8 STAGING_SUFFIX)

    set(STAGING_PATH "${PARENT_DIR}/.${VERSION_NAME}${CACHE_HANDLER_STAGING_INFIX}${STAGING_SUFFIX}")

    file(MAKE_DIRECTORY "${STAGING_PATH}")

    set(${STAGING_PATH_ARG} "${STAGING_PATH}" PARENT_SCOPE)

endfunction(CacheHandler_Prepare_Staging)


#------------------------------------------------------------------------------#
# Moves completely installed staging folder to the version folder of artifact
# part (see CacheHandler_Prepare_Staging). If the version folder was created
# meanwhile by another configure sharing the cache, that installation is kept
# and the staging folder is removed.
#
# STAGING_PATH_ARG [in]: Staging folder with completely installed artifact part
# TARGET_PATH_ARG  [in]: Version folder of artifact part in cache
#------------------------------------------------------------------------------#
function(CacheHandler_Commit_Staging STAGING_PATH_ARG
                                     TARGET_PATH_ARG)

    file(RENAME "${STAGING_PATH_ARG}" "${TARGET_PATH_ARG}" RESULT RENAME_RESULT)

    if(NOT RENAME_RESULT EQUAL 0)

        if(IS_DIRECTORY "${TARGET_PATH_ARG}")
            message(STATUS "Artifact was installed meanwhile into ${TARGET_PATH_ARG}, it will be used.")
            file(REMOVE_RECURSE "${STAGING_PATH_ARG}")
        else()
            message(FATAL_ERROR "Installed artifact can not be moved to ${TARGET_PATH_ARG}: ${RENAME_RESULT}")
        endif()

    endif()

endfunction(CacheHandler_Commit_Staging)


#------------------------------------------------------------------------------#
# Initialize installed artifact.
#
# ARTIFACT_NAME_ARG [in]: Name of artifact to be processed (name of folder in 
#                     install directory)
# ARTIFACTS_CACHE_PATH_ARG   [in]: Path to the artifacts cache
# ARTIFACT_NAME_ARG          [in]: Name of artifacts to be installed
# ARTIFACT_CORE_VERSION_ARG  [in]: Required Core version to be used
# ARTIFACT_BIN_VERSION_ARG   [in]: Required Bin version to be used
#------------------------------------------------------------------------------#
function(CacheHandler_InitArtifact ARTIFACTS_CACHE_PATH_ARG
                                   ARTIFACT_NAME_ARG 
                                   ARTIFACT_CORE_VERSION_ARG
                                   ARTIFACT_BIN_VERSION_ARG)

    # Check if the current path is a directory
    if((IS_DIRECTORY "${ARTIFACTS_CACHE_PATH_ARG}/${ARTIFACT_NAME_ARG}/Core/${ARTIFACT_CORE_VERSION_ARG}") AND
       (IS_DIRECTORY "${ARTIFACTS_CACHE_PATH_ARG}/${ARTIFACT_NAME_ARG}/Bin/${ARTIFACT_BIN_VERSION_ARG}"  )     )
    
        # Construct the full path to the config file
        set(ARTIFACT_CONFIG_FULL_PATH "${ARTIFACTS_CACHE_PATH_ARG}/${ARTIFACT_NAME_ARG}/Core/${ARTIFACT_CORE_VERSION_ARG}/${CACHE_HANDLER_CONFIG_FILE_NAME}")
        # Construct the full path to the binary
        set(ARTIFACT_BIN_FULL_PATH "${ARTIFACTS_CACHE_PATH_ARG}/${ARTIFACT_NAME_ARG}/Bin/${ARTIFACT_BIN_VERSION_ARG}")
    
        # Check if the config file exists in the current subdirectory
        if(EXISTS "${ARTIFACT_CONFIG_FULL_PATH}")
        
            # Include the config file
            include("${ARTIFACT_CONFIG_FULL_PATH}")
            
            set(FUNCTION_NAME "${ARTIFACT_NAME_ARG}_ArtifactInit")
            
            # Check if artifact support getter for version getting.
            if(COMMAND ${FUNCTION_NAME})
            
                # Call artifact version getter
                cmake_language(CALL "${FUNCTION_NAME}" "${ARTIFACT_BIN_FULL_PATH}")
                
            else()
                
                message(STATUS "Artifact: ${ARTIFACT_NAME_ARG} does not support function ${FUNCTION_NAME}!")
                
            endif()
            
        else()
        
            message(STATUS "Configuration file not found in: ${ARTIFACT_NAME_ARG}")
            
        endif()
        
    else()
    
        message(WARNING "Required artifact path is not correct ${ARTIFACT_NAME_ARG}.") 
        
    endif()

endfunction(CacheHandler_InitArtifact)

#------------------------------------------------------------------------------#
# Returns version of artifact.
#
# ARTIFACT_NAME_ARG_ARG  [in]: Name of artifact to be processed (name of folder 
#                              in installation directory)
# ARTIFACT_VERSION_ARG  [out]: Version of required artifact (in format X.Y.Z)
#------------------------------------------------------------------------------#
function(CacheHandler_Get_ArtifactVersion ARTIFACT_NAME_ARG_ARG 
                                          ARTIFACT_VERSION_ARG)
            
    set(FUNCTION_NAME "${ARTIFACT_NAME_ARG_ARG}_GetArtifactVersion")
    
    # Check if artifact support getter for version getting.
    if(COMMAND ${FUNCTION_NAME})
    
        set(RET_VERSION "")
        
        # Call artifact version getter
        cmake_language(CALL "${FUNCTION_NAME}" RET_VERSION)
        
        # Set value for the parent scope
        set(${ARTIFACT_VERSION_ARG} "${RET_VERSION}" PARENT_SCOPE)
        
    else()
        
        set(${ARTIFACT_VERSION_ARG} "0.0.0" PARENT_SCOPE)
        
        message(STATUS "Artifact: ${ARTIFACT_NAME_ARG_ARG} does not support function ${FUNCTION_NAME}!")
        
    endif()

endfunction(CacheHandler_Get_ArtifactVersion)

