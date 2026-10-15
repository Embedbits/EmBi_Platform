################################################################################
# Author: Mr.Nobody
# file:  Coverage_Summary.cmake
# brief: Prints the coverage of the tests as a table (gcovr JSON summary).
#
# Called by the targets <Test>_CoverageSummary (see Coverage.cmake) or from the
# command line, it needs nothing else than CMake:
#   cmake -DCOV_SUMMARY_FILE=<coverage-summary.json> [-DCOV_GROUP=dir|file]
#         [-DCOV_FILTER=<regex of the path>] [-DCOV_MIN_LINES=<percent>]
#         [-DCOV_TITLE=<text>] -P Coverage_Summary.cmake
#
#   COV_SUMMARY_FILE - JSON summary of gcovr (--json-summary), written by the
#                      report of the tests (<build>/Coverage/coverage-summary.json)
#   COV_GROUP        - dir (default): one row per folder of the sources (a module
#                      has one folder), file: one row per source file
#   COV_FILTER       - only files whose path matches the regular expression (the environment
#                      variable COV_FILTER when the parameter is not given - the targets of the
#                      framework have no parameter for it)
#   COV_MIN_LINES    - the script fails if the line coverage of the printed
#                      files is lower (percent, 0 = not checked)
#
# Included by Coverage_Report.cmake (the table is printed after the report).
################################################################################

include_guard(GLOBAL)

#================================ Functions ===================================#

#------------------------------------------------------------------------------#
# Percentage with one decimal place rounded down (99.96 % is not shown as
# 100.0 %), "-" if there is nothing to cover.
#
# PERCENT_VAR [out]: Text of the percentage
# COVERED     [in]:  Covered count
# TOTAL       [in]:  Total count
#------------------------------------------------------------------------------#
function(coverageSummary_Percent PERCENT_VAR COVERED TOTAL)

    if(TOTAL EQUAL 0)

        set(TEXT "-")

    else()

        math(EXPR TENTHS   "( ${COVERED} * 1000 ) / ${TOTAL}")
        math(EXPR WHOLE    "${TENTHS} / 10")
        math(EXPR FRACTION "${TENTHS} % 10")

        set(TEXT "${WHOLE}.${FRACTION}")

    endif()

    set(${PERCENT_VAR} "${TEXT}" PARENT_SCOPE)

endfunction(coverageSummary_Percent)


#------------------------------------------------------------------------------#
# Text completed by spaces to the width.
#
# TEXT_VAR [out]: Completed text
# TEXT     [in]:  Text
# WIDTH    [in]:  Width
# ALIGN    [in]:  LEFT / RIGHT
#------------------------------------------------------------------------------#
function(coverageSummary_Pad TEXT_VAR TEXT WIDTH ALIGN)

    string(LENGTH "${TEXT}" TEXT_LENGTH)

    set(SPACES "")

    if(TEXT_LENGTH LESS WIDTH)
        math(EXPR SPACES_CNT "${WIDTH} - ${TEXT_LENGTH}")
        string(REPEAT " " ${SPACES_CNT} SPACES)
    endif()

    if(ALIGN STREQUAL "RIGHT")
        set(${TEXT_VAR} "${SPACES}${TEXT}" PARENT_SCOPE)
    else()
        set(${TEXT_VAR} "${TEXT}${SPACES}" PARENT_SCOPE)
    endif()

endfunction(coverageSummary_Pad)


#------------------------------------------------------------------------------#
# Text of one table row: "<covered>/<total> <percent>" of lines, functions and
# branches of a group.
#
# ROW_VAR [out]: Text of the row
# NAME    [in]:  Name of the group
# NAME_WIDTH [in]: Width of the first column
# LC LT FC FT BC BT [in]: Covered / total lines, functions, branches
#------------------------------------------------------------------------------#
function(coverageSummary_Row ROW_VAR NAME NAME_WIDTH LC LT FC FT BC BT)

    coverageSummary_Pad(ROW "${NAME}" ${NAME_WIDTH} LEFT)

    foreach(KIND IN ITEMS L F B)

        set(COVERED "${${KIND}C}")
        set(TOTAL   "${${KIND}T}")

        coverageSummary_Percent(PERCENT ${COVERED} ${TOTAL})

        coverageSummary_Pad(COUNTS  "${COVERED}/${TOTAL}" 13 RIGHT)
        coverageSummary_Pad(PERCENT "${PERCENT}%"           7 RIGHT)

        string(APPEND ROW "  ${COUNTS} ${PERCENT}")

    endforeach()

    set(${ROW_VAR} "${ROW}" PARENT_SCOPE)

