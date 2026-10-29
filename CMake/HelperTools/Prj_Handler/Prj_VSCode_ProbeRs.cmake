################################################################################
#
# probe-rs of the VSCode debug configurations (launch.json).
#
# The debug configurations do not contain a path of probe-rs - the debug adapter
# of the probe-rs extension starts this script ("runtimeExecutable": "cmake"),
# which finds the probe-rs artifact of the artifacts cache and runs
# "probe-rs dap-server" with the arguments of the extension. probe-rs of the
# system is never used.
#
# The extension waits only 5 s for the debug adapter, thus the artifact is not
# downloaded here - it is downloaded by the task of the debug configurations
# (preLaunchTask, FUNCTION_ID=PROVIDE) before the debug adapter is started.
#
# The debug configurations of a picked board ("EmBi: Debug on board") connect to
# a debug server started by their preLaunchTask (FUNCTION_ID=DEBUG_SERVE, a
# background task): the Debug firmware is built, the debug server of the probe of
# the board is started on this machine (IntegrationTesting_DebugServer.cmake) or
# over ssh -tt -L by the agent tools of the IT agent of the board (IT agent
# interface, embi-agent debug-server - probe lock, probe-rs of the agent) and the
# configuration connects when the server listens. The board is
# the one picked by the inputs of the configuration (DEBUG_TARGET_FILE, written
# by Prj_VSCode_Handler.cmake DEBUG_TARGET_SERVER).
#
# Example:
# cmake -DFUNCTION_ID="PROVIDE" -DMCU=STM32F407xG                       -P Prj_VSCode_ProbeRs.cmake : Find or download the probe-rs artifact
# cmake -DFUNCTION_ID="DAP_SERVER" -DMCU=STM32F407xG -P Prj_VSCode_ProbeRs.cmake -- dap-server --port 50000 ... : Run probe-rs with the arguments after "--"
# cmake -DFUNCTION_ID="DEBUG_SERVE" -DBUILD=ON                          -P Prj_VSCode_ProbeRs.cmake : Build the firmware and serve the picked board
#
# The probe-rs version is the one configured for the integration test preset of
# the MCU (ARTIFACTS_HANDLER_REQ_LIST), not the newest cached version.
#
################################################################################

