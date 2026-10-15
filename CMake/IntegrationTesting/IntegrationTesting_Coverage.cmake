################################################################################
# Author: Mr.Nobody
# file:  IntegrationTesting_Coverage.cmake
# brief: Host side of the code coverage of the integration tests - converts the
#        gcov data read from the target to .gcda files.
#
# The firmware serializes the gcov data of the tested code after the last test case
# (ItCore/IntegrationTesting_Coverage.c), IntegrationTesting_Run.cmake reads the stream
# through the debug probe and stores it as a text file (Intel HEX, "<NAME>.cov.ihex"),
# because the hosts of the board farm have nothing but CMake and probe-rs. This script
# converts the stream to .gcda files by the tools of the ARM toolchain:
#   objcopy -I ihex -O binary          Intel HEX -> binary stream
#   gcov-tool merge-stream             stream -> .gcda files (the counters are added up
#                                      to the existing ones, so the results of more
#                                      firmwares and boards sum up)
#
# The .gcda files are written to the folder of the build with the objects (.gcno): the
# stream names them by the path at the time of the build (ORIGINAL_BUILD_DIR), the leading
# components of it are replaced by BUILD_DIR (GCOV_PREFIX / GCOV_PREFIX_STRIP of libgcov).
# This allows to convert the stream on another machine than the one which built the firmware.
#
# Functions (included by IntegrationTesting_Run.cmake):
#   itCoverage_HexToIhex   - hexadecimal bytes -> Intel HEX file
#   itCoverage_Merge       - Intel HEX file -> .gcda files
#
# Script - conversion of the stored streams (target IntegrationTest_CoverageMerge, the coverage
# stage of a pipeline):
#   cmake -DIT_COV_DUMPS=<*.cov.ihex files> -DIT_COV_BUILD_DIR=<folder of the build>
#         [-DIT_COV_ORIGINAL_BUILD_DIR=<folder of the build at the time of the build>]
#         -DIT_OBJCOPY=<arm-none-eabi-objcopy> -DIT_GCOV_TOOL=<arm-none-eabi-gcov-tool>
#         -P IntegrationTesting_Coverage.cmake
################################################################################

include_guard(GLOBAL)

#================================ Functions ===================================#

#------------------------------------------------------------------------------#
# Converts bytes in hexadecimal text to Intel HEX file (records of 16 bytes,
# extended linear address record for every 64 kB). The file is converted back to
# the binary stream by objcopy - CMake cannot write binary files.
#
# HEX      [in]: Bytes, two hexadecimal characters per byte
# OUT_FILE [in]: Intel HEX file
#------------------------------------------------------------------------------#
function(itCoverage_HexToIhex HEX OUT_FILE)

    string(LENGTH "${HEX}" HEX_LENGTH)
    math(EXPR BYTE_CNT "${HEX_LENGTH} / 2")

    set(RECORDS "")
    set(OFFSET  0)
    set(UPPER   -1)

    while(OFFSET LESS BYTE_CNT)

        # Upper 16 bits of the address: extended linear address record
        math(EXPR UPPER_NOW "${OFFSET} >> 16")

        if(NOT UPPER_NOW EQUAL UPPER)

            set(UPPER ${UPPER_NOW})

            math(EXPR UPPER_HIGH "( ${UPPER} >> 8 ) & 255")
            math(EXPR UPPER_LOW  "${UPPER} & 255")

            itCoverage_Hex(UPPER_HEX ${UPPER} 4)
            itCoverage_Checksum(CHECKSUM 2 0 4 ${UPPER_HIGH} ${UPPER_LOW})

            string(APPEND RECORDS ":02000004${UPPER_HEX}${CHECKSUM}\n")

        endif()

        math(EXPR REMAINING "${BYTE_CNT} - ${OFFSET}")

        if(REMAINING GREATER 16)
            set(REMAINING 16)
        endif()

        math(EXPR LOWER "${OFFSET} & 0xFFFF")
        math(EXPR CHAR_POSITION "${OFFSET} * 2")
        math(EXPR CHAR_COUNT "${REMAINING} * 2")

        string(SUBSTRING "${HEX}" ${CHAR_POSITION} ${CHAR_COUNT} DATA)

        # Checksum: two's complement of the sum of all bytes of the record
        string(REGEX MATCHALL ".." DATA_BYTES "${DATA}")

        set(DATA_VALUES "")

        foreach(DATA_BYTE IN LISTS DATA_BYTES)
            list(APPEND DATA_VALUES "0x${DATA_BYTE}")
        endforeach()

        itCoverage_Hex(LOWER_HEX ${LOWER} 4)
        itCoverage_Hex(COUNT_HEX ${REMAINING} 2)
        itCoverage_Checksum(CHECKSUM ${REMAINING} ${LOWER} 0 ${DATA_VALUES})

        string(APPEND RECORDS ":${COUNT_HEX}${LOWER_HEX}00${DATA}${CHECKSUM}\n")

        math(EXPR OFFSET "${OFFSET} + ${REMAINING}")

    endwhile()

    string(APPEND RECORDS ":00000001FF\n")

    string(TOUPPER "${RECORDS}" RECORDS)

    file(WRITE "${OUT_FILE}" "${RECORDS}")

