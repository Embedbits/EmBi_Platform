################################################################################
# Author: Mr.Nobody
# file:  IntegrationTesting_Run.cmake
# brief: Executes integration test firmware on target and reads Unity output.
#
# Called by CTest (test "<NAME>.Run", see IntegrationTesting.cmake):
#   cmake -DIT_ELF=<firmware.elf> -DIT_LOG=<output.log> -DIT_NM=<nm>
#         -DIT_PROGRAMMER=<STM32_Programmer_CLI> -DIT_PROBE="port=SWD [sn=...]"
#         -DIT_BOARD=<NUCLEO-H503RB> -DIT_DEVICE_ID=<0x474>
#         [-DIT_PROBE_RS=<probe-rs> -DIT_PROBE_RS_CHIP=<STM32H503RB>]
#         -DIT_TIMEOUT=<s> -DIT_CASE_TIMEOUT=<s> -P IntegrationTesting_Run.cmake
#
# Steps:
#   1. Address of result mailbox (symbol integrationTesting_Mailbox) from ELF.
#   2. Probe selection - IT_PROBE with "sn=", environment variable
#      INTEGRATION_TEST_PROBE_SN, or the probe of the board IT_BOARD ("Board Name"
#      reported by ST-LINK). MCU of the board is checked (IT_DEVICE_ID).
#   3. Firmware download, verification, start of new test session (IT_MAILBOX_START
#      written into the mailbox) and reset.
#   4. Mailbox header is read (MCU keeps running) until the state is "finished"
#      or timeout expires. Test case without progress for IT_CASE_TIMEOUT is
#      aborted - abort command and reset of the MCU, the firmware reports it as
#      failure and continues by the next test case.
#   5. Unity output is read, printed and stored into IT_LOG.
#
# Steps 3 - 5 use probe-rs when IT_PROBE_RS is set, otherwise STM32_Programmer_CLI.
# STM32_Programmer_CLI clears NVIC interrupt enable registers on every connection
# ("Clear all interrupts", EmBi_Platform AB#342) - interrupt based tests fail when
# the mailbox is read by it during the test case. probe-rs keeps the NVIC state
# (it halts the core for a few milliseconds on attach to clear breakpoints).
#
# The script fails only if the tests were not completely executed (board not
# found, download error, timeout, output overflow, mailbox lost over reset).
# Results of test functions are evaluated by IntegrationTesting_Check.cmake
# from IT_LOG.
################################################################################

cmake_minimum_required(VERSION 3.22)

include("${CMAKE_CURRENT_LIST_DIR}/IntegrationTesting_Probe.cmake")

#=============================== Constant values ==============================#

# Mailbox header (IntegrationTesting.h): 12 x uint32
set(IT_MAILBOX_HEADER_SIZE              48)

# Word indexes of the mailbox header
set(IT_WORD_MAGIC                       0)
set(IT_WORD_STATE                       1)
set(IT_WORD_LENGTH                      2)
set(IT_WORD_SIZE                        3)
set(IT_WORD_SESSION                     4)
set(IT_WORD_COMMAND                     5)
set(IT_WORD_TEST_INDEX                  6)
set(IT_WORD_TEST_COUNT                  7)
set(IT_WORD_TEST_STAGE                  8)

# Mailbox values (hexadecimal as read from memory / written by programmer)
set(IT_MAILBOX_MAGIC                    "49544D42")
set(IT_MAILBOX_START                    "0x49545354")
set(IT_STATE_FINISHED                   "444F4E45")
set(IT_SESSION_LOCAL                    "4C4F434C")
set(IT_COMMAND_ABORT                    "0x41425254")

# Pause between two reads of the mailbox header [s]
set(IT_POLL_PERIOD                      "0.5")

#================================ Functions ===================================#

