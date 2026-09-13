
################################################################################
# file:  CMakeLists.txt
# brief: Template "CMakeLists.txt" for building of executables and static libraries.
#
# usage: Edit "VARIABLES"-section to suit project requirements.
#        For debug build:
#          cmake -DCMAKE_TOOLCHAIN_FILE=cubeide-gcc.cmake  -S ./ -B Debug -G"Unix Makefiles" -DCMAKE_BUILD_TYPE=Debug
#          make -C Debug VERBOSE=1
#        For release build:
#          cmake -DCMAKE_TOOLCHAIN_FILE=cubeide-gcc.cmake  -S ./ -B Release -G"Unix Makefiles" -DCMAKE_BUILD_TYPE=Release
#          make -C Release VERBOSE=1
################################################################################
#
# Necessary operators:
#
# CMAKE_BUILD_TYPE
#    - Debug
#    - Release
#    - UnitTest
#    - IntegrationTest
#
# MCU_TYPE
#    - STM32WXXXyZ
#      Where:
#       W - STM32 Family ID (single letter)
#       XXX - STM32 Family specification (three symbols)
#       y - Must stay unchanged
#       Z - Flash size identification ( A - 0K,6 - 32K, 8 - 64K, B - 128K ...)
#
# Optional operators. If not specified default value will be used
#
# CMAKE_VERBOSE_MAKEFILE
#    - OFF (default)
#    - ON
#
# DOXYGEN_ENABLED
#    - OFF (default)
#    - ON
#
#
################################################################################

cmake_minimum_required(VERSION 3.22)

#=============================== Constant values ==============================#

#======================= Target MCU parameter value check =====================#
# Check if TARGET_MCU is defined and valid, and set the corresponding definitions
if(NOT DEFINED TARGET_MCU)

    if(CMAKE_BUILD_TYPE STREQUAL "UnitTest")
        message(STATUS "TARGET_MCU not defined. Unit test build will be performed.")
    else()
        message(FATAL_ERROR "TARGET_MCU not defined! Build is termianted")
    endif()

