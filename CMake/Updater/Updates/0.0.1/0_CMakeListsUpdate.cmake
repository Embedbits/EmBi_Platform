# ==============================================================================
# Update of CMakeLists.txt files
#
# The CMakeLists.txt files shall be updated to newest version of template file.
#
# Only module CMakeLists.txt files generated from the template (header line
# "# Template version: X.Y.Z") are updated, other CMakeLists.txt files (test
# sets in Tests/, files without the template header) are not touched. Module
# specific content placed after the template part (e.g. registration of unit
# and integration tests added by TestInit) is kept. Template version of the
# file never decreases.
#
# ==============================================================================

#===============================================================================
# Global variables
#===============================================================================

# Configure path to the BSP folder
get_filename_component(SEARCH_PATH "${CMAKE_CURRENT_LIST_DIR}/../../../../../Bsp/Mcal/" REALPATH)

# Configure file name to be updated
set(SEARCH_FILENAME "CMakeLists.txt")

# Configure path to the BSP folder
get_filename_component(CMAKELISTS_HANDLER_PATH "${CMAKE_CURRENT_LIST_DIR}/../../../HelperTools/CMakeLists_Handler/CMakeLists_Handler.cmake" REALPATH)

# Include CMakeLists.txt handler
include(${CMAKELISTS_HANDLER_PATH})

# Header line of CMakeLists.txt files generated from the template
set(TEMPLATE_HEADER_PATTERN "^# Template version:[ \t]*[0-9]+\\.[0-9]+\\.[0-9]+")

# Last part of the template - module specific content follows it
set(TEMPLATE_END_PATTERN "Doxygen_AddPath\\([^\n]*\n[ \t]*endif\\(\\)")

#===============================================================================
# Search for all CMakeLists.txt files
#===============================================================================
if(DEFINED UPDATER_MODULE_DIR)
    # Executed by Updater.cmake for one module
    set(FOUND_FILES "")
    if(EXISTS "${UPDATER_MODULE_DIR}/${SEARCH_FILENAME}")
        set(FOUND_FILES "${UPDATER_MODULE_DIR}/${SEARCH_FILENAME}")
    endif()
else()
    file(GLOB_RECURSE FOUND_FILES
        "${SEARCH_PATH}/**/${SEARCH_FILENAME}"
    )
endif()

#===============================================================================
# Processing of found files
#===============================================================================

if(FOUND_FILES)

    list(LENGTH FOUND_FILES FILE_COUNT)

    message(STATUS "Found ${FILE_COUNT} files.")

    foreach(FILE_PATH ${FOUND_FILES})

        get_filename_component(FILE_DIR "${FILE_PATH}" DIRECTORY)

        file(READ "${FILE_PATH}" ORIGINAL_CONTENT)

        # Only module CMakeLists.txt generated from the template, not test sets
        if(NOT ORIGINAL_CONTENT MATCHES "${TEMPLATE_HEADER_PATTERN}" OR
           FILE_PATH MATCHES "/Tests/")
            message(STATUS "Skipping file (not generated from the template): ${FILE_PATH}")
            continue()
        endif()

        # Module specific content after the template part
        string(REGEX MATCH "${TEMPLATE_END_PATTERN}" TEMPLATE_END "${ORIGINAL_CONTENT}")

        if("${TEMPLATE_END}" STREQUAL "")
            message(STATUS "Skipping file (template part not found): ${FILE_PATH}")
            continue()
        endif()

        string(FIND "${ORIGINAL_CONTENT}" "${TEMPLATE_END}" TEMPLATE_END_POS)
        string(LENGTH "${TEMPLATE_END}" TEMPLATE_END_LEN)
        math(EXPR TAIL_POS "${TEMPLATE_END_POS} + ${TEMPLATE_END_LEN}")
        string(SUBSTRING "${ORIGINAL_CONTENT}" ${TAIL_POS} -1 MODULE_TAIL)

        # Line endings of the file are kept
        CMakeLists_Handler_Get_NewlineStyle( "${FILE_PATH}" NEWLINE_STYLE )

        message(STATUS "================================================================================")
        message(STATUS "Processing file: ${FILE_DIR} to version: ${VERSION_ID}")
        message(STATUS "================================================================================")

        CMakeLists_Handler_Get_Version( ${FILE_DIR} OUT_VERSION )

        # Template version never decreases
        if(OUT_VERSION VERSION_GREATER VERSION_ID)
            CMakeLists_Handler_Set_Version( ${OUT_VERSION} )
        else()
            CMakeLists_Handler_Set_Version( ${VERSION_ID} )
        endif()

        CMakeLists_Handler_Get_PrivateIncludeDirs( ${FILE_DIR} OUT_PRIVATE_INCLUDE_DIRS )
        CMakeLists_Handler_Set_PrivateInlcudeDirs( "${OUT_PRIVATE_INCLUDE_DIRS}" )

        CMakeLists_Handler_Get_PublicIncludeDirs( ${FILE_DIR} OUT_PUBLIC_INCLUDE_DIRS )
        CMakeLists_Handler_Set_PublicInlcudeDirs( "${OUT_PUBLIC_INCLUDE_DIRS}" )

        CMakeLists_Handler_Get_SourceFiles( ${FILE_DIR} OUT_SOURCE_FILES )
        CMakeLists_Handler_Set_SourceFiles( "${OUT_SOURCE_FILES}" )

        CMakeLists_Handler_Get_PublicHeaderFiles( ${FILE_DIR} OUT_PUBLIC_HEADER_FILES )
        CMakeLists_Handler_Set_PublicHeaderFiles( "${OUT_PUBLIC_HEADER_FILES}" )

        CMakeLists_Handler_Get_PublicDependenLibs( ${FILE_DIR} OUT_PUBLIC_DEPENDENT_LIBS )
        CMakeLists_Handler_Set_PublicDependenLibs( "${OUT_PUBLIC_DEPENDENT_LIBS}" )

        CMakeLists_Handler_Get_PrivateDependentLibs( ${FILE_DIR} OUT_PRIVATE_DEPENDENT_LIBS )
        CMakeLists_Handler_Set_PrivateDependentLibs( "${OUT_PRIVATE_DEPENDENT_LIBS}" )

        CMakeLists_Handler_Get_ModuleName( ${FILE_DIR} OUT_MODULE_NAME )
        if("${OUT_MODULE_NAME}" STREQUAL "")
            message(STATUS "Skipping file (module name not found): ${FILE_PATH}")
            continue()
        endif()
        CMakeLists_Handler_Set_ModuleName( "${OUT_MODULE_NAME}" )

        CMakeLists_Handler_Generate_CMakeLists( ${FILE_DIR} )

        # Module specific content after the template part is kept
        file(READ "${FILE_PATH}" GENERATED_CONTENT)
        string(REGEX REPLACE "\n+$" "" GENERATED_CONTENT "${GENERATED_CONTENT}")
        CMakeLists_Handler_Write_File( "${FILE_PATH}" "${GENERATED_CONTENT}${MODULE_TAIL}" ${NEWLINE_STYLE} )

    endforeach()

else()

    message(STATUS "No files found.")

endif()