#------------------------------------------------------------------------------#
# Executes STM32_Programmer_CLI connected to the selected probe (IT_PROBE_ARGS).
#
# RESULT_VAR [out]: Exit code of the programmer
# OUTPUT_VAR [out]: Output of the programmer
# ARGN       [in]:  Programmer commands (after connection arguments)
#------------------------------------------------------------------------------#
function(itRun_Programmer RESULT_VAR OUTPUT_VAR)

    execute_process(
        COMMAND "${IT_PROGRAMMER}" -c ${IT_PROBE_ARGS} ${ARGN}
        RESULT_VARIABLE PROGRAMMER_RESULT
        OUTPUT_VARIABLE PROGRAMMER_OUTPUT
        ERROR_VARIABLE  PROGRAMMER_OUTPUT
    )

    # CLI returns 0 also for some failed connections, error text is checked too
    string(FIND "${PROGRAMMER_OUTPUT}" "Error:" ERROR_POSITION)

    if(PROGRAMMER_RESULT EQUAL 0 AND NOT ERROR_POSITION EQUAL -1)
        set(PROGRAMMER_RESULT 1)
    endif()

    set(${RESULT_VAR} "${PROGRAMMER_RESULT}" PARENT_SCOPE)
    set(${OUTPUT_VAR} "${PROGRAMMER_OUTPUT}" PARENT_SCOPE)

endfunction(itRun_Programmer)


#------------------------------------------------------------------------------#
# Executes probe-rs command connected to the selected probe and chip.
#
# RESULT_VAR [out]: Exit code of probe-rs
# OUTPUT_VAR [out]: Output of probe-rs
# SUBCOMMAND [in]:  probe-rs subcommand (download, read, write, reset)
# ARGN       [in]:  Arguments of the subcommand (after probe options)
#------------------------------------------------------------------------------#
function(itRun_ProbeRs RESULT_VAR OUTPUT_VAR SUBCOMMAND)

    execute_process(
        COMMAND "${IT_PROBE_RS}" ${SUBCOMMAND}
                --chip "${IT_PROBE_RS_CHIP}" --probe "${IT_PROBE_RS_SELECTOR}" --non-interactive
                ${ARGN}
        RESULT_VARIABLE PROBE_RS_RESULT
        OUTPUT_VARIABLE PROBE_RS_OUTPUT
        ERROR_VARIABLE  PROBE_RS_OUTPUT
    )

    set(${RESULT_VAR} "${PROBE_RS_RESULT}" PARENT_SCOPE)
    set(${OUTPUT_VAR} "${PROBE_RS_OUTPUT}" PARENT_SCOPE)

endfunction(itRun_ProbeRs)


#------------------------------------------------------------------------------#
# Resets the MCU by probe-rs (the MCU runs after reset). Reset is repeated once,
# probe-rs reports timeout of the first reset after download (halted core).
#
# RESULT_VAR [out]: Exit code of the last reset
# OUTPUT_VAR [out]: Output of the last reset
#------------------------------------------------------------------------------#
function(itRun_ProbeRsReset RESULT_VAR OUTPUT_VAR)

    itRun_ProbeRs(RESET_RESULT RESET_OUTPUT reset)

    if(NOT RESET_RESULT EQUAL 0)
        itRun_ProbeRs(RESET_RESULT RESET_OUTPUT reset)
    endif()

    set(${RESULT_VAR} "${RESET_RESULT}" PARENT_SCOPE)
    set(${OUTPUT_VAR} "${RESET_OUTPUT}" PARENT_SCOPE)

endfunction(itRun_ProbeRsReset)


#------------------------------------------------------------------------------#
# Reads memory of the running MCU into hexadecimal string.
#
# HEX_VAR  [out]: Read data, two hexadecimal characters per byte ("" on error)
# ADDRESS  [in]:  Start address (decimal)
# SIZE     [in]:  Count of bytes
#------------------------------------------------------------------------------#
function(itRun_ReadMemory HEX_VAR ADDRESS SIZE)

    set(READ_FILE "${IT_LOG}.bin")

    math(EXPR ADDRESS_HEX "${ADDRESS}" OUTPUT_FORMAT HEXADECIMAL)

    if(USE_PROBE_RS)

        # Output lines "20000600: 42 4d 54 49 ..." - address removed, bytes joined
        itRun_ProbeRs(READ_RESULT READ_OUTPUT read b8 ${ADDRESS_HEX} ${SIZE})

        if(READ_RESULT EQUAL 0)
            string(REGEX REPLACE "[0-9a-fA-F]+:" "" READ_HEX "${READ_OUTPUT}")
            string(REGEX REPLACE "[ \t\r\n]" "" READ_HEX "${READ_HEX}")
        else()
            set(READ_HEX "")
        endif()

    else()

        file(REMOVE "${READ_FILE}")

        itRun_Programmer(READ_RESULT READ_OUTPUT mode=HOTPLUG -u ${ADDRESS_HEX} ${SIZE} "${READ_FILE}")

        if(READ_RESULT EQUAL 0 AND EXISTS "${READ_FILE}")
            file(READ "${READ_FILE}" READ_HEX HEX)
        else()
            set(READ_HEX "")
        endif()

    endif()

    # Incomplete read is handled as failed read
    string(LENGTH "${READ_HEX}" READ_HEX_LENGTH)
    math(EXPR READ_HEX_EXPECTED "${SIZE} * 2")

    if(NOT READ_HEX_LENGTH EQUAL READ_HEX_EXPECTED)
        set(READ_HEX "")
    endif()

    string(TOUPPER "${READ_HEX}" READ_HEX)

    set(${HEX_VAR} "${READ_HEX}" PARENT_SCOPE)

