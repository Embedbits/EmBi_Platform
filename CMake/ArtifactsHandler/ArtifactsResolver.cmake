###############################################################################
# Artifacts resolver functionality
#
# Scripts executed outside of the configuration of a preset (VSCode tasks and
# debug configurations, detection of boards, flashing) need a tool of an
# artifact. The tool is never taken from the system or as the newest version
# found in the artifacts cache - the version is the one configured for the
# preset (ARTIFACTS_HANDLER_REQ_LIST of the configure preset, resolved through
# the inheritance of the presets of the project) or by ArtifactsConfig.txt of
# the project, the same list the artifacts handler uses when the preset is
# configured. "latest" of the configuration means the newest version, as the
# handler resolves it (the newest cached version, refreshed from remote once a
# day by the configuration of a preset).
#
# The functions do not print anything (the output of some scripts is read by
# VSCode).
###############################################################################

#------------------------------------------------------------------------------#
# Loads the configure presets of the project (CMakePresets.json and the files
# of its "include") into the variables ARTIFACTS_RESOLVER_PRESET_<name> (JSON
# of the preset) and the list ARTIFACTS_RESOLVER_PRESET_NAMES of the scope
# of the caller (macro).
#
# PROJECT_DIR [in]: Project root folder
#------------------------------------------------------------------------------#
macro(ArtifactsResolver_Load_Presets PROJECT_DIR)

    set(ARTIFACTS_RESOLVER_PRESET_NAMES "")

    set(ARTIFACTS_RESOLVER_QUEUE "${PROJECT_DIR}/CMakePresets.json" "${PROJECT_DIR}/CMakeUserPresets.json")
    set(ARTIFACTS_RESOLVER_SEEN  "")

    while(ARTIFACTS_RESOLVER_QUEUE)

        list(POP_FRONT ARTIFACTS_RESOLVER_QUEUE ARTIFACTS_RESOLVER_FILE)

        if(EXISTS "${ARTIFACTS_RESOLVER_FILE}")
            file(REAL_PATH "${ARTIFACTS_RESOLVER_FILE}" ARTIFACTS_RESOLVER_FILE)
        endif()

        if(EXISTS "${ARTIFACTS_RESOLVER_FILE}" AND NOT "${ARTIFACTS_RESOLVER_FILE}" IN_LIST ARTIFACTS_RESOLVER_SEEN)

            list(APPEND ARTIFACTS_RESOLVER_SEEN "${ARTIFACTS_RESOLVER_FILE}")

            file(READ "${ARTIFACTS_RESOLVER_FILE}" ARTIFACTS_RESOLVER_CONTENT)
            get_filename_component(ARTIFACTS_RESOLVER_DIR "${ARTIFACTS_RESOLVER_FILE}" DIRECTORY)

            # Included files
            string(JSON ARTIFACTS_RESOLVER_CNT ERROR_VARIABLE ARTIFACTS_RESOLVER_ERROR LENGTH "${ARTIFACTS_RESOLVER_CONTENT}" include)

            if(NOT ARTIFACTS_RESOLVER_ERROR AND ARTIFACTS_RESOLVER_CNT GREATER 0)
                math(EXPR ARTIFACTS_RESOLVER_LAST "${ARTIFACTS_RESOLVER_CNT} - 1")
                foreach(ARTIFACTS_RESOLVER_IDX RANGE ${ARTIFACTS_RESOLVER_LAST})
                    string(JSON ARTIFACTS_RESOLVER_INCLUDE GET "${ARTIFACTS_RESOLVER_CONTENT}" include ${ARTIFACTS_RESOLVER_IDX})
                    cmake_path(IS_ABSOLUTE ARTIFACTS_RESOLVER_INCLUDE ARTIFACTS_RESOLVER_IS_ABSOLUTE)
                    if(NOT ARTIFACTS_RESOLVER_IS_ABSOLUTE)
                        set(ARTIFACTS_RESOLVER_INCLUDE "${ARTIFACTS_RESOLVER_DIR}/${ARTIFACTS_RESOLVER_INCLUDE}")
                    endif()
                    list(APPEND ARTIFACTS_RESOLVER_QUEUE "${ARTIFACTS_RESOLVER_INCLUDE}")
                endforeach()
            endif()

            # Configure presets
            string(JSON ARTIFACTS_RESOLVER_CNT ERROR_VARIABLE ARTIFACTS_RESOLVER_ERROR LENGTH "${ARTIFACTS_RESOLVER_CONTENT}" configurePresets)

            if(NOT ARTIFACTS_RESOLVER_ERROR AND ARTIFACTS_RESOLVER_CNT GREATER 0)
                math(EXPR ARTIFACTS_RESOLVER_LAST "${ARTIFACTS_RESOLVER_CNT} - 1")
                foreach(ARTIFACTS_RESOLVER_IDX RANGE ${ARTIFACTS_RESOLVER_LAST})
                    string(JSON ARTIFACTS_RESOLVER_NAME GET "${ARTIFACTS_RESOLVER_CONTENT}" configurePresets ${ARTIFACTS_RESOLVER_IDX} name)
                    string(JSON ARTIFACTS_RESOLVER_JSON GET "${ARTIFACTS_RESOLVER_CONTENT}" configurePresets ${ARTIFACTS_RESOLVER_IDX})
                    set(ARTIFACTS_RESOLVER_PRESET_${ARTIFACTS_RESOLVER_NAME} "${ARTIFACTS_RESOLVER_JSON}")
                    list(APPEND ARTIFACTS_RESOLVER_PRESET_NAMES "${ARTIFACTS_RESOLVER_NAME}")
                endforeach()
            endif()

        endif()

    endwhile()

