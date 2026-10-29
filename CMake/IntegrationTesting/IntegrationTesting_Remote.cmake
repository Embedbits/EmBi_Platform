################################################################################
# Author: Mr.Nobody
# file:  IntegrationTesting_Remote.cmake
# brief: Boards of IT agents - hosts of ItHosts.json and the IT agent interface
#        (README "IT agent interface"): this machine starts the tools of the
#        agent (embi-agent, installed on the agent from EmBi_Tester) over SSH.
#
# An IT agent is a machine with debug probes other than this one, eg. a Linux
# host of the integration test pipeline. It needs:
#   - an SSH server accepting the key of this machine without a password
#     (BatchMode),
#   - the agent tools embi-agent (~/_tools/embi of the pipeline user, installed
#     by the pipeline ItAgentUpdate of EmBi_Tester) - the detection of its boards,
#     the debug server of a board and the run of a test package are done by them,
#     nothing of this machine is copied to the agent and executed there.
#
# ItHosts.json in the project root (optional, not versioned - the hosts and the
# accounts are the ones of the developer):
#   { "hosts": { "<name>": "<user>@<host>[:<SSH port>]",
#                "<name>": { "target": "<user>@<host>[:<SSH port>]",
#                            "tools":  "<path of embi-agent on the agent>" } } }
#   <name>  letters, digits, '_', '-' and '.'; "local" is this machine
#   tools   embi-agent of the agent (default: $HOME/_tools/embi/embi-agent or
#           /home/*/_tools/embi/embi-agent of the agent)
#
# ssh and scp of the system are used (OpenSSH; Windows 10 and newer has them).
################################################################################

include_guard(GLOBAL)

#=============================== Constant values ==============================#

# Options of every ssh / scp call: no password prompt, connection timeout, detection of a broken
# connection (the remote command ends then and releases its probe lock)
set(IT_REMOTE_SSH_OPTIONS               -o BatchMode=yes -o ConnectTimeout=10
                                        -o ServerAliveInterval=15 -o ServerAliveCountMax=4)

# Name of this machine in the host members of the boards file
set(IT_LOCAL_HOST                       "local")

# Board configuration of the project (project root) and its former name (not read any more)
set(IT_PROJECT_BOARDS_NAME              "ItBoards.json")
set(IT_PROJECT_BOARDS_OLD_NAME          "IntegrationTestBoards.json")

# IT agent interface (README "IT agent interface"): version this machine speaks, prefix of the result line of a
# command, the tools of the agent in the tools folder of a user of the agent
set(IT_AGENT_INTERFACE_VERSION          1)
set(IT_AGENT_RESULT_PREFIX              "EMBI-AGENT ")
set(IT_AGENT_TOOLS_PATH                 "_tools/embi/embi-agent")

# Folder of a test package on the agent (new-package; the agent removes a forgotten one after 24 hours)
set(IT_AGENT_PACKAGE_PATTERN            "^/tmp/embi-it-[a-z0-9]+$")

# Exit code of the locator when embi-agent is not installed on the agent, of ssh when the connection failed
set(IT_AGENT_NOT_INSTALLED              127)
set(IT_REMOTE_SSH_FAILED                255)

#================================ Functions ===================================#

