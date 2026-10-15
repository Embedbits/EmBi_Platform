/**
 * \author Mr.Nobody
 * \file Test_RegMemThread.c
 * \ingroup UnitTesting
 * \brief Unit tests of the HW model thread of RegMem (fallback of the synchronous model).
 *
 * The thread mode is selected by environment variable REGMEM_MODEL_MODE=thread, which every test
 * sets before it starts a model. The tests wait for whole model cycles (RegMem_Wait_ModelCycles),
 * not for time.
 *
 * \note Every test runs as separate process (CTest).
 */

/* ============================= INCLUDES =================================== */
#include <stdint.h>                         /* Fixed width types              */
#include <stdlib.h>                         /* setenv / _putenv_s             */
#include "unity.h"                          /* Unity testing framework        */
#include "RegMem.h"                         /* Module under test              */

/* ========================= SYMBOLIC CONSTANTS ============================= */

/** Emulated peripheral address of the tests (RCC->CR of STM32F7) */
#define UT_PLL_CR_ADDR                      ( 0x40023800u )

/** PLL on request bit */
#define UT_PLLON                            ( 1u << 24 )

/** PLL ready flag */
#define UT_PLLRDY                           ( 1u << 25 )

/* ============================== MACROS ==================================== */

/** Emulated register at the address */
#define UT_REG( addr )                      ( *(volatile uint32_t *)(uintptr_t)( addr ) )

/* ======================= FORWARD DECLARATIONS ============================= */

static void Ut_RegMemThread_PllModel    ( void );

/* ============================ TEST FRAME ================================== */

void setUp( void )
{
#if defined(_WIN32)
    (void)_putenv_s( "REGMEM_MODEL_MODE", "thread" );
#else
    (void)setenv( "REGMEM_MODEL_MODE", "thread", 1 );
#endif

    TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Reset() );
}

void tearDown( void )
{
    (void)RegMem_Set_ModelInactive();
}

/* ============================== TESTS ===================================== */

/**
 * \brief   REGMEM_MODEL_MODE=thread selects the model thread.
 *
 * \par Expected results
 * - Mode THREAD while the model is active, NONE after it is stopped.
 */
void Ut_RegMemThread_Set_ModelActive_ThreadMode_ModeThread( void )
{
    TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Set_ModelActive( Ut_RegMemThread_PllModel ) );
    TEST_ASSERT_EQUAL( REGMEM_MODEL_MODE_THREAD, RegMem_Get_ModelMode() );

    TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Set_ModelInactive() );
    TEST_ASSERT_EQUAL( REGMEM_MODEL_MODE_NONE, RegMem_Get_ModelMode() );
}


/**
 * \brief   The model thread sets the ready flag after the enable bit is set.
 *
 * \par Expected results
 * - The flag is set after one awaited model cycle, cleared after the enable bit is cleared.
 */
void Ut_RegMemThread_Wait_ModelCycles_FlagFollowsEnableBit( void )
{
    TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Set_ModelActive( Ut_RegMemThread_PllModel ) );

    __atomic_or_fetch( &UT_REG( UT_PLL_CR_ADDR ), UT_PLLON, __ATOMIC_SEQ_CST );
    TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Wait_ModelCycles( 1u ) );
    TEST_ASSERT_EQUAL_HEX32( UT_PLLRDY, UT_REG( UT_PLL_CR_ADDR ) & UT_PLLRDY );

    __atomic_and_fetch( &UT_REG( UT_PLL_CR_ADDR ), ~UT_PLLON, __ATOMIC_SEQ_CST );
    TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Step_Model() );
    TEST_ASSERT_EQUAL_HEX32( 0u, UT_REG( UT_PLL_CR_ADDR ) & UT_PLLRDY );
}


/**
 * \brief   A new model replaces the running one and RegMem_Reset() stops the thread.
 *
 * \par Expected results
 * - Mode THREAD after the replacement, NONE after the reset.
 */
void Ut_RegMemThread_Set_ModelActive_SecondModel_ReplacesFirst( void )
{
    TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Set_ModelActive( Ut_RegMemThread_PllModel ) );
    TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Set_ModelActive( Ut_RegMemThread_PllModel ) );
    TEST_ASSERT_EQUAL( REGMEM_MODEL_MODE_THREAD, RegMem_Get_ModelMode() );

    TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Reset() );
    TEST_ASSERT_EQUAL( REGMEM_MODEL_MODE_NONE, RegMem_Get_ModelMode() );
}

/* ========================== LOCAL FUNCTIONS =============================== */

/**
 * \brief Model of the PLL - ready flag follows the on bit (level function, atomic operations).
 */
static void Ut_RegMemThread_PllModel( void )
{
    if( 0u != ( UT_REG( UT_PLL_CR_ADDR ) & UT_PLLON ) )
    {
        (void)__atomic_or_fetch( &UT_REG( UT_PLL_CR_ADDR ), UT_PLLRDY, __ATOMIC_SEQ_CST );
    }
    else
    {
        (void)__atomic_and_fetch( &UT_REG( UT_PLL_CR_ADDR ), ~UT_PLLRDY, __ATOMIC_SEQ_CST );
    }
}