endmacro(ArtifactsResolver_Load_Presets)


#------------------------------------------------------------------------------#
# Returns the value of a cache variable of a configure preset - own value of the
# preset or the value of the first preset of its "inherits" that sets it (the
# presets listed earlier take precedence, as CMake does). The presets have to be
# loaded (ArtifactsResolver_Load_Presets) in the scope of the caller.
#
# PRESET    [in]:  Name of the configure preset
# VAR_NAME  [in]:  Name of the cache variable
# VALUE_VAR [out]: Value ("" if the variable is not set)
#------------------------------------------------------------------------------#
function(ArtifactsResolver_Get_PresetCacheVariable PRESET VAR_NAME VALUE_VAR)

    set(VALUE "")

    if(DEFINED ARTIFACTS_RESOLVER_PRESET_${PRESET})

        set(PRESET_JSON "${ARTIFACTS_RESOLVER_PRESET_${PRESET}}")

        string(JSON VALUE_TYPE ERROR_VARIABLE VALUE_ERROR TYPE "${PRESET_JSON}" cacheVariables "${VAR_NAME}")

        if(NOT VALUE_ERROR)

            if(VALUE_TYPE STREQUAL "OBJECT")
                string(JSON VALUE GET "${PRESET_JSON}" cacheVariables "${VAR_NAME}" value)
            else()
                string(JSON VALUE GET "${PRESET_JSON}" cacheVariables "${VAR_NAME}")
            endif()

        else()

            # Parents - one preset or an array of presets
            set(PARENTS "")

            string(JSON INHERITS_TYPE ERROR_VARIABLE INHERITS_ERROR TYPE "${PRESET_JSON}" inherits)

            if(NOT INHERITS_ERROR)
                if(INHERITS_TYPE STREQUAL "ARRAY")
                    string(JSON PARENTS_CNT LENGTH "${PRESET_JSON}" inherits)
                    if(PARENTS_CNT GREATER 0)
                        math(EXPR PARENTS_LAST "${PARENTS_CNT} - 1")
                        foreach(PARENT_IDX RANGE ${PARENTS_LAST})
                            string(JSON PARENT GET "${PRESET_JSON}" inherits ${PARENT_IDX})
                            list(APPEND PARENTS "${PARENT}")
                        endforeach()
                    endif()
                else()
                    string(JSON PARENT GET "${PRESET_JSON}" inherits)
                    list(APPEND PARENTS "${PARENT}")
                endif()
            endif()

            foreach(PARENT IN LISTS PARENTS)
                ArtifactsResolver_Get_PresetCacheVariable("${PARENT}" "${VAR_NAME}" PARENT_VALUE)
                if(NOT "${PARENT_VALUE}" STREQUAL "")
                    set(VALUE "${PARENT_VALUE}")
                    break()
                endif()
            endforeach()

        endif()

    endif()

    set(${VALUE_VAR} "${VALUE}" PARENT_SCOPE)

endfunction(ArtifactsResolver_Get_PresetCacheVariable)


