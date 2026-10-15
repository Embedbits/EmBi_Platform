/**
 * \author Mr.Nobody
 * \file Test_RegMem.c
 * \ingroup UnitTesting
 * \brief Unit tests of the synchronous HW model of RegMem (write trap).
 *
 * The model callbacks count their calls and mirror a register (value + 1) so that the tests
 * can check how many times and when (after the store, with the stored value) the model runs.
 *
 * \note The tests need the synchronous mode. They are ignored (not failed) on hosts where the
 *       write trap is not used (not x86-64 Linux / Windows, debugger attached, trap probe failed,
 *       REGMEM_MODEL_MODE=thread).
 * \note Every test runs as separate process (CTest).
 */

/* ============================= INCLUDES =================================== */
#include <stdint.h>                         /* Fixed width types              */
#include <string.h>                         /* memset, memcpy                 */
#include "unity.h"                          /* Unity testing framework        */
#include "RegMem.h"                         /* Module under test              */

/* ========================= SYMBOLIC CONSTANTS ============================= */

/** Emulated peripheral address of the tests (RCC->CR of STM32F7) */
#define UT_PLL_CR_ADDR                      ( 0x40023800u )

/** Register changed by the tests (source of the mirror model) */
#define UT_SRC_ADDR                         ( 0x40023900u )

/** Register written by the mirror model (source + 1) */
#define UT_MIRROR_ADDR                      ( 0x40023904u )

/** Register of the private peripheral bus (SCB->ICSR) */
#define UT_PPB_ADDR                         ( 0xE000ED04u )

/** PLL on request bit */
#define UT_PLLON                            ( 1u << 24 )

/** PLL ready flag */
#define UT_PLLRDY                           ( 1u << 25 )

/** Count of pages written by the model of the many pages test (more than the page list of Windows) */
#define UT_MANY_PAGES_CNT                   ( 80u )

/* ============================== MACROS ==================================== */

/** Emulated register at the address */
#define UT_REG( addr )                      ( *(volatile uint32_t *)(uintptr_t)( addr ) )

/* ========================= LOCAL VARIABLES ================================ */

/** Count of calls of the model callbacks */
static volatile uint32_t    utRegMem_ModelCnt;

/** Count of calls of the second model */
static volatile uint32_t    utRegMem_SecondModelCnt;

/** Model input which is not a register */
static volatile uint32_t    utRegMem_ModelInput;

/* ======================= FORWARD DECLARATIONS ============================= */

static void Ut_RegMem_MirrorModel       ( void );
static void Ut_RegMem_SecondModel       ( void );
static void Ut_RegMem_PllModel          ( void );
static void Ut_RegMem_InputModel        ( void );
static void Ut_RegMem_ManyPagesModel    ( void );
static void Ut_RegMem_OtherPagesModel   ( void );
static void Ut_RegMem_Activate          ( regMem_ModelCallback_t modelCallback );
static uint32_t Ut_RegMem_WaitPllReady  ( void );

/* ============================ TEST FRAME ================================== */

void setUp( void )
{
    utRegMem_ModelCnt       = 0u;
    utRegMem_SecondModelCnt = 0u;
    utRegMem_ModelInput     = 0u;

    TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Reset() );
}

void tearDown( void )
{
    (void)RegMem_Set_ModelInactive();
}

/* ============================== TESTS ===================================== */

/**
 * \brief   Model activation selects the synchronous mode and evaluates the model once.
 *
 * \par Expected results
 * - Mode SYNC, the model called once before the function returns, mirror register already set.
 * - Mode NONE after the model is stopped.
 */
void Ut_RegMem_Set_ModelActive_SyncMode_ModelCalledOnce( void )
{
    UT_REG( UT_SRC_ADDR ) = 41u;

    Ut_RegMem_Activate( Ut_RegMem_MirrorModel );

    TEST_ASSERT_EQUAL( REGMEM_MODEL_MODE_SYNC, RegMem_Get_ModelMode() );
    TEST_ASSERT_EQUAL_UINT32( 1u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_UINT32( 42u, UT_REG( UT_MIRROR_ADDR ) );

    TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Set_ModelInactive() );
    TEST_ASSERT_EQUAL( REGMEM_MODEL_MODE_NONE, RegMem_Get_ModelMode() );
}


/**
 * \brief   A 32 bit store calls the model once, after the store, with the stored value.
 *
 * \par Expected results
 * - Model called once per store, mirror = stored value + 1 (the model saw the new value).
 */