# Set path to system configuration file
get_filename_component(SYSTEM_CONFIG_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/../../SysConfig.cmake" REALPATH)

# Include file with system configuration values
include("${SYSTEM_CONFIG_FILE_PATH}")

# probe-rs artifact lookup and download
include("${CMAKE_CURRENT_LIST_DIR}/../../IntegrationTesting/IntegrationTesting_Probe.cmake")

# Debug server of a probe of this machine and the IT agent interface (debug server of a board of an agent)
include("${CMAKE_CURRENT_LIST_DIR}/../../IntegrationTesting/IntegrationTesting_DebugServer.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../IntegrationTesting/IntegrationTesting_Remote.cmake")

#==============================================================================#
# Global variables
#==============================================================================#

# Read project root folder path
SysConfig_Get_ProjectRootPath(PROJECT_ROOT_PATH)

# Board picked by the inputs of the debug configuration of a picked board (Prj_VSCode_Handler.cmake)
set(VSCODE_DEBUG_TARGET_FILE    "${PROJECT_ROOT_PATH}/Build/DebugTarget.cmake")

# Build handler (Debug firmware of the picked board)
set(VSCODE_BUILD_HANDLER_SCRIPT "${CMAKE_CURRENT_LIST_DIR}/../Build_Handler/Build_Handler.cmake")
get_filename_component(VSCODE_BUILD_HANDLER_SCRIPT "${VSCODE_BUILD_HANDLER_SCRIPT}" ABSOLUTE)


#==============================================================================#
# Functions
#==============================================================================#

# ------------------------------------------------------------------------------
# Function: Prj_VSCode_ProbeRs_Provide
# Description: Finds the probe-rs artifact in the artifacts cache, downloads it
#              by the artifacts handler if it is missing (preLaunchTask of the
#              debug configurations).
# ------------------------------------------------------------------------------
function(Prj_VSCode_ProbeRs_Provide)

    IntegrationTesting_ProvideProbeRs(PROBE_RS "${PROJECT_ROOT_PATH}" "${MCU}")

    message("probe-rs: ${PROBE_RS}")
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_ProbeRs_Run
# Description: Runs the probe-rs artifact of the artifacts cache with the
#              arguments of the command line after "--" (debug adapter of the
#              probe-rs extension: dap-server --port <port> ...). Nothing is
#              printed before probe-rs is started - the extension takes any
#              error output of the debug adapter as its failure.
# ------------------------------------------------------------------------------
function(Prj_VSCode_ProbeRs_Run)

    IntegrationTesting_FindProbeRs(PROBE_RS "${PROJECT_ROOT_PATH}" "${MCU}")

    if(NOT PROBE_RS)
        message(FATAL_ERROR "The probe-rs artifact (configured version) is not in the artifacts cache - run the task "
                            "\"EmBi: Provide probe-rs ${MCU}\" (it is a part of the debug configurations, preLaunchTask).")
    endif()

    # Arguments after "--" of the command line (CMAKE_ARGV0 is cmake)
    set(PROBE_RS_ARGS "")
    set(AFTER_SEPARATOR FALSE)

    math(EXPR LAST_ARG "${CMAKE_ARGC} - 1")

    foreach(ARG_IDX RANGE 1 ${LAST_ARG})
        if(AFTER_SEPARATOR)
            list(APPEND PROBE_RS_ARGS "${CMAKE_ARGV${ARG_IDX}}")
        elseif("${CMAKE_ARGV${ARG_IDX}}" STREQUAL "--")
            set(AFTER_SEPARATOR TRUE)
        endif()
    endforeach()

    execute_process(COMMAND "${PROBE_RS}" ${PROBE_RS_ARGS} RESULT_VARIABLE PROBE_RS_RESULT)

    if(NOT PROBE_RS_RESULT EQUAL 0)
        message(FATAL_ERROR "probe-rs ended with ${PROBE_RS_RESULT}.")
    endif()
endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_VSCode_ProbeRs_Serve
# Description: preLaunchTask of the debug configurations of a picked board (background task of VS Code):
#              builds the Debug firmware of the MCU of the board (BUILD=ON), starts the debug server of
#              the probe of the board and waits for its end. A board of this machine is served by
#              IntegrationTesting_DebugServer.cmake here, a board of an IT agent by its agent tools
#              (embi-agent debug-server) over ssh -tt -L <local port>:127.0.0.1:<port of the agent>
#              - nothing is copied to the agent. The script prints
#              "EmBi: preparing debugging" at the start and the server
#              "EmBi: debug server listening on port <port>" when the debug configuration can connect.
#              The task ends with the debug session or with an error (board used by another client,
#              build error, agent not reachable).
# ------------------------------------------------------------------------------
function(Prj_VSCode_ProbeRs_Serve)

    if(NOT EXISTS "${VSCODE_DEBUG_TARGET_FILE}")
        message(FATAL_ERROR "${VSCODE_DEBUG_TARGET_FILE} not found - start the debug configuration \"EmBi: Debug on "
                            "board\" (its inputs pick the board).")
    endif()

    include("${VSCODE_DEBUG_TARGET_FILE}")

    message(STATUS "EmBi: preparing debugging of ${DEBUG_TARGET_TEXT}")

    # A stale board of ItBoards.json (no longer in the configuration of its IT agent) - its configuration is not used
    set(BOARDS_CONFIG_FILE "${PROJECT_ROOT_PATH}/${IT_PROJECT_BOARDS_NAME}")
    if(EXISTS "${BOARDS_CONFIG_FILE}")
        file(READ "${BOARDS_CONFIG_FILE}" BOARDS_CONFIG)
        if("${DEBUG_PROBE}" MATCHES "^[0-9A-Fa-f]+:[0-9A-Fa-f]+:(.+)$")
            string(JSON STALE ERROR_VARIABLE STALE_ERROR GET "${BOARDS_CONFIG}" probes "${CMAKE_MATCH_1}" stale)
            if(NOT STALE_ERROR AND
               STALE)
                message(WARNING "The configuration of probe ${DEBUG_PROBE} in ${IT_PROJECT_BOARDS_NAME} is stale (no "
                                "longer in the configuration of its IT agent) - it is not used.")
            endif()
        endif()
    endif()

    # The Debug build of the board (its configuration of ItBoards.json - fixture, own defines - in its build folder)
    if(BUILD)
        set(BUILD_ARGS -DFUNCTION_ID=BUILD "-DBOARD=${DEBUG_BOARD}" -DBUILD_TYPE=Debug -P "${VSCODE_BUILD_HANDLER_SCRIPT}")
        execute_process(COMMAND "${CMAKE_COMMAND}" ${BUILD_ARGS}
                        WORKING_DIRECTORY "${PROJECT_ROOT_PATH}"
                        RESULT_VARIABLE BUILD_RESULT)
        if(NOT BUILD_RESULT EQUAL 0)
            message(FATAL_ERROR "Debug build of the board ${DEBUG_BOARD} failed - the board is not debugged.")
        endif()
    endif()

    IntegrationTesting_ProvideProbeRs(PROBE_RS "${PROJECT_ROOT_PATH}" "${DEBUG_MCU}")
    IntegrationTesting_Get_LockHolder(HOLDER "debugging")

    if("${DEBUG_HOST}" STREQUAL "${IT_LOCAL_HOST}")

        set(SERVE_ARGS -DFUNCTION_ID=DAP_SERVER "-DIT_PROBE_RS=${PROBE_RS}" "-DIT_PROBE=${DEBUG_PROBE}")
        list(APPEND SERVE_ARGS -DIT_PORT=${DEBUG_LOCAL_PORT} "-DIT_HOLDER=${HOLDER}" -P "${IT_DEBUG_SERVER_SCRIPT}")
        execute_process(COMMAND "${CMAKE_COMMAND}" ${SERVE_ARGS}
                        RESULT_VARIABLE SERVE_RESULT)

    else()

        IntegrationTesting_Get_ProbeRsVersion(PROBE_RS_VERSION "${PROBE_RS}")

        # The local port of the tunnel of the previous session of a restart may still be closing
        foreach(POLL_IDX RANGE 1 30)
            IntegrationTesting_IsListening(PORT_USED ${DEBUG_LOCAL_PORT})
            if(NOT PORT_USED)
                break()
            endif()
            execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep 0.5)
        endforeach()

        IntegrationTesting_Get_SshCommand(SSH_COMMAND
                                          "${DEBUG_SSH_TARGET}"
                                          TRUE
                                          -o ExitOnForwardFailure=yes
                                          -L "${DEBUG_LOCAL_PORT}:127.0.0.1:${DEBUG_REMOTE_PORT}")

        IntegrationTesting_Get_AgentLine(REMOTE_COMMAND
                                         "${DEBUG_HOST_TOOLS}"
                                         debug-server
                                         --probe
                                         "${DEBUG_PROBE}"
                                         --port
                                         ${DEBUG_REMOTE_PORT}
                                         --probe-rs
                                         "${PROBE_RS_VERSION}"
                                         --holder
                                         "${HOLDER}")

        execute_process(COMMAND ${SSH_COMMAND} "${REMOTE_COMMAND}"
                        RESULT_VARIABLE SERVE_RESULT)

        if(SERVE_RESULT EQUAL IT_AGENT_NOT_INSTALLED)
            message(FATAL_ERROR "embi-agent is not installed on the IT agent ${DEBUG_HOST} (${DEBUG_SSH_TARGET}) - the "
                                "pipeline ItAgentUpdate of EmBi_Tester installs it (or tools of the host in "
                                "ItHosts.json).")
        endif()

    endif()

    if(NOT SERVE_RESULT EQUAL 0)
        message(FATAL_ERROR "Debugging of ${DEBUG_TARGET_TEXT} ended with ${SERVE_RESULT}.")
    endif()

endfunction()


#==============================================================================#
# Main functionality
#
# If the script is executed in script mode ( -P ), execution is started with
# first direct code out of function, thus functions execution has to be
# triggered.
#==============================================================================#
if(CMAKE_SCRIPT_MODE_FILE AND
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)

    if("${FUNCTION_ID}" STREQUAL "PROVIDE")

        Prj_VSCode_ProbeRs_Provide()

    elseif("${FUNCTION_ID}" STREQUAL "DAP_SERVER")

        Prj_VSCode_ProbeRs_Run()

    elseif("${FUNCTION_ID}" STREQUAL "DEBUG_SERVE")

        Prj_VSCode_ProbeRs_Serve()

    else()

        message(FATAL_ERROR "Unknown FUNCTION_ID '${FUNCTION_ID}'.")

    endif()

endif()
