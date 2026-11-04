################################################################################
# Author: Mr.Nobody
# file:  OptionBytes_Flash.cmake
# brief: Writes the option bytes of a firmware (ELF section .option_bytes of
#        OptionBytes.cmake) to the chip by probe-rs - the flash of the platform
#        (task Flash, integration tests, debugging).
#
#   OptionBytes_ReadElf  - lines of the section .option_bytes of an ELF file
#                          (ELF32 little endian read by CMake - no tool of the
#                          toolchain, also on an IT agent)
#   OptionBytes_Apply    - device variant of the chip (register checks of the
#                          section), the option bytes which differ from the chip
#                          are written by the write procedure of the family
#                          (flash unlock, option unlock, program enable, program
#                          registers, start, busy, launch or lock), the MCU is
#                          reset and the written values are read back. Nothing is
#                          written (and the chip is not reset) when the chip has
#                          the values. Irreversible values (RDP level 2, ...) are
#                          written as configured - the decision is the one of the
#                          project.
#   OptionBytes_Compare  - option bytes of two firmwares (projects of the cores of
#                          a multi-core MCU have to set the same option bytes)
#
# Every probe-rs call attaches to the chip (the core is halted and resumed).
#
# Script mode (firmware flashed by another tool):
#   cmake -DOPTION_BYTES_ELF=<firmware> -DOPTION_BYTES_PROBE_RS=<probe-rs> -DOPTION_BYTES_CHIP=<chip>
#         [-DOPTION_BYTES_PROBE=<VID:PID:SN>] -P OptionBytes_Flash.cmake
################################################################################

include_guard(GLOBAL)

#=============================== Constant values ==============================#

set(OPTION_BYTES_FLASH_SECTION          ".option_bytes")
set(OPTION_BYTES_FLASH_FORMAT           "EMBI_OPTION_BYTES 1")

# Polls of the busy flag of the write (one probe-rs call each, an RDP regression erases the flash)
set(OPTION_BYTES_BUSY_POLLS             200)

#================================ Functions ===================================#

#------------------------------------------------------------------------------#
# Little endian number of a part of a hexadecimal text of the file.
#
# OUT_VALUE [out]: Number (decimal)
# IN_HEX    [in]:  Hexadecimal text (file(READ ... HEX))
# IN_OFFSET [in]:  Byte offset in the text
# IN_SIZE   [in]:  Bytes (1 - 4)
#------------------------------------------------------------------------------#
function(optionBytes_Number OUT_VALUE IN_HEX IN_OFFSET IN_SIZE)

    set(DIGITS "")
    math(EXPR LAST_BYTE "${IN_SIZE} - 1")

    foreach(BYTE_IDX RANGE ${LAST_BYTE})
        math(EXPR POSITION "(${IN_OFFSET} + ${BYTE_IDX}) * 2")
        string(SUBSTRING "${IN_HEX}" ${POSITION} 2 BYTE)
        set(DIGITS "${BYTE}${DIGITS}")
    endforeach()

    math(EXPR VALUE "0x${DIGITS}" OUTPUT_FORMAT DECIMAL)
    set(${OUT_VALUE} ${VALUE} PARENT_SCOPE)

endfunction(optionBytes_Number)


