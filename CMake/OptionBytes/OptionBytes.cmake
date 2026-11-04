################################################################################
# Author: Mr.Nobody
# file:  OptionBytes.cmake
# brief: Option bytes of the MCU - variables of the project CMakeLists.txt,
#        checked by the configuration and stored in the firmware.
#
# The Ral presets (Bsp/Ral/RalPresets.json, ral-presets.sh of Bsp_Linker) hold
# the option bytes of every DEV_ID of the family (vendor data "optionBytes",
# STM32CubeProgrammer database): name, register to read and to program, bits,
# values, device variants and the write procedure of the family. The option
# byte <name> of the MCU is the variable OPTION_BYTE_<name> of the project
# CMakeLists.txt - empty: the value of the chip is kept.
#
#   OptionBytes_UpdateSection - section of the option bytes of the MCUs of the
#       project in CMakeLists.txt (BSP configuration, BSP update, VSCode project
#       initialization): new option bytes are added with an empty value, the
#       set values are kept
#   OptionBytes_Configure     - configuration of an MCU build: the set values
#       are checked (value range; an option byte of another MCU of the project
#       is reported and not written); a cmake parameter
#       -DOPTION_BYTE_<name>=<value> overrides the value of CMakeLists.txt (it
#       stays in the cache of the build folder, -UOPTION_BYTE_<name> removes
#       it); the project of a core of a multi-core MCU (TARGET_CORE) gets the
#       boot of the cores (B<core>: BCM7, BCM4) from TARGET_CORES when it is
#       empty
#   OptionBytes_AddSection    - the values are stored in the non-allocated ELF
#       section .option_bytes of the firmware (generated assembler source - the
#       loaded content and the segments are not changed); no set value - no
#       section (the firmware is unchanged). The flash of the platform writes
#       them (OptionBytes_Flash.cmake).
#
# Text of the section .option_bytes - everything the flash needs (no Ral presets
# on an IT agent), one item per line, values separated by a space:
#   EMBI_OPTION_BYTES 1
#   MCU STM32H755xI
#   DEVICE_ID 0x450
#   PROCEDURE <member> <value>...      write procedure of the family (procedure of the Ral presets)
#   CONFIG <variant>                   device variant the preset can be (in the order of the database)
#   CHECK <variant> read <address> <mask> <value> | write <address> <value>
#                                      register checks of the variant (all true - the chip is the variant)
#   OPTION <name> <value> <read register> <program register> <bit offset> <bit width> <variants | ->
#                                      set option byte (an option byte with other bits per variant has a line
#                                      per variant)
################################################################################

include_guard(GLOBAL)

#=============================== Constant values ==============================#

set(OPTION_BYTES_VENDOR_KEY             "embedbits.com/EmBi")
set(OPTION_BYTES_VARIABLE_PREFIX        "OPTION_BYTE_")
set(OPTION_BYTES_ELF_SECTION            ".option_bytes")
set(OPTION_BYTES_FORMAT                 "EMBI_OPTION_BYTES 1")

# Section of the project CMakeLists.txt - first and last line; a file without the section gets it before the line
# OPTION_BYTES_INSERT_BEFORE of the template (or before project())
set(OPTION_BYTES_BEGIN_LINE             "#================================ Option bytes ================================#")
set(OPTION_BYTES_END_LINE               "#============================== Option bytes end ==============================#")
set(OPTION_BYTES_INSERT_BEFORE          "#=========================== DO NOT CHANGE THIS PART ==========================#")

# Max length of the comment lines, length of "set(<variable>" before the value (as the template)
set(OPTION_BYTES_LINE_LENGTH            120)
set(OPTION_BYTES_VALUE_COLUMN           40)

#================================ Functions ===================================#

#------------------------------------------------------------------------------#
# Variable of an option byte - OPTION_BYTE_<name> (characters of a C
# identifier, nWRP0 -> OPTION_BYTE_nWRP0).
#
# IN_NAME  [in]:  Name of the option byte (Ral presets)
# OUT_VAR  [out]: Variable
#------------------------------------------------------------------------------#
function(OptionBytes_VariableName IN_NAME OUT_VAR)

    string(MAKE_C_IDENTIFIER "${IN_NAME}" IDENTIFIER)
    set(${OUT_VAR} "${OPTION_BYTES_VARIABLE_PREFIX}${IDENTIFIER}" PARENT_SCOPE)

endfunction(OptionBytes_VariableName)


