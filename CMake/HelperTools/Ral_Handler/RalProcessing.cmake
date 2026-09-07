################################################################################
#
# Register Abstraction Layer (RAL) processing CMake script.
#
# User shall not directly access RAL module from Micro-Controller Abstraction 
# Layer (MCAL). Instead of that, he shall access generic port files. This makes
# MCU family migration easier and faster. Every LL header file shall have 
# particular port file with generic name
# (e.g. stm32u5xx_ll_usart.h -> Stm32_usart.h).
#
# Following CMake attributes are configurable by user:
# - INPUT_DIR_ARG  : Path to the folder, containing RAL header files. 
# - OUTPUT_DIR_ARG : Path to the folder, where generated port files shall be 
#                    written.
#
################################################################################
cmake_minimum_required(VERSION 3.21)

# Set path to system configuration file
get_filename_component(SYSTEM_CONFIG_FILE_PATH "${CMAKE_CURRENT_LIST_DIR}/../../SysConfig.cmake" REALPATH)

# Include file with system configuration values
include("${SYSTEM_CONFIG_FILE_PATH}")

#==============================================================================#
# Global variables
#==============================================================================#

# Name of template file to be used for RAL interface generation
set(TEMPLATE_NAME "Template_RalPort.h.in")

# Read project root folder path
SysConfig_Get_ProjectRootPath(PROJECT_ROOT_PATH)

#------------------------------------------------------------------------------#
# Processing all RAL header files and generation of its port headers.  
#------------------------------------------------------------------------------#
function(RalProcessing_GenerateRalPorts INPUT_DIR_ARG OUTPUT_DIR_ARG)

    # Check, if user specified path to the RAL header files
    if(NOT INPUT_DIR_ARG OR INPUT_DIR_ARG STREQUAL "")
        set(INPUT_DIR "${PROJECT_ROOT_PATH}/Bsp/Ral/Stm32_Drv/Inc")
    else()
        set(INPUT_DIR "${INPUT_DIR_ARG}")
    endif()

    # Check, if user specified path to the output folder.
    if(NOT OUTPUT_DIR_ARG OR OUTPUT_DIR_ARG STREQUAL "")
        set(OUTPUT_DIR "${PROJECT_ROOT_PATH}/Bsp/Ral/Port")
    else()
        set(OUTPUT_DIR "${OUTPUT_DIR_ARG}/Port")
    endif()

    set(TEMPLATE_FILE "${TEMPLATE_FILE_PATH}/${TEMPLATE_NAME}")
    
    file(MAKE_DIRECTORY "${OUTPUT_DIR}")
    
    file(GLOB LL_HEADERS "${INPUT_DIR}/stm32*xx_ll_*.h")
    if(LL_HEADERS STREQUAL "")
        message(FATAL_ERROR "No LL headers found in ${INPUT_DIR}")
    endif()
    
    list(GET LL_HEADERS 0 FIRST_LL_HEADER)
    get_filename_component(FIRST_LL_NAME "${FIRST_LL_HEADER}" NAME_WE)

    string(REGEX MATCH "^(stm32[a-z0-9]+xx)_ll_.*" _ "${FIRST_LL_NAME}")
    if(NOT CMAKE_MATCH_1)
        message(FATAL_ERROR "Unable to extract family prefix from '${FIRST_LL_NAME}'")
    endif()

    set(FAMILY_HEADER_PREFIX "${CMAKE_MATCH_1}")
    set(HEADER_NAME "${FAMILY_HEADER_PREFIX}")
    
    set(MODULE_NAME "${CMAKE_MATCH_1}")
    set(OUTPUT_FILE "${OUTPUT_DIR}/Stm32.h")
    
    string(TOUPPER "${MODULE_NAME}" MODULE_NAME_UPPER)
    configure_file("${TEMPLATE_FILE}" "${OUTPUT_FILE}" @ONLY)
    
    
    foreach(HEADER_PATH IN LISTS LL_HEADERS)
        get_filename_component(HEADER_NAME "${HEADER_PATH}" NAME_WE)
    
        string(REGEX MATCH "stm32.*xx_ll_([a-zA-Z0-9_]+)" _ "${HEADER_NAME}")
        if(NOT CMAKE_MATCH_1)
            message(WARNING "Skipping file '${HEADER_NAME}.h' - does not match pattern.")
            continue()
        endif()
    
        set(MODULE_NAME "${CMAKE_MATCH_1}")
        set(OUTPUT_FILE "${OUTPUT_DIR}/Stm32_${MODULE_NAME}.h")
        
        string(TOUPPER "${MODULE_NAME}" MODULE_NAME_UPPER)
    
        configure_file("${TEMPLATE_FILE}" "${OUTPUT_FILE}" @ONLY)
        message(STATUS "Generated: ${OUTPUT_FILE}")
    endforeach()

endfunction()

#==============================================================================#
# Main functionality
#==============================================================================#
# Check if run directly with cmake -P
if(CMAKE_SCRIPT_MODE_FILE AND 
   CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE AND
   DEFINED INPUT_DIR_ARG AND
   DEFINED OUTPUT_DIR_ARG)
   
    message(STATUS "Script RalProcessing.cmake executed in script mode.")
    RalProcessing_GenerateRalPorts()
endif()