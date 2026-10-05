# ==============================================================================
# Update of include directories in module CMakeLists.txt files
#
# Module CMakeLists.txt generated from the template before AB#555 contains in
# target_include_directories() names of include directory variables instead of
# their values, so directories listed in <Module>_PublicIncludeDirs and
# <Module>_PrivateIncludeDirs were never used:
#
#     PUBLIC  ... <Module>_PublicIncludeDirs
#     PRIVATE ${<Module>_IncludeDirs} <Module>_PrivateIncludeDirs
#
# The step changes only these lines to (the rest of the file is kept):
#
#     PUBLIC  ... ${<Module>_PublicIncludeDirs}
#     PRIVATE ${<Module>_PrivateIncludeDirs}
#
# ${<Module>_IncludeDirs} is removed only if the module does not set the
# variable. The step is idempotent and keeps line endings of the file.
#
# Executed by Updater.cmake for every module (UPDATER_MODULE_DIR).
# ==============================================================================

#===============================================================================
# Global variables
#===============================================================================

# Path to CMakeLists.txt handler (file helpers)
get_filename_component(CMAKELISTS_HANDLER_PATH "${CMAKE_CURRENT_LIST_DIR}/../../../HelperTools/CMakeLists_Handler/CMakeLists_Handler.cmake" REALPATH)

# Include CMakeLists.txt handler
include(${CMAKELISTS_HANDLER_PATH})

#===============================================================================
# Processing of module CMakeLists.txt
#===============================================================================

if(NOT DEFINED UPDATER_MODULE_DIR)
    message(FATAL_ERROR "UPDATER_MODULE_DIR is not defined - the step is executed by Updater.cmake.")
endif()

set(INCLUDE_DIRS_FILE_PATH "${UPDATER_MODULE_DIR}/CMakeLists.txt")

if(EXISTS "${INCLUDE_DIRS_FILE_PATH}")

    file(READ "${INCLUDE_DIRS_FILE_PATH}" INCLUDE_DIRS_CONTENT)

    # Include directories of the library target
    string(REGEX MATCH "target_include_directories[ \t]*\\([^)]*\\)" INCLUDE_DIRS_BLOCK "${INCLUDE_DIRS_CONTENT}")

    if(NOT "${INCLUDE_DIRS_BLOCK}" STREQUAL "")

        set(INCLUDE_DIRS_NEW_BLOCK "${INCLUDE_DIRS_BLOCK}")

        # Variable names on own line -> variable values
        string(REGEX REPLACE "\n([ \t]+)([A-Za-z0-9_]+_(Public|Private)IncludeDirs)([ \t]*)\n"
                             "\n\\1\${\\2}\n"
                             INCLUDE_DIRS_NEW_BLOCK "${INCLUDE_DIRS_NEW_BLOCK}")

        # Second pass for directly following lines (shared line break of the first pass)
        string(REGEX REPLACE "\n([ \t]+)([A-Za-z0-9_]+_(Public|Private)IncludeDirs)([ \t]*)\n"
                             "\n\\1\${\\2}\n"
                             INCLUDE_DIRS_NEW_BLOCK "${INCLUDE_DIRS_NEW_BLOCK}")

        # Never defined ${<Module>_IncludeDirs} (template defines _PrivateIncludeDirs)
        string(REGEX MATCHALL "\\\${([A-Za-z0-9_]+)_IncludeDirs}" INCLUDE_DIRS_REFS "${INCLUDE_DIRS_NEW_BLOCK}")

        foreach(INCLUDE_DIRS_REF IN LISTS INCLUDE_DIRS_REFS)

            string(REGEX REPLACE "^\\\${([A-Za-z0-9_]+)}$" "\\1" INCLUDE_DIRS_VAR "${INCLUDE_DIRS_REF}")

            if(NOT INCLUDE_DIRS_CONTENT MATCHES "set[ \t]*\\([ \t\n]*${INCLUDE_DIRS_VAR}[ \t\n]")
                string(REGEX REPLACE "\n[ \t]+\\\${${INCLUDE_DIRS_VAR}}[ \t]*\n"
                                     "\n"
                                     INCLUDE_DIRS_NEW_BLOCK "${INCLUDE_DIRS_NEW_BLOCK}")
            endif()

        endforeach()

        if(NOT "${INCLUDE_DIRS_NEW_BLOCK}" STREQUAL "${INCLUDE_DIRS_BLOCK}")

            string(REPLACE "${INCLUDE_DIRS_BLOCK}" "${INCLUDE_DIRS_NEW_BLOCK}" INCLUDE_DIRS_CONTENT "${INCLUDE_DIRS_CONTENT}")

            CMakeLists_Handler_Get_NewlineStyle( "${INCLUDE_DIRS_FILE_PATH}" INCLUDE_DIRS_NEWLINE_STYLE )
            CMakeLists_Handler_Write_File( "${INCLUDE_DIRS_FILE_PATH}" "${INCLUDE_DIRS_CONTENT}" ${INCLUDE_DIRS_NEWLINE_STYLE} )

            message(STATUS "    Include directories updated: ${INCLUDE_DIRS_FILE_PATH}")

        else()

            message(STATUS "    Include directories up to date")

        endif()

    else()

        message(STATUS "    No target_include_directories() in ${INCLUDE_DIRS_FILE_PATH}")

    endif()

endif()
