################################################################################
# Author: Mr.Nobody
# file:  IntegrationTesting_Lock.cmake
# brief: Probe lock - a debug probe is used by one client at a time (debugging,
#        integration tests, detection of connected boards, pipeline jobs).
#
# Included by IntegrationTesting_Probe.cmake (selection of the probe of the
# tests, detection) and IntegrationTesting_DebugServer.cmake (debug server). The
# same protocol is implemented by ItRun.cmake of EmBi_Tester (pipeline jobs and
# the agent tools embi-agent on the IT agents) - a change of the protocol has to
# be done in both:
#
#   - Lock folder: environment variable INTEGRATION_TEST_LOCK_DIR, otherwise
#     <temporary folder>/embi-probe-locks (/tmp on Linux and macOS, TEMP on
#     Windows) with mode 0777 - the clients run as different users (debugging
#     over SSH as the SSH user, pipeline jobs as the user of the agent).
#   - Lock file probe-<key>.lock (mode 0666), <key> = serial number of the probe
#     (selector VID:PID:SN or SN), VID-PID of a probe without a serial number,
#     characters other than letters, digits, '-' and '_' replaced by '_'. The
#     lock is the lock of the file (CMake file(LOCK): fcntl / LockFileEx) - the
#     operating system releases it when the process ends, also when it is killed
#     or its SSH connection breaks. The file itself is never removed.
#   - Holder file probe-<key>.holder (mode 0666): one line
#     "<holder>, since <YYYY-MM-DD hh:mm:ss> UTC" written by the process that
#     got the lock - read by the clients that wait for it.
#   - Environment variable INTEGRATION_TEST_PROBE_LOCKED: keys of the probes
#     locked by a parent process (eg. ItRun.cmake for the whole ctest run),
#     separated by ';' or ','. Their lock is not requested again - the lock of a
#     file belongs to the process, the child would wait for its parent.
################################################################################

include_guard(GLOBAL)

#=============================== Constant values ==============================#

# Lock folder in the temporary folder of the host
set(IT_LOCK_DIR_NAME                    "embi-probe-locks")

# Longest wait of one file(LOCK) call [s] - the holder is reported after every one
set(IT_LOCK_REPORT_PERIOD               60)

#================================ Functions ===================================#

#------------------------------------------------------------------------------#
# Key of the lock of a probe: serial number of the probe-rs selector (VID:PID:SN
# or SN), VID-PID of a probe without a serial number.
#
# KEY_VAR  [out]: Key
# SELECTOR [in]:  probe-rs selector or serial number
#------------------------------------------------------------------------------#
function(IntegrationTesting_Get_LockKey KEY_VAR SELECTOR)

    if("${SELECTOR}" MATCHES "^[0-9A-Fa-f]+:[0-9A-Fa-f]+:(.+)$")
        set(KEY "${CMAKE_MATCH_1}")
    elseif("${SELECTOR}" MATCHES "^([0-9A-Fa-f]+):([0-9A-Fa-f]+)$")
        set(KEY "${CMAKE_MATCH_1}-${CMAKE_MATCH_2}")
    else()
        set(KEY "${SELECTOR}")
    endif()

    string(REGEX REPLACE "[^A-Za-z0-9_-]" "_" KEY "${KEY}")

    set(${KEY_VAR} "${KEY}" PARENT_SCOPE)

endfunction(IntegrationTesting_Get_LockKey)

#------------------------------------------------------------------------------#
# Sets the mode of a file or folder created by this process, so the clients
# running as other users can use it (no effect on Windows; an error is ignored -
# a file created by another user has its mode already).
#
# PATH [in]: File or folder
# MODE [in]: Octal mode (0777, 0666)
#------------------------------------------------------------------------------#
function(itLock_ShareFile PATH MODE)

    if(NOT CMAKE_HOST_WIN32)
        execute_process(COMMAND chmod ${MODE} "${PATH}" RESULT_VARIABLE CHMOD_RESULT OUTPUT_QUIET ERROR_QUIET)
    else()
        # Lock folder of the user (TEMP), nothing to share
    endif()

endfunction(itLock_ShareFile)