else()

    # Check if the target MCU starts with STM32
    string(REGEX MATCH "^STM32" _match "${TARGET_MCU}")

    if(NOT _match)

        message(FATAL_ERROR "Invalid value '${TARGET_MCU}' of TARGET_MCU.")

    else()

        # Print MCU identification
        message(STATUS "Target MCU selected for build: '${TARGET_MCU}'.")
        
        # Store user required value into temporary variable
        set(TARGET_MCU_TEMP "${TARGET_MCU}")
        
        # Provide global variable storing full MCU name (for linker file generator)
        set(TARGET_MCU_FULL_NAME "${TARGET_MCU_TEMP}")
        
        # Generation of MCU line prefix (e.g. STM32G411, STM32F431...) - this is the
        # family+line part of the part number, BEFORE the pin-count/flash-size/package
        # suffix. It is NOT yet a valid CMSIS compile define on its own.
        string(REGEX MATCH "STM32([A-Z][0-9][A-Z0-9][0-9])" _ ${TARGET_MCU_TEMP})
        set(MCU_LINE_PREFIX "STM32${CMAKE_MATCH_1}")

        # Generation of MCU_FAMILY_ID value (STM32U5xx, STM32F4xx...)
        string(REGEX MATCH "STM32([A-Z][0-9])" _ ${TARGET_MCU_TEMP})
        set(MCU_FAMILY_ID "STM32${CMAKE_MATCH_1}xx")
        message(STATUS "MCU_FAMILY_ID: ${MCU_FAMILY_ID}")
        add_definitions(-D"${MCU_FAMILY_ID}")

        # Not every STM32 family uses a generic "xx" compile define for every line -
        # some (e.g. STM32G411) only define flash-size-specific macros (STM32G411xB /
        # STM32G411xC), never a plain STM32G411xx. Blindly appending "xx" produced an
        # invalid macro for those lines, which the CMSIS device header then rejected
        # with "Please select first the target STM32<family>xx device". Instead, read
        # the ACTUAL set of macros the pinned CMSIS header for this family accepts
        # (Bsp/Ral/CMSIS_ST/Include/stm32<family>xx.h) and pick the one that matches
        # this MCU's line - disambiguating by the flash-size character from the full
        # part number when the header defines more than one variant for this line.
        string(TOLOWER "${MCU_FAMILY_ID}" MCU_FAMILY_HEADER_NAME)
        set(MCU_FAMILY_HEADER_PATH "${CMAKE_SOURCE_DIR}/Bsp/Ral/CMSIS_ST/Include/${MCU_FAMILY_HEADER_NAME}.h")

        set(MCU_ID "")

        if(EXISTS "${MCU_FAMILY_HEADER_PATH}")
            file(STRINGS "${MCU_FAMILY_HEADER_PATH}" MCU_HEADER_DEFINE_LINES REGEX "#(if|elif) *defined *\(STM32[A-Za-z0-9]+\)")

            set(MCU_HEADER_CANDIDATES "")
            foreach(DEFINE_LINE ${MCU_HEADER_DEFINE_LINES})
                string(REGEX MATCH "defined *\((STM32[A-Za-z0-9]+)\)" _ "${DEFINE_LINE}")
                if(CMAKE_MATCH_1)
                    list(APPEND MCU_HEADER_CANDIDATES "${CMAKE_MATCH_1}")
                endif()
            endforeach()

            # Keep only candidates that actually belong to this exact line (plain prefix
            # match, not regex, so e.g. "STM32G41" can never accidentally match "STM32G411").
            set(MCU_LINE_MATCHES "")
            foreach(CANDIDATE ${MCU_HEADER_CANDIDATES})
                string(FIND "${CANDIDATE}" "${MCU_LINE_PREFIX}" MATCH_POS)
                if(MATCH_POS EQUAL 0)
                    list(APPEND MCU_LINE_MATCHES "${CANDIDATE}")
                endif()
            endforeach()

            list(LENGTH MCU_LINE_MATCHES MCU_LINE_MATCH_COUNT)

            if(MCU_LINE_MATCH_COUNT EQUAL 1)
                list(GET MCU_LINE_MATCHES 0 MCU_ID)
            elseif(MCU_LINE_MATCH_COUNT GREATER 1)
                # More than one variant exists for this line (e.g. STM32G411xB / STM32G411xC) -
                # disambiguate using the flash-size character from the full part number, which
                # sits right after the pin-count letter that follows MCU_LINE_PREFIX
                # (e.g. in STM32G411C6Tx: "C" = pin-count, "6" = flash size).
                string(LENGTH "${MCU_LINE_PREFIX}" MCU_LINE_PREFIX_LEN)
                string(SUBSTRING "${TARGET_MCU_TEMP}" ${MCU_LINE_PREFIX_LEN} -1 MCU_SUFFIX_REMAINDER)
                string(SUBSTRING "${MCU_SUFFIX_REMAINDER}" 1 1 MCU_FLASH_CODE)

                foreach(CANDIDATE ${MCU_LINE_MATCHES})
                    if(CANDIDATE MATCHES "${MCU_FLASH_CODE}$")
                        set(MCU_ID "${CANDIDATE}")
                        break()
                    endif()
                endforeach()

                if("${MCU_ID}" STREQUAL "")
                    message(FATAL_ERROR "TARGET_MCU '${TARGET_MCU_TEMP}' matches line '${MCU_LINE_PREFIX}', but the pinned CMSIS header '${MCU_FAMILY_HEADER_PATH}' only defines: ${MCU_LINE_MATCHES} (none matches flash code '${MCU_FLASH_CODE}'). This exact part is not supported by the currently checked-out Bsp/Ral/CMSIS_ST - pick one of the listed defines, or update the BSP.")
                endif()
            endif()
        endif()

        if("${MCU_ID}" STREQUAL "")
            # Header missing at configure time, or none of its defines matched this line at
            # all (unusual naming) - fall back to the previous best-effort "xx" guess, but
            # warn loudly since the CMSIS header may well reject it.
            set(MCU_ID "${MCU_LINE_PREFIX}xx")
            message(WARNING "Could not verify TARGET_MCU define against '${MCU_FAMILY_HEADER_PATH}' - falling back to '${MCU_ID}', which the CMSIS header may not accept.")
        endif()

        message(STATUS "MCU_ID: ${MCU_ID}")
        add_definitions(-D"${MCU_ID}")

        set(TARGET_MCU "${MCU_ID}")
    
    endif()
    
endif()

#=========================== Build type values check ==========================#
# Check if CMAKE_BUILD_TYPE is defined and valid, and set the corresponding messages
if(NOT DEFINED CMAKE_BUILD_TYPE)

    message(STATUS "Build type not defined. Default value is set to 'Debug'")

    set(CMAKE_BUILD_TYPE "Debug")

else()

    # Check if the value is correct
    list(FIND BUILD_TYPE_ALLOWED_VALUES "${CMAKE_BUILD_TYPE}" INDEX)

    if(INDEX EQUAL -1)
        message(FATAL_ERROR "Invalid value '${CMAKE_BUILD_TYPE}' of CMAKE_BUILD_TYPE. Allowed values are: ${BUILD_TYPE_ALLOWED_VALUES}")
    else()
        message(STATUS "Build type is set to: '${CMAKE_BUILD_TYPE}'.")
    endif()
endif()  

