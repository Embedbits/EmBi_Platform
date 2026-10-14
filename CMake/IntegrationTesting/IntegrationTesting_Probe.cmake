################################################################################
# Author: Mr.Nobody
# file:  IntegrationTesting_Probe.cmake
# brief: Search of connected debug probes and identification of their MCU by
#        probe-rs.
#
# Included by host scripts IntegrationTesting_Run.cmake,
# IntegrationTesting_Detect.cmake and IntegrationTesting_AllBoards.cmake. Every
# probe supported by probe-rs can be used. The MCU of the board is identified
# by its ID register (and flash size register) read over the probe - address,
# mask and value come from the MCU identification of the Ral presets
# (RalPresets.json) or from parameters, the framework knows no MCU.
#
# Variables of the host configuration (IntegrationTesting_Host.cmake generated
# by IntegrationTesting.cmake):
#   IT_PROBE_RS          - probe-rs executable
#   IT_CHIP              - probe-rs chip name
#   IT_PROBE             - candidate probes (probe-rs selectors VID:PID[:SN] or
#                          serial numbers), empty = all connected probes
#   IT_ID_ADDRESS        - address of the ID register (empty = MCU is not checked)
#   IT_ID_MASK           - mask of the ID bits
#   IT_ID_VALUE          - expected ID (after mask)
#   IT_FLASH_SIZE_ADDRESS - address of the 16-bit flash size register [KB]
#                          (empty = flash size is not checked)
#   IT_FLASH_SIZE_KB     - expected flash size [KB]
#
# MCU identification of the Ral presets (vendor data of every MCU preset):
#   "vendor": { "embedbits.com/EmBi": { "target": "mcu",
#       "identification": { "device": "STM32F407VG", "core": "Cortex-M4",
#                           "idAddress": "0xE0042000", "idMask": "0x00000FFF", "idValue": "0x413",
#                           "flashSizeAddress": "0x1FFF7A22", "flashSizeKB": 1024 } } }
# The core is a generic probe-rs target - registers are read before the chip
# of the board is known. The device is the default probe-rs chip of the MCU.
################################################################################

include_guard(GLOBAL)

# Functions of the artifacts handler (cache folder, configuration file); the
# handler itself is not started by this include. The include is on the level of
# the script, the functions use the variables set by it.
set(ARTIFACTS_HANDLER_NO_RUN TRUE)
include("${CMAKE_CURRENT_LIST_DIR}/../ArtifactsHandler/ArtifactsHandler.cmake")
unset(ARTIFACTS_HANDLER_NO_RUN)

# Vendor key of EmBi data in CMake presets
set(IT_PRESETS_VENDOR_KEY               "embedbits.com/EmBi")

#------------------------------------------------------------------------------#
# Returns the artifacts cache folder of the project, the folder the artifacts
# handler installs the artifacts into when it is started for the project
# (IntegrationTesting_InstallProbeRs): ArtifactsHandler_Get_ArtifactsCachePath -
# CMake parameter or environment variable ARTIFACTS_HANDLER_CACHE_PATH, path of
# the host operating system in ArtifactsConfig.txt of the project, default cache
# folder of the handler.
#
# CACHE_PATH_VAR [out]: Artifacts cache folder (CMake path)
# PROJECT_DIR    [in]:  Project root folder
#------------------------------------------------------------------------------#
function(IntegrationTesting_Get_ArtifactsCachePath CACHE_PATH_VAR PROJECT_DIR)

    ArtifactsHandler_Get_ArtifactsCachePath("${PROJECT_DIR}/ArtifactsConfig.txt" CACHE_PATH)

    if(CMAKE_HOST_WIN32)

        file(TO_CMAKE_PATH "${CACHE_PATH}" CACHE_PATH)

    else()

        # Unix path is a CMake path already (':' would be taken as a separator)

    endif()

    set(${CACHE_PATH_VAR} "${CACHE_PATH}" PARENT_SCOPE)