#------------------------------------------------------------------------------#
# Reads the option bytes of an MCU preset of the Ral presets file - the option
# bytes of its DEV_ID (vendor data "optionBytes") which exist in the device
# variants the preset can be (identification "optionByteConfigs", every
# variant when not given). Sets in the parent scope:
#   <prefix>_FOUND                          - TRUE when the MCU has option bytes
#   <prefix>_DEVICE_ID, <prefix>_CONFIGS    - DEV_ID, variants of the preset
#   <prefix>_TABLE                          - JSON object of the DEV_ID (procedure, configs, items)
#   <prefix>_ITEMS                          - indexes of the option bytes of the MCU (items of the table)
#   <prefix>_<index>_NAME, _CATEGORY, _DESCRIPTION, _READ, _PROGRAM, _OFFSET, _WIDTH, _CONFIGS,
#   _MULTIPLIER, _ADDRESS_OFFSET (equation of an address), _BYBIT, _VALUES (text "0x0: ..., 0x1: ...")
#
# IN_PRESETS_FILE [in]: Ral presets file (RalPresets.json)
# IN_MCU          [in]: MCU preset (STM32H755xI)
# OUT_PREFIX      [in]: Prefix of the variables
#------------------------------------------------------------------------------#
function(OptionBytes_ReadMcu IN_PRESETS_FILE IN_MCU OUT_PREFIX)

    set(${OUT_PREFIX}_FOUND FALSE PARENT_SCOPE)
    set(${OUT_PREFIX}_ITEMS "" PARENT_SCOPE)

    if(NOT EXISTS "${IN_PRESETS_FILE}")
        return()
    endif()

    file(READ "${IN_PRESETS_FILE}" CONTENT)

    string(JSON PRESET_COUNT ERROR_VARIABLE JSON_ERROR LENGTH "${CONTENT}" configurePresets)
    if(JSON_ERROR OR PRESET_COUNT EQUAL 0)
        return()
    endif()

    math(EXPR PRESET_LAST "${PRESET_COUNT} - 1")
    set(IDENTIFICATION "")

    foreach(PRESET_IDX RANGE ${PRESET_LAST})
        string(JSON PRESET_NAME GET "${CONTENT}" configurePresets ${PRESET_IDX} name)
        if(PRESET_NAME STREQUAL IN_MCU)
            string(JSON IDENTIFICATION ERROR_VARIABLE JSON_ERROR
                   GET "${CONTENT}" configurePresets ${PRESET_IDX} vendor "${OPTION_BYTES_VENDOR_KEY}" identification)
            break()
        endif()
    endforeach()

    if("${IDENTIFICATION}" STREQUAL "" OR JSON_ERROR)
        return()
    endif()

    string(JSON DEVICE_ID ERROR_VARIABLE JSON_ERROR GET "${IDENTIFICATION}" idValue)
    if(JSON_ERROR)
        return()
    endif()

    string(JSON TABLE ERROR_VARIABLE JSON_ERROR
           GET "${CONTENT}" vendor "${OPTION_BYTES_VENDOR_KEY}" optionBytes "${DEVICE_ID}")
    if(JSON_ERROR)
        return()
    endif()

    # Device variants the preset can be (every variant when not given)
    set(CONFIGS "")
    string(JSON CONFIG_COUNT ERROR_VARIABLE JSON_ERROR LENGTH "${IDENTIFICATION}" optionByteConfigs)
    if(NOT JSON_ERROR AND CONFIG_COUNT GREATER 0)
        math(EXPR CONFIG_LAST "${CONFIG_COUNT} - 1")
        foreach(CONFIG_IDX RANGE ${CONFIG_LAST})
            string(JSON CONFIG GET "${IDENTIFICATION}" optionByteConfigs ${CONFIG_IDX})
            list(APPEND CONFIGS "${CONFIG}")
        endforeach()
    endif()

    string(JSON ITEM_COUNT ERROR_VARIABLE JSON_ERROR LENGTH "${TABLE}" items)
    if(JSON_ERROR OR ITEM_COUNT EQUAL 0)
        return()
    endif()

    math(EXPR ITEM_LAST "${ITEM_COUNT} - 1")
    set(ITEMS "")

    foreach(ITEM_IDX RANGE ${ITEM_LAST})

        string(JSON ITEM GET "${TABLE}" items ${ITEM_IDX})

        # Variants of the option byte - one of them has to be a variant of the preset
        set(ITEM_CONFIGS "")
        string(JSON ITEM_CONFIG_COUNT ERROR_VARIABLE JSON_ERROR LENGTH "${ITEM}" configs)
        if(NOT JSON_ERROR AND ITEM_CONFIG_COUNT GREATER 0)
            math(EXPR ITEM_CONFIG_LAST "${ITEM_CONFIG_COUNT} - 1")
            foreach(CONFIG_IDX RANGE ${ITEM_CONFIG_LAST})
                string(JSON CONFIG GET "${ITEM}" configs ${CONFIG_IDX})
                list(APPEND ITEM_CONFIGS "${CONFIG}")
            endforeach()
        endif()

        if(ITEM_CONFIGS AND CONFIGS)
            string(REPLACE ";" "|" CONFIG_REGEX "${CONFIGS}")
            set(COMMON_CONFIGS ${ITEM_CONFIGS})
            list(FILTER COMMON_CONFIGS INCLUDE REGEX "^(${CONFIG_REGEX})$")
            if(NOT COMMON_CONFIGS)
                continue()
            endif()
        endif()

        foreach(MEMBER IN ITEMS name:NAME category:CATEGORY description:DESCRIPTION read:READ program:PROGRAM
                                offset:OFFSET width:WIDTH byBit:BYBIT)
            string(REPLACE ":" ";" MEMBER "${MEMBER}")
            list(GET MEMBER 0 KEY)
            list(GET MEMBER 1 SUFFIX)
            string(JSON VALUE ERROR_VARIABLE JSON_ERROR GET "${ITEM}" ${KEY})
            if(JSON_ERROR)
                set(VALUE "")
            endif()
            set(${OUT_PREFIX}_${ITEM_IDX}_${SUFFIX} "${VALUE}" PARENT_SCOPE)
        endforeach()

        foreach(MEMBER IN ITEMS multiplier:MULTIPLIER offset:ADDRESS_OFFSET)
            string(REPLACE ":" ";" MEMBER "${MEMBER}")
            list(GET MEMBER 0 KEY)
            list(GET MEMBER 1 SUFFIX)
            string(JSON VALUE ERROR_VARIABLE JSON_ERROR GET "${ITEM}" equation ${KEY})
            if(JSON_ERROR)
                set(VALUE "")
            endif()
            set(${OUT_PREFIX}_${ITEM_IDX}_${SUFFIX} "${VALUE}" PARENT_SCOPE)
        endforeach()

        # Values with their meaning as one text
        set(VALUES_TEXT "")
        string(JSON VALUE_COUNT ERROR_VARIABLE JSON_ERROR LENGTH "${ITEM}" values)
        if(NOT JSON_ERROR AND VALUE_COUNT GREATER 0)
            math(EXPR VALUE_LAST "${VALUE_COUNT} - 1")
            foreach(VALUE_IDX RANGE ${VALUE_LAST})
                string(JSON VALUE GET "${ITEM}" values ${VALUE_IDX} value)
                string(JSON TEXT GET "${ITEM}" values ${VALUE_IDX} text)
                if(NOT "${VALUES_TEXT}" STREQUAL "")
                    string(APPEND VALUES_TEXT ", ")
                endif()
                string(APPEND VALUES_TEXT "${VALUE}: ${TEXT}")
            endforeach()
        endif()

        set(${OUT_PREFIX}_${ITEM_IDX}_VALUES "${VALUES_TEXT}" PARENT_SCOPE)
        set(${OUT_PREFIX}_${ITEM_IDX}_CONFIGS "${ITEM_CONFIGS}" PARENT_SCOPE)
        list(APPEND ITEMS ${ITEM_IDX})

    endforeach()

    set(${OUT_PREFIX}_FOUND TRUE PARENT_SCOPE)
    set(${OUT_PREFIX}_DEVICE_ID "${DEVICE_ID}" PARENT_SCOPE)
    set(${OUT_PREFIX}_CONFIGS "${CONFIGS}" PARENT_SCOPE)
    set(${OUT_PREFIX}_TABLE "${TABLE}" PARENT_SCOPE)
    set(${OUT_PREFIX}_ITEMS "${ITEMS}" PARENT_SCOPE)