#------------------------------------------------------------------------------#
# Lines of the section .option_bytes of a firmware (ELF32, little endian).
#
# OUT_LINES [out]: Lines of the section ("" - no section, no option bytes)
# IN_ELF    [in]:  Firmware (ELF)
#------------------------------------------------------------------------------#
function(OptionBytes_ReadElf OUT_LINES IN_ELF)

    set(${OUT_LINES} "" PARENT_SCOPE)

    if(NOT EXISTS "${IN_ELF}")
        message(FATAL_ERROR "Firmware ${IN_ELF} not found.")
    endif()

    file(READ "${IN_ELF}" HEADER LIMIT 52 HEX)

    if(NOT HEADER MATCHES "^7f454c460101")
        message(FATAL_ERROR "${IN_ELF} is no ELF32 little endian file.")
    endif()

    optionBytes_Number(SECTIONS_OFFSET "${HEADER}" 32 4)
    optionBytes_Number(ENTRY_SIZE      "${HEADER}" 46 2)
    optionBytes_Number(SECTION_COUNT   "${HEADER}" 48 2)
    optionBytes_Number(NAMES_INDEX     "${HEADER}" 50 2)

    math(EXPR TABLE_SIZE "${ENTRY_SIZE} * ${SECTION_COUNT}")
    file(READ "${IN_ELF}" TABLE OFFSET ${SECTIONS_OFFSET} LIMIT ${TABLE_SIZE} HEX)

    # Names of the sections (section header string table)
    math(EXPR NAMES_ENTRY "${NAMES_INDEX} * ${ENTRY_SIZE}")
    math(EXPR NAMES_OFFSET_POS "${NAMES_ENTRY} + 16")
    math(EXPR NAMES_SIZE_POS "${NAMES_ENTRY} + 20")
    optionBytes_Number(NAMES_OFFSET "${TABLE}" ${NAMES_OFFSET_POS} 4)
    optionBytes_Number(NAMES_SIZE   "${TABLE}" ${NAMES_SIZE_POS} 4)
    file(READ "${IN_ELF}" NAMES OFFSET ${NAMES_OFFSET} LIMIT ${NAMES_SIZE} HEX)

    string(HEX "${OPTION_BYTES_FLASH_SECTION}" SECTION_NAME_HEX)
    string(APPEND SECTION_NAME_HEX "00")
    string(LENGTH "${SECTION_NAME_HEX}" SECTION_NAME_LENGTH)
    string(LENGTH "${NAMES}" NAMES_LENGTH)

    math(EXPR LAST_SECTION "${SECTION_COUNT} - 1")

    foreach(SECTION_IDX RANGE ${LAST_SECTION})

        math(EXPR ENTRY "${SECTION_IDX} * ${ENTRY_SIZE}")
        optionBytes_Number(NAME_OFFSET "${TABLE}" ${ENTRY} 4)

        math(EXPR NAME_POSITION "${NAME_OFFSET} * 2")
        math(EXPR NAME_END "${NAME_POSITION} + ${SECTION_NAME_LENGTH}")
        if(NAME_END GREATER NAMES_LENGTH)
            continue()
        endif()

        string(SUBSTRING "${NAMES}" ${NAME_POSITION} ${SECTION_NAME_LENGTH} NAME_HEX)

        if(NAME_HEX STREQUAL SECTION_NAME_HEX)
            math(EXPR OFFSET_POS "${ENTRY} + 16")
            math(EXPR SIZE_POS "${ENTRY} + 20")
            optionBytes_Number(CONTENT_OFFSET "${TABLE}" ${OFFSET_POS} 4)
            optionBytes_Number(CONTENT_SIZE   "${TABLE}" ${SIZE_POS} 4)
            file(READ "${IN_ELF}" CONTENT OFFSET ${CONTENT_OFFSET} LIMIT ${CONTENT_SIZE})
            string(REGEX REPLACE "\n$" "" CONTENT "${CONTENT}")
            string(REPLACE "\n" ";" LINES "${CONTENT}")
            list(GET LINES 0 FORMAT)
            if(NOT FORMAT STREQUAL OPTION_BYTES_FLASH_FORMAT)
                message(FATAL_ERROR "${IN_ELF}: option bytes of an unknown format ('${FORMAT}', expected "
                                    "'${OPTION_BYTES_FLASH_FORMAT}') - flash it by the platform of its build.")
            endif()
            set(${OUT_LINES} "${LINES}" PARENT_SCOPE)
            return()
        endif()

    endforeach()

endfunction(OptionBytes_ReadElf)


#------------------------------------------------------------------------------#
# Option bytes of a firmware as "<name>=<value>" (OPTION lines of the section).
#
# OUT_VALUES [out]: Sorted list of the set option bytes
# IN_LINES   [in]:  Lines of the section (OptionBytes_ReadElf)
#------------------------------------------------------------------------------#
function(optionBytes_Values OUT_VALUES IN_LINES)

    set(VALUES "")

    foreach(LINE IN LISTS IN_LINES)
        if(LINE MATCHES "^OPTION ([^ ]+) ([^ ]+) ")
            list(APPEND VALUES "${CMAKE_MATCH_1}=${CMAKE_MATCH_2}")
        endif()
    endforeach()

    list(REMOVE_DUPLICATES VALUES)
    list(SORT VALUES)

    set(${OUT_VALUES} "${VALUES}" PARENT_SCOPE)

