# Usage: cmake -DMODULE_NAME=MyLib -DMODULE_PATH=./path -P LibCMakeConvert.cmake

# 1. Validation
if(NOT MODULE_NAME OR NOT MODULE_PATH)
    message(FATAL_ERROR "Missing arguments! Usage: cmake -DMODULE_NAME=Name -DMODULE_PATH=Path -P LibCMakeConvert.cmake")
endif()

set(TEMPLATE_FILE "Template_CMakeLists.txt.in")
set(OUTPUT_FILE "${MODULE_PATH}/CMakeLists.txt")

# 2. Collect all files recursively
file(GLOB_RECURSE ALL_FILES RELATIVE "${MODULE_PATH}" "${MODULE_PATH}/*")

# 3. Define keywords
set(EXCLUDE_KEYWORDS "test" "example" "documentation" "docs" "build")
set(PUBLIC_DIR_KEYWORDS "include" "inc")
set(PORT_KEYWORD "_port")

set(SOURCES "")
set(PUB_HEADERS "")
set(PUB_INC_DIRS "")

foreach(FILE_PATH ${ALL_FILES})
    string(TOLOWER "${FILE_PATH}" FILE_PATH_LOWER)
    
    # Filter out hidden files (starting with dot)
    get_filename_component(FILE_NAME "${FILE_PATH}" NAME)
    if(FILE_NAME MATCHES "^\\.")
        continue()
    endif()

    # Filter out excluded directory keywords (case-insensitive)
    set(SKIP_FILE FALSE)
    foreach(KEYWORD ${EXCLUDE_KEYWORDS})
        if(FILE_PATH_LOWER MATCHES "${KEYWORD}")
            set(SKIP_FILE TRUE)
            break()
        endif()
    endforeach()

    if(SKIP_FILE)
        continue()
    endif()

    get_filename_component(FILE_EXT "${FILE_PATH}" LAST_EXT)
    get_filename_component(DIR_PATH "${FILE_PATH}" DIRECTORY)
    string(TOLOWER "${DIR_PATH}" DIR_PATH_LOWER)
    string(TOLOWER "${FILE_NAME}" FILE_NAME_LOWER)

    # Process Headers
    if(FILE_EXT MATCHES "\\.(h|hpp|hxx)$")
        set(IS_PUBLIC FALSE)

        # Condition A: Directory contains "include" or "inc"
        foreach(INC_KEY ${PUBLIC_DIR_KEYWORDS})
            if(DIR_PATH_LOWER MATCHES "${INC_KEY}")
                set(IS_PUBLIC TRUE)
                break()
            endif()
        endforeach()

        # Condition B: Filename contains "_port"
        if(FILE_NAME_LOWER MATCHES "${PORT_KEYWORD}")
            set(IS_PUBLIC TRUE)
        endif()

        if(IS_PUBLIC)
            list(APPEND PUB_HEADERS "${FILE_PATH}")
            if(NOT DIR_PATH STREQUAL "")
                list(APPEND PUB_INC_DIRS "${DIR_PATH}")
            endif()
        endif()
    
    # Process Sources
    elseif(FILE_EXT MATCHES "\\.(c|cpp|cc|cxx)$")
        list(APPEND SOURCES "${FILE_PATH}")
    endif()
endforeach()

# Clean up duplicates
if(PUB_INC_DIRS)
    list(REMOVE_DUPLICATES PUB_INC_DIRS)
endif()

# 4. Map to @TEMPLATE_..._LIST@ placeholders
string(REPLACE ";" "\n    " TEMPLATE_FILE_SOURCE_FILE_LIST "${SOURCES}")
string(REPLACE ";" "\n    " TEMPLATE_FILE_PUBLIC_HEADER_LIST "${PUB_HEADERS}")
string(REPLACE ";" "\n    " TEMPLATE_FILE_PUBLIC_INCLUDE_DIRS_LIST "${PUB_INC_DIRS}")

# Set remaining fields
set(TEMPLATE_FILE_PRIVATE_INCLUDE_DIRS_LIST "")
set(TEMPLATE_FILE_MODULE_NAME "${MODULE_NAME}")
set(TEMPLATE_FILE_MODULE_VERSION "1.0.0")
set(TEMPLATE_FILE_PUBLIC_DEPENDENT_LIBS_LIST "")
set(TEMPLATE_FILE_PRIVATE_DEPENDENT_LIBS_LIST "")

# 5. Generate File
configure_file("${TEMPLATE_FILE}" "${OUTPUT_FILE}" @ONLY)

message(STATUS "Generated: ${OUTPUT_FILE}")