################################################################################
# Author: Mr.Nobody
# file:  IntegrationTesting_DebugServer.cmake
# brief: Debug server of a probe of this machine (probe-rs dap-server, one
#        session) - started by the debug configurations of VS Code of a picked
#        board of this machine (Prj_VSCode_ProbeRs.cmake). A board of an IT agent
#        is served by the agent itself (IT agent interface, embi-agent
#        debug-server - the same behavior).
#
#   cmake -DFUNCTION_ID=DAP_SERVER -DIT_PROBE_RS=<probe-rs> -DIT_PROBE=<VID:PID:SN>
#         -DIT_PORT=<port of 127.0.0.1> -DIT_HOLDER=<holder>
#         -P IntegrationTesting_DebugServer.cmake
#   - the probe is locked for the whole session (IntegrationTesting_Lock.cmake):
#     a board used by another client (pipeline job, tests) is not debugged, the
#     holder is reported; a lock of the same holder (previous session of a
#     restart still ending) is waited for IT_DEBUG_RESTART_WAIT seconds
#   - "EmBi: debug server listening on port <port>" is printed when the server
#     listens (the debug configuration connects then - background task of VS Code)
#   - the server ends with the session (disconnect); on Linux the temporary folder
#     of probe-rs is /tmp/embi-dap-<probe> (removed at the start and at the end)
################################################################################

cmake_minimum_required(VERSION 3.25)

include("${CMAKE_CURRENT_LIST_DIR}/IntegrationTesting_Lock.cmake")

#=============================== Constant values ==============================#

# This script (the watcher of the debug server is a second cmake process of it)
set(IT_DEBUG_SERVER_SCRIPT              "${CMAKE_CURRENT_LIST_FILE}")

# Wait for the end of the previous debug session of the same holder (restart) [s]
set(IT_DEBUG_RESTART_WAIT               15)

# Polls of the listening debug server and the pause between them [s] (10 s)
set(IT_DEBUG_LISTEN_POLLS               100)
set(IT_DEBUG_LISTEN_PERIOD              "0.1")

#================================ Functions ===================================#

#------------------------------------------------------------------------------#
# Checks whether a TCP port of 127.0.0.1 listens - /proc/net/tcp on Linux,
# netstat on Windows (a listening socket has the remote address 0.0.0.0:0).
#
# LISTENING_VAR [out]: TRUE when the port listens
# PORT          [in]:  TCP port
#------------------------------------------------------------------------------#
function(IntegrationTesting_IsListening LISTENING_VAR PORT)

    set(LISTENING FALSE)

    if(CMAKE_HOST_WIN32)

        execute_process(COMMAND netstat -an -p TCP OUTPUT_VARIABLE NETSTAT_OUTPUT ERROR_QUIET)

        if("${NETSTAT_OUTPUT}" MATCHES "127\\.0\\.0\\.1:${PORT}[ \t]+0\\.0\\.0\\.0:0[ \t]")
            set(LISTENING TRUE)
        endif()

    else()

        # Local address <address in hex>:<port in hex>, state 0A = LISTEN
        math(EXPR PORT_HEX "${PORT}" OUTPUT_FORMAT HEXADECIMAL)
        string(TOUPPER "${PORT_HEX}" PORT_HEX)
        string(REGEX REPLACE "^0X" "" PORT_HEX "${PORT_HEX}")
        string(LENGTH "${PORT_HEX}" PORT_HEX_LENGTH)
        math(EXPR PADDING_LENGTH "4 - ${PORT_HEX_LENGTH}")
        if(PADDING_LENGTH GREATER 0)
            string(REPEAT "0" ${PADDING_LENGTH} PADDING)
            string(PREPEND PORT_HEX "${PADDING}")
        endif()

        foreach(TABLE IN ITEMS /proc/net/tcp /proc/net/tcp6)
            if(EXISTS "${TABLE}")
                file(READ "${TABLE}" TABLE_CONTENT)
                if("${TABLE_CONTENT}" MATCHES ":${PORT_HEX} [0-9A-F]+:[0-9A-F]+ 0A ")
                    set(LISTENING TRUE)
                endif()
            endif()
        endforeach()

    endif()

    set(${LISTENING_VAR} ${LISTENING} PARENT_SCOPE)

endfunction(IntegrationTesting_IsListening)