endfunction(OptionBytes_ReadMcu)


#------------------------------------------------------------------------------#
# Comment lines of a text - words of the text in lines of at most
# OPTION_BYTES_LINE_LENGTH characters.
#
# IN_TEXT   [in]:  Text
# IN_FIRST  [in]:  Start of the first line ("# ")
# IN_NEXT   [in]:  Start of the next lines ("#   ")
# OUT_LINES [out]: Lines (list)
#------------------------------------------------------------------------------#
function(OptionBytes_CommentLines IN_TEXT IN_FIRST IN_NEXT OUT_LINES)

    string(REGEX REPLACE "[ \t\r\n]+" " " TEXT "${IN_TEXT}")
    string(STRIP "${TEXT}" TEXT)
    # ";" of the text is not a separator of the list of the words
    string(REPLACE ";" "," TEXT "${TEXT}")
    string(REPLACE " " ";" WORDS "${TEXT}")

    set(LINES "")
    set(LINE "${IN_FIRST}")
    set(LINE_START "${IN_FIRST}")

    foreach(WORD IN LISTS WORDS)
        string(LENGTH "${LINE}${WORD}" NEW_LENGTH)
        if(NEW_LENGTH GREATER OPTION_BYTES_LINE_LENGTH AND NOT "${LINE}" STREQUAL "${LINE_START}")
            string(STRIP "${LINE}" LINE)
            list(APPEND LINES "${LINE}")
            set(LINE "${IN_NEXT}")
            set(LINE_START "${IN_NEXT}")
        endif()
        string(APPEND LINE "${WORD} ")
    endforeach()

    string(STRIP "${LINE}" LINE)
    list(APPEND LINES "${LINE}")

    set(${OUT_LINES} "${LINES}" PARENT_SCOPE)