#------------------------------------------------------------------------------#
# Returns the lock folder (created when it does not exist).
#
# DIR_VAR [out]: Lock folder
#------------------------------------------------------------------------------#
function(IntegrationTesting_Get_LockDir DIR_VAR)

    if(NOT "$ENV{INTEGRATION_TEST_LOCK_DIR}" STREQUAL "")
        file(TO_CMAKE_PATH "$ENV{INTEGRATION_TEST_LOCK_DIR}" LOCK_DIR)
    elseif(CMAKE_HOST_WIN32)
        set(TEMP_DIR "$ENV{TEMP}")
        if("${TEMP_DIR}" STREQUAL "")
            set(TEMP_DIR "$ENV{TMP}")
        endif()
        file(TO_CMAKE_PATH "${TEMP_DIR}" TEMP_DIR)
        set(LOCK_DIR "${TEMP_DIR}/${IT_LOCK_DIR_NAME}")
    else()
        set(LOCK_DIR "/tmp/${IT_LOCK_DIR_NAME}")
    endif()

    if(NOT EXISTS "${LOCK_DIR}")
        file(MAKE_DIRECTORY "${LOCK_DIR}")
        itLock_ShareFile("${LOCK_DIR}" 0777)
    endif()

    set(${DIR_VAR} "${LOCK_DIR}" PARENT_SCOPE)

endfunction(IntegrationTesting_Get_LockDir)

#------------------------------------------------------------------------------#
# Returns the default holder of a lock: the pipeline run (Azure Pipelines
# variables of a job) or <login>@<computer>, followed by the purpose.
#
# HOLDER_VAR [out]: Holder
# PURPOSE    [in]:  Purpose ("debugging", "integration tests", "" = none)
#------------------------------------------------------------------------------#
function(IntegrationTesting_Get_LockHolder HOLDER_VAR PURPOSE)

    if(NOT "$ENV{BUILD_BUILDNUMBER}" STREQUAL "")
        set(HOLDER "pipeline $ENV{BUILD_DEFINITIONNAME} $ENV{BUILD_BUILDNUMBER}")
    else()
        set(LOGIN "$ENV{USERNAME}")
        if("${LOGIN}" STREQUAL "")
            set(LOGIN "$ENV{USER}")
        endif()
        cmake_host_system_information(RESULT COMPUTER QUERY HOSTNAME)
        set(HOLDER "${LOGIN}@${COMPUTER}")
    endif()

    if(NOT "${PURPOSE}" STREQUAL "")
        string(APPEND HOLDER " (${PURPOSE})")
    endif()

    set(${HOLDER_VAR} "${HOLDER}" PARENT_SCOPE)

endfunction(IntegrationTesting_Get_LockHolder)

#------------------------------------------------------------------------------#
# Checks whether a parent process holds the lock of a probe
# (INTEGRATION_TEST_PROBE_LOCKED).
#
# LOCKED_VAR [out]: TRUE when the parent process holds the lock
# KEY        [in]:  Key of the lock (IntegrationTesting_Get_LockKey)
#------------------------------------------------------------------------------#
function(itLock_IsParentLock LOCKED_VAR KEY)

    string(REPLACE "," ";" PARENT_KEYS "$ENV{INTEGRATION_TEST_PROBE_LOCKED}")

    if("${KEY}" IN_LIST PARENT_KEYS)
        set(${LOCKED_VAR} TRUE PARENT_SCOPE)
    else()
        set(${LOCKED_VAR} FALSE PARENT_SCOPE)
    endif()

endfunction(itLock_IsParentLock)

#------------------------------------------------------------------------------#
# Reads the holder of a lock from its holder file.
#
# HOLDER_VAR  [out]: Holder ("unknown holder" when the file is empty)
# HOLDER_FILE [in]:  Holder file
#------------------------------------------------------------------------------#
function(itLock_ReadHolder HOLDER_VAR HOLDER_FILE)

    set(HOLDER "")

    if(EXISTS "${HOLDER_FILE}")
        file(READ "${HOLDER_FILE}" HOLDER)
        string(STRIP "${HOLDER}" HOLDER)
    endif()

    if("${HOLDER}" STREQUAL "")
        set(HOLDER "unknown holder")
    endif()

    set(${HOLDER_VAR} "${HOLDER}" PARENT_SCOPE)

endfunction(itLock_ReadHolder)

