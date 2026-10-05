set(RUBY_CURRENT_LIST_DIR ${CMAKE_CURRENT_LIST_DIR})
#------------------------------------------------------------------------------#
# Returns artifact version.
#
# The name of function must consist of folder name (ruby) and postfix
# (_GetArtifactVersion). Otherwise the buildprocess will fail.
#
# RET_VERSION [out]: Version of artifact in format X.Y.Z
#------------------------------------------------------------------------------#
function(ruby_GetArtifactVersion RET_VERSION)

    execute_process(COMMAND "${RUBY_EXECUTABLE}" --version
                    OUTPUT_VARIABLE ARTIFACT_VERSION
                    OUTPUT_STRIP_TRAILING_WHITESPACE)

    string(REGEX MATCH "[0-9]+\\.[0-9]+\\.[0-9]+" VERSION "${ARTIFACT_VERSION}")

    set(${RET_VERSION} "${VERSION}" PARENT_SCOPE)

endfunction()


#------------------------------------------------------------------------------#
# Initialize artifact for build.
#
# The name of function must consist of folder name (ruby) and postfix
# (_ArtifactInit). Otherwise the buildprocess will fail.
#
# Binary part (Windows) is extracted RubyInstaller archive (without devkit).
# On Unix the system Ruby is expected, artifact is released only for Win.
# Sets RUBY_EXECUTABLE used by UnitTesting.cmake.
#
# ARTIFACT_BIN_PATH_ARG [in]: Path to the binary part of artifact
#------------------------------------------------------------------------------#
function(ruby_ArtifactInit ARTIFACT_BIN_PATH_ARG)

    if(${CMAKE_HOST_SYSTEM_NAME} STREQUAL "Windows")
        set(RUBY_FILE_NAME "ruby.exe")
        set(PATH_SEPARATOR ";")
    else()
        set(RUBY_FILE_NAME "ruby")
        set(PATH_SEPARATOR ":")
    endif()

    file(GLOB_RECURSE RUBY_FILES "${ARTIFACT_BIN_PATH_ARG}/*/${RUBY_FILE_NAME}")

    list(FILTER RUBY_FILES INCLUDE REGEX "/bin/${RUBY_FILE_NAME}$")

    if(RUBY_FILES)

        list(GET RUBY_FILES 0 RUBY_FILE)

        get_filename_component(RUBY_BIN_DIR "${RUBY_FILE}" DIRECTORY)

        set(ENV{PATH} "${RUBY_BIN_DIR}${PATH_SEPARATOR}$ENV{PATH}")

        set(RUBY_EXECUTABLE "${RUBY_FILE}" CACHE FILEPATH "Ruby interpreter" FORCE)

        message(STATUS "Ruby found in: ${RUBY_BIN_DIR}")

    else()

        message(FATAL_ERROR "File ${RUBY_FILE_NAME} not found in ${ARTIFACT_BIN_PATH_ARG}.")

    endif()

endfunction()