void Ut_RegMem_Store32_ModelCalledOncePerStore( void )
{
    Ut_RegMem_Activate( Ut_RegMem_MirrorModel );

    UT_REG( UT_SRC_ADDR ) = 5u;

    TEST_ASSERT_EQUAL_UINT32( 2u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_UINT32( 6u, UT_REG( UT_MIRROR_ADDR ) );
    TEST_ASSERT_EQUAL_UINT32( 5u, UT_REG( UT_SRC_ADDR ) );

    UT_REG( UT_SRC_ADDR ) = 0x1234u;

    TEST_ASSERT_EQUAL_UINT32( 3u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_UINT32( 0x1235u, UT_REG( UT_MIRROR_ADDR ) );
}


/**
 * \brief   8, 16 and 64 bit stores call the model once per store.
 *
 * \par Expected results
 * - Model called once per store and sees the stored value.
 */
void Ut_RegMem_StoreWidths_ModelCalledOncePerStore( void )
{
    Ut_RegMem_Activate( Ut_RegMem_MirrorModel );

    *(volatile uint8_t *)(uintptr_t)UT_SRC_ADDR = 9u;
    TEST_ASSERT_EQUAL_UINT32( 2u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_UINT32( 10u, UT_REG( UT_MIRROR_ADDR ) );

    *(volatile uint16_t *)(uintptr_t)UT_SRC_ADDR = 0x1234u;
    TEST_ASSERT_EQUAL_UINT32( 3u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_UINT32( 0x1235u, UT_REG( UT_MIRROR_ADDR ) );

    *(volatile uint64_t *)(uintptr_t)UT_SRC_ADDR = 0x0000000700000011ull;
    TEST_ASSERT_EQUAL_UINT32( 4u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_UINT32( 0x12u, UT_REG( UT_MIRROR_ADDR ) );
}


/**
 * \brief   Read-modify-write and atomic operations call the model once per store.
 *
 * \par Expected results
 * - Model called once per operation, the model sees the modified value.
 */
void Ut_RegMem_ReadModifyWriteAndAtomics_ModelCalledOncePerStore( void )
{
    Ut_RegMem_Activate( Ut_RegMem_MirrorModel );

    UT_REG( UT_SRC_ADDR ) |= 0x100u;
    TEST_ASSERT_EQUAL_UINT32( 2u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_UINT32( 0x101u, UT_REG( UT_MIRROR_ADDR ) );

    (void)__atomic_fetch_or( &UT_REG( UT_SRC_ADDR ), 0x1000u, __ATOMIC_SEQ_CST );
    TEST_ASSERT_EQUAL_UINT32( 3u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_UINT32( 0x1101u, UT_REG( UT_MIRROR_ADDR ) );

    (void)__atomic_exchange_n( &UT_REG( UT_SRC_ADDR ), 3u, __ATOMIC_SEQ_CST );
    TEST_ASSERT_EQUAL_UINT32( 4u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_UINT32( 4u, UT_REG( UT_MIRROR_ADDR ) );
}


/**
 * \brief   memset and memcpy into the registers call the model (at least once).
 *
 * \par Expected results
 * - Model called, the written bytes are in the registers.
 */
void Ut_RegMem_MemsetAndMemcpy_ModelCalled( void )
{
    uint8_t source[ 64u ];

    Ut_RegMem_Activate( Ut_RegMem_MirrorModel );
    utRegMem_ModelCnt = 0u;

    memset( (void *)(uintptr_t)0x40024000u, 0xAB, 256u );

    TEST_ASSERT_GREATER_THAN_UINT32( 0u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_HEX32( 0xABABABABu, UT_REG( 0x400240FCu ) );

    utRegMem_ModelCnt = 0u;
    memset( source, 0x5A, sizeof( source ) );
    memcpy( (void *)(uintptr_t)0x40024100u, source, sizeof( source ) );

    TEST_ASSERT_GREATER_THAN_UINT32( 0u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_HEX32( 0x5A5A5A5Au, UT_REG( 0x4002413Cu ) );
}


/**
 * \brief   A store to the private peripheral bus calls the model.
 *
 * \par Expected results
 * - Model called once, the stored value is in the register.
 */
void Ut_RegMem_StorePpb_ModelCalled( void )
{
    Ut_RegMem_Activate( Ut_RegMem_MirrorModel );

    UT_REG( UT_PPB_ADDR ) = 0x10000000u;

    TEST_ASSERT_EQUAL_UINT32( 2u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_HEX32( 0x10000000u, UT_REG( UT_PPB_ADDR ) );
}


/**
 * \brief   Reads do not call the model.
 *
 * \par Expected results
 * - 100000 reads of two registers, the model is not called.
 */
void Ut_RegMem_Read_ModelNotCalled( void )
{
    volatile uint32_t sink = 0u;

    Ut_RegMem_Activate( Ut_RegMem_MirrorModel );

    for( uint32_t idx = 0u; 100000u > idx; idx++ )
    {
        sink += UT_REG( UT_SRC_ADDR );
        sink += UT_REG( UT_PPB_ADDR );
    }

    TEST_ASSERT_EQUAL_UINT32( 1u, utRegMem_ModelCnt );
}


/**
 * \brief   A store to the emulated SRAM does not call the model.
 *
 * \par Expected results
 * - The model is not called, the value is stored.
 */
void Ut_RegMem_StoreSram_ModelNotCalled( void )
{
    Ut_RegMem_Activate( Ut_RegMem_MirrorModel );

    *REGMEM_SRAM_PTR( volatile uint32_t, 0x100u ) = 0xCAFEu;

    TEST_ASSERT_EQUAL_UINT32( 1u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_HEX32( 0xCAFEu, *REGMEM_SRAM_PTR( volatile uint32_t, 0x100u ) );
}


/**
 * \brief   A stopped model is not called.
 *
 * \par Expected results
 * - Stores after RegMem_Set_ModelInactive() do not call the model and are stored.
 */
void Ut_RegMem_Set_ModelInactive_StoreModelNotCalled( void )
{
    Ut_RegMem_Activate( Ut_RegMem_MirrorModel );

    TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Set_ModelInactive() );

    UT_REG( UT_SRC_ADDR ) = 77u;

    TEST_ASSERT_EQUAL_UINT32( 1u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_UINT32( 77u, UT_REG( UT_SRC_ADDR ) );
    TEST_ASSERT_EQUAL_UINT32( 0u, UT_REG( UT_MIRROR_ADDR ) - 1u );
}


/**
 * \brief   RegMem_Reset() stops the model.
 *
 * \par Expected results
 * - Mode NONE, stores do not call the model, registers are cleared.
 */
void Ut_RegMem_Reset_ModelStopped( void )
{
    Ut_RegMem_Activate( Ut_RegMem_MirrorModel );

    TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Reset() );
    TEST_ASSERT_EQUAL( REGMEM_MODEL_MODE_NONE, RegMem_Get_ModelMode() );

    UT_REG( UT_SRC_ADDR ) = 5u;

    TEST_ASSERT_EQUAL_UINT32( 1u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_UINT32( 0u, UT_REG( UT_MIRROR_ADDR ) );
}


/**
 * \brief   A new model replaces the active one.
 *
 * \par Expected results
 * - Stores call only the second model.
 */
void Ut_RegMem_Set_ModelActive_SecondModel_ReplacesFirst( void )
{
    Ut_RegMem_Activate( Ut_RegMem_MirrorModel );
    Ut_RegMem_Activate( Ut_RegMem_SecondModel );

    utRegMem_ModelCnt = 0u;
    UT_REG( UT_SRC_ADDR ) = 5u;

    TEST_ASSERT_EQUAL_UINT32( 0u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_UINT32( 2u, utRegMem_SecondModelCnt );
}


/**
 * \brief   The model writes to registers on other pages than the stored one.
 *
 * \details The model of the test writes to three other pages of the peripherals and to the
 *          private peripheral bus - its stores do not call the model again.
 *
 * \par Expected results
 * - Model called once per store, all stores of the model are visible.
 */
void Ut_RegMem_Model_StoresToOtherPages_NoRecursion( void )
{
    Ut_RegMem_Activate( Ut_RegMem_OtherPagesModel );
    utRegMem_ModelCnt = 0u;

    UT_REG( UT_SRC_ADDR ) = 7u;

    TEST_ASSERT_EQUAL_UINT32( 1u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_UINT32( 8u, UT_REG( 0x40030010u ) );
    TEST_ASSERT_EQUAL_UINT32( 9u, UT_REG( 0x40041010u ) );
    TEST_ASSERT_EQUAL_UINT32( 10u, UT_REG( 0x50002010u ) );
    TEST_ASSERT_EQUAL_UINT32( 11u, UT_REG( UT_PPB_ADDR ) );

    UT_REG( UT_SRC_ADDR ) = 20u;

    TEST_ASSERT_EQUAL_UINT32( 2u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_UINT32( 21u, UT_REG( 0x40030010u ) );
    TEST_ASSERT_EQUAL_UINT32( 24u, UT_REG( UT_PPB_ADDR ) );
}


/**
 * \brief   The model writes to many pages (more than the page list of the Windows implementation).
 *
 * \par Expected results
 * - All stores of the model are visible, the model is called once per store.
 */
void Ut_RegMem_Model_StoresToManyPages_AllVisible( void )
{
    Ut_RegMem_Activate( Ut_RegMem_ManyPagesModel );
    utRegMem_ModelCnt = 0u;

    UT_REG( UT_SRC_ADDR ) = 3u;

    TEST_ASSERT_EQUAL_UINT32( 1u, utRegMem_ModelCnt );

    for( uint32_t pageIdx = 0u; UT_MANY_PAGES_CNT > pageIdx; pageIdx++ )
    {
        TEST_ASSERT_EQUAL_UINT32( 3u + pageIdx, UT_REG( 0x40100000u + ( pageIdx * 4096u ) ) );
    }

    UT_REG( UT_SRC_ADDR ) = 100u;

    TEST_ASSERT_EQUAL_UINT32( 2u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_UINT32( 100u + ( UT_MANY_PAGES_CNT - 1u ), UT_REG( 0x40100000u + ( ( UT_MANY_PAGES_CNT - 1u ) * 4096u ) ) );
}


/**
 * \brief   A busy-wait of the code under test finds the flag set by the model at the first read.
 *
 * \details Same pattern as the PLL lock wait of Rcc: set the enable bit, poll the ready flag in
 *          a bounded loop.
 *
 * \par Expected results
 * - The flag is set at the first read (no iteration is lost), 200 times in a row.
 */
void Ut_RegMem_BusyWait_ModelSetsFlag_FoundAtFirstRead( void )
{
    for( uint32_t trial = 0u; 200u > trial; trial++ )
    {
        TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Reset() );
        Ut_RegMem_Activate( Ut_RegMem_PllModel );

        UT_REG( UT_PLL_CR_ADDR ) |= UT_PLLON;

        TEST_ASSERT_EQUAL_UINT32( 0u, Ut_RegMem_WaitPllReady() );

        UT_REG( UT_PLL_CR_ADDR ) &= ~UT_PLLON;

        TEST_ASSERT_EQUAL_HEX32( 0u, UT_REG( UT_PLL_CR_ADDR ) & UT_PLLRDY );
    }
}


/**
 * \brief   RegMem_Wait_ModelCycles() calls the model n times.
 *
 * \par Expected results
 * - n calls for n = 3, no call for n = 0.
 */
void Ut_RegMem_Wait_ModelCycles_ModelCalledNTimes( void )
{
    Ut_RegMem_Activate( Ut_RegMem_MirrorModel );
    utRegMem_ModelCnt = 0u;

    TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Wait_ModelCycles( 3u ) );
    TEST_ASSERT_EQUAL_UINT32( 3u, utRegMem_ModelCnt );

    TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Wait_ModelCycles( 0u ) );
    TEST_ASSERT_EQUAL_UINT32( 3u, utRegMem_ModelCnt );

    UT_REG( UT_SRC_ADDR ) = 5u;

    TEST_ASSERT_EQUAL_UINT32( 4u, utRegMem_ModelCnt );
}


/**
 * \brief   RegMem_Step_Model() lets the model evaluate a model input which is not a register.
 *
 * \par Expected results
 * - The flag is not set after the input is changed (no store), it is set after the step.
 */
void Ut_RegMem_Step_Model_ModelInputNotRegister_Evaluated( void )
{
    Ut_RegMem_Activate( Ut_RegMem_InputModel );

    utRegMem_ModelInput = 1u;

    TEST_ASSERT_EQUAL_HEX32( 0u, UT_REG( UT_PLL_CR_ADDR ) & UT_PLLRDY );

    TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Step_Model() );

    TEST_ASSERT_EQUAL_HEX32( UT_PLLRDY, UT_REG( UT_PLL_CR_ADDR ) & UT_PLLRDY );
}


/**
 * \brief   The model is called for every one of many stores.
 *
 * \par Expected results
 * - 2000 stores, 2000 model calls (plus the call of the activation).
 */
void Ut_RegMem_ManyStores_ModelCalledForEveryStore( void )
{
    Ut_RegMem_Activate( Ut_RegMem_MirrorModel );

    for( uint32_t idx = 0u; 2000u > idx; idx++ )
    {
        UT_REG( UT_SRC_ADDR ) = idx;
    }

    TEST_ASSERT_EQUAL_UINT32( 2001u, utRegMem_ModelCnt );
    TEST_ASSERT_EQUAL_UINT32( 2000u, UT_REG( UT_MIRROR_ADDR ) );
}


/**
 * \brief   A model which is NULL is refused.
 *
 * \par Expected results
 * - REGMEM_REQUEST_ERROR and no active model.
 */
void Ut_RegMem_Set_ModelActive_NullCallback_ReturnsError( void )
{
    TEST_ASSERT_EQUAL( REGMEM_REQUEST_ERROR, RegMem_Set_ModelActive( NULL ) );
    TEST_ASSERT_EQUAL( REGMEM_MODEL_MODE_NONE, RegMem_Get_ModelMode() );
}

/* ========================== LOCAL FUNCTIONS =============================== */

/**
 * \brief Model - mirror register = source register + 1, counts its calls.
 */
static void Ut_RegMem_MirrorModel( void )
{
    utRegMem_ModelCnt++;
    UT_REG( UT_MIRROR_ADDR ) = UT_REG( UT_SRC_ADDR ) + 1u;
}


/**
 * \brief Second model - counts its calls.
 */
static void Ut_RegMem_SecondModel( void )
{
    utRegMem_SecondModelCnt++;
}


/**
 * \brief Model of the PLL - ready flag follows the on bit (level function, atomic operations).
 */
static void Ut_RegMem_PllModel( void )
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


/**
 * \brief Model with an input which is not a register - the flag is set while the input is set.
 */
static void Ut_RegMem_InputModel( void )
{
    if( 0u != utRegMem_ModelInput )
    {
        (void)__atomic_or_fetch( &UT_REG( UT_PLL_CR_ADDR ), UT_PLLRDY, __ATOMIC_SEQ_CST );
    }
    else
    {
        (void)__atomic_and_fetch( &UT_REG( UT_PLL_CR_ADDR ), ~UT_PLLRDY, __ATOMIC_SEQ_CST );
    }
}


/**
 * \brief Model which writes to registers of other pages (peripherals of other buses, PPB).
 */
static void Ut_RegMem_OtherPagesModel( void )
{
    const uint32_t src = UT_REG( UT_SRC_ADDR );

    utRegMem_ModelCnt++;

    UT_REG( 0x40030010u ) = src + 1u;
    UT_REG( 0x40041010u ) = src + 2u;
    UT_REG( 0x50002010u ) = src + 3u;
    UT_REG( UT_PPB_ADDR ) = src + 4u;
}


/**
 * \brief Model which writes to many different pages.
 */
static void Ut_RegMem_ManyPagesModel( void )
{
    const uint32_t src = UT_REG( UT_SRC_ADDR );

    utRegMem_ModelCnt++;

    for( uint32_t pageIdx = 0u; UT_MANY_PAGES_CNT > pageIdx; pageIdx++ )
    {
        UT_REG( 0x40100000u + ( pageIdx * 4096u ) ) = src + pageIdx;
    }
}


/**
 * \brief Starts the model, the test is ignored if the synchronous mode is not used on the host.
 *
 * \param modelCallback [in]: Model callback
 */
static void Ut_RegMem_Activate( regMem_ModelCallback_t modelCallback )
{
    TEST_ASSERT_EQUAL( REGMEM_REQUEST_OK, RegMem_Set_ModelActive( modelCallback ) );

    if( REGMEM_MODEL_MODE_SYNC != RegMem_Get_ModelMode() )
    {
        TEST_IGNORE_MESSAGE( "Synchronous HW model (write trap) is not used on this host" );
    }
}


/**
 * \brief Waits for the PLL ready flag like the code under test (bounded loop of the register reads).
 *
 * \return Count of the reads without the flag. 0xFFFFFFFF if the flag was not set within the loop.
 */
static uint32_t Ut_RegMem_WaitPllReady( void )
{
    uint32_t lostReads = 0xFFFFFFFFu;

    for( uint32_t iterationCnt = 0u; 0x84FCBu > iterationCnt; iterationCnt++ )
    {
        if( 0u != ( UT_REG( UT_PLL_CR_ADDR ) & UT_PLLRDY ) )
        {
            lostReads = iterationCnt;
            break;
        }
        else
        {
            /* Not ready yet */
        }
    }

    return ( lostReads );
}