endfunction(OptionBytes_CommentLines)


#------------------------------------------------------------------------------#
# Writes the section of the option bytes of the MCUs of the project into the
# project CMakeLists.txt (OPTION_BYTES_BEGIN_LINE .. OPTION_BYTES_END_LINE) -
# one variable per option byte (comment: name, category, description, values,
# address equation, MCUs which have it when not all), in the order of the Ral
# presets. The set values of the existing section are kept, a set option byte
# the MCUs do not have stays with a note. A file without the section gets it
# before OPTION_BYTES_INSERT_BEFORE (or project()); the file is written only
# when it changes. MCUs without option bytes in the Ral presets - no change.
#
# IN_CMAKELISTS   [in]: Project CMakeLists.txt
# IN_PRESETS_FILE [in]: Ral presets file (RalPresets.json)
# IN_MCUS         [in]: MCU presets of the project
#------------------------------------------------------------------------------#
function(OptionBytes_UpdateSection IN_CMAKELISTS IN_PRESETS_FILE IN_MCUS)

    if(NOT EXISTS "${IN_CMAKELISTS}")
        return()
    endif()

    list(LENGTH IN_MCUS MCU_COUNT)

    # Option bytes of the MCUs - in the order of the first MCU which has the option byte
    set(VARIABLES "")

    foreach(MCU IN LISTS IN_MCUS)

        OptionBytes_ReadMcu("${IN_PRESETS_FILE}" "${MCU}" OB)
        if(NOT OB_FOUND)
            continue()
        endif()

        foreach(IDX IN LISTS OB_ITEMS)

            OptionBytes_VariableName("${OB_${IDX}_NAME}" VARIABLE)

            if(NOT VARIABLE IN_LIST VARIABLES)
                list(APPEND VARIABLES "${VARIABLE}")
                foreach(SUFFIX IN ITEMS NAME CATEGORY DESCRIPTION WIDTH MULTIPLIER ADDRESS_OFFSET BYBIT VALUES)
                    set(INFO_${VARIABLE}_${SUFFIX} "${OB_${IDX}_${SUFFIX}}")
                endforeach()
                set(INFO_${VARIABLE}_MCUS "${MCU}")
            elseif(NOT MCU IN_LIST INFO_${VARIABLE}_MCUS)
                list(APPEND INFO_${VARIABLE}_MCUS "${MCU}")
            endif()

        endforeach()

    endforeach()

    if(NOT VARIABLES)
        return()
    endif()

    file(READ "${IN_CMAKELISTS}" CONTENT)

    set(NEWLINE "\n")
    if(CONTENT MATCHES "\r\n")
        set(NEWLINE "\r\n")
    endif()

    # Existing section - its set values are kept
    string(FIND "${CONTENT}" "${OPTION_BYTES_BEGIN_LINE}" BEGIN_POS)
    string(FIND "${CONTENT}" "${OPTION_BYTES_END_LINE}" END_POS)
    set(SET_VARIABLES "")

    if(BEGIN_POS GREATER -1 AND END_POS GREATER BEGIN_POS)

        string(LENGTH "${OPTION_BYTES_END_LINE}${NEWLINE}" END_LENGTH)
        math(EXPR SECTION_LENGTH "${END_POS} + ${END_LENGTH} - ${BEGIN_POS}")
        string(SUBSTRING "${CONTENT}" ${BEGIN_POS} ${SECTION_LENGTH} OLD_SECTION)

        string(REGEX MATCHALL "set\\(${OPTION_BYTES_VARIABLE_PREFIX}[A-Za-z0-9_]+[ \t]+\"[^\"]*\"\\)" SET_LINES
               "${OLD_SECTION}")
        foreach(SET_LINE IN LISTS SET_LINES)
            if(SET_LINE MATCHES "set\\((${OPTION_BYTES_VARIABLE_PREFIX}[A-Za-z0-9_]+)[ \t]+\"([^\"]*)\"\\)")
                set(VALUE_${CMAKE_MATCH_1} "${CMAKE_MATCH_2}")
                if(NOT "${CMAKE_MATCH_2}" STREQUAL "")
                    list(APPEND SET_VARIABLES "${CMAKE_MATCH_1}")
                endif()
            endif()
        endforeach()

    else()
        set(OLD_SECTION "")
    endif()

    # New section
    set(LINES "${OPTION_BYTES_BEGIN_LINE}")
    set(HEADER "Option bytes of the MCU - the flash of the platform (task Flash, integration tests, debugging) writes "
               "the set values which differ from the chip. Empty value - the value of the chip is kept. A cmake "
               "parameter -D<variable>=<value> overrides the value of this file. Irreversible values (RDP level 2, "
               "...) are written as configured. Generated from Bsp/Ral/RalPresets.json for the MCUs of the project "
               "(BSP configuration, BSP update, VSCode project initialization) - the set values are kept.")
    string(CONCAT HEADER ${HEADER})
    OptionBytes_CommentLines("${HEADER}" "# " "# " COMMENT_LINES)
    list(APPEND LINES ${COMMENT_LINES})

    foreach(VARIABLE IN LISTS VARIABLES)

        set(TEXT "${INFO_${VARIABLE}_NAME} (${INFO_${VARIABLE}_CATEGORY})")
        if(NOT "${INFO_${VARIABLE}_DESCRIPTION}" STREQUAL "")
            string(APPEND TEXT ": ${INFO_${VARIABLE}_DESCRIPTION}")
        endif()
        if(NOT "${INFO_${VARIABLE}_MULTIPLIER}" STREQUAL "")
            string(APPEND TEXT " - ${INFO_${VARIABLE}_WIDTH} bits, address = ${INFO_${VARIABLE}_ADDRESS_OFFSET} + value * "
                               "${INFO_${VARIABLE}_MULTIPLIER}")
        elseif(INFO_${VARIABLE}_BYBIT)
            string(APPEND TEXT " - ${INFO_${VARIABLE}_WIDTH} bits, every bit: ${INFO_${VARIABLE}_VALUES}")
        elseif(NOT "${INFO_${VARIABLE}_VALUES}" STREQUAL "")
            string(APPEND TEXT " - ${INFO_${VARIABLE}_VALUES}")
        else()
            string(APPEND TEXT " - ${INFO_${VARIABLE}_WIDTH} bits")
        endif()

        list(LENGTH INFO_${VARIABLE}_MCUS VARIABLE_MCU_COUNT)
        if(VARIABLE_MCU_COUNT LESS MCU_COUNT)
            list(JOIN INFO_${VARIABLE}_MCUS ", " MCUS_TEXT)
            string(APPEND TEXT " (only ${MCUS_TEXT})")
        endif()

        OptionBytes_CommentLines("${TEXT}" "# " "#   " COMMENT_LINES)
        list(APPEND LINES "" ${COMMENT_LINES})

        set(SET_LINE "set(${VARIABLE}")
        string(LENGTH "${SET_LINE}" SET_LENGTH)
        if(SET_LENGTH LESS OPTION_BYTES_VALUE_COLUMN)
            math(EXPR PAD_LENGTH "${OPTION_BYTES_VALUE_COLUMN} - ${SET_LENGTH}")
            string(REPEAT " " ${PAD_LENGTH} PAD)
        else()
            set(PAD " ")
        endif()
        list(APPEND LINES "${SET_LINE}${PAD}\"${VALUE_${VARIABLE}}\")")

    endforeach()

    # Set values of option bytes the MCUs of the project do not have
    foreach(VARIABLE IN LISTS SET_VARIABLES)
        if(NOT VARIABLE IN_LIST VARIABLES)
            list(APPEND LINES "" "# Not an option byte of the MCUs of the project"
                         "set(${VARIABLE} \"${VALUE_${VARIABLE}}\")")
        endif()
    endforeach()

    list(APPEND LINES "${OPTION_BYTES_END_LINE}")
    list(JOIN LINES "${NEWLINE}" SECTION)
    string(APPEND SECTION "${NEWLINE}")

    if(NOT "${OLD_SECTION}" STREQUAL "")
        string(REPLACE "${OLD_SECTION}" "${SECTION}" NEW_CONTENT "${CONTENT}")
    else()
        string(FIND "${CONTENT}" "${OPTION_BYTES_INSERT_BEFORE}" INSERT_POS)
        if(INSERT_POS EQUAL -1)
            string(FIND "${CONTENT}" "\nproject(" INSERT_POS)
            if(INSERT_POS GREATER -1)
                math(EXPR INSERT_POS "${INSERT_POS} + 1")
            endif()
        endif()
        if(INSERT_POS EQUAL -1)
            message(WARNING "${IN_CMAKELISTS}: no place for the option bytes (\"${OPTION_BYTES_INSERT_BEFORE}\" or "
                            "project()) - section not written.")
            return()
        endif()
        string(SUBSTRING "${CONTENT}" 0 ${INSERT_POS} BEFORE)
        string(SUBSTRING "${CONTENT}" ${INSERT_POS} -1 AFTER)
        set(NEW_CONTENT "${BEFORE}${SECTION}${NEWLINE}${AFTER}")
    endif()

    if(NOT "${NEW_CONTENT}" STREQUAL "${CONTENT}")
        file(WRITE "${IN_CMAKELISTS}" "${NEW_CONTENT}")
        list(LENGTH VARIABLES VARIABLE_COUNT)
        message("Option bytes of the MCUs of the project in CMakeLists.txt: ${VARIABLE_COUNT}")
    endif()