#------------------------------------------------------------------------------#
# Reads the IT hosts of the project (ItHosts.json in the project root, optional).
# For every host <name> sets in the parent scope:
#   IT_HOST_<name>_TARGET   <user>@<host>[:<SSH port>]
#   IT_HOST_<name>_TOOLS    embi-agent on the agent ("" = the default of the agent)
#
# HOSTS_VAR   [out]: Names of the hosts ("" if none)
# PROJECT_DIR [in]:  Project root folder
#------------------------------------------------------------------------------#
function(IntegrationTesting_ReadItHosts HOSTS_VAR PROJECT_DIR)

    set(HOSTS_FILE "${PROJECT_DIR}/ItHosts.json")
    set(HOSTS "")

    if(EXISTS "${HOSTS_FILE}")

        file(READ "${HOSTS_FILE}" HOSTS_CONTENT)
        string(JSON HOSTS_CNT ERROR_VARIABLE HOSTS_ERROR LENGTH "${HOSTS_CONTENT}" hosts)

        if(HOSTS_ERROR)
            message(WARNING "${HOSTS_FILE}: object \"hosts\" not found - ignored.")
            set(HOSTS_CNT 0)
        endif()

        if(HOSTS_CNT GREATER 0)

            math(EXPR HOSTS_LAST "${HOSTS_CNT} - 1")

            foreach(HOST_IDX RANGE ${HOSTS_LAST})

                string(JSON NAME MEMBER "${HOSTS_CONTENT}" hosts ${HOST_IDX})
                string(JSON HOST_TYPE TYPE "${HOSTS_CONTENT}" hosts "${NAME}")

                set(TOOLS "")

                if("${HOST_TYPE}" STREQUAL "OBJECT")
                    string(JSON TARGET ERROR_VARIABLE TARGET_ERROR GET "${HOSTS_CONTENT}" hosts "${NAME}" target)
                    string(JSON VALUE ERROR_VARIABLE VALUE_ERROR GET "${HOSTS_CONTENT}" hosts "${NAME}" tools)
                    if(NOT VALUE_ERROR)
                        set(TOOLS "${VALUE}")
                    endif()
                else()
                    string(JSON TARGET GET "${HOSTS_CONTENT}" hosts "${NAME}")
                    set(TARGET_ERROR "")
                endif()

                if(NOT "${NAME}" MATCHES "^[A-Za-z0-9_.-]+$" OR
                   "${NAME}" STREQUAL "${IT_LOCAL_HOST}")
                    message(WARNING "${HOSTS_FILE}: host name '${NAME}' is not valid (letters, digits, '_', '-', '.'; "
                                    "\"${IT_LOCAL_HOST}\" is reserved) - ignored.")
                    continue()
                endif()

                if(TARGET_ERROR OR
                   NOT "${TARGET}" MATCHES "^[^@ ]+@[^: ]+(:[0-9]+)?$")
                    message(WARNING "${HOSTS_FILE}: host ${NAME} has no target <user>@<host>[:<SSH port>] - ignored.")
                    continue()
                endif()

                list(APPEND HOSTS "${NAME}")
                set(IT_HOST_${NAME}_TARGET "${TARGET}" PARENT_SCOPE)
                set(IT_HOST_${NAME}_TOOLS  "${TOOLS}"  PARENT_SCOPE)

            endforeach()

        endif()

    endif()

    set(${HOSTS_VAR} "${HOSTS}" PARENT_SCOPE)

endfunction(IntegrationTesting_ReadItHosts)

#------------------------------------------------------------------------------#
# Returns the SSH target of a host: a name of ItHosts.json or a target
# <user>@<host>[:<SSH port>] itself.
#
# TARGET_VAR  [out]: <user>@<host>[:<SSH port>]
# HOST        [in]:  Host name or target
# PROJECT_DIR [in]:  Project root folder (ItHosts.json)
#------------------------------------------------------------------------------#
function(IntegrationTesting_Get_HostTarget TARGET_VAR HOST PROJECT_DIR)

    if("${HOST}" MATCHES "@")
        set(TARGET "${HOST}")
    else()
        IntegrationTesting_ReadItHosts(HOSTS "${PROJECT_DIR}")
        if(NOT "${HOST}" IN_LIST HOSTS)
            message(FATAL_ERROR "IT host '${HOST}' is not defined in ${PROJECT_DIR}/ItHosts.json.")
        endif()
        set(TARGET "${IT_HOST_${HOST}_TARGET}")
    endif()

    set(${TARGET_VAR} "${TARGET}" PARENT_SCOPE)

endfunction(IntegrationTesting_Get_HostTarget)

#------------------------------------------------------------------------------#
# Splits an SSH target <user>@<host>[:<SSH port>].
#
# DESTINATION_VAR [out]: <user>@<host>
# PORT_VAR        [out]: SSH port ("" = default)
# TARGET          [in]:  SSH target
#------------------------------------------------------------------------------#
function(itRemote_SplitTarget DESTINATION_VAR PORT_VAR TARGET)

    if("${TARGET}" MATCHES "^(.+):([0-9]+)$")
        set(${DESTINATION_VAR} "${CMAKE_MATCH_1}" PARENT_SCOPE)
        set(${PORT_VAR}        "${CMAKE_MATCH_2}" PARENT_SCOPE)
    else()
        set(${DESTINATION_VAR} "${TARGET}" PARENT_SCOPE)
        set(${PORT_VAR}        ""          PARENT_SCOPE)
    endif()

