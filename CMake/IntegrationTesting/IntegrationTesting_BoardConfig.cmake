################################################################################
# Author: Mr.Nobody
# file:  IntegrationTesting_BoardConfig.cmake
# brief: Compile definitions of the configuration of a board (ItBoards.json of the
#        project, the configuration of an IT agent - the boards file of the
#        detection, Build/IntegrationTestBoards.json): the integration test
#        firmware (IntegrationTesting.cmake) and the Debug / Release build of a
#        picked board (TARGET_BOARD, Build.cmake) get them.
#
#   features   the fixture of the board - its wiring and the attached ICs:
#              IT_FIXTURE, IT_FEATURE_<X>, IT_FEATURE_<X>_<KEY>=<value>
#              (no "features" = no fixture, IT_FIXTURE not defined)
#   defines    own defines of the board, given as written: <NAME>=<value>
#              ("" = <NAME> without a value)
################################################################################

include_guard(GLOBAL)

#------------------------------------------------------------------------------#
# Compile definitions of the configuration of a board.
#
# DEFINITIONS_VAR  [out]: Compile definitions (list)
# FIXTURE_TEXT_VAR [out]: Features for messages ("X, Y (KEY=value)", "none" for an empty fixture, "" = no fixture)
# DEFINES_TEXT_VAR [out]: Own defines for messages ("A=1, B", "" = none)
# BOARD_CONFIG     [in]:  Configuration of the board (JSON object of the boards file)
# BOARD            [in]:  Board name (messages)
#------------------------------------------------------------------------------#
function(IntegrationTesting_Get_BoardDefinitions DEFINITIONS_VAR FIXTURE_TEXT_VAR DEFINES_TEXT_VAR BOARD_CONFIG BOARD)

    set(DEFINITIONS "")
    set(FEATURES_TEXT "")
    set(DEFINES_TEXT "")

    # Fixture - features
    string(JSON FEATURES_CNT ERROR_VARIABLE FEATURES_ERROR LENGTH "${BOARD_CONFIG}" features)

    if(NOT FEATURES_ERROR)

        list(APPEND DEFINITIONS IT_FIXTURE)
        set(FEATURES_TEXT "")

        set(FEATURE_IDX 0)
        while(FEATURE_IDX LESS FEATURES_CNT)

            string(JSON FEATURE MEMBER "${BOARD_CONFIG}" features ${FEATURE_IDX})

            if(NOT "${FEATURE}" MATCHES "^[A-Za-z0-9_]+$")
                message(FATAL_ERROR "Feature '${FEATURE}' of board ${BOARD} is not a name (letters, digits and '_').")
            endif()

            list(APPEND DEFINITIONS IT_FEATURE_${FEATURE})
            set(FEATURE_TEXT "${FEATURE}")

            string(JSON KEYS_CNT ERROR_VARIABLE KEYS_ERROR LENGTH "${BOARD_CONFIG}" features ${FEATURE})

            if(NOT KEYS_ERROR AND
               KEYS_CNT GREATER 0)

                set(KEYS_TEXT "")
                set(KEY_IDX 0)
                while(KEY_IDX LESS KEYS_CNT)
                    string(JSON KEY   MEMBER "${BOARD_CONFIG}" features ${FEATURE} ${KEY_IDX})
                    string(JSON VALUE GET    "${BOARD_CONFIG}" features ${FEATURE} ${KEY})
                    if(NOT "${KEY}" MATCHES "^[A-Za-z0-9_]+$")
                        message(FATAL_ERROR "Parameter '${KEY}' of feature ${FEATURE} of board ${BOARD} is not a name "
                                            "(letters, digits and '_').")
                    endif()
                    list(APPEND DEFINITIONS "IT_FEATURE_${FEATURE}_${KEY}=${VALUE}")
                    list(APPEND KEYS_TEXT "${KEY}=${VALUE}")
                    math(EXPR KEY_IDX "${KEY_IDX} + 1")
                endwhile()

                list(JOIN KEYS_TEXT ", " KEYS_TEXT)
                string(APPEND FEATURE_TEXT " (${KEYS_TEXT})")

            endif()

            list(APPEND FEATURES_TEXT "${FEATURE_TEXT}")
            math(EXPR FEATURE_IDX "${FEATURE_IDX} + 1")

        endwhile()

        list(JOIN FEATURES_TEXT ", " FEATURES_TEXT)
        # A fixture without features (the board has none of the wiring of the test sets)
        if("${FEATURES_TEXT}" STREQUAL "")
            set(FEATURES_TEXT "none")
        endif()

    endif()

    # Own defines of the board
    string(JSON DEFINES_CNT ERROR_VARIABLE DEFINES_ERROR LENGTH "${BOARD_CONFIG}" defines)

    if(NOT DEFINES_ERROR AND
       DEFINES_CNT GREATER 0)

        set(DEFINE_IDX 0)
        while(DEFINE_IDX LESS DEFINES_CNT)

            string(JSON NAME  MEMBER "${BOARD_CONFIG}" defines ${DEFINE_IDX})
            string(JSON VALUE GET    "${BOARD_CONFIG}" defines ${NAME})

            if(NOT "${NAME}" MATCHES "^[A-Za-z_][A-Za-z0-9_]*$")
                message(FATAL_ERROR "Define '${NAME}' of board ${BOARD} is not a name of a macro.")
            endif()

            if("${VALUE}" STREQUAL "")
                list(APPEND DEFINITIONS "${NAME}")
                list(APPEND DEFINES_TEXT "${NAME}")
            else()
                list(APPEND DEFINITIONS "${NAME}=${VALUE}")
                list(APPEND DEFINES_TEXT "${NAME}=${VALUE}")
            endif()

            math(EXPR DEFINE_IDX "${DEFINE_IDX} + 1")

        endwhile()

        list(JOIN DEFINES_TEXT ", " DEFINES_TEXT)

    endif()

    set(${DEFINITIONS_VAR}  "${DEFINITIONS}"   PARENT_SCOPE)
    set(${FIXTURE_TEXT_VAR} "${FEATURES_TEXT}" PARENT_SCOPE)
    set(${DEFINES_TEXT_VAR} "${DEFINES_TEXT}"  PARENT_SCOPE)

