# ==============================================================================
# Definition of the doxygen group of the module
#
# Files of modules generated from the templates before AB#612 are assigned to
# the module group (\ingroup <Module>), but the group is never defined, so
# doxygen ignores the assignment ("Found non-existing group") and the modules
# have no group page in the documentation.
#
# For every group used by the files of the module folder (not subfolders) and
# not defined anywhere in the module, the step inserts at the beginning of the
# header of the group (same block as the current templates):
#
#     /**
#      * \defgroup <Module> <Module>
#      * \brief <Module> module
#      */
#
# Header of the group is <Module>_Types.h (one per module), otherwise
# <Module>.h, otherwise the first header of the module folder assigned to the
# group. The rest of the file is kept. The step is idempotent and keeps line
# endings of the file.
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
# Processing of module files
#===============================================================================

if(NOT DEFINED UPDATER_MODULE_DIR)
    message(FATAL_ERROR "UPDATER_MODULE_DIR is not defined - the step is executed by Updater.cmake.")
endif()

# Groups used by the files of the module folder
file(GLOB DOXY_GROUP_ROOT_FILES
    "${UPDATER_MODULE_DIR}/*.h"
    "${UPDATER_MODULE_DIR}/*.c"
    "${UPDATER_MODULE_DIR}/*.hpp"
    "${UPDATER_MODULE_DIR}/*.cpp")

list(SORT DOXY_GROUP_ROOT_FILES)

set(DOXY_GROUP_LIST "")

foreach(DOXY_GROUP_FILE IN LISTS DOXY_GROUP_ROOT_FILES)

    file(READ "${DOXY_GROUP_FILE}" DOXY_GROUP_FILE_CONTENT)
    string(REGEX MATCHALL "[\\\\@]ingroup[ \t]+[A-Za-z0-9_]+" DOXY_GROUP_REFS "${DOXY_GROUP_FILE_CONTENT}")

    foreach(DOXY_GROUP_REF IN LISTS DOXY_GROUP_REFS)
        string(REGEX REPLACE "^[\\\\@]ingroup[ \t]+" "" DOXY_GROUP_NAME "${DOXY_GROUP_REF}")
        list(APPEND DOXY_GROUP_LIST "${DOXY_GROUP_NAME}")
    endforeach()

endforeach()

list(REMOVE_DUPLICATES DOXY_GROUP_LIST)

if(NOT DOXY_GROUP_LIST)
    message(STATUS "    No doxygen group used in ${UPDATER_MODULE_DIR}")
endif()

# Groups already defined anywhere in the module (also tests, documents)
file(GLOB_RECURSE DOXY_GROUP_ALL_FILES
    "${UPDATER_MODULE_DIR}/*.h"
    "${UPDATER_MODULE_DIR}/*.c"
    "${UPDATER_MODULE_DIR}/*.hpp"
    "${UPDATER_MODULE_DIR}/*.cpp"
    "${UPDATER_MODULE_DIR}/*.md"
    "${UPDATER_MODULE_DIR}/*.dox")

set(DOXY_GROUP_DEFINED "")

foreach(DOXY_GROUP_FILE IN LISTS DOXY_GROUP_ALL_FILES)

    file(READ "${DOXY_GROUP_FILE}" DOXY_GROUP_FILE_CONTENT)
    string(REGEX MATCHALL "[\\\\@]defgroup[ \t]+[A-Za-z0-9_]+" DOXY_GROUP_DEFS "${DOXY_GROUP_FILE_CONTENT}")

    foreach(DOXY_GROUP_DEF IN LISTS DOXY_GROUP_DEFS)
        string(REGEX REPLACE "^[\\\\@]defgroup[ \t]+" "" DOXY_GROUP_NAME "${DOXY_GROUP_DEF}")
        list(APPEND DOXY_GROUP_DEFINED "${DOXY_GROUP_NAME}")
    endforeach()

endforeach()

foreach(DOXY_GROUP_NAME IN LISTS DOXY_GROUP_LIST)

    if("${DOXY_GROUP_NAME}" IN_LIST DOXY_GROUP_DEFINED)
        message(STATUS "    Doxygen group ${DOXY_GROUP_NAME} up to date")
        continue()
    endif()

    # Header of the group
    set(DOXY_GROUP_HEADER "")

    if(EXISTS "${UPDATER_MODULE_DIR}/${DOXY_GROUP_NAME}_Types.h")
        set(DOXY_GROUP_HEADER "${UPDATER_MODULE_DIR}/${DOXY_GROUP_NAME}_Types.h")
    elseif(EXISTS "${UPDATER_MODULE_DIR}/${DOXY_GROUP_NAME}.h")
        set(DOXY_GROUP_HEADER "${UPDATER_MODULE_DIR}/${DOXY_GROUP_NAME}.h")
    else()
        foreach(DOXY_GROUP_FILE IN LISTS DOXY_GROUP_ROOT_FILES)
            if("${DOXY_GROUP_FILE}" MATCHES "\\.(h|hpp)$")
                file(READ "${DOXY_GROUP_FILE}" DOXY_GROUP_FILE_CONTENT)
                if("${DOXY_GROUP_FILE_CONTENT}" MATCHES "[\\\\@]ingroup[ \t]+${DOXY_GROUP_NAME}([^A-Za-z0-9_]|$)")
                    set(DOXY_GROUP_HEADER "${DOXY_GROUP_FILE}")
                    break()
                endif()
            endif()
        endforeach()
    endif()

    if("${DOXY_GROUP_HEADER}" STREQUAL "")
        message(STATUS "    No header for doxygen group ${DOXY_GROUP_NAME} in ${UPDATER_MODULE_DIR}")
        continue()
    endif()

    file(READ "${DOXY_GROUP_HEADER}" DOXY_GROUP_HEADER_CONTENT)

    set(DOXY_GROUP_BLOCK "/**\n * \\defgroup ${DOXY_GROUP_NAME} ${DOXY_GROUP_NAME}\n * \\brief ${DOXY_GROUP_NAME} module\n */\n\n")

    CMakeLists_Handler_Get_NewlineStyle( "${DOXY_GROUP_HEADER}" DOXY_GROUP_NEWLINE_STYLE )
    CMakeLists_Handler_Write_File( "${DOXY_GROUP_HEADER}" "${DOXY_GROUP_BLOCK}${DOXY_GROUP_HEADER_CONTENT}" ${DOXY_GROUP_NEWLINE_STYLE} )

    message(STATUS "    Doxygen group ${DOXY_GROUP_NAME} defined: ${DOXY_GROUP_HEADER}")

endforeach()