#================================ MCU build ===================================#
if (CMAKE_BUILD_TYPE STREQUAL "Debug" OR CMAKE_BUILD_TYPE STREQUAL "Release")

    include("${CMAKE_CURRENT_LIST_DIR}/Flags.cmake")

    # Build configuration flags (Necessary part before project build)
    set(CMAKE_C_FLAGS                   "${ENABLE_ALL_WARNINGS} ${ENABLE_EXTRA_WARNINGS} ${REMOVE_UNUSED_DATA} ${REMOVE_UNUSED_FUNCTIONS} ${LINKER_NOSYS}")

    # BSP part processing (Needs to be processed first because of MCU configuration)
    if(EXISTS "${CMAKE_SOURCE_DIR}/Bsp/Bsp.cmake")
        include("${CMAKE_SOURCE_DIR}/Bsp/Bsp.cmake")
    else()
        message(WARNING "BSP module not found. Skipping...")
    endif()
    
    # Middlewares part processing
    if(EXISTS "${CMAKE_SOURCE_DIR}/Middlewares/Middlewares.cmake")
        include("${CMAKE_SOURCE_DIR}/Middlewares/Middlewares.cmake")
    else()
        message(STATUS "Middlewares module not found. Skipping...")
    endif()
    
    # Application part processing
    if(EXISTS "${CMAKE_SOURCE_DIR}/Application/App.cmake")
        include("${CMAKE_SOURCE_DIR}/Application/App.cmake")
    else()
        message(WARNING "Application module not found. Skipping...")
    endif()
    
    # Build necessary flags
    set(CMAKE_C_FLAGS                   "${CMAKE_C_FLAGS} ${ENABLE_GC_SECTIONS}")
    set(CMAKE_C_FLAGS                   "${CMAKE_C_FLAGS} ${LINKER_START_GROUP} ${LINK_LIB_C} ${LINK_LIB_MATH} ${LINKER_END_GROUP}")
    set(CMAKE_C_FLAGS                   "${CMAKE_C_FLAGS} ${PRINT_HEADER_DEPENDENCIES}")
    set(CMAKE_C_FLAGS                   "${CMAKE_C_FLAGS} ${PRINT_MEMORY_USAGE}")

    set(CMAKE_CXX_FLAGS                 "${CMAKE_CXX_FLAGS} ${CMAKE_C_FLAGS} ${LINKER_START_GROUP} ${LINK_LIB_STDCPP} ${LINK_LIB_SUPCXX} ${LINKER_END_GROUP}")

    # Update linker script path
    set(CMAKE_C_FLAGS                   "${CMAKE_C_FLAGS} -T \"${LINKER_SCRIPT}\" -Wl,-Map=${PROJECT_NAME}.map")
    set(CMAKE_CXX_FLAGS                 "${CMAKE_CXX_FLAGS} -T \"${LINKER_SCRIPT}\" -Wl,-Map=${PROJECT_NAME}.map")

    # Create an executable object type
    add_executable(${CMAKE_PROJECT_NAME} ${CMAKE_CURRENT_LIST_DIR}/Platform.c)

    target_compile_definitions(${CMAKE_PROJECT_NAME}
        INTERFACE
        USE_HAL_DRIVER                  # Set using of ST's RAL
        ${TARGET_MCU}                   # Set definition of target MCU
        $<$<CONFIG:Debug>:DEBUG>        # Set uppercase "DEBUG" if build type is "Debug"
        $<$<CONFIG:Release>:RELEASE>    # Set uppercase "RELEASE" if build type is "Release"
        ${CMAKE_BUILD_TYPE}             # Set definition of build type
    )


    # Link directories setup
    target_link_directories(${CMAKE_PROJECT_NAME}
        PRIVATE
    )

    # Add sources to executable
    target_sources(${PROJECT_NAME}
        PRIVATE
    )

    # Add include paths
    target_include_directories(${CMAKE_PROJECT_NAME}
        PRIVATE
    )

    # Add project symbols (macros)
    target_compile_definitions(${CMAKE_PROJECT_NAME}
        PRIVATE
    ) 
    
    # Add linked libraries
    target_link_libraries(${CMAKE_PROJECT_NAME}
        StartUp_Lib
        BspMain_Lib
    )
    
#============================ Unit Testing Build ==============================#
elseif(CMAKE_BUILD_TYPE STREQUAL "UnitTest")

    # Configure project modules
    set(PROJECT_INCLUDE_LIST "")
    
    if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/UnitTesting/UnitTesting.cmake")
        # Include unit testing functionality
        include("${CMAKE_CURRENT_LIST_DIR}/UnitTesting/UnitTesting.cmake")
    else()
        message(FATAL_ERROR "Unit testing module not found.")
    endif()
    
    find_unit_tests("${CMAKE_SOURCE_DIR}/Application/")
    find_unit_tests("${CMAKE_SOURCE_DIR}/Middlewares/")
    find_unit_tests("${CMAKE_SOURCE_DIR}/Bsp/")

endif()

#========================= Documentation generation ===========================#
if(DOXYGEN_ENABLED)
    
    set(DOXYGEN_PROJECT_NAME "${PROJECT_NAME}")
    Doxygen_Generate()
    
endif()


# Validate that STM32CubeMX code is compatible with C standard
if(CMAKE_C_STANDARD LESS 11)
    message(ERROR "Generated code requires C11 or higher")
endif()