endfunction(coverageSummary_Row)


#------------------------------------------------------------------------------#
# Prints the table of the coverage summary.
#
# TOTAL_LINES_VAR [out]: Percent of the covered lines (integer, rounded down)
# SUMMARY_FILE    [in]:  JSON summary of gcovr
# GROUP           [in]:  dir / file
# FILTER          [in]:  Regular expression of the path ("" = all files)
# TITLE           [in]:  Title of the table
#------------------------------------------------------------------------------#
function(coverageSummary_Print TOTAL_LINES_VAR SUMMARY_FILE GROUP FILTER TITLE)

    if(NOT EXISTS "${SUMMARY_FILE}")
        message(FATAL_ERROR "Coverage summary ${SUMMARY_FILE} does not exist. Create the report first "
                            "(run the tests and build the target of the coverage report).")
    endif()

    file(READ "${SUMMARY_FILE}" SUMMARY_JSON)

    string(JSON FILES_CNT LENGTH "${SUMMARY_JSON}" files)

    set(GROUP_KEYS "")
    set(TOTAL_VALUES 0 0 0 0 0 0)

    if(FILES_CNT GREATER 0)

        math(EXPR FILES_LAST "${FILES_CNT} - 1")

        foreach(FILE_IDX RANGE ${FILES_LAST})

            string(JSON FILE_JSON GET "${SUMMARY_JSON}" files ${FILE_IDX})
            string(JSON FILE_NAME GET "${FILE_JSON}" filename)

            if(NOT "${FILTER}" STREQUAL "" AND NOT FILE_NAME MATCHES "${FILTER}")
                continue()
            endif()

            if(GROUP STREQUAL "file")
                set(KEY "${FILE_NAME}")
            else()
                get_filename_component(KEY "${FILE_NAME}" DIRECTORY)
                if("${KEY}" STREQUAL "")
                    set(KEY ".")
                endif()
            endif()

            string(MD5 KEY_ID "${KEY}")

            if(NOT DEFINED COVERAGE_GROUP_${KEY_ID})
                list(APPEND GROUP_KEYS "${KEY}")
                set(COVERAGE_GROUP_${KEY_ID} 0 0 0 0 0 0)
            endif()

            set(VALUES "")

            foreach(FIELD IN ITEMS line_covered line_total function_covered function_total branch_covered branch_total)
                string(JSON VALUE ERROR_VARIABLE VALUE_ERROR GET "${FILE_JSON}" ${FIELD})
                if(VALUE_ERROR OR "${VALUE}" STREQUAL "null" OR "${VALUE}" STREQUAL "")
                    set(VALUE 0)
                endif()
                list(APPEND VALUES ${VALUE})
            endforeach()

            # Sums of the group and of the table
            set(SUM_GROUP "")
            set(SUM_TOTAL "")

            foreach(VALUE_IDX RANGE 5)
                list(GET VALUES                       ${VALUE_IDX} VALUE)
                list(GET COVERAGE_GROUP_${KEY_ID}     ${VALUE_IDX} GROUP_VALUE)
                list(GET TOTAL_VALUES                 ${VALUE_IDX} TOTAL_VALUE)
                math(EXPR GROUP_VALUE "${GROUP_VALUE} + ${VALUE}")
                math(EXPR TOTAL_VALUE "${TOTAL_VALUE} + ${VALUE}")
                list(APPEND SUM_GROUP "${GROUP_VALUE}")
                list(APPEND SUM_TOTAL "${TOTAL_VALUE}")
            endforeach()

            set(COVERAGE_GROUP_${KEY_ID} ${SUM_GROUP})
            set(TOTAL_VALUES             ${SUM_TOTAL})

        endforeach()

    endif()

    list(SORT GROUP_KEYS)

    # Width of the first column
    set(NAME_WIDTH 5)

    foreach(KEY IN LISTS GROUP_KEYS)
        string(LENGTH "${KEY}" KEY_LENGTH)
        if(KEY_LENGTH GREATER NAME_WIDTH)
            set(NAME_WIDTH ${KEY_LENGTH})
        endif()
    endforeach()

    if(GROUP STREQUAL "file")
        set(NAME_TITLE "File")
    else()
        set(NAME_TITLE "Folder")
    endif()

    coverageSummary_Pad(HEADER_NAME "${NAME_TITLE}" ${NAME_WIDTH} LEFT)
    coverageSummary_Pad(HEADER_L "Lines"     21 RIGHT)
    coverageSummary_Pad(HEADER_F "Functions" 21 RIGHT)
    coverageSummary_Pad(HEADER_B "Branches"  21 RIGHT)

    string(LENGTH "${HEADER_NAME}  ${HEADER_L}  ${HEADER_F}  ${HEADER_B}" LINE_LENGTH)
    string(REPEAT "-" ${LINE_LENGTH} LINE)

    set(TABLE "")

    if(NOT "${TITLE}" STREQUAL "")
        string(APPEND TABLE "${TITLE}\n")
    endif()

    string(APPEND TABLE "${LINE}\n${HEADER_NAME}  ${HEADER_L}  ${HEADER_F}  ${HEADER_B}\n${LINE}\n")

    foreach(KEY IN LISTS GROUP_KEYS)

        string(MD5 KEY_ID "${KEY}")
        list(GET COVERAGE_GROUP_${KEY_ID} 0 LC)
        list(GET COVERAGE_GROUP_${KEY_ID} 1 LT)
        list(GET COVERAGE_GROUP_${KEY_ID} 2 FC)
        list(GET COVERAGE_GROUP_${KEY_ID} 3 FT)
        list(GET COVERAGE_GROUP_${KEY_ID} 4 BC)
        list(GET COVERAGE_GROUP_${KEY_ID} 5 BT)

        coverageSummary_Row(ROW "${KEY}" ${NAME_WIDTH} ${LC} ${LT} ${FC} ${FT} ${BC} ${BT})

        string(APPEND TABLE "${ROW}\n")

    endforeach()

    list(GET TOTAL_VALUES 0 LC)
    list(GET TOTAL_VALUES 1 LT)
    list(GET TOTAL_VALUES 2 FC)
    list(GET TOTAL_VALUES 3 FT)
    list(GET TOTAL_VALUES 4 BC)
    list(GET TOTAL_VALUES 5 BT)

    coverageSummary_Row(ROW "TOTAL" ${NAME_WIDTH} ${LC} ${LT} ${FC} ${FT} ${BC} ${BT})

    string(APPEND TABLE "${LINE}\n${ROW}\n${LINE}")

    message(NOTICE "${TABLE}")

    if(LT EQUAL 0)
        set(LINES_PERCENT 0)
    else()
        math(EXPR LINES_PERCENT "( ${LC} * 100 ) / ${LT}")
    endif()

    set(${TOTAL_LINES_VAR} "${LINES_PERCENT}" PARENT_SCOPE)

