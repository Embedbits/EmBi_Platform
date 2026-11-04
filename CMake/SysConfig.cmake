# ==============================================================================
# System configuration file.
# Description:
# This file shall be single point of configurations for STM Template system. The 
# user can use his own GIT repositories and design for system. All other modules 
# shall use this file to get actual configurations.
# ==============================================================================


# URL path to Board Support Packages (BSP) GIT repository
set(SYS_CONFIG_BSP_REPO_URL                             "https://github.com/Embedbits/Bsp.git")

# URL path to Middlewares (MW) GIT repository
set(SYS_CONFIG_MW_REPO_URL                              "https://github.com/Embedbits/Middlewares.git")

# URL path to Artifacts GIT repository
set(SYS_CONFIG_ARTIFACTS_REPO_URL                       "https://github.com/Embedbits/Artifacts.git")

# URL path to Documentation GIT repository
set(SYS_CONFIG_DOCS_REPO_URL                            "https://github.com/Embedbits/Bsp-Docs.git")


# Path to the platform root folder (EmBi_Platform, Bsp).
get_filename_component(SYS_CONFIG_PLATFORM_ROOT_PATH    "${CMAKE_CURRENT_LIST_DIR}/../../" REALPATH)

# Path to project root folder - the platform root folder, or the folder of the project of a core of a multi-core
# MCU: a subfolder of the platform root folder with its own CMakeLists.txt and CMakePresets.json (CM7, CM4), the
# projects of the cores share EmBi_Platform and Bsp. CMAKE_SOURCE_DIR is the source folder of the configuration or
# the working folder of a script (cmake -P).
set(SYS_CONFIG_PROJECT_ROOT_PATH                        "${SYS_CONFIG_PLATFORM_ROOT_PATH}")

get_filename_component(SYS_CONFIG_SOURCE_PATH           "${CMAKE_SOURCE_DIR}" REALPATH)
get_filename_component(SYS_CONFIG_SOURCE_PARENT_PATH    "${SYS_CONFIG_SOURCE_PATH}/.." REALPATH)
get_filename_component(SYS_CONFIG_PLATFORM_PATH         "${CMAKE_CURRENT_LIST_DIR}/.." REALPATH)

if("${SYS_CONFIG_SOURCE_PARENT_PATH}" STREQUAL "${SYS_CONFIG_PLATFORM_ROOT_PATH}" AND
   NOT "${SYS_CONFIG_SOURCE_PATH}"    STREQUAL "${SYS_CONFIG_PLATFORM_PATH}"      AND
   EXISTS "${SYS_CONFIG_SOURCE_PATH}/CMakeLists.txt"                              AND
   EXISTS "${SYS_CONFIG_SOURCE_PATH}/CMakePresets.json")
    set(SYS_CONFIG_PROJECT_ROOT_PATH                    "${SYS_CONFIG_SOURCE_PATH}")
endif()

# Path to documentation folder.
get_filename_component(SYS_CONFIG_DOCS_PATH             "${CMAKE_CURRENT_LIST_DIR}/../Docs" REALPATH)

# ------------------------------------------------------------------------------
# Function: SysConfig_Get_BspRepoURL
# Description:
#   Returns URL path for Board Support Packages (BSP) GIT module.
# Parameters:
#   OUT_BSP_REPO_URL [out]: URL path of BSP GIT repository.
# ------------------------------------------------------------------------------
function(SysConfig_Get_BspRepoURL OUT_BSP_REPO_URL)

    if (NOT DEFINED SYS_CONFIG_BSP_REPO_URL)
        message(FATAL_ERROR "SYS_CONFIG_BSP_REPO_URL is not defined")
    endif()

    set(${OUT_BSP_REPO_URL} "${SYS_CONFIG_BSP_REPO_URL}" PARENT_SCOPE)
    
endfunction()


# ------------------------------------------------------------------------------
# Function: SysConfig_Get_ArtifactsRepoURL
# Description:
#   Returns URL path for Artifacts GIT module.
# Parameters:
#   OUT_ARTIFACTS_REPO_URL [out]: URL path of Artifacts GIT repository.
# ------------------------------------------------------------------------------
function(SysConfig_Get_ArtifactsRepoURL OUT_ARTIFACTS_REPO_URL)

    if (NOT DEFINED SYS_CONFIG_ARTIFACTS_REPO_URL)
        message(FATAL_ERROR "SYS_CONFIG_ARTIFACTS_REPO_URL is not defined")
    endif()

    set(${OUT_ARTIFACTS_REPO_URL} "${SYS_CONFIG_ARTIFACTS_REPO_URL}" PARENT_SCOPE)
    
