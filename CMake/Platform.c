/**
 * \author Mr.Nobody
 * \file Platform.c
 * \ingroup CMake
 * \brief Platform common functionality source file
 *
 */

/* ============================= INCLUDES =================================== */
#include "Platform.h"                               /* Self include           */
/* ============================= TYPEDEFS =================================== */

/* ======================= FORWARD DECLARATIONS ============================= */

/* ========================= SYMBOLIC CONSTANTS ============================= */

/** Platform version major value. */
#define PLATFORM_MAJOR_VERSION                  (0u)
/** Platform version minor value. */
#define PLATFORM_MINOR_VERSION                  (0u)
/** Platform version patch value. */
#define PLATFORM_PATCH_VERSION                  (0u)

/* ============================== MACROS ==================================== */

/* ========================= EXPORTED VARIABLES ============================= */

/* ========================== LOCAL VARIABLES =============================== */

/* ======================== EXPORTED FUNCTIONS ============================== */

/**
 * \brief Returns platform semantic version.
 *
 * \return Platform semantic version.
 */
project_ModuleVersion_t Platform_Get_Version( void )
{
    project_ModuleVersion_t retVersion;

    retVersion.Major = PLATFORM_MAJOR_VERSION;
    retVersion.Minor = PLATFORM_MINOR_VERSION;
    retVersion.Patch = PLATFORM_PATCH_VERSION;

    return (retVersion);
}

/* ========================== LOCAL FUNCTIONS =============================== */

/* =============================== TASKS ==================================== */