endfunction(coverageSummary_Print)


#------------------------------------------------------------------------------#
# Checks the minimum of the line coverage, fails if it is not reached.
#
# LINES_PERCENT [in]: Percent of the covered lines (integer)
# MIN_LINES     [in]: Required minimum (percent, 0 = not checked)
#------------------------------------------------------------------------------#
function(coverageSummary_Check LINES_PERCENT MIN_LINES)

    if(MIN_LINES AND LINES_PERCENT LESS MIN_LINES)
        message(FATAL_ERROR "Line coverage ${LINES_PERCENT} % is lower than the required ${MIN_LINES} %.")
    endif()

endfunction(coverageSummary_Check)

#================================== Script ====================================#

# Executed only as the script (-P), not when included by Coverage_Report.cmake
if(CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)

    if(NOT COV_SUMMARY_FILE)
        message(FATAL_ERROR "Parameter COV_SUMMARY_FILE is not set.")
    endif()

    if(NOT COV_GROUP)
        set(COV_GROUP "dir")
    elseif(NOT COV_GROUP MATCHES "^(dir|file)$")
        message(FATAL_ERROR "Invalid value '${COV_GROUP}' of COV_GROUP (dir / file).")
    endif()

    if(NOT COV_FILTER AND DEFINED ENV{COV_FILTER})
        set(COV_FILTER "$ENV{COV_FILTER}")
    endif()

    coverageSummary_Print(COV_LINES_PERCENT "${COV_SUMMARY_FILE}" "${COV_GROUP}" "${COV_FILTER}" "${COV_TITLE}")
    coverageSummary_Check("${COV_LINES_PERCENT}" "${COV_MIN_LINES}")

endif()
