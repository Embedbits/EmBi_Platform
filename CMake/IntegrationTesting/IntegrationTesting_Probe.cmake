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
# of the board is known. The device is the default probe-rs chip of the MCU (it
# also reads the registers of an MCU the generic core does not reach, eg.
# STM32H503).
################################################################################

include_guard(GLOBAL)

# Functions of the artifacts handler (cache folder, configuration file); the
# handler itself is not started by this include. The include is on the level of
# the script, the functions use the variables set by it.
set(ARTIFACTS_HANDLER_NO_RUN TRUE)
include("${CMAKE_CURRENT_LIST_DIR}/../ArtifactsHandler/ArtifactsHandler.cmake")
unset(ARTIFACTS_HANDLER_NO_RUN)

# Probe lock - one client of a probe at a time (selection of the probe of the tests, detection)
include("${CMAKE_CURRENT_LIST_DIR}/IntegrationTesting_Lock.cmake")

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
# Returns the configure preset whose configuration defines the probe-rs artifact
# (ARTIFACTS_HANDLER_REQ_LIST of the integration test preset): the preset of the
# MCU, without the MCU the first integration test preset of the project.
#
# PRESET_VAR  [out]: Preset ("" if the project has no integration test preset -
#                    ArtifactsConfig.txt of the project is used then)
# PROJECT_DIR [in]:  Project root folder
# MCU         [in]:  MCU ("" = any)
#------------------------------------------------------------------------------#
function(IntegrationTesting_Get_ProbeRsPreset PRESET_VAR PROJECT_DIR MCU)

    ArtifactsResolver_Find_Preset(PRESET "${PROJECT_DIR}" "_IntegrationTest" "${MCU}")

    set(${PRESET_VAR} "${PRESET}" PARENT_SCOPE)

endfunction(IntegrationTesting_Get_ProbeRsPreset)

#------------------------------------------------------------------------------#
# Finds probe-rs for host scripts executed outside of the configuration of a
# preset: IT_PROBE_RS / PROBE_RS_EXECUTABLE (parameter or environment - explicit
# path chosen by the user), otherwise the probe-rs artifact of the artifacts
# cache in the version configured for the integration test preset of the MCU
# (ArtifactsResolver_Get_BinDir) - never the newest cached version and never
# probe-rs installed in the system (PATH). The artifact is downloaded by
# IntegrationTesting_InstallProbeRs when it is not cached.
#
# PROBE_RS_VAR [out]: probe-rs executable ("" if not found)
# PROJECT_DIR  [in]:  Project root folder
# MCU          [in]:  MCU, optional (the preset of the MCU defines the version,
#                     without it the first integration test preset of the project)
#------------------------------------------------------------------------------#
function(IntegrationTesting_FindProbeRs PROBE_RS_VAR PROJECT_DIR)

    # Optional MCU (ARGV2 of a function called without the argument is inherited from the
    # caller, ARGC is not)
    set(MCU "")

    if(ARGC GREATER 2)
        set(MCU "${ARGV2}")
    else()
        # No MCU - the first integration test preset of the project defines the version
    endif()

    set(PROBE_RS "")

    foreach(CANDIDATE IN ITEMS "${IT_PROBE_RS}" "${PROBE_RS_EXECUTABLE}" "$ENV{PROBE_RS_EXECUTABLE}")
        if(CANDIDATE AND EXISTS "${CANDIDATE}")
            set(PROBE_RS "${CANDIDATE}")
            break()
        endif()
    endforeach()

    if(NOT PROBE_RS)

        IntegrationTesting_Get_ProbeRsPreset(PRESET "${PROJECT_DIR}" "${MCU}")
        ArtifactsResolver_Get_BinDir(BIN_DIR RECORD "${PROJECT_DIR}" "${PRESET}" probe-rs)

        if(BIN_DIR)

            file(GLOB_RECURSE PROBE_RS_FILES "${BIN_DIR}/*probe-rs" "${BIN_DIR}/*probe-rs.exe")
            list(FILTER PROBE_RS_FILES INCLUDE REGEX "/probe-rs(\\.exe)?$")

            foreach(PROBE_RS_FILE IN LISTS PROBE_RS_FILES)
                if(NOT IS_DIRECTORY "${PROBE_RS_FILE}")
                    set(PROBE_RS "${PROBE_RS_FILE}")
                    break()
                endif()
            endforeach()

        endif()

    endif()

    set(${PROBE_RS_VAR} "${PROBE_RS}" PARENT_SCOPE)

endfunction(IntegrationTesting_FindProbeRs)