endfunction(itRemote_SplitTarget)

#------------------------------------------------------------------------------#
# Returns the ssh command of a target (list, the remote command follows it).
#
# COMMAND_VAR [out]: ssh command
# TARGET      [in]:  <user>@<host>[:<SSH port>]
# TTY         [in]:  TRUE - pseudo terminal (-tt): the remote command gets SIGHUP and
#                    ends when the connection breaks (a debug server, a test run)
# ARGN        [in]:  Other ssh options (eg. -L <local port>:127.0.0.1:<port>)
#------------------------------------------------------------------------------#
function(IntegrationTesting_Get_SshCommand COMMAND_VAR TARGET TTY)

    itRemote_SplitTarget(DESTINATION PORT "${TARGET}")

    set(COMMAND ssh ${IT_REMOTE_SSH_OPTIONS} ${ARGN})

    if(TTY)
        list(APPEND COMMAND -tt)
    endif()

    if(NOT "${PORT}" STREQUAL "")
        list(APPEND COMMAND -p ${PORT})
    endif()

    list(APPEND COMMAND "${DESTINATION}")

    set(${COMMAND_VAR} "${COMMAND}" PARENT_SCOPE)

endfunction(IntegrationTesting_Get_SshCommand)

#------------------------------------------------------------------------------#
# Quotes arguments for the shell of the agent (POSIX sh): every argument in
# single quotes, a single quote of an argument as '\''.
#
# TEXT_VAR [out]: Remote command line
# ARGN     [in]:  Arguments
#------------------------------------------------------------------------------#
function(IntegrationTesting_QuoteRemote TEXT_VAR)

    set(TEXT "")

    foreach(ARG IN LISTS ARGN)
        string(REPLACE "'" "'\\''" ARG "${ARG}")
        string(APPEND TEXT " '${ARG}'")
    endforeach()

    string(STRIP "${TEXT}" TEXT)

    set(${TEXT_VAR} "${TEXT}" PARENT_SCOPE)

endfunction(IntegrationTesting_QuoteRemote)

#------------------------------------------------------------------------------#
# Returns the remote command line of embi-agent (IT agent interface): the
# locator finds embi-agent (TOOLS, otherwise $HOME/_tools/embi/embi-agent or
# /home/*/_tools/embi/embi-agent) and runs it with the arguments; without it the
# command ends with exit code IT_AGENT_NOT_INSTALLED.
#
# LINE_VAR [out]: Remote command line (the remote command of ssh)
# TOOLS    [in]:  embi-agent of the agent ("" = the default)
# ARGN     [in]:  Command and options of embi-agent
#------------------------------------------------------------------------------#
function(IntegrationTesting_Get_AgentLine LINE_VAR TOOLS)

    set(LOCATOR "f=\"$1\"; shift; ")
    string(APPEND LOCATOR "if [ -z \"$f\" ]; then for c in \"$HOME/${IT_AGENT_TOOLS_PATH}\" ")
    string(APPEND LOCATOR "/home/*/${IT_AGENT_TOOLS_PATH}; do if [ -x \"$c\" ]; then f=\"$c\"; break; fi; done; fi; ")
    string(APPEND LOCATOR "if [ -z \"$f\" ] || [ ! -x \"$f\" ]; then ")
    string(APPEND LOCATOR "echo 'embi-agent is not installed on this IT agent' >&2; ")
    string(APPEND LOCATOR "exit ${IT_AGENT_NOT_INSTALLED}; fi; ")
    string(APPEND LOCATOR "exec \"$f\" \"$@\"")

    # The locator has semicolons - it is quoted here, not passed as a list element
    string(REPLACE "'" "'\\''" LOCATOR "${LOCATOR}")
    IntegrationTesting_QuoteRemote(AGENT_ARGS embi-agent "${TOOLS}" ${ARGN})

    set(${LINE_VAR} "sh -c '${LOCATOR}' ${AGENT_ARGS}" PARENT_SCOPE)

endfunction(IntegrationTesting_Get_AgentLine)