endfunction(IntegrationTesting_Get_BoardDefinitions)

#------------------------------------------------------------------------------#
# Compile definitions of a board of a boards file (the detection,
# Build/IntegrationTestBoards.json).
#
# DEFINITIONS_VAR  [out]: Compile definitions (list)
# FIXTURE_TEXT_VAR [out]: Features for messages (IntegrationTesting_Get_BoardDefinitions)
# DEFINES_TEXT_VAR [out]: Own defines for messages
# BOARDS_FILE      [in]:  Boards file
# BOARD            [in]:  Board name
#------------------------------------------------------------------------------#
function(IntegrationTesting_Get_BoardFileDefinitions DEFINITIONS_VAR
                                                    FIXTURE_TEXT_VAR
                                                    DEFINES_TEXT_VAR
                                                    BOARDS_FILE
                                                    BOARD)

    if(NOT EXISTS "${BOARDS_FILE}")
        message(FATAL_ERROR "${BOARDS_FILE} not found - detect the connected boards first (board ${BOARD}).")
    endif()

    file(READ "${BOARDS_FILE}" BOARDS_CONTENT)
    string(JSON BOARD_CONFIG ERROR_VARIABLE BOARD_ERROR GET "${BOARDS_CONTENT}" boards "${BOARD}")

    if(BOARD_ERROR)
        message(FATAL_ERROR "Board ${BOARD} is not in ${BOARDS_FILE} - detect the connected boards first.")
    endif()

    IntegrationTesting_Get_BoardDefinitions(DEFINITIONS
                                            FIXTURE_TEXT
                                            DEFINES_TEXT
                                            "${BOARD_CONFIG}"
                                            "${BOARD}")

    set(${DEFINITIONS_VAR}  "${DEFINITIONS}"  PARENT_SCOPE)
    set(${FIXTURE_TEXT_VAR} "${FIXTURE_TEXT}" PARENT_SCOPE)
    set(${DEFINES_TEXT_VAR} "${DEFINES_TEXT}" PARENT_SCOPE)

endfunction(IntegrationTesting_Get_BoardFileDefinitions)