#------------------------------------------------------------------------------#
# Locks a probe for this process - the lock is released when the process ends
# or by IntegrationTesting_UnlockProbe. A probe locked by another process is
# waited for at most WAIT seconds, its holder is reported every
# IT_LOCK_REPORT_PERIOD seconds.
#
# RESULT_VAR [out]: "" when this process (or its parent process,
#                   INTEGRATION_TEST_PROBE_LOCKED) holds the lock, otherwise the
#                   holder of the lock or the error of the lock
# SELECTOR   [in]:  probe-rs selector or serial number
# WAIT       [in]:  Longest wait [s], 0 = no waiting
# HOLDER     [in]:  Holder written into the holder file
#                   (IntegrationTesting_Get_LockHolder)
#------------------------------------------------------------------------------#
function(IntegrationTesting_LockProbe RESULT_VAR SELECTOR WAIT HOLDER)

    IntegrationTesting_Get_LockKey(KEY "${SELECTOR}")
    itLock_IsParentLock(PARENT_LOCK "${KEY}")

    if(PARENT_LOCK)
        set(${RESULT_VAR} "" PARENT_SCOPE)
        return()
    endif()

    IntegrationTesting_Get_LockDir(LOCK_DIR)
    set(LOCK_FILE   "${LOCK_DIR}/probe-${KEY}.lock")
    set(HOLDER_FILE "${LOCK_DIR}/probe-${KEY}.holder")

    foreach(SHARED_FILE IN ITEMS "${LOCK_FILE}" "${HOLDER_FILE}")
        if(NOT EXISTS "${SHARED_FILE}")
            file(TOUCH "${SHARED_FILE}")
            itLock_ShareFile("${SHARED_FILE}" 0666)
        endif()
    endforeach()

    file(LOCK "${LOCK_FILE}" GUARD PROCESS TIMEOUT 0 RESULT_VARIABLE LOCK_RESULT)

    if(NOT "${LOCK_RESULT}" STREQUAL "0" AND
       WAIT GREATER 0)

        math(EXPR PERIODS_CNT "( ${WAIT} + ${IT_LOCK_REPORT_PERIOD} - 1 ) / ${IT_LOCK_REPORT_PERIOD}")
        set(WAIT_LEFT ${WAIT})

        foreach(PERIOD_IDX RANGE 1 ${PERIODS_CNT})

            itLock_ReadHolder(LOCK_HOLDER "${HOLDER_FILE}")
            message(STATUS "Probe ${SELECTOR} is used by ${LOCK_HOLDER} - waiting for it (${WAIT_LEFT} s left)")

            set(WAIT_STEP ${IT_LOCK_REPORT_PERIOD})
            if(WAIT_LEFT LESS WAIT_STEP)
                set(WAIT_STEP ${WAIT_LEFT})
            endif()

            file(LOCK "${LOCK_FILE}" GUARD PROCESS TIMEOUT ${WAIT_STEP} RESULT_VARIABLE LOCK_RESULT)

            if("${LOCK_RESULT}" STREQUAL "0")
                break()
            endif()

            math(EXPR WAIT_LEFT "${WAIT_LEFT} - ${WAIT_STEP}")

        endforeach()

    endif()

    if("${LOCK_RESULT}" STREQUAL "0")
        string(TIMESTAMP NOW "%Y-%m-%d %H:%M:%S" UTC)
        file(WRITE "${HOLDER_FILE}" "${HOLDER}, since ${NOW} UTC\n")
        set(RESULT "")
    elseif("${LOCK_RESULT}" MATCHES "[Tt]imeout")
        itLock_ReadHolder(RESULT "${HOLDER_FILE}")
    else()
        set(RESULT "lock error of ${LOCK_FILE}: ${LOCK_RESULT}")
    endif()

    set(${RESULT_VAR} "${RESULT}" PARENT_SCOPE)

endfunction(IntegrationTesting_LockProbe)

#------------------------------------------------------------------------------#
# Releases the lock of a probe held by this process (a lock of a parent process
# is not released).
#
# SELECTOR [in]: probe-rs selector or serial number
#------------------------------------------------------------------------------#
function(IntegrationTesting_UnlockProbe SELECTOR)

    IntegrationTesting_Get_LockKey(KEY "${SELECTOR}")
    itLock_IsParentLock(PARENT_LOCK "${KEY}")

    if(NOT PARENT_LOCK)
        IntegrationTesting_Get_LockDir(LOCK_DIR)
        file(LOCK "${LOCK_DIR}/probe-${KEY}.lock" RELEASE RESULT_VARIABLE RELEASE_RESULT)
    else()
        # The lock belongs to the parent process
    endif()

endfunction(IntegrationTesting_UnlockProbe)