endfunction(itCoverage_HexToIhex)


#------------------------------------------------------------------------------#
# Hexadecimal text of a number with leading zeros.
#
# HEX_VAR [out]: Text (uppercase)
# VALUE   [in]:  Number
# DIGITS  [in]:  Count of the digits
#------------------------------------------------------------------------------#
function(itCoverage_Hex HEX_VAR VALUE DIGITS)

    math(EXPR VALUE_HEX "${VALUE}" OUTPUT_FORMAT HEXADECIMAL)
    string(REGEX REPLACE "^0x" "" VALUE_HEX "${VALUE_HEX}")
    string(LENGTH "${VALUE_HEX}" VALUE_LENGTH)

    if(VALUE_LENGTH LESS DIGITS)
        math(EXPR ZEROS "${DIGITS} - ${VALUE_LENGTH}")
        string(REPEAT "0" ${ZEROS} ZERO_TEXT)
        set(VALUE_HEX "${ZERO_TEXT}${VALUE_HEX}")
    endif()

    string(TOUPPER "${VALUE_HEX}" VALUE_HEX)

    set(${HEX_VAR} "${VALUE_HEX}" PARENT_SCOPE)

endfunction(itCoverage_Hex)


#------------------------------------------------------------------------------#
# Checksum of an Intel HEX record: two's complement of the sum of the bytes of
# the record (count, address bytes, type, data).
#
# CHECKSUM_VAR [out]: Checksum, two hexadecimal characters
# COUNT        [in]:  Count of the data bytes
# ADDRESS      [in]:  16-bit address of the record
# TYPE         [in]:  Type of the record (0 data, 4 extended linear address)
# ARGN         [in]:  Data bytes (numbers)
#------------------------------------------------------------------------------#
function(itCoverage_Checksum CHECKSUM_VAR COUNT ADDRESS TYPE)

    math(EXPR SUM "${COUNT} + ( ${ADDRESS} >> 8 ) + ( ${ADDRESS} & 255 ) + ${TYPE}")

    foreach(DATA_VALUE IN LISTS ARGN)
        math(EXPR SUM "${SUM} + ${DATA_VALUE}")
    endforeach()

    math(EXPR CHECKSUM "( 256 - ( ${SUM} & 255 ) ) & 255")

    itCoverage_Hex(CHECKSUM_HEX ${CHECKSUM} 2)

    set(${CHECKSUM_VAR} "${CHECKSUM_HEX}" PARENT_SCOPE)

endfunction(itCoverage_Checksum)