endfunction(IntegrationTesting_Get_ArtifactsCachePath)

#------------------------------------------------------------------------------#
# Finds probe-rs for host scripts executed before configuration of a preset:
# IT_PROBE_RS / PROBE_RS_EXECUTABLE (parameter or environment), PATH, host
# configuration of a configured preset (Build/*/IntegrationTesting_Host.cmake),
# artifacts cache of the project (probe-rs artifact) - the folder returned by
# IntegrationTesting_Get_ArtifactsCachePath.
#
# PROBE_RS_VAR [out]: probe-rs executable ("" if not found)
# PROJECT_DIR  [in]:  Project root folder
#------------------------------------------------------------------------------#
function(IntegrationTesting_FindProbeRs PROBE_RS_VAR PROJECT_DIR)

    set(PROBE_RS "")

    foreach(CANDIDATE IN ITEMS "${IT_PROBE_RS}" "${PROBE_RS_EXECUTABLE}" "$ENV{PROBE_RS_EXECUTABLE}")
        if(CANDIDATE AND EXISTS "${CANDIDATE}")
            set(PROBE_RS "${CANDIDATE}")
            break()
        endif()
    endforeach()

    if(NOT PROBE_RS)
        find_program(IT_PROBE_RS_FOUND NAMES probe-rs NO_CACHE)
        if(IT_PROBE_RS_FOUND)
            set(PROBE_RS "${IT_PROBE_RS_FOUND}")
        endif()
    endif()

    if(NOT PROBE_RS)
        file(GLOB HOST_CONFIGS "${PROJECT_DIR}/Build/*/IntegrationTesting_Host.cmake")
        foreach(HOST_CONFIG IN LISTS HOST_CONFIGS)
            file(STRINGS "${HOST_CONFIG}" PROBE_RS_LINE REGEX "^set\\(IT_PROBE_RS ")
            if(PROBE_RS_LINE MATCHES "\\[==\\[(.+)\\]==\\]" AND EXISTS "${CMAKE_MATCH_1}")
                set(PROBE_RS "${CMAKE_MATCH_1}")
                break()
            endif()
        endforeach()
    endif()

    if(NOT PROBE_RS)
        IntegrationTesting_Get_ArtifactsCachePath(ARTIFACTS_CACHE "${PROJECT_DIR}")

        file(GLOB CACHED_PROBE_RS "${ARTIFACTS_CACHE}/probe-rs/Bin/*/probe-rs" "${ARTIFACTS_CACHE}/probe-rs/Bin/*/probe-rs.exe")
        list(SORT CACHED_PROBE_RS COMPARE NATURAL ORDER DESCENDING)
        if(CACHED_PROBE_RS)
            list(GET CACHED_PROBE_RS 0 PROBE_RS)
        endif()
    endif()

    set(${PROBE_RS_VAR} "${PROBE_RS}" PARENT_SCOPE)

endfunction(IntegrationTesting_FindProbeRs)

