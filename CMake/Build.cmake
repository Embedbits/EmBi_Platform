
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
        
        # Generation of MCU_ID value (STM32U5A5xx, STM32F431xx...)
        string(REGEX MATCH "STM32([A-Z][0-9][A-Z0-9][0-9])" _ ${TARGET_MCU_TEMP})
        set(MCU_ID "STM32${CMAKE_MATCH_1}xx")
        message(STATUS "MCU_ID: ${MCU_ID}")
        add_definitions(-D"STM32${MCU_ID}")
        
        # Generation of MCU_FAMILY_ID value (STM32U5xx, STM32F4xx...)
        string(REGEX MATCH "STM32([A-Z][0-9])" _ ${TARGET_MCU_TEMP})
        set(MCU_FAMILY_ID "STM32${CMAKE_MATCH_1}xx")
        message(STATUS "MCU_FAMILY_ID: ${MCU_FAMILY_ID}")
        add_definitions(-D"${MCU_FAMILY_ID}")
        
        set(TARGET_MCU "${MCU_ID}")

        add_definitions(-D"${TARGET_MCU}")
    
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

#======================= Documentation availability ===========================#
# Modules register their sources by Doxygen_AddPath() (condition
# DOXYGEN_AVAILABLE) - available if the documentation is enabled and doxygen
# artifact is loaded (ArtifactsConfig.txt).
set(DOXYGEN_AVAILABLE "OFF")

if(DOXYGEN_ENABLED)
    if(COMMAND Doxygen_AddPath AND COMMAND Doxygen_Generate)
        set(DOXYGEN_AVAILABLE "ON")
    else()
        message(WARNING "DOXYGEN_ENABLED is ON but doxygen artifact is not loaded (ArtifactsConfig.txt) - documentation is not generated.")
    endif()
endif()

#================================ MCU build ===================================#
# "IntegrationTest" is MCU build too - modules are built for target exactly as
# in firmware, instead of project firmware every registered integration test
# creates its own test firmware (see IntegrationTesting/IntegrationTesting.cmake).
if (CMAKE_BUILD_TYPE STREQUAL "Debug" OR CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "IntegrationTest")

    include("${CMAKE_CURRENT_LIST_DIR}/Flags.cmake")

    # Build configuration flags (Necessary part before project build)
    set(CMAKE_C_FLAGS                   "${ENABLE_ALL_WARNINGS} ${ENABLE_EXTRA_WARNINGS} ${REMOVE_UNUSED_DATA} ${REMOVE_UNUSED_FUNCTIONS} ${LINKER_NOSYS} ${LINKER_NOSTARTFILES}")

    if(CMAKE_BUILD_TYPE STREQUAL "IntegrationTest")
        if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/IntegrationTesting/IntegrationTesting.cmake")
            # Include integration testing functionality (sets INTEGRATION_TESTING_AVAILABLE)
            include("${CMAKE_CURRENT_LIST_DIR}/IntegrationTesting/IntegrationTesting.cmake")
        else()
            message(FATAL_ERROR "Integration testing module not found.")
        endif()
    endif()

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

    if(CMAKE_BUILD_TYPE STREQUAL "IntegrationTest")

        # Creation of all registered integration test firmwares (no project firmware)
        IntegrationTesting_Generate()

    else()

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

    endif()

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

    # Modules are processed as in MCU build. Every module registers its unit tests
    # by UnitTesting_AddPath() (condition UNIT_TESTING_AVAILABLE). Module libraries
    # are not built for host, only the tests (see UnitTesting_Generate).

    # BSP part processing (MCU dependent, needs TARGET_MCU)
    if(NOT DEFINED TARGET_MCU)
        message(STATUS "TARGET_MCU not defined. BSP unit tests will be skipped.")
    elseif(EXISTS "${CMAKE_SOURCE_DIR}/Bsp/Bsp.cmake")
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
        message(STATUS "Application module not found. Skipping...")
    endif()

    # Creation of all registered unit tests
    UnitTesting_Generate()

endif()

#========================= Documentation generation ===========================#
if(DOXYGEN_AVAILABLE STREQUAL "ON")

    set(DOXYGEN_PROJECT_NAME "${PROJECT_NAME}")

    # C firmware settings, values defined by the project before are kept
    if(NOT DEFINED DOXYGEN_OPTIMIZE_OUTPUT_FOR_C)
        set(DOXYGEN_OPTIMIZE_OUTPUT_FOR_C YES)
    endif()

    # Static functions and variables are most of the modules implementation
    if(NOT DEFINED DOXYGEN_EXTRACT_STATIC)
        set(DOXYGEN_EXTRACT_STATIC YES)
    endif()

    if(NOT DEFINED DOXYGEN_FILE_PATTERNS)
        set(DOXYGEN_FILE_PATTERNS *.c *.h *.cpp *.hpp *.md)
    endif()

    # Code is documented as compiled - compile definitions of the project
    # (MCU, MCU family...), GCC attributes are ignored
    if(NOT DEFINED DOXYGEN_PREDEFINED)
        get_directory_property(DOXYGEN_COMPILE_DEFINITIONS DIRECTORY "${CMAKE_SOURCE_DIR}" COMPILE_DEFINITIONS)
        list(APPEND DOXYGEN_COMPILE_DEFINITIONS ${MCU_FAMILY_ID} ${TARGET_MCU})
        list(JOIN DOXYGEN_COMPILE_DEFINITIONS " " DOXYGEN_COMPILE_DEFINITIONS)
        set(DOXYGEN_PREDEFINED "__attribute__(x)= ${DOXYGEN_COMPILE_DEFINITIONS}")
    endif()

    # Only macros of DOXYGEN_PREDEFINED are expanded (__attribute__)
    if(NOT DEFINED DOXYGEN_MACRO_EXPANSION)
        set(DOXYGEN_MACRO_EXPANSION YES)
    endif()

    if(NOT DEFINED DOXYGEN_EXPAND_ONLY_PREDEF)
        set(DOXYGEN_EXPAND_ONLY_PREDEF YES)
    endif()

    Doxygen_Generate()
    
endif()


# Validate that STM32CubeMX code is compatible with C standard
if(CMAKE_C_STANDARD LESS 11)
    message(ERROR "Generated code requires C11 or higher")
endif()