endfunction(itRun_ReadMemory)


#------------------------------------------------------------------------------#
# Returns 32-bit little endian word from hexadecimal memory dump.
#
# WORD_VAR  [out]: Word as 8 hexadecimal characters (most significant first)
# HEX       [in]:  Memory dump (itRun_ReadMemory)
# WORD_IDX  [in]:  Index of the word
#------------------------------------------------------------------------------#
function(itRun_GetWord WORD_VAR HEX WORD_IDX)

    set(WORD "")

    foreach(BYTE_IDX RANGE 3 0 -1)
        math(EXPR CHAR_POSITION "( ${WORD_IDX} * 4 + ${BYTE_IDX} ) * 2")
        string(SUBSTRING "${HEX}" ${CHAR_POSITION} 2 BYTE_HEX)
        string(APPEND WORD "${BYTE_HEX}")
    endforeach()

    set(${WORD_VAR} "${WORD}" PARENT_SCOPE)

endfunction(itRun_GetWord)

#============================== Parameters check ==============================#

foreach(PARAMETER IN ITEMS IT_ELF IT_LOG IT_NM IT_PROGRAMMER IT_PROBE IT_TIMEOUT IT_CASE_TIMEOUT)
    if(NOT ${PARAMETER})
        message(FATAL_ERROR "Parameter ${PARAMETER} is not set.")
    endif()
endforeach()

if(NOT EXISTS "${IT_PROGRAMMER}")
    message(FATAL_ERROR "STM32_Programmer_CLI not found ('${IT_PROGRAMMER}'). Configure with -DSTM32_PROGRAMMER_CLI=<path>.")
endif()

if(IT_PROBE_RS)
    if(NOT EXISTS "${IT_PROBE_RS}")
        message(FATAL_ERROR "probe-rs not found ('${IT_PROBE_RS}').")
    elseif(NOT IT_PROBE_RS_CHIP)
        message(FATAL_ERROR "Parameter IT_PROBE_RS_CHIP is not set.")
    endif()
    set(USE_PROBE_RS TRUE)
else()
    set(USE_PROBE_RS FALSE)
endif()

file(REMOVE "${IT_LOG}")

#========================= 1: Mailbox localization ============================#

execute_process(
    COMMAND "${IT_NM}" "${IT_ELF}"
    RESULT_VARIABLE NM_RESULT
    OUTPUT_VARIABLE NM_OUTPUT
)

string(REGEX MATCH "([0-9A-Fa-f]+) [BbDd] integrationTesting_Mailbox" _ "${NM_OUTPUT}")

if(NOT NM_RESULT EQUAL 0 OR NOT CMAKE_MATCH_1)
    message(FATAL_ERROR "Symbol integrationTesting_Mailbox not found in ${IT_ELF}.")
endif()

math(EXPR MAILBOX_ADDRESS "0x${CMAKE_MATCH_1}")
math(EXPR OUTPUT_ADDRESS  "${MAILBOX_ADDRESS} + ${IT_MAILBOX_HEADER_SIZE}")
math(EXPR COMMAND_ADDRESS "${MAILBOX_ADDRESS} + ${IT_WORD_COMMAND} * 4" OUTPUT_FORMAT HEXADECIMAL)
math(EXPR MAILBOX_ADDRESS_HEX "${MAILBOX_ADDRESS}" OUTPUT_FORMAT HEXADECIMAL)

#=========================== 2: Probe selection ===============================#

separate_arguments(IT_PROBE_ARGS NATIVE_COMMAND "${IT_PROBE}")

string(FIND "${IT_PROBE}" "sn=" PROBE_SN_POSITION)

if(NOT PROBE_SN_POSITION EQUAL -1)

    message(STATUS "Probe: ${IT_PROBE} (selected by INTEGRATION_TEST_PROBE)")

