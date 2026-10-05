################################################################################
#
# Project CMake presets generation CMake script.
#
# Project root CMakePresets.json (created from Template_CMakePresets.json.in)
# includes two preset files and combines them:
#
#   EmBi_Platform/CMake/Presets/PlatformPresets.json
#       Build options of the platform - "base" and the build types (Debug,
#       Release, UnitTest, IntegrationTest). No MCU information.
#   Bsp/Ral/RalPresets.json
#       Every MCU of the configured BSP family (Ral maintained by the
#       platform, ral-link.sh). Only target selection
#       (TARGET_MCU), no build options.
#
# CMake presets cannot create combinations by themselves, so this script
# writes one visible preset for every "<MCU>_<build type>" pair into the
# project root CMakePresets.json (presets of every MCU separated by an empty
# line):
#
#   STM32H533xE_Debug : inherits [ "project", "STM32H533xE", "Debug", "base" ]
#
# Build types ({ "buildType": true }) and MCUs ({ "target": "mcu" }) are
# recognized by the "embedbits.com/EmBi" vendor data of the presets.
# Generated presets are marked with { "generated": true } in the same vendor
# data and replaced on every run - all other content of the root file (the
# "project" preset, presets added by the user, ...) is kept.
#
# Executed by BSP configuration / update (Bsp_ModuleHandler.cmake), can also
# run standalone:
#   cmake -P Prj_PresetsHandler.cmake
#
################################################################################

