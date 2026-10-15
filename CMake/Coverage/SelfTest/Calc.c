/**
 * \author Mr.Nobody
 * \file Calc.c
 * \ingroup Coverage
 * \brief Tiny module for the self-test of the coverage report.
 */

/* ============================= INCLUDES =================================== */
#include "Calc.h"

/* ============================ FUNCTIONS =================================== */

int Calc_Abs( int value )
{
    int result = value;

    if( 0 > value )
    {
        result = -value;
    }

    return result;
}


int Calc_Clamp( int value, int min, int max )
{
    int result = value;

    if( value > max )
    {
        result = max;
    }
    else if( value < min )
    {
        result = min;
    }
    else
    {
        /* Value is in the range */
    }

    return result;
}


int Calc_Unused( int value )
{
    return value + 1;
}