#------------------------------------------------------------------------------#
# Converts the stream stored by IntegrationTesting_Run.cmake to .gcda files
# (the counters are added to the existing .gcda files).
#
# DUMP_FILE           [in]: Intel HEX file of the stream
# BUILD_DIR           [in]: Folder of the build with the objects and .gcno files
# ORIGINAL_BUILD_DIR  [in]: Folder of the build at the time of the build (names in the stream)
# OBJCOPY             [in]: objcopy of the ARM toolchain
# GCOV_TOOL           [in]: gcov-tool of the ARM toolchain
#------------------------------------------------------------------------------#
function(itCoverage_Merge DUMP_FILE BUILD_DIR ORIGINAL_BUILD_DIR OBJCOPY GCOV_TOOL)

    foreach(TOOL IN ITEMS OBJCOPY GCOV_TOOL)
        if(NOT ${TOOL} OR NOT EXISTS "${${TOOL}}")
            message(FATAL_ERROR "Tool ${TOOL} for the conversion of the coverage data not found ('${${TOOL}}').")
        endif()
    endforeach()

    if(NOT EXISTS "${DUMP_FILE}")
        message(FATAL_ERROR "Coverage data ${DUMP_FILE} does not exist.")
    endif()

    set(STREAM_FILE "${DUMP_FILE}.bin")

    execute_process(
        COMMAND "${OBJCOPY}" -I ihex -O binary "${DUMP_FILE}" "${STREAM_FILE}"
        RESULT_VARIABLE OBJCOPY_RESULT
        ERROR_VARIABLE  OBJCOPY_ERROR
    )

    if(NOT OBJCOPY_RESULT EQUAL 0)
        message(FATAL_ERROR "Conversion of ${DUMP_FILE} to the stream failed (${OBJCOPY_RESULT}): ${OBJCOPY_ERROR}")
    endif()

    # Count of the leading components of the original path, which are replaced by BUILD_DIR
    # (a drive "D:" is a component)
    string(REPLACE "\\" "/" ORIGINAL_DIR "${ORIGINAL_BUILD_DIR}")
    string(REGEX REPLACE "/+$" "" ORIGINAL_DIR "${ORIGINAL_DIR}")
    string(REPLACE "/" ";" ORIGINAL_PARTS "${ORIGINAL_DIR}")
    list(REMOVE_ITEM ORIGINAL_PARTS "")
    list(LENGTH ORIGINAL_PARTS STRIP_COUNT)

    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E env "GCOV_PREFIX=${BUILD_DIR}" "GCOV_PREFIX_STRIP=${STRIP_COUNT}"
                "${GCOV_TOOL}" merge-stream "${STREAM_FILE}"
        RESULT_VARIABLE MERGE_RESULT
        OUTPUT_VARIABLE MERGE_OUTPUT
        ERROR_VARIABLE  MERGE_ERROR
    )

    file(REMOVE "${STREAM_FILE}")

    if(NOT MERGE_RESULT EQUAL 0)
        message("${MERGE_OUTPUT}${MERGE_ERROR}")
        message(FATAL_ERROR "gcov-tool merge-stream of ${DUMP_FILE} failed (${MERGE_RESULT}).")
    endif()

endfunction(itCoverage_Merge)

#================================== Script ====================================#

# Executed only as the script (-P), not when included by IntegrationTesting_Run.cmake
if(CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)

    cmake_minimum_required(VERSION 3.22)

    foreach(PARAMETER IN ITEMS IT_COV_DUMPS IT_COV_BUILD_DIR IT_OBJCOPY IT_GCOV_TOOL)
        if(NOT ${PARAMETER})
            message(FATAL_ERROR "Parameter ${PARAMETER} is not set.")
        endif()
    endforeach()

    if(NOT IT_COV_ORIGINAL_BUILD_DIR)
        set(IT_COV_ORIGINAL_BUILD_DIR "${IT_COV_BUILD_DIR}")
    endif()

    foreach(DUMP IN LISTS IT_COV_DUMPS)
        message(STATUS "Coverage data: ${DUMP}")
        itCoverage_Merge("${DUMP}" "${IT_COV_BUILD_DIR}" "${IT_COV_ORIGINAL_BUILD_DIR}" "${IT_OBJCOPY}" "${IT_GCOV_TOOL}")
    endforeach()

endif()