#------------------------------------------------------------------------------#
# Downloads the artifact probe-rs in the configured version (the same version
# the integration test preset configures) by the artifacts handler of the
# platform (cache of the project: parameter, environment variable,
# ArtifactsConfig.txt, default cache) and finds it. For host scripts executed
# before any integration test preset was configured (nothing else downloads
# probe-rs then).
#
# PROBE_RS_VAR [out]: probe-rs executable ("" if the download failed)
# PROJECT_DIR  [in]:  Project root folder
# MCU          [in]:  MCU, optional (see IntegrationTesting_FindProbeRs)
#------------------------------------------------------------------------------#
function(IntegrationTesting_InstallProbeRs PROBE_RS_VAR PROJECT_DIR)

    # Optional MCU (ARGV2 of a function called without the argument is inherited from the
    # caller, ARGC is not)
    set(MCU "")

    if(ARGC GREATER 2)
        set(MCU "${ARGV2}")
    else()
        # No MCU - the first integration test preset of the project defines the version
    endif()

    IntegrationTesting_Get_ProbeRsPreset(PRESET "${PROJECT_DIR}" "${MCU}")

    ArtifactsResolver_Provide(BIN_DIR "${PROJECT_DIR}" "${PRESET}" probe-rs)

    IntegrationTesting_FindProbeRs(PROBE_RS "${PROJECT_DIR}" "${MCU}")

    set(${PROBE_RS_VAR} "${PROBE_RS}" PARENT_SCOPE)

endfunction(IntegrationTesting_InstallProbeRs)

#------------------------------------------------------------------------------#
# Provides probe-rs for host scripts that execute it (flash, detection of boards,
# execution of tests): probe-rs found by IntegrationTesting_FindProbeRs (explicit
# path, the configured version in the artifacts cache), otherwise the artifact
# is downloaded by the artifacts handler (IntegrationTesting_InstallProbeRs).
# probe-rs of the system is never used. The script ends with an error if the
# artifact cannot be provided.
#
# PROBE_RS_VAR [out]: probe-rs executable
# PROJECT_DIR  [in]:  Project root folder
# MCU          [in]:  MCU, optional (see IntegrationTesting_FindProbeRs)
#------------------------------------------------------------------------------#
function(IntegrationTesting_ProvideProbeRs PROBE_RS_VAR PROJECT_DIR)

    # Optional MCU (ARGV2 of a function called without the argument is inherited from the
    # caller, ARGC is not)
    set(MCU "")

    if(ARGC GREATER 2)
        set(MCU "${ARGV2}")
    else()
        # No MCU - the first integration test preset of the project defines the version
    endif()

    IntegrationTesting_FindProbeRs(PROBE_RS "${PROJECT_DIR}" "${MCU}")

    if(NOT PROBE_RS)
        IntegrationTesting_InstallProbeRs(PROBE_RS "${PROJECT_DIR}" "${MCU}")
    endif()

    if(NOT PROBE_RS)

        IntegrationTesting_Get_ProbeRsPreset(PRESET "${PROJECT_DIR}" "${MCU}")
        ArtifactsResolver_Get_Record(RECORD "${PROJECT_DIR}" "${PRESET}" probe-rs)

        if("${RECORD}" STREQUAL "")
            message(FATAL_ERROR "The artifact probe-rs is not configured - add it to ARTIFACTS_HANDLER_REQ_LIST of the "
                                "integration test preset (or to ArtifactsConfig.txt of the project) or pass -DIT_PROBE_RS=<path>.")
        else()
            message(FATAL_ERROR "The artifact probe-rs in the configured version (${RECORD}) was not found and its download "
                                "failed - check the artifacts configuration (ArtifactsConfig.txt, network) or pass "
                                "-DIT_PROBE_RS=<path>.")
        endif()

    endif()

    set(${PROBE_RS_VAR} "${PROBE_RS}" PARENT_SCOPE)