#------------------------------------------------------------------------------#
# Installs the artifact probe-rs by the artifacts handler of the platform (cache
# of the project: parameter, environment variable, ArtifactsConfig.txt, default cache) and
# finds it. For host scripts executed before any integration test preset was
# configured (nothing else installs probe-rs then).
#
# PROBE_RS_VAR [out]: probe-rs executable ("" if the installation failed)
# PROJECT_DIR  [in]:  Project root folder
#------------------------------------------------------------------------------#
function(IntegrationTesting_InstallProbeRs PROBE_RS_VAR PROJECT_DIR)

    set(HANDLER "${CMAKE_CURRENT_LIST_DIR}/../ArtifactsHandler/ArtifactsHandler.cmake")

    if(EXISTS "${HANDLER}")
        message(STATUS "probe-rs not found - installing the artifact probe-rs.")

        # The handler runs in its own process - it does not see the CMake
        # parameters of this script, so the cache folder parameter is passed on.
        set(HANDLER_ARGS "-DCONFIG_FILE_PATH=${PROJECT_DIR}")

        if(NOT "${ARTIFACTS_HANDLER_CACHE_PATH}" STREQUAL "")
            list(APPEND HANDLER_ARGS "-DARTIFACTS_HANDLER_CACHE_PATH=${ARTIFACTS_HANDLER_CACHE_PATH}")
        else()
            # Cache folder from the environment variable / ArtifactsConfig.txt
        endif()

        set(ENV{ARTIFACTS_HANDLER_REQ_LIST} "probe-rs;latest;latest")
        execute_process(COMMAND           "${CMAKE_COMMAND}" ${HANDLER_ARGS} -P "${HANDLER}"
                        WORKING_DIRECTORY "${PROJECT_DIR}"
                        RESULT_VARIABLE   INSTALL_RESULT)
        unset(ENV{ARTIFACTS_HANDLER_REQ_LIST})

        if(NOT INSTALL_RESULT EQUAL 0)
            message(WARNING "Installation of the artifact probe-rs failed (${INSTALL_RESULT}).")
        endif()
    endif()

    IntegrationTesting_FindProbeRs(PROBE_RS "${PROJECT_DIR}")

    set(${PROBE_RS_VAR} "${PROBE_RS}" PARENT_SCOPE)

endfunction(IntegrationTesting_InstallProbeRs)


#------------------------------------------------------------------------------#
# Reads MCU identification of all MCU presets of the Ral presets file. For
# every MCU <mcu> sets variables in the parent scope:
#   IT_MCU_<mcu>_DEVICE, IT_MCU_<mcu>_CORE, IT_MCU_<mcu>_ID_ADDRESS, IT_MCU_<mcu>_ID_MASK,
#   IT_MCU_<mcu>_ID_VALUE, IT_MCU_<mcu>_FLASH_SIZE_ADDRESS, IT_MCU_<mcu>_FLASH_SIZE_KB
#
# MCUS_VAR     [out]: List of MCU presets with identification
# PRESETS_FILE [in]:  Ral presets file (RalPresets.json)
#------------------------------------------------------------------------------#
function(IntegrationTesting_ReadMcuIdentification MCUS_VAR PRESETS_FILE)

    set(MCUS "")

    if(EXISTS "${PRESETS_FILE}")

        file(READ "${PRESETS_FILE}" PRESETS_CONTENT)
        string(JSON PRESETS_CNT ERROR_VARIABLE PRESETS_ERROR LENGTH "${PRESETS_CONTENT}" configurePresets)

        if(NOT PRESETS_ERROR AND PRESETS_CNT GREATER 0)
            math(EXPR PRESETS_LAST "${PRESETS_CNT} - 1")

            foreach(PRESET_IDX RANGE ${PRESETS_LAST})

                string(JSON MCU GET "${PRESETS_CONTENT}" configurePresets ${PRESET_IDX} name)
                string(JSON IDENTIFICATION ERROR_VARIABLE IDENTIFICATION_ERROR
                       GET "${PRESETS_CONTENT}" configurePresets ${PRESET_IDX} vendor "${IT_PRESETS_VENDOR_KEY}" identification)

                if(IDENTIFICATION_ERROR)
                    continue()
                endif()

                foreach(ITEM IN ITEMS device:DEVICE core:CORE idAddress:ID_ADDRESS idMask:ID_MASK idValue:ID_VALUE
                                      flashSizeAddress:FLASH_SIZE_ADDRESS flashSizeKB:FLASH_SIZE_KB)
                    string(REPLACE ":" ";" ITEM "${ITEM}")
                    list(GET ITEM 0 KEY)
                    list(GET ITEM 1 SUFFIX)
                    string(JSON VALUE ERROR_VARIABLE VALUE_ERROR GET "${IDENTIFICATION}" ${KEY})
                    if(VALUE_ERROR)
                        set(VALUE "")
                    endif()
                    set(IT_MCU_${MCU}_${SUFFIX} "${VALUE}" PARENT_SCOPE)
                    set(MCU_${SUFFIX} "${VALUE}")
                endforeach()

                if(MCU_CORE AND MCU_ID_ADDRESS AND MCU_ID_MASK AND NOT "${MCU_ID_VALUE}" STREQUAL "")
                    list(APPEND MCUS "${MCU}")
                endif()

            endforeach()
        endif()

    endif()

    set(${MCUS_VAR} "${MCUS}" PARENT_SCOPE)

