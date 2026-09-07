# ==============================================================================
# Platform updates handler.
#
# User shall place their updates in folder "Updates" and then create folder for 
# every version. The version folder can contain multiple .cmake files for 
# separate update stages/steps. Its execution will be in alphabetical order.
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
# Function: Updater_RunVersionUpdate
# Description: Executes all necessary steps in update for required version.
# ------------------------------------------------------------------------------
function(Updater_RunVersionUpdate IN_TARGET_VERSION)

    # Read list of update steps
    Updater_Get_UpdateStepsList(${IN_TARGET_VERSION} STEP_LIST)
    
    # Loop through every update step
    foreach(UPDATE_STEP IN LISTS STEP_LIST)
    
        # Execute update step
        include("${UPDATE_VERSIONS_DIR}/${IN_TARGET_VERSION}/${UPDATE_STEP}")
        
    endforeach()
    
    # Update actual version
    Platform_VersionHandler_Set_Version(${IN_TARGET_VERSION})

endfunction()


#==============================================================================#
# Main functionality
# Usage: cmake -DTARGET_VERSION="1.0.3" -P Updater.cmake
#==============================================================================#
if(CMAKE_SCRIPT_MODE_FILE AND 
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)
   
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
    
endif()

