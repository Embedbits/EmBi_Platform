# Usage: cmake -DMIDDLEWARES_DIR="./path/to/Middlewares" -P BatchLibConvert.cmake

cmake_minimum_required(VERSION 3.12...4.1.2)

if(NOT DEFINED MIDDLEWARES_DIR)
    message(FATAL_ERROR "Error: 'MIDDLEWARES_DIR' is missing.")
endif()

get_filename_component(BASE_PATH "${MIDDLEWARES_DIR}" ABSOLUTE)
message(STATUS "Scanning for libraries in: ${BASE_PATH}")

file(GLOB ITEMS RELATIVE "${BASE_PATH}" "${BASE_PATH}/*")

set(COUNT 0)
set(LIBS_CONTENT "")

foreach(ITEM ${ITEMS})
    set(FULL_PATH "${BASE_PATH}/${ITEM}")
    
    if(IS_DIRECTORY "${FULL_PATH}")
        set(LIB_NAME "${ITEM}")
        
        message(STATUS "--------------------------------------------------")
        message(STATUS "Processing: ${LIB_NAME}")

        # Calls LibCMakeConvert.cmake instead of the old name
        execute_process(
            COMMAND ${CMAKE_COMMAND}
                -DMODULE_NAME=${LIB_NAME}
                -DMODULE_PATH=${FULL_PATH}
                -P "${CMAKE_CURRENT_LIST_DIR}/LibCMakeConvert.cmake"
            RESULT_VARIABLE RET_CODE
        )

        if(RET_CODE EQUAL 0)
            math(EXPR COUNT "${COUNT} + 1")
            string(APPEND LIBS_CONTENT "add_subdirectory(${LIB_NAME})\n")
        else()
            message(SEND_ERROR "Failed to generate CMake for ${LIB_NAME}")
        endif()
    endif()
endforeach()

# Write Libs.cmake
set(LIBS_FILE "${BASE_PATH}/Libs.cmake")
file(WRITE "${LIBS_FILE}" "${LIBS_CONTENT}")

message(STATUS "--------------------------------------------------")
message(STATUS "Batch conversion complete. Processed ${COUNT} libraries.")