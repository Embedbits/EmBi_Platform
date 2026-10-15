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
# Example:
# cmake -DFUNCTION_ID="PROVIDE" -DMCU=STM32F407xG                       -P Prj_VSCode_ProbeRs.cmake : Find or download the probe-rs artifact
# cmake -DFUNCTION_ID="DAP_SERVER" -DMCU=STM32F407xG -P Prj_VSCode_ProbeRs.cmake -- dap-server --port 50000 ... : Run probe-rs with the arguments after "--"
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

#==============================================================================#
# Global variables
#==============================================================================#

# Read project root folder path
SysConfig_Get_ProjectRootPath(PROJECT_ROOT_PATH)


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

    else()

        message(FATAL_ERROR "Unknown FUNCTION_ID '${FUNCTION_ID}'.")

    endif()

endif()