elseif(DEFINED ENV{INTEGRATION_TEST_PROBE_SN} AND NOT "$ENV{INTEGRATION_TEST_PROBE_SN}" STREQUAL "")

    list(APPEND IT_PROBE_ARGS "sn=$ENV{INTEGRATION_TEST_PROBE_SN}")
    message(STATUS "Probe: sn=$ENV{INTEGRATION_TEST_PROBE_SN} (selected by environment INTEGRATION_TEST_PROBE_SN)")

else()

    IntegrationTesting_ListProbes("${IT_PROGRAMMER}" PROBE_SNS PROBE_BOARDS)

    list(LENGTH PROBE_SNS PROBE_CNT)

    set(CONNECTED_TEXT "")
    set(MATCHED_SNS    "")

    if(PROBE_CNT GREATER 0)
        math(EXPR PROBE_LAST "${PROBE_CNT} - 1")

        foreach(PROBE_IDX RANGE ${PROBE_LAST})
            list(GET PROBE_SNS    ${PROBE_IDX} PROBE_SN)
            list(GET PROBE_BOARDS ${PROBE_IDX} PROBE_BOARD)

            string(APPEND CONNECTED_TEXT "\n  ${PROBE_BOARD} (sn=${PROBE_SN})")

            if(NOT IT_BOARD OR PROBE_BOARD STREQUAL IT_BOARD)
                list(APPEND MATCHED_SNS "${PROBE_SN}")
            endif()
        endforeach()
    endif()

    list(LENGTH MATCHED_SNS MATCHED_CNT)

    if(PROBE_CNT EQUAL 0)
        message(FATAL_ERROR "No ST-LINK probe connected.")
    elseif(MATCHED_CNT EQUAL 0)
        message(FATAL_ERROR "Board ${IT_BOARD} is not connected. Connected boards:${CONNECTED_TEXT}")
    elseif(NOT IT_BOARD AND MATCHED_CNT GREATER 1)
        message(FATAL_ERROR "Board is not specified (INTEGRATION_TEST_BOARD) and more probes are connected:${CONNECTED_TEXT}")
    endif()

    list(GET MATCHED_SNS 0 SELECTED_SN)
    list(APPEND IT_PROBE_ARGS "sn=${SELECTED_SN}")

    if(MATCHED_CNT GREATER 1)
        message(STATUS "Probe: sn=${SELECTED_SN} - first of ${MATCHED_CNT} boards ${IT_BOARD}, "
                       "other one is selected by environment variable INTEGRATION_TEST_PROBE_SN.")
    else()
        message(STATUS "Probe: sn=${SELECTED_SN} (board ${IT_BOARD})")
    endif()

endif()

# MCU of the board - firmware is built for one MCU (TARGET_MCU)
itRun_Programmer(CONNECT_RESULT CONNECT_OUTPUT mode=UR)

if(NOT CONNECT_RESULT EQUAL 0)
    message("${CONNECT_OUTPUT}")
    message(FATAL_ERROR "Connection to the board failed (${IT_PROBE_ARGS}).")
endif()

string(REGEX MATCH "Device ID[ \t]*:[ \t]*0x([0-9A-Fa-f]+)" _ "${CONNECT_OUTPUT}")
set(BOARD_DEVICE_ID "${CMAKE_MATCH_1}")

if(IT_DEVICE_ID AND BOARD_DEVICE_ID)
    math(EXPR BOARD_DEVICE_ID_VALUE    "0x${BOARD_DEVICE_ID}")
    math(EXPR EXPECTED_DEVICE_ID_VALUE "${IT_DEVICE_ID}")

    if(NOT BOARD_DEVICE_ID_VALUE EQUAL EXPECTED_DEVICE_ID_VALUE)
        message(FATAL_ERROR "MCU of the board (Device ID 0x${BOARD_DEVICE_ID}) does not match the firmware "
                            "(TARGET_MCU, Device ID ${IT_DEVICE_ID}). Select the board of the preset.")
    endif()
elseif(IT_DEVICE_ID)
    message(WARNING "Device ID was not reported by STM32_Programmer_CLI, MCU of the board is not checked.")
endif()

#================== 3: Download, session start and reset ======================#

message(STATUS "Download of ${IT_ELF}")

