/**
 * \author Mr.Nobody
 * \file Platform.h
 * \ingroup CMake
 * \brief Platform common functionality header file
 *
 */

#ifndef PROJECT_H
#define PROJECT_H

#ifdef __cplusplus
 extern "C" {
#endif /* __cplusplus */

/* ============================= INCLUDES =================================== */
#include "stdint.h"                         /* Module types definition        */
/* ============================= TYPEDEFS =================================== */

 /** \brief Type signaling major version of SW module */
 typedef uint8_t project_MajorVersion_t;


 /** \brief Type signaling minor version of SW module */
 typedef uint8_t project_MinorVersion_t;


 /** \brief Type signaling patch version of SW module */
 typedef uint8_t project_PatchVersion_t;


 /** \brief Type signaling actual version of SW module */
 typedef struct
 {
     project_MajorVersion_t Major; /**< Major version */
     project_MinorVersion_t Minor; /**< Minor version */
     project_PatchVersion_t Patch; /**< Patch version */
 }   project_ModuleVersion_t;

/* ========================= SYMBOLIC CONSTANTS ============================= */

/* ========================= EXPORTED MACROS ================================ */

/* ========================= EXPORTED VARIABLES ============================= */

/* ======================== EXPORTED FUNCTIONS ============================== */

project_ModuleVersion_t     Project_Get_Version         ( void );

#ifdef __cplusplus
}
#endif /* __cplusplus */

#endif /* PROJECT_H */
