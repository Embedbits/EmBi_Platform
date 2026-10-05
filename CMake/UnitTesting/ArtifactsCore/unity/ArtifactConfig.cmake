set(UNITY_CURRENT_LIST_DIR ${CMAKE_CURRENT_LIST_DIR})
#------------------------------------------------------------------------------#
# Returns artifact version.
#
# The name of function must consist of folder name (unity) and postfix
# (_GetArtifactVersion). Otherwise the buildprocess will fail.
#
# RET_VERSION [out]: Version of artifact in format X.Y.Z
#------------------------------------------------------------------------------#
function(unity_GetArtifactVersion RET_VERSION)

    set(VERSION "")

    if(EXISTS "${UNITY_ROOT}/src/unity.h")

        file(STRINGS "${UNITY_ROOT}/src/unity.h" VERSION_LINES
             REGEX "#define[ \t]+UNITY_VERSION_(MAJOR|MINOR|BUILD)[ \t]")

        foreach(VERSION_PART IN ITEMS MAJOR MINOR BUILD)
            string(REGEX MATCH "UNITY_VERSION_${VERSION_PART}[ \t]+([0-9]+)" _ "${VERSION_LINES}")
            list(APPEND VERSION "${CMAKE_MATCH_1}")
        endforeach()

        string(REPLACE ";" "." VERSION "${VERSION}")

    endif()

    set(${RET_VERSION} "${VERSION}" PARENT_SCOPE)

endfunction()


#------------------------------------------------------------------------------#
# Initialize artifact for build.
#
# The name of function must consist of folder name (unity) and postfix
# (_ArtifactInit). Otherwise the buildprocess will fail.
#
# Binary part contains Unity sources (OS independent, same archive is released
# for Win, Unix and DarwinARM). Sets UNITY_ROOT used by UnitTesting.cmake.
#
# ARTIFACT_BIN_PATH_ARG [in]: Path to the binary part of artifact
#------------------------------------------------------------------------------#
function(unity_ArtifactInit ARTIFACT_BIN_PATH_ARG)

    file(GLOB_RECURSE UNITY_SOURCES "${ARTIFACT_BIN_PATH_ARG}/*/unity.c")

    list(FILTER UNITY_SOURCES INCLUDE REGEX "/src/unity\\.c$")
    list(FILTER UNITY_SOURCES EXCLUDE REGEX "/vendor/")

    if(UNITY_SOURCES)

        list(GET UNITY_SOURCES 0 UNITY_SOURCE)

        get_filename_component(UNITY_SRC_DIR "${UNITY_SOURCE}" DIRECTORY)
        get_filename_component(UNITY_ROOT_DIR "${UNITY_SRC_DIR}" DIRECTORY)

        set(UNITY_ROOT "${UNITY_ROOT_DIR}" CACHE PATH "Unity root folder" FORCE)

        message(STATUS "Unity found in: ${UNITY_ROOT_DIR}")

    else()

        message(FATAL_ERROR "File src/unity.c not found in ${ARTIFACT_BIN_PATH_ARG}.")

    endif()

endfunction()