# Set path to system configuration file
get_filename_component(SYSTEM_CONFIG_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/../../SysConfig.cmake" REALPATH)

# Include file with system configuration values
include("${SYSTEM_CONFIG_FILE_PATH}")

#==============================================================================#
# Global variables
#==============================================================================#

# Read project root folder path
SysConfig_Get_ProjectRootPath(PROJECT_ROOT_PATH)

# Vendor key of EmBi specific preset data
set(PRJ_PRESETS_VENDOR_KEY              "embedbits.com/EmBi")

# Project root presets file and its template
set(PRJ_PRESETS_FILE                    "${PROJECT_ROOT_PATH}/CMakePresets.json")
set(PRJ_PRESETS_TEMPLATE_FILE           "${CMAKE_CURRENT_LIST_DIR}/Template_CMakePresets.json.in")

# Included preset files (paths relative to project root, as used by "include")
get_filename_component(PRJ_PLATFORM_PRESETS_PATH "${CMAKE_CURRENT_LIST_DIR}/../../Presets/PlatformPresets.json" REALPATH)
file(RELATIVE_PATH PRJ_PLATFORM_PRESETS_REL_PATH "${PROJECT_ROOT_PATH}" "${PRJ_PLATFORM_PRESETS_PATH}")
set(PRJ_RAL_PRESETS_REL_PATH            "Bsp/Ral/RalPresets.json")

# Hidden preset of the project root file inherited by every generated preset
set(PRJ_PROJECT_PRESET_NAME             "project")

# Hidden preset of the platform with common build options
set(PRJ_BASE_PRESET_NAME                "base")

# Indentation unit of the written file
set(PRJ_PRESETS_INDENT                  "    ")

# Marker of the last entry of a group (empty line is written after it)
set(PRJ_PRESETS_GROUP_END               "<GROUP_END>")


# ------------------------------------------------------------------------------
# Function: Prj_PresetsHandler_JsonEscape
# Description: Escapes string to be used as JSON string value (without quotes).
#
# IN_STRING  [in]:  Raw string.
# OUT_STRING [out]: Escaped string.
# ------------------------------------------------------------------------------
function(Prj_PresetsHandler_JsonEscape IN_STRING OUT_STRING)

    string(REPLACE "\\" "\\\\" ESCAPED "${IN_STRING}")
    string(REPLACE "\"" "\\\"" ESCAPED "${ESCAPED}")
    string(REPLACE "\n" "\\n"  ESCAPED "${ESCAPED}")
    string(REPLACE "\t" "\\t"  ESCAPED "${ESCAPED}")

    set(${OUT_STRING} "${ESCAPED}" PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_PresetsHandler_JsonFormat
# Description:
#   Formats JSON value with 4 spaces indentation - objects one member per
#   line, arrays of scalars on a single line. Used to rewrite preset entries
#   kept from the existing root file in the same style as the generated ones.
#
# IN_JSON   [in]:  JSON value.
# IN_INDENT [in]:  Indentation of the value's own line.
# OUT_TEXT  [out]: Formatted JSON text.
# ------------------------------------------------------------------------------
function(Prj_PresetsHandler_JsonFormat IN_JSON IN_INDENT OUT_TEXT)

    string(JSON VALUE_TYPE TYPE "${IN_JSON}")

    if(VALUE_TYPE STREQUAL "OBJECT")

        string(JSON MEMBER_COUNT LENGTH "${IN_JSON}")

        if(MEMBER_COUNT EQUAL 0)
            set(${OUT_TEXT} "{}" PARENT_SCOPE)
            return()
        endif()

        set(TEXT "{\n")
        math(EXPR LAST_INDEX "${MEMBER_COUNT} - 1")

        # CMake JSON parser sorts members alphabetically - "name" (presets)
        # and "version" (file) are moved to the first place for readability
        set(MEMBER_NAMES "")
        foreach(INDEX RANGE ${LAST_INDEX})
            string(JSON MEMBER_NAME MEMBER "${IN_JSON}" ${INDEX})
            list(APPEND MEMBER_NAMES "${MEMBER_NAME}")
        endforeach()
        foreach(FIRST_MEMBER IN ITEMS "version" "name")
            if(FIRST_MEMBER IN_LIST MEMBER_NAMES)
                list(REMOVE_ITEM MEMBER_NAMES "${FIRST_MEMBER}")
                list(PREPEND MEMBER_NAMES "${FIRST_MEMBER}")
            endif()
        endforeach()

        foreach(INDEX RANGE ${LAST_INDEX})

            list(GET MEMBER_NAMES ${INDEX} MEMBER_NAME)
            string(JSON MEMBER_VALUE GET "${IN_JSON}" "${MEMBER_NAME}")
            string(JSON MEMBER_TYPE TYPE "${IN_JSON}" "${MEMBER_NAME}")

            if(MEMBER_TYPE STREQUAL "STRING")
                Prj_PresetsHandler_JsonEscape("${MEMBER_VALUE}" MEMBER_VALUE)
                set(MEMBER_VALUE "\"${MEMBER_VALUE}\"")
            elseif(MEMBER_TYPE STREQUAL "OBJECT" OR MEMBER_TYPE STREQUAL "ARRAY")
                Prj_PresetsHandler_JsonFormat("${MEMBER_VALUE}" "${IN_INDENT}${PRJ_PRESETS_INDENT}" MEMBER_VALUE)
            elseif(MEMBER_TYPE STREQUAL "NULL")
                set(MEMBER_VALUE "null")
            elseif(MEMBER_TYPE STREQUAL "BOOLEAN")
                if(MEMBER_VALUE)
                    set(MEMBER_VALUE "true")
                else()
                    set(MEMBER_VALUE "false")
                endif()
            endif()

            Prj_PresetsHandler_JsonEscape("${MEMBER_NAME}" MEMBER_NAME)
            string(APPEND TEXT "${IN_INDENT}${PRJ_PRESETS_INDENT}\"${MEMBER_NAME}\": ${MEMBER_VALUE}")

            if(INDEX LESS LAST_INDEX)
                string(APPEND TEXT ",")
            endif()
            string(APPEND TEXT "\n")

        endforeach()

        string(APPEND TEXT "${IN_INDENT}}")

    elseif(VALUE_TYPE STREQUAL "ARRAY")

        string(JSON ITEM_COUNT LENGTH "${IN_JSON}")

        if(ITEM_COUNT EQUAL 0)
            set(${OUT_TEXT} "[]" PARENT_SCOPE)
            return()
        endif()

        math(EXPR LAST_INDEX "${ITEM_COUNT} - 1")

        # Array of scalars is written on a single line
        set(SCALAR_ONLY TRUE)
        foreach(INDEX RANGE ${LAST_INDEX})
            string(JSON ITEM_TYPE TYPE "${IN_JSON}" ${INDEX})
            if(ITEM_TYPE STREQUAL "OBJECT" OR ITEM_TYPE STREQUAL "ARRAY")
                set(SCALAR_ONLY FALSE)
            endif()
        endforeach()

        if(SCALAR_ONLY)
            set(TEXT "[ ")
        else()
            set(TEXT "[\n")
        endif()

        foreach(INDEX RANGE ${LAST_INDEX})

            string(JSON ITEM_VALUE GET "${IN_JSON}" ${INDEX})
            string(JSON ITEM_TYPE TYPE "${IN_JSON}" ${INDEX})

            if(ITEM_TYPE STREQUAL "STRING")
                Prj_PresetsHandler_JsonEscape("${ITEM_VALUE}" ITEM_VALUE)
                set(ITEM_VALUE "\"${ITEM_VALUE}\"")
            elseif(ITEM_TYPE STREQUAL "OBJECT" OR ITEM_TYPE STREQUAL "ARRAY")
                Prj_PresetsHandler_JsonFormat("${ITEM_VALUE}" "${IN_INDENT}${PRJ_PRESETS_INDENT}" ITEM_VALUE)
            elseif(ITEM_TYPE STREQUAL "NULL")
                set(ITEM_VALUE "null")
            elseif(ITEM_TYPE STREQUAL "BOOLEAN")
                if(ITEM_VALUE)
                    set(ITEM_VALUE "true")
                else()
                    set(ITEM_VALUE "false")
                endif()
            endif()

            if(SCALAR_ONLY)
                string(APPEND TEXT "${ITEM_VALUE}")
                if(INDEX LESS LAST_INDEX)
                    string(APPEND TEXT ", ")
                endif()
            else()
                string(APPEND TEXT "${IN_INDENT}${PRJ_PRESETS_INDENT}${ITEM_VALUE}")
                if(INDEX LESS LAST_INDEX)
                    string(APPEND TEXT ",")
                endif()
                string(APPEND TEXT "\n")
            endif()

        endforeach()

        if(SCALAR_ONLY)
            string(APPEND TEXT " ]")
        else()
            string(APPEND TEXT "${IN_INDENT}]")
        endif()

    else()
        set(TEXT "${IN_JSON}")
    endif()

    set(${OUT_TEXT} "${TEXT}" PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_PresetsHandler_ReadPresets
# Description:
#   Reads presets of the given kind which carry EmBi vendor data.
#
# IN_JSON        [in]:  Content of presets file.
# IN_VENDOR_ITEM [in]:  Vendor data member identifying the presets
#                       ("buildType" for build types, "target" for targets).
# OUT_NAMES      [out]: Names of found presets.
# ------------------------------------------------------------------------------
function(Prj_PresetsHandler_ReadPresets IN_JSON IN_VENDOR_ITEM OUT_NAMES)

    set(NAMES "")

    string(JSON PRESET_COUNT ERROR_VARIABLE JSON_ERROR LENGTH "${IN_JSON}" configurePresets)

    if(NOT JSON_ERROR AND PRESET_COUNT GREATER 0)

        math(EXPR LAST_INDEX "${PRESET_COUNT} - 1")

        foreach(INDEX RANGE ${LAST_INDEX})

            string(JSON VENDOR_ITEM ERROR_VARIABLE JSON_ERROR
                   GET "${IN_JSON}" configurePresets ${INDEX} vendor "${PRJ_PRESETS_VENDOR_KEY}" ${IN_VENDOR_ITEM})

            if(NOT JSON_ERROR)
                string(JSON PRESET_NAME GET "${IN_JSON}" configurePresets ${INDEX} name)
                list(APPEND NAMES "${PRESET_NAME}")
            endif()

        endforeach()

    endif()

    set(${OUT_NAMES} "${NAMES}" PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_PresetsHandler_FindPreset
# Description: Returns index of configure preset with given name.
#
# IN_JSON     [in]:  Content of presets file.
# IN_NAME     [in]:  Preset name.
# OUT_INDEX   [out]: Index of preset in "configurePresets", -1 if not found.
# ------------------------------------------------------------------------------
function(Prj_PresetsHandler_FindPreset IN_JSON IN_NAME OUT_INDEX)

    set(FOUND_INDEX -1)

    string(JSON PRESET_COUNT ERROR_VARIABLE JSON_ERROR LENGTH "${IN_JSON}" configurePresets)

    if(NOT JSON_ERROR AND PRESET_COUNT GREATER 0)
        math(EXPR LAST_INDEX "${PRESET_COUNT} - 1")

        foreach(INDEX RANGE ${LAST_INDEX})
            string(JSON PRESET_NAME GET "${IN_JSON}" configurePresets ${INDEX} name)
            if(PRESET_NAME STREQUAL IN_NAME)
                set(FOUND_INDEX ${INDEX})
                break()
            endif()
        endforeach()
    endif()

    set(${OUT_INDEX} ${FOUND_INDEX} PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_PresetsHandler_KeptEntries
# Description:
#   Returns entries of the root file preset array which were NOT generated
#   by this script, formatted for writing.
#
# IN_JSON      [in]:  Content of the root presets file.
# IN_ARRAY     [in]:  Preset array name (configurePresets, buildPresets, ...).
# OUT_ENTRIES  [out]: List of formatted entries.
# ------------------------------------------------------------------------------
function(Prj_PresetsHandler_KeptEntries IN_JSON IN_ARRAY OUT_ENTRIES)

    set(ENTRIES "")

    string(JSON ITEM_COUNT ERROR_VARIABLE JSON_ERROR LENGTH "${IN_JSON}" ${IN_ARRAY})

    if(NOT JSON_ERROR AND ITEM_COUNT GREATER 0)

        math(EXPR LAST_INDEX "${ITEM_COUNT} - 1")

        foreach(INDEX RANGE ${LAST_INDEX})

            string(JSON GENERATED ERROR_VARIABLE JSON_ERROR
                   GET "${IN_JSON}" ${IN_ARRAY} ${INDEX} vendor "${PRJ_PRESETS_VENDOR_KEY}" generated)

            if(JSON_ERROR OR NOT GENERATED)
                string(JSON ITEM GET "${IN_JSON}" ${IN_ARRAY} ${INDEX})
                Prj_PresetsHandler_JsonFormat("${ITEM}" "${PRJ_PRESETS_INDENT}${PRJ_PRESETS_INDENT}" ITEM)
                # List separator inside entry text has to be protected
                string(REPLACE ";" "\\;" ITEM "${ITEM}")
                list(APPEND ENTRIES "${ITEM}")
            endif()

        endforeach()

    endif()

    set(${OUT_ENTRIES} "${ENTRIES}" PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_PresetsHandler_MarkGroupEnd
# Description:
#   Marks the last entry of the list as end of a group - an empty line is
#   written after it (Prj_PresetsHandler_WriteArray).
#
# IN_OUT_ENTRIES [in/out]: Name of list variable with formatted entries.
# ------------------------------------------------------------------------------
function(Prj_PresetsHandler_MarkGroupEnd IN_OUT_ENTRIES)

    set(ENTRIES "${${IN_OUT_ENTRIES}}")

    if(ENTRIES)
        list(POP_BACK ENTRIES LAST_ENTRY)
        if(NOT LAST_ENTRY MATCHES "${PRJ_PRESETS_GROUP_END}$")
            string(APPEND LAST_ENTRY "${PRJ_PRESETS_GROUP_END}")
        endif()
        list(APPEND ENTRIES "${LAST_ENTRY}")
    endif()

    set(${IN_OUT_ENTRIES} "${ENTRIES}" PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_PresetsHandler_WriteArray
# Description: Appends JSON array member with given entries to the text.
#
# IN_OUT_TEXT [in/out]: Text of written file.
# IN_NAME     [in]:     Array member name.
# IN_ENTRIES  [in]:     Formatted entries (list).
# IN_IS_LAST  [in]:     TRUE if it is the last member of the file object.
# ------------------------------------------------------------------------------
function(Prj_PresetsHandler_WriteArray IN_OUT_TEXT IN_NAME IN_ENTRIES IN_IS_LAST)

    set(TEXT "${${IN_OUT_TEXT}}")
    list(LENGTH IN_ENTRIES ENTRY_COUNT)

    if(ENTRY_COUNT EQUAL 0)
        string(APPEND TEXT "${PRJ_PRESETS_INDENT}\"${IN_NAME}\": []")
    else()
        string(APPEND TEXT "${PRJ_PRESETS_INDENT}\"${IN_NAME}\": [\n")
        set(ENTRY_INDEX 0)
        foreach(ENTRY IN LISTS IN_ENTRIES)
            math(EXPR ENTRY_INDEX "${ENTRY_INDEX} + 1")

            set(GROUP_END FALSE)
            if(ENTRY MATCHES "${PRJ_PRESETS_GROUP_END}$")
                set(GROUP_END TRUE)
                string(REGEX REPLACE "${PRJ_PRESETS_GROUP_END}$" "" ENTRY "${ENTRY}")
            endif()

            string(APPEND TEXT "${PRJ_PRESETS_INDENT}${PRJ_PRESETS_INDENT}${ENTRY}")
            if(ENTRY_INDEX LESS ENTRY_COUNT)
                string(APPEND TEXT ",")
                if(GROUP_END)
                    string(APPEND TEXT "\n")
                endif()
            endif()
            string(APPEND TEXT "\n")
        endforeach()
        string(APPEND TEXT "${PRJ_PRESETS_INDENT}]")
    endif()

    if(NOT IN_IS_LAST)
        string(APPEND TEXT ",")
    endif()
    string(APPEND TEXT "\n")

    set(${IN_OUT_TEXT} "${TEXT}" PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: Prj_PresetsHandler_Generate
# Description:
#   Writes "<MCU>_<build type>" configure, build and test presets of every
#   Ral MCU into the project root CMakePresets.json (see file header).
#   The root file is created from the template if it does not exist yet.
# ------------------------------------------------------------------------------
function(Prj_PresetsHandler_Generate)

    if(NOT EXISTS "${PRJ_PRESETS_FILE}")
        configure_file("${PRJ_PRESETS_TEMPLATE_FILE}" "${PRJ_PRESETS_FILE}" COPYONLY)
    endif()

    file(READ "${PRJ_PRESETS_FILE}" ROOT_JSON)
    file(READ "${PRJ_PLATFORM_PRESETS_PATH}" PLATFORM_JSON)

    set(RAL_PRESETS_PATH "${PROJECT_ROOT_PATH}/${PRJ_RAL_PRESETS_REL_PATH}")

    if(EXISTS "${RAL_PRESETS_PATH}")
        file(READ "${RAL_PRESETS_PATH}" RAL_JSON)
    else()
        message(WARNING "${PRJ_RAL_PRESETS_REL_PATH} not found - configure BSP module first. Generated presets are removed.")
        set(RAL_JSON "{}")
    endif()

    # ----------------------------------------------------------
    # Build types (platform) and MCUs (Ral)
    # ----------------------------------------------------------
    Prj_PresetsHandler_ReadPresets("${PLATFORM_JSON}" buildType BUILD_TYPES)
    Prj_PresetsHandler_ReadPresets("${RAL_JSON}" target TARGETS)

    # ----------------------------------------------------------
    # Generated presets
    # ----------------------------------------------------------
    set(GENERATED_MARK "\"vendor\": { \"${PRJ_PRESETS_VENDOR_KEY}\": { \"generated\": true } }")
    set(GEN_CONFIGURE_ENTRIES "")
    set(GEN_BUILD_ENTRIES "")
    set(GEN_TEST_ENTRIES "")

    foreach(TARGET_NAME IN LISTS TARGETS)

        Prj_PresetsHandler_FindPreset("${RAL_JSON}" "${TARGET_NAME}" TARGET_INDEX)
        string(JSON TARGET_DISPLAY ERROR_VARIABLE JSON_ERROR GET "${RAL_JSON}" configurePresets ${TARGET_INDEX} displayName)
        if(JSON_ERROR)
            set(TARGET_DISPLAY "${TARGET_NAME}")
        endif()

        foreach(BUILD_TYPE IN LISTS BUILD_TYPES)

            Prj_PresetsHandler_FindPreset("${PLATFORM_JSON}" "${BUILD_TYPE}" TYPE_INDEX)

            string(JSON TYPE_DISPLAY ERROR_VARIABLE JSON_ERROR GET "${PLATFORM_JSON}" configurePresets ${TYPE_INDEX} displayName)
            if(JSON_ERROR)
                set(TYPE_DISPLAY "${BUILD_TYPE}")
            endif()

            set(PRESET_NAME "${TARGET_NAME}_${BUILD_TYPE}")
            set(PRESET_DISPLAY "${TARGET_DISPLAY} ${TYPE_DISPLAY}")

            list(APPEND GEN_CONFIGURE_ENTRIES
                 "{ \"name\": \"${PRESET_NAME}\", \"displayName\": \"${PRESET_DISPLAY}\", \"inherits\": [ \"${PRJ_PROJECT_PRESET_NAME}\", \"${TARGET_NAME}\", \"${BUILD_TYPE}\", \"${PRJ_BASE_PRESET_NAME}\" ], ${GENERATED_MARK} }")

            list(APPEND GEN_BUILD_ENTRIES
                 "{ \"name\": \"${PRESET_NAME}\", \"displayName\": \"${PRESET_DISPLAY}\", \"configurePreset\": \"${PRESET_NAME}\", ${GENERATED_MARK} }")

            string(JSON TEST_PRESET ERROR_VARIABLE JSON_ERROR
                   GET "${PLATFORM_JSON}" configurePresets ${TYPE_INDEX} vendor "${PRJ_PRESETS_VENDOR_KEY}" testPreset)
            if(NOT JSON_ERROR)
                list(APPEND GEN_TEST_ENTRIES
                     "{ \"name\": \"${PRESET_NAME}\", \"displayName\": \"${PRESET_DISPLAY}\", \"configurePreset\": \"${PRESET_NAME}\", \"inherits\": [ \"${TEST_PRESET}\" ], ${GENERATED_MARK} }")
            endif()

        endforeach()

        # Presets of every MCU are separated by an empty line
        foreach(GEN_ENTRIES IN ITEMS GEN_CONFIGURE_ENTRIES GEN_BUILD_ENTRIES GEN_TEST_ENTRIES)
            Prj_PresetsHandler_MarkGroupEnd(${GEN_ENTRIES})
        endforeach()

    endforeach()

    # ----------------------------------------------------------
    # Root file content - everything except generated presets is kept
    # ----------------------------------------------------------
    set(TEXT "{\n")
    string(JSON MEMBER_COUNT LENGTH "${ROOT_JSON}")
    math(EXPR LAST_MEMBER_INDEX "${MEMBER_COUNT} - 1")

    set(HANDLED_MEMBERS include configurePresets buildPresets testPresets)

    # "version" is written first (CMake JSON parser sorts members)
    set(MEMBER_NAMES "")
    foreach(INDEX RANGE ${LAST_MEMBER_INDEX})
        string(JSON MEMBER_NAME MEMBER "${ROOT_JSON}" ${INDEX})
        list(APPEND MEMBER_NAMES "${MEMBER_NAME}")
    endforeach()
    if("version" IN_LIST MEMBER_NAMES)
        list(REMOVE_ITEM MEMBER_NAMES "version")
        list(PREPEND MEMBER_NAMES "version")
    endif()

    foreach(MEMBER_NAME IN LISTS MEMBER_NAMES)

        if(NOT MEMBER_NAME IN_LIST HANDLED_MEMBERS)
            string(JSON MEMBER_VALUE GET "${ROOT_JSON}" "${MEMBER_NAME}")
            string(JSON MEMBER_TYPE TYPE "${ROOT_JSON}" "${MEMBER_NAME}")
            if(MEMBER_TYPE STREQUAL "STRING")
                Prj_PresetsHandler_JsonEscape("${MEMBER_VALUE}" MEMBER_VALUE)
                set(MEMBER_VALUE "\"${MEMBER_VALUE}\"")
            else()
                Prj_PresetsHandler_JsonFormat("${MEMBER_VALUE}" "${PRJ_PRESETS_INDENT}" MEMBER_VALUE)
            endif()
            string(APPEND TEXT "${PRJ_PRESETS_INDENT}\"${MEMBER_NAME}\": ${MEMBER_VALUE},\n")
        endif()

    endforeach()

    # Included files - platform and Ral presets are always included
    set(INCLUDES "")
    string(JSON INCLUDE_COUNT ERROR_VARIABLE JSON_ERROR LENGTH "${ROOT_JSON}" include)
    if(NOT JSON_ERROR AND INCLUDE_COUNT GREATER 0)
        math(EXPR LAST_INCLUDE_INDEX "${INCLUDE_COUNT} - 1")
        foreach(INDEX RANGE ${LAST_INCLUDE_INDEX})
            string(JSON INCLUDE_PATH GET "${ROOT_JSON}" include ${INDEX})
            # Missing included file would make all presets unreadable
            if(EXISTS "${PROJECT_ROOT_PATH}/${INCLUDE_PATH}")
                list(APPEND INCLUDES "${INCLUDE_PATH}")
            else()
                message(STATUS "Included file ${INCLUDE_PATH} does not exist - removed from CMakePresets.json.")
            endif()
        endforeach()
    endif()

    list(PREPEND INCLUDES "${PRJ_PLATFORM_PRESETS_REL_PATH}")
    if(EXISTS "${RAL_PRESETS_PATH}")
        list(INSERT INCLUDES 1 "${PRJ_RAL_PRESETS_REL_PATH}")
    else()
        list(REMOVE_ITEM INCLUDES "${PRJ_RAL_PRESETS_REL_PATH}")
    endif()
    list(REMOVE_DUPLICATES INCLUDES)

    set(INCLUDE_ENTRIES "")
    foreach(INCLUDE_PATH IN LISTS INCLUDES)
        list(APPEND INCLUDE_ENTRIES "\"${INCLUDE_PATH}\"")
    endforeach()
    Prj_PresetsHandler_WriteArray(TEXT "include" "${INCLUDE_ENTRIES}" FALSE)

    # Preset arrays - kept entries first, generated ones after them. The
    # "project" preset inherited by generated presets is added if missing.
    Prj_PresetsHandler_KeptEntries("${ROOT_JSON}" configurePresets ENTRIES)
    Prj_PresetsHandler_FindPreset("${ROOT_JSON}" "${PRJ_PROJECT_PRESET_NAME}" PROJECT_INDEX)
    if(PROJECT_INDEX EQUAL -1)
        list(PREPEND ENTRIES "{ \"name\": \"${PRJ_PROJECT_PRESET_NAME}\", \"hidden\": true, \"description\": \"Project specific options inherited by every generated preset (cacheVariables, environment, ...)\" }")
    endif()
    Prj_PresetsHandler_MarkGroupEnd(ENTRIES)
    list(APPEND ENTRIES ${GEN_CONFIGURE_ENTRIES})
    Prj_PresetsHandler_WriteArray(TEXT "configurePresets" "${ENTRIES}" FALSE)

    Prj_PresetsHandler_KeptEntries("${ROOT_JSON}" buildPresets ENTRIES)
    Prj_PresetsHandler_MarkGroupEnd(ENTRIES)
    list(APPEND ENTRIES ${GEN_BUILD_ENTRIES})
    Prj_PresetsHandler_WriteArray(TEXT "buildPresets" "${ENTRIES}" FALSE)

    Prj_PresetsHandler_KeptEntries("${ROOT_JSON}" testPresets ENTRIES)
    Prj_PresetsHandler_MarkGroupEnd(ENTRIES)
    list(APPEND ENTRIES ${GEN_TEST_ENTRIES})
    Prj_PresetsHandler_WriteArray(TEXT "testPresets" "${ENTRIES}" TRUE)

    string(APPEND TEXT "}\n")

    file(WRITE "${PRJ_PRESETS_FILE}" "${TEXT}")

    list(LENGTH GEN_CONFIGURE_ENTRIES GEN_COUNT)
    message(STATUS "CMakePresets.json updated - ${GEN_COUNT} presets generated from ${PRJ_RAL_PRESETS_REL_PATH}.")

endfunction()


#==============================================================================#
# Main functionality
#
# If the script is executed in script mode ( -P ), no functions are called, thus
# direct execution has to be triggered.
#
# Example:
# cmake -P Prj_PresetsHandler.cmake
#==============================================================================#
if(CMAKE_SCRIPT_MODE_FILE AND
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)

    Prj_PresetsHandler_Generate()

endif()