endfunction(IntegrationTesting_ReadMcuIdentification)


#------------------------------------------------------------------------------#
# Reads one register of the MCU connected to the probe.
#
# VALUE_VAR [out]: Register value & MASK in hexadecimal format (0x...), "" if
#                  the read failed
# SELECTOR  [in]:  probe-rs probe selector
# CHIP      [in]:  probe-rs chip or generic core (Cortex-M4)
# ADDRESS   [in]:  Register address
# WIDTH     [in]:  b32 or b16
# MASK      [in]:  Mask of the value
#------------------------------------------------------------------------------#
function(IntegrationTesting_ReadRegister VALUE_VAR SELECTOR CHIP ADDRESS WIDTH MASK)

    execute_process(
        COMMAND "${IT_PROBE_RS}" read ${WIDTH} ${ADDRESS} 1
                --chip "${CHIP}" --probe "${SELECTOR}" --non-interactive
        RESULT_VARIABLE READ_RESULT
        OUTPUT_VARIABLE READ_OUTPUT
        ERROR_VARIABLE  READ_ERROR
    )

    set(VALUE "")

    # Output "e0042000: 10076413" / "1fff7a22: 0400"
    if(READ_RESULT EQUAL 0 AND READ_OUTPUT MATCHES "[0-9A-Fa-f]+:[ \t]*([0-9A-Fa-f]+)")
        math(EXPR VALUE "0x${CMAKE_MATCH_1} & ${MASK}" OUTPUT_FORMAT HEXADECIMAL)
    endif()

    set(${VALUE_VAR} "${VALUE}" PARENT_SCOPE)

endfunction(IntegrationTesting_ReadRegister)


