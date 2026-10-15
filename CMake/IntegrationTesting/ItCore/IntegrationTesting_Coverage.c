/**
 * \author Mr.Nobody
 * \file IntegrationTesting_Coverage.c
 * \ingroup IntegrationTesting
 * \brief Integration testing on target - code coverage (gcov) of the tested code.
 *
 * See IntegrationTesting_Coverage.h. Compiled into ItCore only with
 * INTEGRATION_TEST_COVERAGE.
 */

/* ============================= INCLUDES =================================== */
#include "IntegrationTesting_Coverage.h"    /* Self include                   */
#include "gcov.h"                           /* libgcov: __gcov_info_to_gcda   */
#include "stddef.h"                         /* NULL                           */
/* ============================= TYPEDEFS =================================== */

/* ======================= FORWARD DECLARATIONS ============================= */

static void  integrationTesting_Coverage_Put        ( const void* data, unsigned length, void* arg );
static void  integrationTesting_Coverage_Filename   ( const char* filename, void* arg );
static void* integrationTesting_Coverage_Allocate   ( unsigned length, void* arg );

/* ========================= SYMBOLIC CONSTANTS ============================= */

/** Size of the memory pool for libgcov [B] (the information of one object file is serialized at a time) */
#define IT_COVERAGE_POOL_SIZE               ( 1024u )

/** Alignment of the memory for libgcov [B] */
#define IT_COVERAGE_POOL_ALIGNMENT          ( 8u )

/* ========================= EXPORTED VARIABLES ============================= */

/**
 * Coverage buffer read by host. Located in ".noinit" - the content is kept over reset
 * like the result mailbox.
 */
__attribute__((section(".noinit")))
integrationTesting_Coverage_t integrationTesting_Coverage;

/* ========================== LOCAL VARIABLES =============================== */

/* Provided by the linker scripts of the coverage (IntegrationTesting_GcovInfo.ld, IntegrationTesting_GcovCounters.ld).
   The array notation avoids issues with a small-data area. */
extern const struct gcov_info * const   __gcov_info_start[];
extern const struct gcov_info * const   __gcov_info_end[];
extern uint8_t                          __it_gcov_counters_start[];
extern uint8_t                          __it_gcov_counters_end[];

/** Memory pool of libgcov */
static uint64_t     integrationTesting_Coverage_Pool[ IT_COVERAGE_POOL_SIZE / sizeof( uint64_t ) ];

/** Used part of the memory pool [B] */
static uint32_t     integrationTesting_Coverage_PoolUsed;

/* ======================== EXPORTED FUNCTIONS ============================== */

/**
 * \brief Starts the coverage of a new test session: the counters of the gcov
 *        instrumentation are cleared and the coverage buffer is emptied.
 *
 * Called when the mailbox is not valid (new session of the host, power-on), before the tested
 * code runs. The counters are kept over the resets between the test cases, so they sum up
 * the execution of all test cases of the session.
 */
void IntegrationTesting_Coverage_Clear( void )
{
    volatile uint8_t* counter = __it_gcov_counters_start;

    while( counter < __it_gcov_counters_end )
    {
        *counter = 0u;
        counter++;
    }

    integrationTesting_Coverage.Length = 0u;
    integrationTesting_Coverage.Size   = IT_COVERAGE_SIZE;
    integrationTesting_Coverage.State  = IT_COVERAGE_STATE_NONE;
    integrationTesting_Coverage.Magic  = IT_COVERAGE_MAGIC;
}


/**
 * \brief Serializes the gcov information of all instrumented objects (counters of all test
 *        cases) into the coverage buffer. Called after the last test case.
 *
 * The stream of every object consists of the name of its .gcda file and its data
 * (libgcov: __gcov_filename_to_gcfn, __gcov_info_to_gcda); gcov-tool merge-stream on
 * the host creates the .gcda files of it.
 */
void IntegrationTesting_Coverage_Dump( void )
{
    integrationTesting_Coverage.Length = 0u;

    const struct gcov_info * const * info = __gcov_info_start;
    const struct gcov_info * const * end  = __gcov_info_end;

    /* Obfuscated to prevent compiler optimizations (the array has no known size) */
    __asm__ ( "" : "+r" ( info ) );

    while( info != end )
    {
        integrationTesting_Coverage_PoolUsed = 0u;

        __gcov_info_to_gcda( *info,
                             integrationTesting_Coverage_Filename,
                             integrationTesting_Coverage_Put,
                             integrationTesting_Coverage_Allocate,
                             NULL );
        info++;
    }

    if( IT_COVERAGE_STATE_NONE == integrationTesting_Coverage.State )
    {
        integrationTesting_Coverage.State = IT_COVERAGE_STATE_DONE;
    }
    else
    {
        /* Overflow or missing memory is kept */
    }
}

/* ========================== LOCAL FUNCTIONS =============================== */

/**
 * \brief Appends bytes of the stream to the coverage buffer.
 *
 * \param data   [in]: Bytes of the stream
 * \param length [in]: Count of the bytes
 * \param arg    [in]: Unused
 */
static void integrationTesting_Coverage_Put( const void* data, unsigned length, void* arg )
{
    (void)arg;

    const uint8_t* const source = (const uint8_t*)data;
    uint32_t             used   = integrationTesting_Coverage.Length;

    for( unsigned idx = 0u; idx < length; idx++ )
    {
        if( IT_COVERAGE_SIZE > used )
        {
            integrationTesting_Coverage.Data[ used ] = source[ idx ];
            used++;
        }
        else
        {
            integrationTesting_Coverage.State = IT_COVERAGE_STATE_OVERFLOW;
        }
    }

    integrationTesting_Coverage.Length = used;
}


/**
 * \brief Serializes the name of the .gcda file (a record of the stream).
 *
 * \param filename [in]: Name of the .gcda file
 * \param arg      [in]: Unused
 */
static void integrationTesting_Coverage_Filename( const char* filename, void* arg )
{
    __gcov_filename_to_gcfn( filename, integrationTesting_Coverage_Put, arg );
}


/**
 * \brief Memory for libgcov from the static pool.
 *
 * \param length [in]: Requested size [B]
 * \param arg    [in]: Unused
 * \return Aligned memory, NULL if the pool is exhausted
 */
static void* integrationTesting_Coverage_Allocate( unsigned length, void* arg )
{
    (void)arg;

    const uint32_t size   = ( length + ( IT_COVERAGE_POOL_ALIGNMENT - 1u ) ) & ~( IT_COVERAGE_POOL_ALIGNMENT - 1u );
    void*          memory = NULL;

    if( ( IT_COVERAGE_POOL_SIZE - integrationTesting_Coverage_PoolUsed ) >= size )
    {
        memory = &( (uint8_t*)integrationTesting_Coverage_Pool )[ integrationTesting_Coverage_PoolUsed ];
        integrationTesting_Coverage_PoolUsed += size;
    }
    else
    {
        integrationTesting_Coverage.State = IT_COVERAGE_STATE_NO_MEMORY;
    }

    return memory;
}


/* =============================== TASKS ==================================== */