endfunction()


# ------------------------------------------------------------------------------
# Function: SysConfig_Get_MwRepoURL
# Description:
#   Returns URL path for Middlewares (MW) GIT module.
# Parameters:
#   OUT_MW_REPO_URL [out]: URL path of Mw GIT repository.
# ------------------------------------------------------------------------------
function(SysConfig_Get_MwRepoURL OUT_MW_REPO_URL)

    if (NOT DEFINED SYS_CONFIG_MW_REPO_URL)
        message(FATAL_ERROR "SYS_CONFIG_MW_REPO_URL is not defined")
    endif()

    set(${OUT_MW_REPO_URL} "${SYS_CONFIG_MW_REPO_URL}" PARENT_SCOPE)
    
endfunction()


# ------------------------------------------------------------------------------
# Function: SysConfig_Get_DocsRepoURL
# Description:
#   Returns URL path for Documentation GIT module.
# Parameters:
#   OUT_DOCS_REPO_URL [out]: URL path of Mw GIT repository.
# ------------------------------------------------------------------------------
function(SysConfig_Get_DocsRepoURL OUT_DOCS_REPO_URL)

    if (NOT DEFINED SYS_CONFIG_DOCS_REPO_URL)
        message(FATAL_ERROR "SYS_CONFIG_DOCS_REPO_URL is not defined")
    endif()

    set(${OUT_DOCS_REPO_URL} "${SYS_CONFIG_DOCS_REPO_URL}" PARENT_SCOPE)
    
endfunction()


# ------------------------------------------------------------------------------
# Function: SysConfig_Get_ProjectRootPath
# Description:
#   Returns system path to the project root folder.
# Parameters:
#   OUT_PRJ_ROOT_PATH [out]: Path to the project root folder.
# ------------------------------------------------------------------------------
function(SysConfig_Get_ProjectRootPath OUT_PRJ_ROOT_PATH)

    if (NOT DEFINED SYS_CONFIG_PROJECT_ROOT_PATH)
        message(FATAL_ERROR "SYS_CONFIG_PROJECT_ROOT_PATH is not defined")
    endif()

    set(${OUT_PRJ_ROOT_PATH} "${SYS_CONFIG_PROJECT_ROOT_PATH}" PARENT_SCOPE)
    
endfunction()


# ------------------------------------------------------------------------------
# Function: SysConfig_Get_PlatformRootPath
# Description:
#   Returns system path to the platform root folder (EmBi_Platform, Bsp) - the
#   project root folder, the parent folder of the projects of the cores of a
#   multi-core MCU.
# Parameters:
#   OUT_PLATFORM_ROOT_PATH [out]: Path to the platform root folder.
# ------------------------------------------------------------------------------
function(SysConfig_Get_PlatformRootPath OUT_PLATFORM_ROOT_PATH)

    if (NOT DEFINED SYS_CONFIG_PLATFORM_ROOT_PATH)
        message(FATAL_ERROR "SYS_CONFIG_PLATFORM_ROOT_PATH is not defined")
    endif()

    set(${OUT_PLATFORM_ROOT_PATH} "${SYS_CONFIG_PLATFORM_ROOT_PATH}" PARENT_SCOPE)

endfunction()


# ------------------------------------------------------------------------------
# Function: SysConfig_Get_DocsPath
# Description:
#   Returns system path to the project root folder.
# Parameters:
#   OUT_PRJ_ROOT_PATH [out]: Path to the project root folder.
# ------------------------------------------------------------------------------
function(SysConfig_Get_DocsPath OUT_DOCS_PATH)

    if (NOT DEFINED SYS_CONFIG_DOCS_PATH)
        message(FATAL_ERROR "SYS_CONFIG_DOCS_PATH is not defined")
    endif()

    set(${OUT_DOCS_PATH} "${SYS_CONFIG_DOCS_PATH}" PARENT_SCOPE)
    
endfunction()

#================================= END OF FILE =================================