endfunction(OptionBytes_UpdateSection)


#------------------------------------------------------------------------------#
# Option bytes of an MCU build (MCU preset TARGET_MCU_FULL_NAME): checks the
# set values and writes the file of the ELF section (OPTION_BYTES_FILE in the
# parent scope, "" when no value is set). The value of a variable is the cmake parameter (-D, cache) or
# the value of the project CMakeLists.txt; hexadecimal (0x...) or decimal, at
# most <width> bits of the option byte. The project of a core (TARGET_CORE)
# gets B<core> (BCM7, BCM4) of an empty variable from TARGET_CORES.
#------------------------------------------------------------------------------#
function(OptionBytes_Configure)

    set(OPTION_BYTES_FILE "" PARENT_SCOPE)

    OptionBytes_ReadMcu("${PLATFORM_ROOT_PATH}/Bsp/Ral/RalPresets.json" "${TARGET_MCU_FULL_NAME}" OB)

    # Variables of the option bytes of the MCU (first item of a name, the widest width of the name)
    set(MCU_VARIABLES "")
    foreach(IDX IN LISTS OB_ITEMS)
        OptionBytes_VariableName("${OB_${IDX}_NAME}" VARIABLE)
        if(NOT VARIABLE IN_LIST MCU_VARIABLES)
            list(APPEND MCU_VARIABLES "${VARIABLE}")
            set(NAME_${VARIABLE} "${OB_${IDX}_NAME}")
            set(WIDTH_${VARIABLE} ${OB_${IDX}_WIDTH})
        elseif(OB_${IDX}_WIDTH GREATER WIDTH_${VARIABLE})
            set(WIDTH_${VARIABLE} ${OB_${IDX}_WIDTH})
        endif()
    endforeach()

    # Variables of the project (CMakeLists.txt) and of the cmake parameters (cache)
    get_cmake_property(NORMAL_VARIABLES VARIABLES)
    get_cmake_property(CACHE_VARIABLES CACHE_VARIABLES)
    set(VARIABLES ${NORMAL_VARIABLES} ${CACHE_VARIABLES})
    list(FILTER VARIABLES INCLUDE REGEX "^${OPTION_BYTES_VARIABLE_PREFIX}")
    list(REMOVE_DUPLICATES VARIABLES)

    set(LINES "")
    set(TEXTS "")

    foreach(VARIABLE IN LISTS MCU_VARIABLES VARIABLES)

        if(DEFINED DONE_${VARIABLE})
            continue()
        endif()
        set(DONE_${VARIABLE} TRUE)

        if(DEFINED CACHE{${VARIABLE}} AND NOT "$CACHE{${VARIABLE}}" STREQUAL "")
            set(VALUE "$CACHE{${VARIABLE}}")
        else()
            set(VALUE "${${VARIABLE}}")
        endif()
        string(STRIP "${VALUE}" VALUE)

        # Boot of the cores of a multi-core MCU (BCM7, BCM4) of the project of a core
        if("${VALUE}" STREQUAL "" AND NOT "${TARGET_CORE}" STREQUAL "" AND VARIABLE IN_LIST MCU_VARIABLES AND
           "${NAME_${VARIABLE}}" MATCHES "^B(CM[0-9]+)$")
            if("${CMAKE_MATCH_1}" IN_LIST TARGET_CORES)
                set(VALUE 1)
            else()
                set(VALUE 0)
            endif()
        endif()

        if("${VALUE}" STREQUAL "")
            continue()
        endif()

        # The section of the project holds the option bytes of all MCUs of the project - an option byte of another MCU
        # is not written
        if(NOT VARIABLE IN_LIST MCU_VARIABLES)
            if(NOT OB_FOUND)
                message(FATAL_ERROR "${VARIABLE} is set, but the Ral presets (Bsp/Ral/RalPresets.json) have no option "
                                    "bytes of ${TARGET_MCU_FULL_NAME}.")
            endif()
            message(WARNING "${VARIABLE}: not an option byte of ${TARGET_MCU_FULL_NAME} (Bsp/Ral/RalPresets.json) - "
                            "not written.")
            continue()
        endif()

        if(NOT "${VALUE}" MATCHES "^(0[xX][0-9A-Fa-f]+|[0-9]+)$")
            message(FATAL_ERROR "${VARIABLE}: value '${VALUE}' is not a number (hexadecimal 0x... or decimal).")
        endif()

        math(EXPR NUMBER "${VALUE}" OUTPUT_FORMAT DECIMAL)
        math(EXPR LIMIT "1 << ${WIDTH_${VARIABLE}}" OUTPUT_FORMAT DECIMAL)
        if(NUMBER LESS 0 OR NOT NUMBER LESS LIMIT)
            message(FATAL_ERROR "${VARIABLE}: value ${VALUE} does not fit into ${WIDTH_${VARIABLE}} bits of the option "
                                "byte ${NAME_${VARIABLE}} of ${TARGET_MCU_FULL_NAME}.")
        endif()

        math(EXPR HEX "${NUMBER}" OUTPUT_FORMAT HEXADECIMAL)
        list(APPEND TEXTS "${NAME_${VARIABLE}}=${HEX}")

        # Registers and bits of the option byte - every variant with its own bits
        foreach(IDX IN LISTS OB_ITEMS)
            if("${OB_${IDX}_NAME}" STREQUAL "${NAME_${VARIABLE}}")
                set(ITEM_CONFIGS "${OB_${IDX}_CONFIGS}")
                string(REPLACE ";" "," ITEM_CONFIGS "${ITEM_CONFIGS}")
                if("${ITEM_CONFIGS}" STREQUAL "")
                    set(ITEM_CONFIGS "-")
                endif()
                string(CONCAT LINE "OPTION ${NAME_${VARIABLE}} ${HEX} ${OB_${IDX}_READ} ${OB_${IDX}_PROGRAM} "
                                   "${OB_${IDX}_OFFSET} ${OB_${IDX}_WIDTH} ${ITEM_CONFIGS}")
                list(APPEND LINES "${LINE}")
            endif()
        endforeach()

    endforeach()

    set(SECTION_DIR "${CMAKE_BINARY_DIR}/OptionBytes")

    if(NOT LINES)
        file(REMOVE "${SECTION_DIR}/option_bytes.S")
        return()
    endif()

    list(JOIN TEXTS ", " TEXTS)
    message(STATUS "Option bytes:         ${TEXTS}")

    # Write procedure of the family
    string(JSON PROCEDURE ERROR_VARIABLE JSON_ERROR GET "${OB_TABLE}" procedure)
    if(JSON_ERROR)
        message(FATAL_ERROR "Option bytes of ${TARGET_MCU_FULL_NAME} are set, but the Ral presets have no write "
                            "procedure of the family (ral-presets.sh) - they can not be written.")
    endif()

    set(HEADER_LINES "${OPTION_BYTES_FORMAT}" "MCU ${TARGET_MCU_FULL_NAME}" "DEVICE_ID ${OB_DEVICE_ID}")

    string(JSON MEMBER_COUNT LENGTH "${PROCEDURE}")
    math(EXPR MEMBER_LAST "${MEMBER_COUNT} - 1")
    foreach(MEMBER_IDX RANGE ${MEMBER_LAST})
        string(JSON MEMBER MEMBER "${PROCEDURE}" ${MEMBER_IDX})
        string(JSON MEMBER_TYPE TYPE "${PROCEDURE}" ${MEMBER})
        if(MEMBER_TYPE STREQUAL "ARRAY")
            string(JSON VALUE_COUNT LENGTH "${PROCEDURE}" ${MEMBER})
            math(EXPR VALUE_LAST "${VALUE_COUNT} - 1")
            set(VALUES "")
            foreach(VALUE_IDX RANGE ${VALUE_LAST})
                string(JSON VALUE GET "${PROCEDURE}" ${MEMBER} ${VALUE_IDX})
                string(APPEND VALUES " ${VALUE}")
            endforeach()
        else()
            string(JSON VALUE GET "${PROCEDURE}" ${MEMBER})
            set(VALUES " ${VALUE}")
        endif()
        list(APPEND HEADER_LINES "PROCEDURE ${MEMBER}${VALUES}")
    endforeach()

    # Device variants the preset can be with the register checks of the chip
    string(JSON CONFIG_COUNT ERROR_VARIABLE JSON_ERROR LENGTH "${OB_TABLE}" configs)
    if(NOT JSON_ERROR AND CONFIG_COUNT GREATER 0)
        math(EXPR CONFIG_LAST "${CONFIG_COUNT} - 1")
        foreach(CONFIG_IDX RANGE ${CONFIG_LAST})
            string(JSON CONFIG GET "${OB_TABLE}" configs ${CONFIG_IDX} number)
            if(OB_CONFIGS AND NOT CONFIG IN_LIST OB_CONFIGS)
                continue()
            endif()
            list(APPEND HEADER_LINES "CONFIG ${CONFIG}")
            string(JSON CHECK_COUNT LENGTH "${OB_TABLE}" configs ${CONFIG_IDX} checks)
            if(CHECK_COUNT GREATER 0)
                math(EXPR CHECK_LAST "${CHECK_COUNT} - 1")
                foreach(CHECK_IDX RANGE ${CHECK_LAST})
                    string(JSON CHECK GET "${OB_TABLE}" configs ${CONFIG_IDX} checks ${CHECK_IDX})
                    string(JSON CHECK_VALUE GET "${CHECK}" value)
                    string(JSON ADDRESS ERROR_VARIABLE JSON_ERROR GET "${CHECK}" read)
                    if(NOT JSON_ERROR)
                        string(JSON MASK GET "${CHECK}" mask)
                        list(APPEND HEADER_LINES "CHECK ${CONFIG} read ${ADDRESS} ${MASK} ${CHECK_VALUE}")
                    else()
                        string(JSON ADDRESS GET "${CHECK}" write)
                        list(APPEND HEADER_LINES "CHECK ${CONFIG} write ${ADDRESS} ${CHECK_VALUE}")
                    endif()
                endforeach()
            endif()
        endforeach()
    endif()

    list(PREPEND LINES ${HEADER_LINES})

    # Assembler source of the section - the linker places the non-allocated section next to the debug information,
    # the loaded content and the segments of the firmware stay the same (objcopy --add-section of the linked firmware
    # moves the segments of a firmware with a section loaded at another address, e.g. .data). Flag "R" (SHF_GNU_RETAIN)
    # - the section is not removed by --gc-sections (nothing refers to it). The file changes only with the values.
    set(SOURCE "/* Option bytes of the firmware - generated by OptionBytes.cmake, read by the flash of the platform */\n")
    string(APPEND SOURCE "    .section ${OPTION_BYTES_ELF_SECTION}, \"R\", %progbits\n")
    foreach(LINE IN LISTS LINES)
        string(APPEND SOURCE "    .ascii \"${LINE}\\n\"\n")
    endforeach()

    file(WRITE "${SECTION_DIR}/option_bytes.S.new" "${SOURCE}")
    configure_file("${SECTION_DIR}/option_bytes.S.new" "${SECTION_DIR}/option_bytes.S" COPYONLY)

    set(OPTION_BYTES_FILE "${SECTION_DIR}/option_bytes.S" PARENT_SCOPE)

endfunction(OptionBytes_Configure)


#------------------------------------------------------------------------------#
# Stores the option bytes of the build (OPTION_BYTES_FILE of
# OptionBytes_Configure) in the non-allocated ELF section .option_bytes of a
# firmware target (source of the target) - nothing when no option byte is set.
#
# IN_TARGET [in]: Firmware target
#------------------------------------------------------------------------------#
function(OptionBytes_AddSection IN_TARGET)

    if("${OPTION_BYTES_FILE}" STREQUAL "")
        return()
    endif()

    target_sources(${IN_TARGET} PRIVATE "${OPTION_BYTES_FILE}")

endfunction(OptionBytes_AddSection)
