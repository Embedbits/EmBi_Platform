################################################################################
# Author: Mr.Nobody
# file:  IntegrationTesting_Probe.cmake
# brief: Search of connected ST-LINK probes and their boards.
#
# Included by host scripts IntegrationTesting_Run.cmake and
# IntegrationTesting_AllBoards.cmake. Board is identified by "Board Name"
# reported by ST-LINK (eg. NUCLEO-H503RB) - STLINK-V3 of Nucleo boards.
################################################################################

include_guard(GLOBAL)

#------------------------------------------------------------------------------#
# Finds connected ST-LINK probes.
#
# PROGRAMMER [in]:  STM32_Programmer_CLI
# SN_VAR     [out]: List of serial numbers
# BOARD_VAR  [out]: List of board names (same order, "-" if not reported)
#------------------------------------------------------------------------------#
function(IntegrationTesting_ListProbes PROGRAMMER SN_VAR BOARD_VAR)

    execute_process(
        COMMAND "${PROGRAMMER}" -l st-link
        OUTPUT_VARIABLE LIST_OUTPUT
        ERROR_VARIABLE  LIST_OUTPUT
    )

    string(REGEX MATCHALL "[^\r\n]+" LIST_LINES "${LIST_OUTPUT}")

    set(PROBE_SNS    "")
    set(PROBE_BOARDS "")
    set(PROBE_SN     "")

    foreach(LIST_LINE IN LISTS LIST_LINES)

        if(LIST_LINE MATCHES "ST-LINK SN[ \t]*:[ \t]*([0-9A-Za-z]+)")
            # Board of the previous probe was not reported
            if(PROBE_SN)
                list(APPEND PROBE_SNS    "${PROBE_SN}")
                list(APPEND PROBE_BOARDS "-")
            endif()
            set(PROBE_SN "${CMAKE_MATCH_1}")
        elseif(LIST_LINE MATCHES "Board Name[ \t]*:[ \t]*([^ \t]+)" AND PROBE_SN)
            list(APPEND PROBE_SNS    "${PROBE_SN}")
            list(APPEND PROBE_BOARDS "${CMAKE_MATCH_1}")
            set(PROBE_SN "")
        endif()

    endforeach()

    if(PROBE_SN)
        list(APPEND PROBE_SNS    "${PROBE_SN}")
        list(APPEND PROBE_BOARDS "-")
    endif()

    set(${SN_VAR}    "${PROBE_SNS}"    PARENT_SCOPE)
    set(${BOARD_VAR} "${PROBE_BOARDS}" PARENT_SCOPE)

endfunction(IntegrationTesting_ListProbes)