if(USE_PROBE_RS)

    # probe-rs probe selector "VID:PID:SN" of the selected ST-LINK
    string(REGEX MATCH "sn=([^ ;]+)" _ "${IT_PROBE_ARGS}")
    set(SELECTED_SN "${CMAKE_MATCH_1}")

    execute_process(COMMAND "${IT_PROBE_RS}" list
                    OUTPUT_VARIABLE PROBE_RS_LIST
                    ERROR_VARIABLE  PROBE_RS_LIST)

    string(REGEX MATCH "([0-9a-fA-F]+:[0-9a-fA-F]+:${SELECTED_SN})" _ "${PROBE_RS_LIST}")
    set(IT_PROBE_RS_SELECTOR "${CMAKE_MATCH_1}")

    if(NOT SELECTED_SN OR NOT IT_PROBE_RS_SELECTOR)
        message("${PROBE_RS_LIST}")
        message(FATAL_ERROR "Probe sn=${SELECTED_SN} not found by probe-rs.")
    endif()

    message(STATUS "probe-rs: ${IT_PROBE_RS_CHIP}, probe ${IT_PROBE_RS_SELECTOR}")

    itRun_ProbeRs(DOWNLOAD_RESULT DOWNLOAD_OUTPUT download --verify "${IT_ELF}")

    if(DOWNLOAD_RESULT EQUAL 0)
        itRun_ProbeRs(DOWNLOAD_RESULT DOWNLOAD_OUTPUT write b32 ${MAILBOX_ADDRESS_HEX} ${IT_MAILBOX_START})
    endif()

    if(DOWNLOAD_RESULT EQUAL 0)
        itRun_ProbeRsReset(DOWNLOAD_RESULT DOWNLOAD_OUTPUT)
    endif()

else()

    itRun_Programmer(DOWNLOAD_RESULT DOWNLOAD_OUTPUT
                     mode=UR -d "${IT_ELF}" -v
                     -w32 ${MAILBOX_ADDRESS_HEX} ${IT_MAILBOX_START}
                     -rst)

endif()

if(NOT DOWNLOAD_RESULT EQUAL 0)
    message("${DOWNLOAD_OUTPUT}")
    message(FATAL_ERROR "Download of the test firmware failed.")
endif()

#======================= 4: Waiting for the end ===============================#

string(TIMESTAMP START_TIME "%s")
math(EXPR END_TIME "${START_TIME} + ${IT_TIMEOUT}")

set(TESTS_FINISHED  FALSE)
set(OUTPUT_LENGTH   0)
set(OUTPUT_SIZE     -1)
set(CASE_PROGRESS   "")
set(CASE_START_TIME ${START_TIME})

