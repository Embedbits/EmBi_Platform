/**
 * \author Mr.Nobody
 * \file IntegrationTesting_Coverage.h
 * \ingroup IntegrationTesting
 * \brief Integration testing on target - code coverage (gcov) of the tested code.
 *
 * The code under test is compiled with the gcov instrumentation (INTEGRATION_TEST_COVERAGE,
 * options --coverage -fprofile-info-section), which counts the executions of the
 * branches of the code in RAM counters. Two features of the target are needed:
 *
 *  - Every test case runs after the reset of the MCU, which clears .bss. The counters are
 *    therefore placed in the section ".gcov_counters" (linker script
 *    IntegrationTesting_GcovCounters.ld), which is not initialized by the startup code and
 *    kept over reset like the result mailbox. The counters are cleared when a new test
 *    session starts (\ref IntegrationTesting_Coverage_Clear) and sum up the execution of
 *    all test cases.
 *  - Neither a file system nor global constructors/destructors are used: the instrumented
 *    objects register their gcov information in the section ".gcov_info" (linker script
 *    IntegrationTesting_GcovInfo.ld, symbols __gcov_info_start / __gcov_info_end). After
 *    the last test case the framework serializes the information by libgcov
 *    (__gcov_info_to_gcda) into the coverage buffer (\ref integrationTesting_Coverage)
 *    in the RAM section ".noinit" and the host reads it through the debug probe. The
 *    host converts the stream to .gcda files (gcov-tool merge-stream,
 *    IntegrationTesting_Coverage.cmake).
 *
 * \note The size of the buffer is INTEGRATION_TEST_COVERAGE_SIZE. The data of a module
 *       are a few kB; the host reports the overflow (\ref IT_COVERAGE_STATE_OVERFLOW).
 */

#ifndef INTEGRATIONTESTING_INTEGRATIONTESTING_COVERAGE_H
#define INTEGRATIONTESTING_INTEGRATIONTESTING_COVERAGE_H

#ifdef __cplusplus
 extern "C" {
#endif /* __cplusplus */

/* ============================= INCLUDES =================================== */
#include "stdint.h"                         /* Standard types                 */
/* ============================= TYPEDEFS =================================== */

/** \brief State of the coverage buffer */
typedef enum
{
    IT_COVERAGE_STATE_NONE      = 0x4E4F4E45u,  /**< No data yet ("NONE")                                        */
    IT_COVERAGE_STATE_DONE      = 0x444F4E45u,  /**< Stream of the gcov data is complete ("DONE")                */
    IT_COVERAGE_STATE_OVERFLOW  = 0x4F564552u,  /**< The stream does not fit into the buffer ("OVER")            */
    IT_COVERAGE_STATE_NO_MEMORY = 0x4E4F4D45u   /**< libgcov asked for more memory than the pool has ("NOME")    */
}   integrationTesting_CoverageState_t;


/**
 * \brief Coverage buffer read by host (see IntegrationTesting_Run.cmake).
 *
 * \note Layout of the header (4 words) is part of the host interface.
 */
typedef struct
{
    volatile uint32_t                           Magic;      /**< \ref IT_COVERAGE_MAGIC when the buffer is valid         */
    volatile integrationTesting_CoverageState_t State;      /**< State of the buffer                                     */
    volatile uint32_t                           Length;     /**< Count of bytes of the stream stored in Data             */
    volatile uint32_t                           Size;       /**< Size of Data (overflow detection)                       */
    volatile uint8_t                            Data[ IT_COVERAGE_SIZE ];   /**< Stream of the gcov data (binary)        */
}   integrationTesting_Coverage_t;

/* ========================= SYMBOLIC CONSTANTS ============================= */

/** Identification of the coverage buffer ("ITCV") */
#define IT_COVERAGE_MAGIC                   ( 0x49544356u )

/* ========================= EXPORTED VARIABLES ============================= */

extern integrationTesting_Coverage_t        integrationTesting_Coverage;

/* ======================== EXPORTED FUNCTIONS ============================== */

void IntegrationTesting_Coverage_Clear      ( void );
void IntegrationTesting_Coverage_Dump       ( void );

#ifdef __cplusplus
}
#endif /* __cplusplus */

#endif /* INTEGRATIONTESTING_INTEGRATIONTESTING_COVERAGE_H */
