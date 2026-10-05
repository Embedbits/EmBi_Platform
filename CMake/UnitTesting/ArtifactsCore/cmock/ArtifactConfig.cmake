set(CMOCK_CURRENT_LIST_DIR ${CMAKE_CURRENT_LIST_DIR})
#------------------------------------------------------------------------------#
# Returns artifact version.
#
# The name of function must consist of folder name (cmock) and postfix
# (_GetArtifactVersion). Otherwise the buildprocess will fail.
#
# RET_VERSION [out]: Version of artifact in format X.Y.Z
#------------------------------------------------------------------------------#
function(cmock_GetArtifactVersion RET_VERSION)

    set(VERSION "")

    if(EXISTS "${CMOCK_ROOT}/src/cmock.h")

        file(STRINGS "${CMOCK_ROOT}/src/cmock.h" VERSION_LINES
             REGEX "#define[ \t]+CMOCK_VERSION_(MAJOR|MINOR|BUILD)[ \t]")

        foreach(VERSION_PART IN ITEMS MAJOR MINOR BUILD)
            string(REGEX MATCH "CMOCK_VERSION_${VERSION_PART}[ \t]+([0-9]+)" _ "${VERSION_LINES}")
            list(APPEND VERSION "${CMAKE_MATCH_1}")
        endforeach()

        string(REPLACE ";" "." VERSION "${VERSION}")

    endif()

    set(${RET_VERSION} "${VERSION}" PARENT_SCOPE)

endfunction()


#------------------------------------------------------------------------------#
# Initialize artifact for build.
#
# The name of function must consist of folder name (cmock) and postfix
# (_ArtifactInit). Otherwise the buildprocess will fail.
#
# Binary part contains CMock sources INCLUDING its git submodules
# (vendor/unity, vendor/c_exception) - cmock.rb loads Ruby scripts from
# vendor/unity/auto. Archive is OS independent. Sets CMOCK_ROOT used by
# UnitTesting.cmake.
#
# ARTIFACT_BIN_PATH_ARG [in]: Path to the binary part of artifact
#------------------------------------------------------------------------------#
function(cmock_ArtifactInit ARTIFACT_BIN_PATH_ARG)

    file(GLOB_RECURSE CMOCK_SCRIPTS "${ARTIFACT_BIN_PATH_ARG}/*/cmock.rb")

    list(FILTER CMOCK_SCRIPTS INCLUDE REGEX "/lib/cmock\\.rb$")

    if(CMOCK_SCRIPTS)

        list(GET CMOCK_SCRIPTS 0 CMOCK_SCRIPT)

        get_filename_component(CMOCK_LIB_DIR "${CMOCK_SCRIPT}" DIRECTORY)
        get_filename_component(CMOCK_ROOT_DIR "${CMOCK_LIB_DIR}" DIRECTORY)

        if(NOT EXISTS "${CMOCK_ROOT_DIR}/vendor/unity/auto/type_sanitizer.rb")
            message(FATAL_ERROR "CMock artifact is incomplete, vendor/unity submodule is missing.")
        endif()

        set(CMOCK_ROOT "${CMOCK_ROOT_DIR}" CACHE PATH "CMock root folder" FORCE)

        message(STATUS "CMock found in: ${CMOCK_ROOT_DIR}")

    else()

        message(FATAL_ERROR "File lib/cmock.rb not found in ${ARTIFACT_BIN_PATH_ARG}.")

    endif()

endfunction()