#------------------------------------------------------------------------------#
# Waits until the debug server listens on IT_PORT and prints the line the
# debug configuration of VS Code waits for (watcher of itDebug_DapServer).
#------------------------------------------------------------------------------#
function(itDebug_WaitListen)

    set(LISTENING FALSE)

    foreach(POLL_IDX RANGE 1 ${IT_DEBUG_LISTEN_POLLS})

        IntegrationTesting_IsListening(LISTENING ${IT_PORT})

        if(LISTENING)
            break()
        endif()

        execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep ${IT_DEBUG_LISTEN_PERIOD})

    endforeach()

    if(LISTENING)
        message("EmBi: debug server listening on port ${IT_PORT}")
    else()
        message("EmBi: debug server does not listen on port ${IT_PORT} - see the output of probe-rs above.")
    endif()

endfunction(itDebug_WaitListen)

#------------------------------------------------------------------------------#
# Runs the debug server of the probe IT_PROBE on IT_PORT of 127.0.0.1 under the
# lock of the probe (one debug session, probe-rs dap-server --single-session)
# with its watcher (itDebug_WaitListen).
#------------------------------------------------------------------------------#
function(itDebug_DapServer)

    foreach(PARAMETER IN ITEMS IT_PROBE_RS IT_PROBE IT_PORT IT_HOLDER)
        if("${${PARAMETER}}" STREQUAL "")
            message(FATAL_ERROR "Parameter ${PARAMETER} is not set.")
        endif()
    endforeach()

    IntegrationTesting_LockProbe(LOCK_RESULT "${IT_PROBE}" 0 "${IT_HOLDER}")

    # The previous debug session of the same holder is still ending (restart of the session)
    string(FIND "${LOCK_RESULT}" "${IT_HOLDER}," HOLDER_POSITION)
    if(HOLDER_POSITION EQUAL 0)
        IntegrationTesting_LockProbe(LOCK_RESULT "${IT_PROBE}" ${IT_DEBUG_RESTART_WAIT} "${IT_HOLDER}")
    endif()

    if(NOT "${LOCK_RESULT}" STREQUAL "")
        message(FATAL_ERROR "The board of probe ${IT_PROBE} is used by ${LOCK_RESULT} - it is not debugged now.")
    endif()

    # The port of the previous session of a restart may still be closing
    set(PORT_USED TRUE)
    math(EXPR PORT_POLLS "${IT_DEBUG_RESTART_WAIT} * 2")
    foreach(POLL_IDX RANGE 1 ${PORT_POLLS})
        IntegrationTesting_IsListening(PORT_USED ${IT_PORT})
        if(NOT PORT_USED)
            break()
        endif()
        execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep 0.5)
    endforeach()

    if(PORT_USED)
        message(FATAL_ERROR "Port ${IT_PORT} of 127.0.0.1 is used by another program - "
                            "the debug server is not started.")
    endif()

    # Temporary folder of probe-rs (Linux): the folder of the probe, the folder of a session ended by a
    # broken connection is removed now
    set(ENV_COMMAND "")
    set(TMP_DIR "")

    if(NOT CMAKE_HOST_WIN32)
        IntegrationTesting_Get_LockKey(KEY "${IT_PROBE}")
        set(TMP_DIR "/tmp/embi-dap-${KEY}")
        file(REMOVE_RECURSE "${TMP_DIR}")
        file(MAKE_DIRECTORY "${TMP_DIR}")
        set(ENV_COMMAND "${CMAKE_COMMAND}" -E env "TMPDIR=${TMP_DIR}")
    endif()

    message(STATUS "probe-rs dap-server of probe ${IT_PROBE} on port ${IT_PORT} (${IT_PROBE_RS})")

    execute_process(COMMAND "${CMAKE_COMMAND}" -DFUNCTION_ID=WAIT_LISTEN -DIT_PORT=${IT_PORT} -P "${IT_DEBUG_SERVER_SCRIPT}"
                    COMMAND ${ENV_COMMAND} "${IT_PROBE_RS}" dap-server --port ${IT_PORT} --single-session
                    RESULT_VARIABLE DAP_RESULT)

    if(NOT "${TMP_DIR}" STREQUAL "")
        file(REMOVE_RECURSE "${TMP_DIR}")
    endif()

    if(NOT DAP_RESULT EQUAL 0)
        message(FATAL_ERROR "probe-rs dap-server ended with ${DAP_RESULT}.")
    endif()

    message(STATUS "Debug session of probe ${IT_PROBE} ended.")

endfunction(itDebug_DapServer)

#==============================================================================#
# Script mode
#==============================================================================#
if(CMAKE_SCRIPT_MODE_FILE AND
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)

    if("${FUNCTION_ID}" STREQUAL "DAP_SERVER")

        itDebug_DapServer()

    elseif("${FUNCTION_ID}" STREQUAL "WAIT_LISTEN")

        itDebug_WaitListen()

    else()

        message(FATAL_ERROR "Unknown FUNCTION_ID '${FUNCTION_ID}'.")

    endif()

endif()