#------------------------------------------------------------------------------#
# Returns the configure preset of the project whose name ends with the suffix
# (e.g. "_IntegrationTest"): the preset of the MCU if the MCU is given, otherwise
# the first generated preset of the project.
#
# PRESET_VAR [out]: Preset ("" if there is none)
# PROJECT_DIR [in]: Project root folder
# SUFFIX      [in]: Suffix of the preset name
# MCU         [in]: MCU ("" = any)
#------------------------------------------------------------------------------#
function(ArtifactsResolver_Find_Preset PRESET_VAR PROJECT_DIR SUFFIX MCU)

    ArtifactsResolver_Load_Presets("${PROJECT_DIR}")

    set(FOUND "")

    if(NOT "${MCU}" STREQUAL "" AND "${MCU}${SUFFIX}" IN_LIST ARTIFACTS_RESOLVER_PRESET_NAMES)

        set(FOUND "${MCU}${SUFFIX}")

    elseif("${MCU}" STREQUAL "")

        foreach(NAME IN LISTS ARTIFACTS_RESOLVER_PRESET_NAMES)
            string(JSON HIDDEN ERROR_VARIABLE HIDDEN_ERROR GET "${ARTIFACTS_RESOLVER_PRESET_${NAME}}" hidden)
            if("${NAME}" MATCHES "${SUFFIX}$" AND (HIDDEN_ERROR OR NOT HIDDEN))
                set(FOUND "${NAME}")
                break()
            endif()
        endforeach()

    endif()

    set(${PRESET_VAR} "${FOUND}" PARENT_SCOPE)

endfunction(ArtifactsResolver_Find_Preset)


#------------------------------------------------------------------------------#
# Returns the configured record of an artifact: "<name>|<Bin version>|<Core
# version>". The list is the same one the artifacts handler uses: the parameter
# or the environment variable ARTIFACTS_HANDLER_REQ_LIST, ARTIFACTS_HANDLER_REQ_LIST
# of the preset, ArtifactsConfig.txt of the project.
#
# RECORD_VAR  [out]: Record ("" if the artifact is not configured)
# PROJECT_DIR [in]:  Project root folder
# PRESET      [in]:  Configure preset ("" = only ArtifactsConfig.txt)
# NAME        [in]:  Name of the artifact
#------------------------------------------------------------------------------#
function(ArtifactsResolver_Get_Record RECORD_VAR PROJECT_DIR PRESET NAME)

    set(REQ_LIST "")

    if(DEFINED ARTIFACTS_HANDLER_REQ_LIST AND NOT "${ARTIFACTS_HANDLER_REQ_LIST}" STREQUAL "")
        set(REQ_LIST "${ARTIFACTS_HANDLER_REQ_LIST}")
    elseif(DEFINED ENV{ARTIFACTS_HANDLER_REQ_LIST} AND NOT "$ENV{ARTIFACTS_HANDLER_REQ_LIST}" STREQUAL "")
        set(REQ_LIST "$ENV{ARTIFACTS_HANDLER_REQ_LIST}")
    elseif(NOT "${PRESET}" STREQUAL "")
        ArtifactsResolver_Load_Presets("${PROJECT_DIR}")
        ArtifactsResolver_Get_PresetCacheVariable("${PRESET}" ARTIFACTS_HANDLER_REQ_LIST REQ_LIST)
    endif()

    # The list is parsed by the functions of the handler (the same list and format the handler uses)
    set(ARTIFACTS "")

    if(NOT "${REQ_LIST}" STREQUAL "")
        ParamsHandler_Get_ArtifactsList("${REQ_LIST}" ARTIFACTS)
    elseif(EXISTS "${PROJECT_DIR}/ArtifactsConfig.txt")
        ConfigFileHandler_Get_ArtifactsList("${PROJECT_DIR}/ArtifactsConfig.txt" ARTIFACTS)
    endif()

    string(REPLACE "_" "-" NAME_NORMALIZED "${NAME}")

    set(FOUND "")

    foreach(ARTIFACT IN LISTS ARTIFACTS)

        list(GET ARTIFACT 0 ARTIFACT_NAME)

        if("${ARTIFACT_NAME}" STREQUAL "${NAME_NORMALIZED}")
            list(GET ARTIFACT 1 ARTIFACT_BIN_VERSION)
            list(GET ARTIFACT 2 ARTIFACT_CORE_VERSION)
            set(FOUND "${ARTIFACT_NAME}|${ARTIFACT_BIN_VERSION}|${ARTIFACT_CORE_VERSION}")
            break()
        endif()

    endforeach()

    set(${RECORD_VAR} "${FOUND}" PARENT_SCOPE)

endfunction(ArtifactsResolver_Get_Record)


