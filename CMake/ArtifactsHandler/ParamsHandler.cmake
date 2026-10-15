###############################################################################
# Artifacts Handler parameters handler functionality
###############################################################################


#------------------------------------------------------------------------------#
# Returns list of Required Artifacts from entered string.
#
# List of Required Artifacts can be entered through CMake parameter or
# environment variable "ARTIFACTS_HANDLER_REQ_LIST". Artifacts are separated by
# ',', every artifact has the same format as a line of ArtifactsConfig.txt:
#
#   ninja;1.12.0;latest,gcc-arm-none-eabi;latest;latest
#
# The list is returned in the same format as from ArtifactsConfig.txt file
# (ConfigFileHandler_Get_ArtifactsList).
#
# ARTIFACTS_LIST_STRING_ARG [in]:  Entered list of Required Artifacts.
# ARTIFACTS_LIST_ARG        [out]: List of Required Artifacts.
#------------------------------------------------------------------------------#
function(ParamsHandler_Get_ArtifactsList ARTIFACTS_LIST_STRING_ARG
                                         ARTIFACTS_LIST_ARG)

    if("${ARTIFACTS_LIST_STRING_ARG}" STREQUAL "")
        message(FATAL_ERROR "List of Required Artifacts is empty.")
    endif()

    # Version separator ';' is replaced, so the artifacts can be split by ','
    string(REPLACE ";" "|" ARTIFACTS_STRING "${ARTIFACTS_LIST_STRING_ARG}")
    string(REPLACE " " ""  ARTIFACTS_STRING "${ARTIFACTS_STRING}")
    string(REGEX MATCHALL "[^,]+" ARTIFACTS "${ARTIFACTS_STRING}")

    set(PARSED_LIST "")

    foreach(ARTIFACT IN LISTS ARTIFACTS)

        # Check format: NAME;BINARY_VERSION;HANDLER_VERSION
        if(NOT ARTIFACT MATCHES "^([^|]+)\\|([^|]+)\\|([^|]+)$")
            string(REPLACE "|" ";" ARTIFACT "${ARTIFACT}")
            message(FATAL_ERROR "Incorrect artifact format: '${ARTIFACT}'\nRequired format: NAME;BINARY_VERSION;HANDLER_VERSION")
        endif()

        string(REPLACE "|" "\;" ARTIFACT "${ARTIFACT}")
        string(REPLACE "_" "-"  ARTIFACT "${ARTIFACT}")

        list(APPEND PARSED_LIST "${ARTIFACT}")

    endforeach()

    set(${ARTIFACTS_LIST_ARG} "${PARSED_LIST}" PARENT_SCOPE)

endfunction(ParamsHandler_Get_ArtifactsList)