endfunction(optionBytes_Values)


#------------------------------------------------------------------------------#
# Compares the option bytes of two firmwares - the projects of the cores of a
# multi-core MCU flash one chip, they have to set the same option bytes.
#
# OUT_DIFFERENCE [out]: "" when equal, otherwise the text of the difference
# IN_ELF         [in]:  Firmware
# IN_OTHER_ELF   [in]:  Firmware of the other project
#------------------------------------------------------------------------------#
function(OptionBytes_Compare OUT_DIFFERENCE IN_ELF IN_OTHER_ELF)

    OptionBytes_ReadElf(LINES "${IN_ELF}")
    OptionBytes_ReadElf(OTHER_LINES "${IN_OTHER_ELF}")
    optionBytes_Values(VALUES "${LINES}")
    optionBytes_Values(OTHER_VALUES "${OTHER_LINES}")

    if("${VALUES}" STREQUAL "${OTHER_VALUES}")
        set(${OUT_DIFFERENCE} "" PARENT_SCOPE)
    else()
        list(JOIN VALUES ", " TEXT)
        list(JOIN OTHER_VALUES ", " OTHER_TEXT)
        if("${TEXT}" STREQUAL "")
            set(TEXT "none")
        endif()
        if("${OTHER_TEXT}" STREQUAL "")
            set(OTHER_TEXT "none")
        endif()
        set(${OUT_DIFFERENCE} "${TEXT} | ${OTHER_TEXT}" PARENT_SCOPE)
    endif()

endfunction(OptionBytes_Compare)


#------------------------------------------------------------------------------#
# probe-rs call of the option bytes (OPTION_BYTES_PROBE_RS, OPTION_BYTES_PROBE_ARGS
# of OptionBytes_Apply).
#
# OUT_RESULT [out]: Exit code
# OUT_OUTPUT [out]: Output (standard and error)
# ARGN       [in]:  Subcommand and its parameters (the probe parameters are added after the subcommand)
#------------------------------------------------------------------------------#
function(optionBytes_ProbeRs OUT_RESULT OUT_OUTPUT)

    list(POP_FRONT ARGN SUBCOMMAND)

    execute_process(COMMAND "${OPTION_BYTES_PROBE_RS}" ${SUBCOMMAND} ${OPTION_BYTES_PROBE_ARGS} ${ARGN}
                    RESULT_VARIABLE RESULT
                    OUTPUT_VARIABLE OUTPUT
                    ERROR_VARIABLE  OUTPUT)

    set(${OUT_RESULT} ${RESULT} PARENT_SCOPE)
    set(${OUT_OUTPUT} "${OUTPUT}" PARENT_SCOPE)

endfunction(optionBytes_ProbeRs)


#------------------------------------------------------------------------------#
# Reads a 32-bit register of the chip.
#
# OUT_VALUE  [out]: Value (decimal)
# IN_ADDRESS [in]:  Address
#------------------------------------------------------------------------------#
function(optionBytes_Read OUT_VALUE IN_ADDRESS)

    optionBytes_ProbeRs(RESULT OUTPUT read b32 ${IN_ADDRESS} 1)

    if(NOT RESULT EQUAL 0 OR NOT OUTPUT MATCHES "([0-9A-Fa-f]+)[ \t\r\n]*$")
        message(FATAL_ERROR "Option bytes: probe-rs could not read ${IN_ADDRESS}:\n${OUTPUT}")
    endif()

    math(EXPR VALUE "0x${CMAKE_MATCH_1}" OUTPUT_FORMAT DECIMAL)
    set(${OUT_VALUE} ${VALUE} PARENT_SCOPE)

endfunction(optionBytes_Read)