#------------------------------------------------------------------------------#
# Identifies the MCU connected to the probe - reads ID register (and flash size
# register) with the generic core of every identification of the MCUs
# (IntegrationTesting_ReadMcuIdentification) and returns the matching MCUs.
#
# MATCHED_VAR [out]: List of MCUs matching ID and flash size
# TEXT_VAR    [out]: Read values for messages ("ID 0x413, 1024 KB" / "ID not read")
# SELECTOR    [in]:  probe-rs probe selector
# MCUS        [in]:  MCUs with identification
#------------------------------------------------------------------------------#
function(IntegrationTesting_IdentifyProbe MATCHED_VAR TEXT_VAR SELECTOR MCUS)

    set(MATCHED "")
    set(TEXT    "ID not read")
    set(PLANS_DONE "")

    foreach(MCU IN LISTS MCUS)

        # One read per register set (core, ID register, flash size register)
        set(PLAN "${IT_MCU_${MCU}_CORE}|${IT_MCU_${MCU}_ID_ADDRESS}|${IT_MCU_${MCU}_ID_MASK}|${IT_MCU_${MCU}_FLASH_SIZE_ADDRESS}")
        if("${PLAN}" IN_LIST PLANS_DONE)
            continue()
        endif()
        list(APPEND PLANS_DONE "${PLAN}")

        IntegrationTesting_ReadRegister(MCU_ID "${SELECTOR}" "${IT_MCU_${MCU}_CORE}"
                                        "${IT_MCU_${MCU}_ID_ADDRESS}" b32 "${IT_MCU_${MCU}_ID_MASK}")
        if(NOT MCU_ID)
            continue()
        endif()

        set(FLASH_SIZE_KB "")
        if(IT_MCU_${MCU}_FLASH_SIZE_ADDRESS)
            IntegrationTesting_ReadRegister(FLASH_SIZE "${SELECTOR}" "${IT_MCU_${MCU}_CORE}"
                                            "${IT_MCU_${MCU}_FLASH_SIZE_ADDRESS}" b16 0xFFFF)
            if(FLASH_SIZE)
                math(EXPR FLASH_SIZE_KB "${FLASH_SIZE}")
            endif()
        endif()

        set(PLAN_TEXT "ID ${MCU_ID}")
        if(FLASH_SIZE_KB)
            string(APPEND PLAN_TEXT ", ${FLASH_SIZE_KB} KB")
        endif()

        # MCUs of the same register set with matching values
        foreach(CANDIDATE IN LISTS MCUS)
            set(CANDIDATE_PLAN "${IT_MCU_${CANDIDATE}_CORE}|${IT_MCU_${CANDIDATE}_ID_ADDRESS}|${IT_MCU_${CANDIDATE}_ID_MASK}|${IT_MCU_${CANDIDATE}_FLASH_SIZE_ADDRESS}")
            if(NOT "${CANDIDATE_PLAN}" STREQUAL "${PLAN}")
                continue()
            endif()

            math(EXPR CANDIDATE_ID "${IT_MCU_${CANDIDATE}_ID_VALUE} & ${IT_MCU_${CANDIDATE}_ID_MASK}" OUTPUT_FORMAT HEXADECIMAL)
            if(NOT CANDIDATE_ID STREQUAL MCU_ID)
                continue()
            endif()

            if(FLASH_SIZE_KB AND IT_MCU_${CANDIDATE}_FLASH_SIZE_KB AND NOT FLASH_SIZE_KB EQUAL IT_MCU_${CANDIDATE}_FLASH_SIZE_KB)
                continue()
            endif()

            list(APPEND MATCHED "${CANDIDATE}")
        endforeach()

        set(TEXT "${PLAN_TEXT}")

        if(MATCHED)
            break()
        endif()

    endforeach()

    set(${MATCHED_VAR} "${MATCHED}" PARENT_SCOPE)
    set(${TEXT_VAR}    "${TEXT}"    PARENT_SCOPE)

endfunction(IntegrationTesting_IdentifyProbe)

#------------------------------------------------------------------------------#
# Finds connected debug probes ("probe-rs list").
#
# SELECTORS_VAR [out]: List of probe-rs probe selectors (VID:PID[:SN])
#------------------------------------------------------------------------------#
function(IntegrationTesting_ListProbes SELECTORS_VAR)

    execute_process(
        COMMAND "${IT_PROBE_RS}" list
        OUTPUT_VARIABLE LIST_OUTPUT
        ERROR_VARIABLE  LIST_OUTPUT
    )

    # Lines "[0]: STLink V3 -- 0483:374e:001700084D4B500B20373831 (ST-LINK)"
    string(REGEX MATCHALL "[^\r\n]+" LIST_LINES "${LIST_OUTPUT}")

    set(PROBE_SELECTORS "")

    foreach(LIST_LINE IN LISTS LIST_LINES)

        if(LIST_LINE MATCHES "-- ([0-9A-Fa-f]+:[0-9A-Fa-f]+(:[^ \t]*)?)")
            # Probe without serial number is reported as "VID:PID:"
            string(REGEX REPLACE ":$" "" PROBE_SELECTOR "${CMAKE_MATCH_1}")
            list(APPEND PROBE_SELECTORS "${PROBE_SELECTOR}")
        endif()

    endforeach()

    set(${SELECTORS_VAR} "${PROBE_SELECTORS}" PARENT_SCOPE)

endfunction(IntegrationTesting_ListProbes)