#------------------------------------------------------------------------------#
# Returns the Bin folder of the cached artifact in the version configured for
# the preset (the version of the artifacts handler: the exact version, or the
# newest cached one for "latest").
#
# DIR_VAR     [out]: Bin folder of the artifact ("" if the artifact is not
#                    configured or the configured version is not cached)
# RECORD_VAR  [out]: Configured record of the artifact ("" if it is not
#                    configured), see ArtifactsResolver_Get_Record
# PROJECT_DIR [in]:  Project root folder
# PRESET      [in]:  Configure preset ("" = only ArtifactsConfig.txt)
# NAME        [in]:  Name of the artifact
#------------------------------------------------------------------------------#
function(ArtifactsResolver_Get_BinDir DIR_VAR RECORD_VAR PROJECT_DIR PRESET NAME)

    ArtifactsResolver_Get_Record(RECORD "${PROJECT_DIR}" "${PRESET}" "${NAME}")

    set(DIR "")

    if(NOT "${RECORD}" STREQUAL "")

        string(REPLACE "|" ";" RECORD_FIELDS "${RECORD}")
        list(GET RECORD_FIELDS 0 ARTIFACT_NAME)
        list(GET RECORD_FIELDS 1 BIN_VERSION)

        ArtifactsHandler_Get_ArtifactsCachePath("${PROJECT_DIR}/ArtifactsConfig.txt" CACHE_PATH)
        file(TO_CMAKE_PATH "${CACHE_PATH}" CACHE_PATH)

        CacheHandler_Check_CachedArtifact_Bin("${CACHE_PATH}" "${ARTIFACT_NAME}" "${BIN_VERSION}" CACHED_STATE CACHED_VERSION)

        if(CACHED_STATE)
            set(DIR "${CACHE_PATH}/${ARTIFACT_NAME}/Bin/${CACHED_VERSION}")
        endif()

    endif()

    set(${DIR_VAR}    "${DIR}"    PARENT_SCOPE)
    set(${RECORD_VAR} "${RECORD}" PARENT_SCOPE)

endfunction(ArtifactsResolver_Get_BinDir)


#------------------------------------------------------------------------------#
# Downloads the artifact in the configured version by the artifacts handler
# (separate process, the cache folder of the project) into the artifacts cache.
#
# PROJECT_DIR [in]: Project root folder
# RECORD      [in]: Configured record of the artifact, see ArtifactsResolver_Get_Record
#------------------------------------------------------------------------------#
function(ArtifactsResolver_Download PROJECT_DIR RECORD)

    set(HANDLER "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/ArtifactsHandler.cmake")

    if(NOT EXISTS "${HANDLER}")
        message(WARNING "The artifacts handler was not found (${HANDLER}).")
        return()
    endif()

    message(STATUS "Downloading the artifact ${RECORD} by the artifacts handler.")

    # The handler runs in its own process - it does not see the CMake parameters of
    # this script, so the cache folder parameter is passed on.
    set(HANDLER_ARGS "-DCONFIG_FILE_PATH=${PROJECT_DIR}")

    if(NOT "${ARTIFACTS_HANDLER_CACHE_PATH}" STREQUAL "")
        list(APPEND HANDLER_ARGS "-DARTIFACTS_HANDLER_CACHE_PATH=${ARTIFACTS_HANDLER_CACHE_PATH}")
    else()
        # Cache folder from the environment variable / ArtifactsConfig.txt
    endif()

    string(REPLACE "|" ";" ENV_LIST "${RECORD}")
    set(ENV{ARTIFACTS_HANDLER_REQ_LIST} "${ENV_LIST}")

    execute_process(COMMAND           "${CMAKE_COMMAND}" ${HANDLER_ARGS} -P "${HANDLER}"
                    WORKING_DIRECTORY "${PROJECT_DIR}"
                    RESULT_VARIABLE   DOWNLOAD_RESULT)

    unset(ENV{ARTIFACTS_HANDLER_REQ_LIST})

    if(NOT DOWNLOAD_RESULT EQUAL 0)
        message(WARNING "Download of the artifact ${RECORD} failed (${DOWNLOAD_RESULT}).")
    endif()

endfunction(ArtifactsResolver_Download)


#------------------------------------------------------------------------------#
# Provides the Bin folder of the artifact in the configured version - the cached
# one, otherwise the artifact is downloaded by the artifacts handler.
#
# DIR_VAR     [out]: Bin folder of the artifact ("" if the artifact is not
#                    configured or its download failed)
# PROJECT_DIR [in]:  Project root folder
# PRESET      [in]:  Configure preset ("" = only ArtifactsConfig.txt)
# NAME        [in]:  Name of the artifact
#------------------------------------------------------------------------------#
function(ArtifactsResolver_Provide DIR_VAR PROJECT_DIR PRESET NAME)

    ArtifactsResolver_Get_BinDir(DIR RECORD "${PROJECT_DIR}" "${PRESET}" "${NAME}")

    if("${DIR}" STREQUAL "" AND NOT "${RECORD}" STREQUAL "")
        ArtifactsResolver_Download("${PROJECT_DIR}" "${RECORD}")
        ArtifactsResolver_Get_BinDir(DIR RECORD "${PROJECT_DIR}" "${PRESET}" "${NAME}")
    endif()

    set(${DIR_VAR} "${DIR}" PARENT_SCOPE)

endfunction(ArtifactsResolver_Provide)
