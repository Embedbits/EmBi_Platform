/**
 * \author Mr.Nobody
 * \file Test_Calc.c
 * \ingroup Coverage
 * \brief Unit tests of the self-test module of the coverage report.
 */

/* ============================= INCLUDES =================================== */
#include "unity.h"
#include "Calc.h"

/* ============================ FUNCTIONS =================================== */

void setUp( void )
{
}


void tearDown( void )
{
}


/**
 * \brief Calc_Abs returns a positive value unchanged.
 */
void Ut_Calc_Abs_PositiveValue_ReturnsValue( void )
{
    TEST_ASSERT_EQUAL_INT( 5, Calc_Abs( 5 ) );
}


/**
 * \brief Calc_Abs changes the sign of a negative value.
 */
void Ut_Calc_Abs_NegativeValue_ReturnsOppositeValue( void )
{
    TEST_ASSERT_EQUAL_INT( 5, Calc_Abs( -5 ) );
}


/**
 * \brief Calc_Clamp returns a value in the range unchanged.
 */
void Ut_Calc_Clamp_ValueInRange_ReturnsValue( void )
{
    TEST_ASSERT_EQUAL_INT( 3, Calc_Clamp( 3, 1, 5 ) );
}


/**
 * \brief Calc_Clamp limits a value above the range (the branch below the range is not tested).
 */
void Ut_Calc_Clamp_ValueAboveRange_ReturnsMax( void )
{
    TEST_ASSERT_EQUAL_INT( 5, Calc_Clamp( 9, 1, 5 ) );
}