#------------------------------------------------------------------------------#
# Finds connected probes of the board - candidates (IT_PROBE, all connected
# probes if empty) whose MCU has the expected ID (if IT_ID_ADDRESS is set) and
# flash size (if IT_FLASH_SIZE_ADDRESS is set).
#
# MATCHED_VAR   [out]: List of probe-rs selectors of matching probes
# CONNECTED_VAR [out]: Text with connected probes (and their IDs) for messages
#------------------------------------------------------------------------------#
function(IntegrationTesting_FindProbes MATCHED_VAR CONNECTED_VAR)

    IntegrationTesting_ListProbes(CONNECTED_SELECTORS)

    if(IT_ID_ADDRESS)
        math(EXPR EXPECTED_ID "${IT_ID_VALUE} & ${IT_ID_MASK}" OUTPUT_FORMAT HEXADECIMAL)
    endif()

    set(MATCHED_SELECTORS "")
    set(CONNECTED_TEXT    "")

    foreach(SELECTOR IN LISTS CONNECTED_SELECTORS)

        # Candidate: probe-rs selector or serial number listed in IT_PROBE
        set(IS_CANDIDATE FALSE)

        if(NOT IT_PROBE)
            set(IS_CANDIDATE TRUE)
        else()
            foreach(PROBE IN LISTS IT_PROBE)
                if(SELECTOR STREQUAL PROBE OR SELECTOR MATCHES ":${PROBE}$")
                    set(IS_CANDIDATE TRUE)
                endif()
            endforeach()
        endif()

        if(NOT IS_CANDIDATE)
            string(APPEND CONNECTED_TEXT "\n  ${SELECTOR} (not selected)")
        elseif(NOT IT_ID_ADDRESS)
            string(APPEND CONNECTED_TEXT "\n  ${SELECTOR}")
            list(APPEND MATCHED_SELECTORS "${SELECTOR}")
        else()
            IntegrationTesting_ReadRegister(MCU_ID "${SELECTOR}" "${IT_CHIP}" "${IT_ID_ADDRESS}" b32 "${IT_ID_MASK}")

            set(FLASH_SIZE_KB "")
            if(MCU_ID STREQUAL EXPECTED_ID AND IT_FLASH_SIZE_ADDRESS AND IT_FLASH_SIZE_KB)
                IntegrationTesting_ReadRegister(FLASH_SIZE "${SELECTOR}" "${IT_CHIP}" "${IT_FLASH_SIZE_ADDRESS}" b16 0xFFFF)
                if(FLASH_SIZE)
                    math(EXPR FLASH_SIZE_KB "${FLASH_SIZE}")
                endif()
            endif()

            if(NOT MCU_ID)
                string(APPEND CONNECTED_TEXT "\n  ${SELECTOR} (ID not read)")
            elseif(NOT MCU_ID STREQUAL EXPECTED_ID)
                string(APPEND CONNECTED_TEXT "\n  ${SELECTOR} (ID ${MCU_ID}, expected ${EXPECTED_ID})")
            elseif(FLASH_SIZE_KB AND NOT FLASH_SIZE_KB EQUAL IT_FLASH_SIZE_KB)
                string(APPEND CONNECTED_TEXT "\n  ${SELECTOR} (ID ${MCU_ID}, flash ${FLASH_SIZE_KB} KB, expected ${IT_FLASH_SIZE_KB} KB)")
            else()
                string(APPEND CONNECTED_TEXT "\n  ${SELECTOR} (ID ${MCU_ID})")
                list(APPEND MATCHED_SELECTORS "${SELECTOR}")
            endif()
        endif()

    endforeach()

    if(NOT CONNECTED_SELECTORS)
        set(CONNECTED_TEXT "\n  none")
    endif()

    set(${MATCHED_VAR}   "${MATCHED_SELECTORS}" PARENT_SCOPE)
    set(${CONNECTED_VAR} "${CONNECTED_TEXT}"    PARENT_SCOPE)

endfunction(IntegrationTesting_FindProbes)