#------------------------------------------------------------------------------#
# Runs a command of embi-agent on an IT agent and returns its result (the JSON of
# the line EMBI-AGENT <JSON>, interface version checked).
#
# RESULT_VAR [out]: Result (JSON object), "" when the command failed
# ERROR_VAR  [out]: Why it failed ("" = done)
# TARGET     [in]:  <user>@<host>[:<SSH port>]
# TOOLS      [in]:  embi-agent of the agent ("" = the default)
# OPTIONS    [in]:  TTY - pseudo terminal (the command ends when the connection breaks),
#                   PRINT - the log of the agent is printed (otherwise only on a failure);
#                   "" for none
# ARGN       [in]:  Command and options of embi-agent
#------------------------------------------------------------------------------#
function(IntegrationTesting_AgentCall RESULT_VAR ERROR_VAR TARGET TOOLS OPTIONS)

    set(TTY FALSE)
    if("TTY" IN_LIST OPTIONS)
        set(TTY TRUE)
    endif()

    IntegrationTesting_Get_SshCommand(SSH_COMMAND "${TARGET}" ${TTY})
    IntegrationTesting_Get_AgentLine(AGENT_LINE "${TOOLS}" ${ARGN})

    execute_process(COMMAND ${SSH_COMMAND} "${AGENT_LINE}"
                    RESULT_VARIABLE SSH_RESULT
                    OUTPUT_VARIABLE SSH_OUTPUT
                    ERROR_VARIABLE  SSH_OUTPUT)

    string(REPLACE "\r" "" SSH_OUTPUT "${SSH_OUTPUT}")

    # The result line (the last one) and the log (the other lines)
    set(RESULT "")
    set(LOG "")
    string(REGEX MATCHALL "[^\n]+" OUTPUT_LINES "${SSH_OUTPUT}")

    foreach(OUTPUT_LINE IN LISTS OUTPUT_LINES)
        string(FIND "${OUTPUT_LINE}" "${IT_AGENT_RESULT_PREFIX}" PREFIX_POSITION)
        if(PREFIX_POSITION EQUAL 0)
            string(LENGTH "${IT_AGENT_RESULT_PREFIX}" PREFIX_LENGTH)
            string(SUBSTRING "${OUTPUT_LINE}" ${PREFIX_LENGTH} -1 RESULT)
        else()
            string(APPEND LOG "${OUTPUT_LINE}\n")
        endif()
    endforeach()

    set(ERROR "")

    if(SSH_RESULT EQUAL IT_AGENT_NOT_INSTALLED)
        set(ERROR "embi-agent is not installed on ${TARGET} - the pipeline ItAgentUpdate of EmBi_Tester installs it "
                  "(or tools of the host in ItHosts.json)")
    elseif(SSH_RESULT EQUAL IT_REMOTE_SSH_FAILED AND
           "${RESULT}" STREQUAL "")
        string(STRIP "${LOG}" LOG_TEXT)
        set(ERROR "${TARGET} is not reachable (${LOG_TEXT}) - is the SSH key of this machine authorized there?")
    elseif("${RESULT}" STREQUAL "")
        set(ERROR "embi-agent of ${TARGET} gave no result (exit code ${SSH_RESULT})")
    else()
        string(JSON INTERFACE ERROR_VARIABLE INTERFACE_ERROR GET "${RESULT}" interface)
        string(JSON AGENT_ERROR ERROR_VARIABLE AGENT_ERROR_ERROR GET "${RESULT}" error)
        if(INTERFACE_ERROR)
            set(ERROR "the result of embi-agent of ${TARGET} is not valid (${RESULT})")
        elseif(NOT "${INTERFACE}" STREQUAL "${IT_AGENT_INTERFACE_VERSION}")
            set(ERROR "embi-agent of ${TARGET} has the interface ${INTERFACE}, this platform needs "
                      "${IT_AGENT_INTERFACE_VERSION} - update the agent tools (pipeline ItAgentUpdate) or the platform")
        elseif(NOT AGENT_ERROR_ERROR)
            set(ERROR "${AGENT_ERROR}")
        endif()
    endif()

    if("PRINT" IN_LIST OPTIONS OR
       NOT "${ERROR}" STREQUAL "")
        string(STRIP "${LOG}" LOG)
        if(NOT "${LOG}" STREQUAL "")
            message("${LOG}")
        endif()
    endif()

    if(NOT "${ERROR}" STREQUAL "")
        # The pieces of a text of more lines of set()
        string(REPLACE ";" "" ERROR "${ERROR}")
        set(RESULT "")
    endif()

    set(${RESULT_VAR} "${RESULT}" PARENT_SCOPE)
    set(${ERROR_VAR}  "${ERROR}"  PARENT_SCOPE)