#------------------------------------------------------------------------------#
# Writes a 32-bit register of the chip.
#
# IN_ADDRESS [in]: Address
# IN_VALUE   [in]: Value
# ARGN       [in]: MAY_FAIL - the write resets the MCU (launch of the option bytes), an error of probe-rs is ignored
#------------------------------------------------------------------------------#
function(optionBytes_Write IN_ADDRESS IN_VALUE)

    math(EXPR HEX "${IN_VALUE}" OUTPUT_FORMAT HEXADECIMAL)
    optionBytes_ProbeRs(RESULT OUTPUT write b32 ${IN_ADDRESS} ${HEX})

    if(NOT RESULT EQUAL 0 AND NOT "MAY_FAIL" IN_LIST ARGN)
        message(FATAL_ERROR "Option bytes: probe-rs could not write ${HEX} to ${IN_ADDRESS}:\n${OUTPUT}")
    endif()

endfunction(optionBytes_Write)


#------------------------------------------------------------------------------#
# Writes the option bytes of a firmware to the chip - only when the chip has
# other values (OPTION_BYTES_PROBE_RS / OPTION_BYTES_PROBE_ARGS for the probe-rs
# calls). Stops with FATAL_ERROR when the chip is no device variant of the
# section or a written value is not read back.
#
# OUT_TEXT        [out]: Text of the result ("" - the firmware has no option bytes)
# IN_ELF          [in]:  Firmware (ELF)
# IN_PROBE_RS     [in]:  probe-rs executable
# IN_PROBE_ARGS   [in]:  Parameters of the probe and chip (--chip <chip> [--probe <VID:PID:SN>])
#------------------------------------------------------------------------------#
function(OptionBytes_Apply OUT_TEXT IN_ELF IN_PROBE_RS IN_PROBE_ARGS)

    set(${OUT_TEXT} "" PARENT_SCOPE)

    OptionBytes_ReadElf(LINES "${IN_ELF}")
    if(NOT LINES)
        return()
    endif()

    set(OPTION_BYTES_PROBE_RS   "${IN_PROBE_RS}")
    set(OPTION_BYTES_PROBE_ARGS "${IN_PROBE_ARGS}")

    # Content of the section
    set(MCU "")
    set(CONFIGS "")
    set(OPTIONS "")

    foreach(LINE IN LISTS LINES)
        string(REPLACE " " ";" FIELDS "${LINE}")
        list(POP_FRONT FIELDS KIND)
        if(KIND STREQUAL "MCU")
            list(GET FIELDS 0 MCU)
        elseif(KIND STREQUAL "PROCEDURE")
            list(POP_FRONT FIELDS MEMBER)
            set(PROC_${MEMBER} "${FIELDS}")
        elseif(KIND STREQUAL "CONFIG")
            list(APPEND CONFIGS "${FIELDS}")
            set(CHECKS_${FIELDS} "")
        elseif(KIND STREQUAL "CHECK")
            list(POP_FRONT FIELDS CONFIG)
            string(REPLACE ";" "|" CHECK "${FIELDS}")
            list(APPEND CHECKS_${CONFIG} "${CHECK}")
        elseif(KIND STREQUAL "OPTION")
            string(REPLACE ";" "|" OPTION "${FIELDS}")
            list(APPEND OPTIONS "${OPTION}")
        endif()
    endforeach()

    # Device variant of the chip - the first one whose checks are true. A register written by a check (clock of the
    # peripheral read by the next check) gets its value back.
    set(CHIP_CONFIG "")
    set(WRITTEN_ADDRESSES "")

    foreach(CONFIG IN LISTS CONFIGS)
        set(MATCH TRUE)
        foreach(CHECK IN LISTS CHECKS_${CONFIG})
            string(REPLACE "|" ";" CHECK "${CHECK}")
            list(GET CHECK 0 ACCESS)
            list(GET CHECK 1 ADDRESS)
            if(ACCESS STREQUAL "write")
                list(GET CHECK 2 VALUE)
                if(NOT ADDRESS IN_LIST WRITTEN_ADDRESSES)
                    optionBytes_Read(ORIGINAL_${ADDRESS} ${ADDRESS})
                    list(PREPEND WRITTEN_ADDRESSES "${ADDRESS}")
                endif()
                optionBytes_Write(${ADDRESS} ${VALUE})
            else()
                list(GET CHECK 2 MASK)
                list(GET CHECK 3 VALUE)
                optionBytes_Read(READ_VALUE ${ADDRESS})
                math(EXPR MASKED "${READ_VALUE} & ${MASK}")
                math(EXPR EXPECTED "${VALUE}")
                if(NOT MASKED EQUAL EXPECTED)
                    set(MATCH FALSE)
                    break()
                endif()
            endif()
        endforeach()
        if(MATCH)
            set(CHIP_CONFIG "${CONFIG}")
            break()
        endif()
    endforeach()

    foreach(ADDRESS IN LISTS WRITTEN_ADDRESSES)
        optionBytes_Write(${ADDRESS} ${ORIGINAL_${ADDRESS}})
    endforeach()

    if(CONFIGS AND "${CHIP_CONFIG}" STREQUAL "")
        list(JOIN CONFIGS ", " CONFIGS_TEXT)
        message(FATAL_ERROR "Option bytes: the chip is no device variant of ${MCU} (${CONFIGS_TEXT}) - wrong MCU "
                            "connected, the option bytes are not written.")
    endif()

    # Option bytes of the variant with the values of the chip
    set(NAMES "")
    set(CHANGES "")
    set(UNCHANGED "")

    foreach(OPTION IN LISTS OPTIONS)

        string(REPLACE "|" ";" OPTION "${OPTION}")
        list(GET OPTION 0 NAME)
        list(GET OPTION 1 VALUE)
        list(GET OPTION 6 OPTION_CONFIGS)

        if(NAME IN_LIST NAMES)
            continue()
        endif()

        if(NOT OPTION_CONFIGS STREQUAL "-")
            string(REPLACE "," ";" OPTION_CONFIGS "${OPTION_CONFIGS}")
            if(NOT CHIP_CONFIG IN_LIST OPTION_CONFIGS)
                continue()
            endif()
        endif()

        list(APPEND NAMES "${NAME}")
        list(GET OPTION 2 READ_ADDRESS)
        list(GET OPTION 3 PROGRAM_ADDRESS)
        list(GET OPTION 4 OFFSET)
        list(GET OPTION 5 WIDTH)

        math(EXPR MASK "(1 << ${WIDTH}) - 1")
        math(EXPR VALUE "${VALUE}")
        if(VALUE GREATER MASK)
            message(FATAL_ERROR "Option bytes: ${NAME}=${VALUE} does not fit into ${WIDTH} bits of the device variant "
                                "${CHIP_CONFIG} of the chip.")
        endif()

        optionBytes_Read(CURRENT_REGISTER ${READ_ADDRESS})
        math(EXPR CURRENT "(${CURRENT_REGISTER} >> ${OFFSET}) & ${MASK}" OUTPUT_FORMAT HEXADECIMAL)
        math(EXPR WANTED "${VALUE}" OUTPUT_FORMAT HEXADECIMAL)

        set(OPTION_${NAME} "${READ_ADDRESS};${PROGRAM_ADDRESS};${OFFSET};${MASK};${WANTED};${CURRENT}")

        if(CURRENT STREQUAL WANTED)
            list(APPEND UNCHANGED "${NAME}=${WANTED}")
        else()
            list(APPEND CHANGES "${NAME}")
        endif()

    endforeach()

    foreach(NAME IN LISTS OPTIONS)
        string(REGEX REPLACE "\\|.*" "" NAME "${NAME}")
        if(NOT NAME IN_LIST NAMES)
            message(WARNING "Option bytes: ${NAME} does not exist in the device variant ${CHIP_CONFIG} of the chip - "
                            "not written.")
            list(APPEND NAMES "${NAME}")
        endif()
    endforeach()

    list(JOIN UNCHANGED ", " UNCHANGED_TEXT)

    set(VARIANT_TEXT "")
    if(NOT "${CHIP_CONFIG}" STREQUAL "")
        set(VARIANT_TEXT " (device variant ${CHIP_CONFIG})")
    endif()

    if(NOT CHANGES)
        set(${OUT_TEXT} "Option bytes of the chip${VARIANT_TEXT} are the configured ones: ${UNCHANGED_TEXT}" PARENT_SCOPE)
        return()
    endif()

    foreach(MEMBER IN ITEMS controlRegister optionLockMask optionKeyRegister optionKeys statusRegister busyMask)
        if("${PROC_${MEMBER}}" STREQUAL "")
            message(FATAL_ERROR "Option bytes: write procedure of ${MCU} without ${MEMBER} - not written.")
        endif()
    endforeach()

    # Unlock of the flash (families whose option lock is released only with the flash lock released) and of the
    # option bytes
    if(NOT "${PROC_flashKeyRegister}" STREQUAL "")
        optionBytes_Read(CONTROL ${PROC_controlRegister})
        math(EXPR LOCKED "${CONTROL} & ${PROC_flashLockMask}")
        if(NOT LOCKED EQUAL 0)
            foreach(KEY IN LISTS PROC_flashKeys)
                optionBytes_Write(${PROC_flashKeyRegister} ${KEY})
            endforeach()
        endif()
    endif()

    optionBytes_Read(CONTROL ${PROC_controlRegister})
    math(EXPR LOCKED "${CONTROL} & ${PROC_optionLockMask}")
    if(NOT LOCKED EQUAL 0)
        foreach(KEY IN LISTS PROC_optionKeys)
            optionBytes_Write(${PROC_optionKeyRegister} ${KEY})
        endforeach()
        optionBytes_Read(CONTROL ${PROC_controlRegister})
        math(EXPR LOCKED "${CONTROL} & ${PROC_optionLockMask}")
        if(NOT LOCKED EQUAL 0)
            message(FATAL_ERROR "Option bytes: the option lock of ${MCU} was not released - not written.")
        endif()
    endif()

    if(NOT "${PROC_programMask}" STREQUAL "")
        math(EXPR CONTROL "${CONTROL} | ${PROC_programMask}")
        optionBytes_Write(${PROC_controlRegister} ${CONTROL})
    endif()

    # Program registers - every changed option byte in its register (read, changed, written)
    set(PROGRAM_ADDRESSES "")
    foreach(NAME IN LISTS CHANGES)
        list(GET OPTION_${NAME} 1 PROGRAM_ADDRESS)
        list(APPEND PROGRAM_ADDRESSES "${PROGRAM_ADDRESS}")
    endforeach()
    list(REMOVE_DUPLICATES PROGRAM_ADDRESSES)

    set(CHANGE_TEXTS "")
    foreach(PROGRAM_ADDRESS IN LISTS PROGRAM_ADDRESSES)
        optionBytes_Read(PROGRAM ${PROGRAM_ADDRESS})
        foreach(NAME IN LISTS CHANGES)
            list(GET OPTION_${NAME} 1 NAME_PROGRAM)
            if(NOT NAME_PROGRAM STREQUAL PROGRAM_ADDRESS)
                continue()
            endif()
            list(GET OPTION_${NAME} 2 OFFSET)
            list(GET OPTION_${NAME} 3 MASK)
            list(GET OPTION_${NAME} 4 WANTED)
            list(GET OPTION_${NAME} 5 CURRENT)
            math(EXPR PROGRAM "(${PROGRAM} & ~(${MASK} << ${OFFSET})) | (${WANTED} << ${OFFSET})")
            list(APPEND CHANGE_TEXTS "${NAME} ${CURRENT} -> ${WANTED}")
        endforeach()
        optionBytes_Write(${PROGRAM_ADDRESS} ${PROGRAM})
    endforeach()

    list(JOIN CHANGE_TEXTS ", " CHANGES_TEXT)
    message(STATUS "Option bytes of ${MCU}: ${CHANGES_TEXT}")

    if(NOT "${PROC_startMask}" STREQUAL "")
        optionBytes_Read(CONTROL ${PROC_controlRegister})
        math(EXPR CONTROL "${CONTROL} | ${PROC_startMask}")
        optionBytes_Write(${PROC_controlRegister} ${CONTROL})
    endif()

    # End of the write
    if(NOT "${PROC_statusRegister}" STREQUAL "" AND NOT "${PROC_busyMask}" STREQUAL "")
        set(BUSY 1)
        foreach(POLL RANGE ${OPTION_BYTES_BUSY_POLLS})
            optionBytes_Read(STATUS ${PROC_statusRegister})
            math(EXPR BUSY "${STATUS} & ${PROC_busyMask}")
            if(BUSY EQUAL 0)
                break()
            endif()
        endforeach()
        if(NOT BUSY EQUAL 0)
            message(FATAL_ERROR "Option bytes: the write of ${MCU} did not end (busy) - check the option bytes of the "
                                "chip.")
        endif()
    endif()

    if(NOT "${PROC_programMask}" STREQUAL "")
        optionBytes_Read(CONTROL ${PROC_controlRegister})
        math(EXPR CONTROL "${CONTROL} & ~${PROC_programMask}")
        optionBytes_Write(${PROC_controlRegister} ${CONTROL})
    endif()

    # Loading of the option bytes (resets the MCU) or option lock
    optionBytes_Read(CONTROL ${PROC_controlRegister})
    if(NOT "${PROC_launchMask}" STREQUAL "")
        math(EXPR CONTROL "${CONTROL} | ${PROC_launchMask}")
        optionBytes_Write(${PROC_controlRegister} ${CONTROL} MAY_FAIL)
    else()
        math(EXPR CONTROL "${CONTROL} | ${PROC_optionLockMask}")
        optionBytes_Write(${PROC_controlRegister} ${CONTROL})
    endif()

    # Reset - the MCU starts with the new option bytes (a reset after the download may report a timeout once)
    optionBytes_ProbeRs(RESET_RESULT RESET_OUTPUT reset)
    if(NOT RESET_RESULT EQUAL 0)
        optionBytes_ProbeRs(RESET_RESULT RESET_OUTPUT reset)
    endif()
    if(NOT RESET_RESULT EQUAL 0)
        message(FATAL_ERROR "Option bytes: reset of ${MCU} after the write failed:\n${RESET_OUTPUT}")
    endif()

    # Read back
    foreach(NAME IN LISTS CHANGES)
        list(GET OPTION_${NAME} 0 READ_ADDRESS)
        list(GET OPTION_${NAME} 2 OFFSET)
        list(GET OPTION_${NAME} 3 MASK)
        list(GET OPTION_${NAME} 4 WANTED)
        optionBytes_Read(CURRENT_REGISTER ${READ_ADDRESS})
        math(EXPR CURRENT "(${CURRENT_REGISTER} >> ${OFFSET}) & ${MASK}" OUTPUT_FORMAT HEXADECIMAL)
        if(NOT CURRENT STREQUAL WANTED)
            message(FATAL_ERROR "Option bytes: ${NAME} of the chip is ${CURRENT} after the write, not ${WANTED} "
                                "(protection of the chip or a value the chip refuses).")
        endif()
    endforeach()

    set(${OUT_TEXT} "Option bytes written${VARIANT_TEXT}: ${CHANGES_TEXT}" PARENT_SCOPE)

endfunction(OptionBytes_Apply)


#==============================================================================#
# Script mode
#==============================================================================#
if(CMAKE_SCRIPT_MODE_FILE AND CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)

    foreach(PARAMETER IN ITEMS OPTION_BYTES_ELF OPTION_BYTES_PROBE_RS OPTION_BYTES_CHIP)
        if("${${PARAMETER}}" STREQUAL "")
            message(FATAL_ERROR "Required parameter ${PARAMETER} not set.")
        endif()
    endforeach()

    set(PROBE_ARGS --chip "${OPTION_BYTES_CHIP}")
    if(NOT "${OPTION_BYTES_PROBE}" STREQUAL "")
        list(APPEND PROBE_ARGS --probe "${OPTION_BYTES_PROBE}")
    endif()

    OptionBytes_Apply(TEXT "${OPTION_BYTES_ELF}" "${OPTION_BYTES_PROBE_RS}" "${PROBE_ARGS}")

    if(NOT "${TEXT}" STREQUAL "")
        message("${TEXT}")
    endif()

endif()
