/**
 * \author Mr.Nobody
 * \file UtCommon.h
 * \ingroup UnitTesting
 * \brief Common helpers of unit tests.
 *
 */

#ifndef UNITTESTING_UTCOMMON_H
#define UNITTESTING_UTCOMMON_H

/* ============================= INCLUDES =================================== */
#include "unity.h"                          /* Unity testing framework        */

/* ========================= EXPORTED MACROS ================================ */

/**
 * \brief Marks test of known (reported, not yet fixed) defect of the module.
 *
 * The test describes the required behavior. By default it is reported as
 * ignored with the defect description, so the test suite stays green and the
 * defect stays visible in the report. With CMake option
 * UNIT_TEST_RUN_KNOWN_DEFECTS=ON the test is executed and fails until the
 * defect is fixed - then the macro shall be removed from the test.
 *
 * Usage (first statement of the test):
 * \code
 * UT_KNOWN_DEFECT( "Reset of peripheral without reset bit writes 0xFF to RSTR" );
 * \endcode
 */
#if defined(UT_RUN_KNOWN_DEFECTS)
    #define UT_KNOWN_DEFECT( description )      do { } while( 0 )
#else
    #define UT_KNOWN_DEFECT( description )      TEST_IGNORE_MESSAGE( "KNOWN DEFECT: " description )
#endif

#endif /* UNITTESTING_UTCOMMON_H */