endfunction(IntegrationTesting_ProvideProbeRs)


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
# When the generic core does not read the registers, the devices of the MCUs of
# the same register set are tried (the first device that reads them is used).
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
        set(READ_CHIP "${IT_MCU_${MCU}_CORE}")

        # The generic core does not reach the registers of some MCUs (STM32H503: SwdApWdataError) -
        # the devices of the MCUs of the same register set are tried then, the first one that reads wins
        if(NOT MCU_ID)

            set(DEVICES_TRIED "")

            foreach(CANDIDATE IN LISTS MCUS)

                set(CANDIDATE_PLAN "${IT_MCU_${CANDIDATE}_CORE}|${IT_MCU_${CANDIDATE}_ID_ADDRESS}|${IT_MCU_${CANDIDATE}_ID_MASK}|${IT_MCU_${CANDIDATE}_FLASH_SIZE_ADDRESS}")
                set(DEVICE "${IT_MCU_${CANDIDATE}_DEVICE}")

                if(NOT "${CANDIDATE_PLAN}" STREQUAL "${PLAN}" OR
                   "${DEVICE}" STREQUAL "" OR
                   "${DEVICE}" IN_LIST DEVICES_TRIED)
                    continue()
                endif()

                list(APPEND DEVICES_TRIED "${DEVICE}")

                IntegrationTesting_ReadRegister(MCU_ID
                                                "${SELECTOR}"
                                                "${DEVICE}"
                                                "${IT_MCU_${MCU}_ID_ADDRESS}"
                                                b32
                                                "${IT_MCU_${MCU}_ID_MASK}")

                if(MCU_ID)
                    set(READ_CHIP "${DEVICE}")
                    break()
                endif()

            endforeach()

        endif()

        if(NOT MCU_ID)
            continue()
        endif()

        set(FLASH_SIZE_KB "")
        if(IT_MCU_${MCU}_FLASH_SIZE_ADDRESS)
            IntegrationTesting_ReadRegister(FLASH_SIZE
                                            "${SELECTOR}"
                                            "${READ_CHIP}"
                                            "${IT_MCU_${MCU}_FLASH_SIZE_ADDRESS}"
                                            b16
                                            0xFFFF)
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
# Checks whether a connected probe is a candidate probe of the board - every
# probe without IT_PROBE, otherwise the probes listed in IT_PROBE (probe-rs
# selectors or serial numbers).
#
# CANDIDATE_VAR [out]: TRUE for a candidate probe
# SELECTOR      [in]:  probe-rs selector of the connected probe
#------------------------------------------------------------------------------#
function(itProbe_IsCandidate CANDIDATE_VAR SELECTOR)

    set(IS_CANDIDATE FALSE)

    if(NOT IT_PROBE)
        set(IS_CANDIDATE TRUE)
    else()
        foreach(PROBE IN LISTS IT_PROBE)
            if("${SELECTOR}" STREQUAL "${PROBE}" OR
               "${SELECTOR}" MATCHES ":${PROBE}$")
                set(IS_CANDIDATE TRUE)
            endif()
        endforeach()
    endif()

    set(${CANDIDATE_VAR} ${IS_CANDIDATE} PARENT_SCOPE)

endfunction(itProbe_IsCandidate)

#------------------------------------------------------------------------------#
# Checks the MCU connected to a probe - ID register (IT_ID_ADDRESS) and flash
# size register (IT_FLASH_SIZE_ADDRESS) read with the chip of the board
# (IT_CHIP). Without IT_ID_ADDRESS every probe matches.
#
# MATCH_VAR [out]: TRUE when the MCU matches
# TEXT_VAR  [out]: Read values for messages ("ID 0x413", "ID not read", ...)
# SELECTOR  [in]:  probe-rs selector
#------------------------------------------------------------------------------#
function(itProbe_CheckMcu MATCH_VAR TEXT_VAR SELECTOR)

    set(MATCH FALSE)
    set(TEXT  "")

    if(NOT IT_ID_ADDRESS)

        set(MATCH TRUE)
        set(TEXT  "MCU not checked")

    else()

        math(EXPR EXPECTED_ID "${IT_ID_VALUE} & ${IT_ID_MASK}" OUTPUT_FORMAT HEXADECIMAL)

        IntegrationTesting_ReadRegister(MCU_ID "${SELECTOR}" "${IT_CHIP}" "${IT_ID_ADDRESS}" b32 "${IT_ID_MASK}")

        set(FLASH_SIZE_KB "")
        if("${MCU_ID}" STREQUAL "${EXPECTED_ID}" AND
           IT_FLASH_SIZE_ADDRESS AND
           IT_FLASH_SIZE_KB)
            IntegrationTesting_ReadRegister(FLASH_SIZE "${SELECTOR}" "${IT_CHIP}" "${IT_FLASH_SIZE_ADDRESS}" b16 0xFFFF)
            if(FLASH_SIZE)
                math(EXPR FLASH_SIZE_KB "${FLASH_SIZE}")
            endif()
        endif()

        if(NOT MCU_ID)
            set(TEXT "ID not read")
        elseif(NOT "${MCU_ID}" STREQUAL "${EXPECTED_ID}")
            set(TEXT "ID ${MCU_ID}, expected ${EXPECTED_ID}")
        elseif(FLASH_SIZE_KB AND
               NOT FLASH_SIZE_KB EQUAL IT_FLASH_SIZE_KB)
            set(TEXT "ID ${MCU_ID}, flash ${FLASH_SIZE_KB} KB, expected ${IT_FLASH_SIZE_KB} KB")
        else()
            set(TEXT  "ID ${MCU_ID}")
            set(MATCH TRUE)
        endif()

    endif()

    set(${MATCH_VAR} ${MATCH} PARENT_SCOPE)
    set(${TEXT_VAR}  "${TEXT}" PARENT_SCOPE)