while(NOT TESTS_FINISHED)

    itRun_ReadMemory(HEADER_HEX ${MAILBOX_ADDRESS} ${IT_MAILBOX_HEADER_SIZE})

    string(LENGTH "${HEADER_HEX}" HEADER_HEX_LENGTH)
    string(TIMESTAMP ACTUAL_TIME "%s")

    math(EXPR HEADER_HEX_EXPECTED "${IT_MAILBOX_HEADER_SIZE} * 2")

    if(HEADER_HEX_LENGTH EQUAL HEADER_HEX_EXPECTED)

        itRun_GetWord(MAGIC      "${HEADER_HEX}" ${IT_WORD_MAGIC})
        itRun_GetWord(STATE      "${HEADER_HEX}" ${IT_WORD_STATE})
        itRun_GetWord(LENGTH     "${HEADER_HEX}" ${IT_WORD_LENGTH})
        itRun_GetWord(SIZE       "${HEADER_HEX}" ${IT_WORD_SIZE})
        itRun_GetWord(SESSION    "${HEADER_HEX}" ${IT_WORD_SESSION})
        itRun_GetWord(TEST_INDEX "${HEADER_HEX}" ${IT_WORD_TEST_INDEX})
        itRun_GetWord(TEST_COUNT "${HEADER_HEX}" ${IT_WORD_TEST_COUNT})
        itRun_GetWord(TEST_STAGE "${HEADER_HEX}" ${IT_WORD_TEST_STAGE})

        if(MAGIC STREQUAL IT_MAILBOX_MAGIC)

            if(SESSION STREQUAL IT_SESSION_LOCAL)
                message(FATAL_ERROR "Test session was not started by host - mailbox is not kept over system reset "
                                    "(check option bytes SRAM1_3_RST / SRAM2_RST: SRAM must not be erased on reset).")
            endif()

            math(EXPR OUTPUT_LENGTH "0x${LENGTH}")
            math(EXPR OUTPUT_SIZE   "0x${SIZE}")
            math(EXPR CASE_INDEX    "0x${TEST_INDEX}")
            math(EXPR CASE_COUNT    "0x${TEST_COUNT}")
            math(EXPR CASE_STAGE    "0x${TEST_STAGE}")

            if(STATE STREQUAL IT_STATE_FINISHED)

                set(TESTS_FINISHED TRUE)

            elseif(NOT CASE_PROGRESS STREQUAL "${CASE_INDEX}.${CASE_STAGE}")

                # Next test case (or next stage of the test case expecting reset)
                set(CASE_PROGRESS   "${CASE_INDEX}.${CASE_STAGE}")
                set(CASE_START_TIME ${ACTUAL_TIME})

                if(CASE_INDEX LESS CASE_COUNT)
                    math(EXPR CASE_NUMBER "${CASE_INDEX} + 1")
                    message(STATUS "Test case ${CASE_NUMBER}/${CASE_COUNT} (stage ${CASE_STAGE})")
                endif()

            else()

                math(EXPR CASE_DURATION "${ACTUAL_TIME} - ${CASE_START_TIME}")

                if(CASE_DURATION GREATER IT_CASE_TIMEOUT)
                    # Blocked test case - firmware reports it after reset and continues
                    message(STATUS "Test case ${CASE_NUMBER}/${CASE_COUNT} blocked for ${CASE_DURATION} s - aborted (reset of MCU)")

                    if(USE_PROBE_RS)
                        itRun_ProbeRs(ABORT_RESULT ABORT_OUTPUT write b32 ${COMMAND_ADDRESS} ${IT_COMMAND_ABORT})

                        if(ABORT_RESULT EQUAL 0)
                            itRun_ProbeRsReset(ABORT_RESULT ABORT_OUTPUT)
                        endif()
                    else()
                        itRun_Programmer(ABORT_RESULT ABORT_OUTPUT mode=HOTPLUG -w32 ${COMMAND_ADDRESS} ${IT_COMMAND_ABORT} -rst)
                    endif()

                    if(NOT ABORT_RESULT EQUAL 0)
                        message("${ABORT_OUTPUT}")
                        message(WARNING "Abort of the blocked test case failed.")
                    endif()

                    set(CASE_START_TIME ${ACTUAL_TIME})
                endif()

            endif()

        endif()

    endif()

    if(NOT TESTS_FINISHED AND ACTUAL_TIME GREATER END_TIME)
        break()
    elseif(NOT TESTS_FINISHED)
        execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep ${IT_POLL_PERIOD})
    endif()

endwhile()

#========================= 5: Output processing ===============================#

set(OUTPUT_TEXT "")

if(OUTPUT_LENGTH GREATER 0)

    itRun_ReadMemory(OUTPUT_HEX ${OUTPUT_ADDRESS} ${OUTPUT_LENGTH})

    string(LENGTH "${OUTPUT_HEX}" OUTPUT_HEX_LENGTH)
    math(EXPR LAST_CHAR_POSITION "${OUTPUT_HEX_LENGTH} - 2")

    if(LAST_CHAR_POSITION GREATER_EQUAL 0)
        foreach(CHAR_POSITION RANGE 0 ${LAST_CHAR_POSITION} 2)
            string(SUBSTRING "${OUTPUT_HEX}" ${CHAR_POSITION} 2 CHAR_HEX)
            math(EXPR CHAR_CODE "0x${CHAR_HEX}")
            string(ASCII ${CHAR_CODE} CHAR_TEXT)
            string(APPEND OUTPUT_TEXT "${CHAR_TEXT}")
        endforeach()
    endif()

endif()

file(REMOVE "${IT_LOG}.bin")

message("${OUTPUT_TEXT}")

if(NOT TESTS_FINISHED)
    message(FATAL_ERROR "Tests were not finished in ${IT_TIMEOUT} s (MCU crash, blocked test or probe problem). Output above is incomplete.")
elseif(OUTPUT_LENGTH EQUAL OUTPUT_SIZE)
    message(FATAL_ERROR "Output buffer overflow (${OUTPUT_SIZE} B) - increase INTEGRATION_TEST_OUTPUT_SIZE.")
else()
    # Output is stored only when all tests were executed (fixture of test cases)
    file(WRITE "${IT_LOG}" "${OUTPUT_TEXT}")
endif()
