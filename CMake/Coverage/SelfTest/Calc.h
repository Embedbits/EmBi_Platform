/**
 * \author Mr.Nobody
 * \file Calc.h
 * \ingroup Coverage
 * \brief Tiny module for the self-test of the coverage report.
 */

#ifndef COVERAGE_SELFTEST_CALC_H
#define COVERAGE_SELFTEST_CALC_H

#ifdef __cplusplus
extern "C" {
#endif

/* ============================ FUNCTIONS =================================== */

/**
 * \brief Absolute value.
 *
 * \param value Value.
 * \return Absolute value of the value.
 */
int Calc_Abs( int value );

/**
 * \brief Limits the value to the range.
 *
 * \param value Value.
 * \param min   Lower limit.
 * \param max   Upper limit.
 * \return Value limited to min..max.
 */
int Calc_Clamp( int value, int min, int max );

/**
 * \brief Function which is never called by the tests.
 *
 * \param value Value.
 * \return Value increased by one.
 */
int Calc_Unused( int value );

#ifdef __cplusplus
}
#endif

#endif /* COVERAGE_SELFTEST_CALC_H */