endfunction(itProbe_CheckMcu)

#------------------------------------------------------------------------------#
# Selects and locks the probe of the board (IntegrationTesting_Lock.cmake) -
# candidates (IT_PROBE, all connected probes if empty) are locked one after the
# other and the MCU of a locked candidate is checked (itProbe_CheckMcu): the
# first matching probe stays locked by this process, the other candidates are
# released. A candidate used by another client (debugging, pipeline job) is not
# read; when no free candidate matches, the first used candidate is waited for
# at most WAIT seconds and checked then.
#
# SELECTOR_VAR  [out]: Selected probe, locked by this process ("" if none)
# MATCHED_VAR   [out]: Probes whose MCU matches (the selected one first)
# CONNECTED_VAR [out]: Text with the connected probes (IDs, holders) for messages
# USED_BY_VAR   [out]: Holder of the probe still used by another client after the
#                      wait ("" when no probe was waited for or the wait ended)
# WAIT          [in]:  Longest wait for a probe used by another client [s]
# HOLDER        [in]:  Holder of the lock (IntegrationTesting_Get_LockHolder)
#------------------------------------------------------------------------------#
function(IntegrationTesting_SelectProbe SELECTOR_VAR MATCHED_VAR CONNECTED_VAR USED_BY_VAR WAIT HOLDER)

    IntegrationTesting_ListProbes(CONNECTED_SELECTORS)

    set(SELECTED       "")
    set(MATCHED        "")
    set(USED           "")
    set(USED_BY        "")
    set(CONNECTED_TEXT "")

    foreach(SELECTOR IN LISTS CONNECTED_SELECTORS)

        itProbe_IsCandidate(IS_CANDIDATE "${SELECTOR}")

        if(NOT IS_CANDIDATE)
            string(APPEND CONNECTED_TEXT "\n  ${SELECTOR} (not selected)")
            continue()
        endif()

        IntegrationTesting_LockProbe(LOCK_RESULT "${SELECTOR}" 0 "${HOLDER}")

        if(NOT "${LOCK_RESULT}" STREQUAL "")
            string(APPEND CONNECTED_TEXT "\n  ${SELECTOR} (used by ${LOCK_RESULT})")
            list(APPEND USED "${SELECTOR}")
            continue()
        endif()

        itProbe_CheckMcu(MCU_MATCH MCU_TEXT "${SELECTOR}")
        string(APPEND CONNECTED_TEXT "\n  ${SELECTOR} (${MCU_TEXT})")

        if(MCU_MATCH)
            list(APPEND MATCHED "${SELECTOR}")
        endif()

        if(MCU_MATCH AND
           "${SELECTED}" STREQUAL "")
            set(SELECTED "${SELECTOR}")
        else()
            IntegrationTesting_UnlockProbe("${SELECTOR}")
        endif()

    endforeach()

    # No free probe of the board - the first probe used by another client is waited for
    if("${SELECTED}" STREQUAL "" AND
       NOT "${USED}" STREQUAL "")

        list(GET USED 0 SELECTOR)

        IntegrationTesting_LockProbe(LOCK_RESULT "${SELECTOR}" ${WAIT} "${HOLDER}")

        if("${LOCK_RESULT}" STREQUAL "")

            itProbe_CheckMcu(MCU_MATCH MCU_TEXT "${SELECTOR}")
            string(APPEND CONNECTED_TEXT "\n  ${SELECTOR} after the wait (${MCU_TEXT})")

            if(MCU_MATCH)
                set(SELECTED "${SELECTOR}")
                list(APPEND MATCHED "${SELECTOR}")
            else()
                IntegrationTesting_UnlockProbe("${SELECTOR}")
            endif()

        else()
            string(APPEND CONNECTED_TEXT "\n  ${SELECTOR} still used by ${LOCK_RESULT} after ${WAIT} s")
            set(USED_BY "${LOCK_RESULT}")
        endif()

    endif()

    if(NOT CONNECTED_SELECTORS)
        set(CONNECTED_TEXT "\n  none")
    endif()

    set(${SELECTOR_VAR}  "${SELECTED}"       PARENT_SCOPE)
    set(${MATCHED_VAR}   "${MATCHED}"        PARENT_SCOPE)
    set(${CONNECTED_VAR} "${CONNECTED_TEXT}" PARENT_SCOPE)
    set(${USED_BY_VAR}   "${USED_BY}"        PARENT_SCOPE)

endfunction(IntegrationTesting_SelectProbe)