endfunction(IntegrationTesting_AgentCall)

#------------------------------------------------------------------------------#
# Copies the content of a folder of this machine into a folder of the agent
# (eg. a test package into the folder of new-package).
#
# RESULT_VAR [out]: Exit code of scp (0 = copied)
# TARGET     [in]:  <user>@<host>[:<SSH port>]
# LOCAL_DIR  [in]:  Folder of this machine
# REMOTE_DIR [in]:  Existing folder of the agent
#------------------------------------------------------------------------------#
function(IntegrationTesting_RemotePut RESULT_VAR TARGET LOCAL_DIR REMOTE_DIR)

    itRemote_SplitTarget(DESTINATION PORT "${TARGET}")

    set(SCP_COMMAND scp -q -r ${IT_REMOTE_SSH_OPTIONS})
    if(NOT "${PORT}" STREQUAL "")
        list(APPEND SCP_COMMAND -P ${PORT})
    endif()

    file(GLOB ENTRIES LIST_DIRECTORIES true "${LOCAL_DIR}/*")

    execute_process(COMMAND ${SCP_COMMAND} ${ENTRIES} "${DESTINATION}:${REMOTE_DIR}/"
                    RESULT_VARIABLE SCP_RESULT
                    OUTPUT_QUIET
                    ERROR_VARIABLE  SCP_ERROR)

    if(NOT SCP_RESULT EQUAL 0)
        string(STRIP "${SCP_ERROR}" SCP_ERROR)
        message(WARNING "${LOCAL_DIR} could not be copied to ${TARGET}:${REMOTE_DIR} (${SCP_ERROR}).")
    endif()

    set(${RESULT_VAR} "${SCP_RESULT}" PARENT_SCOPE)

endfunction(IntegrationTesting_RemotePut)

#------------------------------------------------------------------------------#
# Copies a file of the agent to this machine.
#
# RESULT_VAR  [out]: Exit code of scp (0 = copied)
# TARGET      [in]:  <user>@<host>[:<SSH port>]
# REMOTE_FILE [in]:  File of the agent
# LOCAL_FILE  [in]:  File of this machine
#------------------------------------------------------------------------------#
function(IntegrationTesting_RemoteFetch RESULT_VAR TARGET REMOTE_FILE LOCAL_FILE)

    itRemote_SplitTarget(DESTINATION PORT "${TARGET}")

    set(SCP_COMMAND scp -q ${IT_REMOTE_SSH_OPTIONS})
    if(NOT "${PORT}" STREQUAL "")
        list(APPEND SCP_COMMAND -P ${PORT})
    endif()

    get_filename_component(LOCAL_DIR "${LOCAL_FILE}" DIRECTORY)
    file(MAKE_DIRECTORY "${LOCAL_DIR}")

    execute_process(COMMAND ${SCP_COMMAND} "${DESTINATION}:${REMOTE_FILE}" "${LOCAL_FILE}"
                    RESULT_VARIABLE SCP_RESULT
                    OUTPUT_QUIET
                    ERROR_QUIET)

    set(${RESULT_VAR} "${SCP_RESULT}" PARENT_SCOPE)

endfunction(IntegrationTesting_RemoteFetch)

#------------------------------------------------------------------------------#
# Returns the version of probe-rs ("probe-rs --version": "probe-rs 0.32.0 ...").
#
# VERSION_VAR [out]: Version x.y.z ("" if not known)
# PROBE_RS    [in]:  probe-rs executable
#------------------------------------------------------------------------------#
function(IntegrationTesting_Get_ProbeRsVersion VERSION_VAR PROBE_RS)

    execute_process(COMMAND "${PROBE_RS}" --version
                    OUTPUT_VARIABLE VERSION_OUTPUT
                    ERROR_QUIET)

    set(VERSION "")
    if("${VERSION_OUTPUT}" MATCHES "probe-rs ([0-9]+\\.[0-9]+\\.[0-9]+)")
        set(VERSION "${CMAKE_MATCH_1}")
    endif()

    set(${VERSION_VAR} "${VERSION}" PARENT_SCOPE)

endfunction(IntegrationTesting_Get_ProbeRsVersion)
