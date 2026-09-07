# ==============================================================================
# Update of CMakeLists.txt files
#
# The CMakeLists.txt files shall be updated to newest version of template file.
#
# ==============================================================================

#===============================================================================
# Global variables
#===============================================================================

# Configure path to the BSP folder
get_filename_component(SEARCH_PATH "${CMAKE_CURRENT_LIST_DIR}../../../../../../Bsp/Mcal/" REALPATH)

# Configure file name to be updated
set(SEARCH_FILENAME "CMakeLists.txt")

# Configure path to the BSP folder
get_filename_component(CMAKELISTS_HANDLER_PATH "${CMAKE_CURRENT_LIST_DIR}/../../../HelperTools/CMakeLists_handler/CMakeLists_Handler.cmake" REALPATH)

# Include CMakeLists.txt handler
include(${CMAKELISTS_HANDLER_PATH})

#===============================================================================
# Search for all CMakeLists.txt files
#===============================================================================
file(GLOB_RECURSE FOUND_FILES
    "${SEARCH_PATH}/**/${SEARCH_FILENAME}"
)

#===============================================================================
# Processing of found files
#===============================================================================

if(FOUND_FILES)

    list(LENGTH FOUND_FILES FILE_COUNT)
    
    message(STATUS "Found ${FILE_COUNT} files.")

    foreach(FILE_PATH ${FOUND_FILES})
    
        get_filename_component(FILE_DIR "${FILE_PATH}" DIRECTORY)
    
        message(STATUS "================================================================================")
        message(STATUS "Processing file: ${FILE_DIR} to version: ${VERSION_ID}")
        message(STATUS "================================================================================")
        
        CMakeLists_Handler_Get_Version( ${FILE_DIR} OUT_VERSION )
        
        CMakeLists_Handler_Set_Version( ${VERSION_ID} )
        
        CMakeLists_Handler_Get_PrivateIncludeDirs( ${FILE_DIR} OUT_PRIVATE_INCLUDE_DIRS )
        
        if(NOT "${OUT_PRIVATE_INCLUDE_DIRS}" STREQUAL "")
            CMakeLists_Handler_Set_PrivateInlcudeDirs( "${OUT_PRIVATE_INCLUDE_DIRS}" )
        endif()
        
        CMakeLists_Handler_Get_PublicIncludeDirs( ${FILE_DIR} OUT_PUBLIC_INCLUDE_DIRS )
        if(NOT "${OUT_PUBLIC_INCLUDE_DIRS}" STREQUAL "")
            CMakeLists_Handler_Set_PublicInlcudeDirs( "${OUT_PUBLIC_INCLUDE_DIRS}" )
        endif()
        
        CMakeLists_Handler_Get_SourceFiles( ${FILE_DIR} OUT_SOURCE_FILES )
        if(NOT "${OUT_SOURCE_FILES}" STREQUAL "")
            CMakeLists_Handler_Set_SourceFiles( "${OUT_SOURCE_FILES}" )
        endif()
        
        CMakeLists_Handler_Get_PublicHeaderFiles( ${FILE_DIR} OUT_PUBLIC_HEADER_FILES )
        if(NOT "${OUT_PUBLIC_HEADER_FILES}" STREQUAL "")
            CMakeLists_Handler_Set_PublicHeaderFiles( "${OUT_PUBLIC_HEADER_FILES}" )
        endif()
        
        CMakeLists_Handler_Get_PublicDependenLibs( ${FILE_DIR} OUT_PUBLIC_DEPENDENT_LIBS )
        if(NOT "${OUT_PUBLIC_DEPENDENT_LIBS}" STREQUAL "")
            CMakeLists_Handler_Set_PublicDependenLibs( "${OUT_PUBLIC_DEPENDENT_LIBS}" )
        endif()
        
        CMakeLists_Handler_Get_PrivateDependentLibs( ${FILE_DIR} OUT_PRIVATE_DEPENDENT_LIBS )
        if(NOT "${OUT_PRIVATE_DEPENDENT_LIBS}" STREQUAL "")
            CMakeLists_Handler_Set_PrivateDependentLibs( "${OUT_PRIVATE_DEPENDENT_LIBS}" )
        endif()
        
        CMakeLists_Handler_Get_ModuleName( ${FILE_DIR} OUT_MODULE_NAME )
        if(NOT "${OUT_MODULE_NAME}" STREQUAL "")
            CMakeLists_Handler_Set_ModuleName( "${OUT_MODULE_NAME}" )
        endif()
        
        CMakeLists_Handler_Generate_CMakeLists( ${FILE_DIR} )
        
    endforeach()
    
else()

    message(STATUS "No files found.")
    
endif()