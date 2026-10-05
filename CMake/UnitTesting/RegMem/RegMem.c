/**
 * \author Mr.Nobody
 * \file RegMem.c
 * \ingroup UnitTesting
 * \brief Register memory emulation for host based unit tests.
 *
 */

/* ============================= INCLUDES =================================== */
#include "RegMem.h"                         /* Self include                   */
#include "stddef.h"                         /* Standard definitions           */
#include "stdio.h"                          /* Error reporting                */
#include "stdlib.h"                         /* Process termination            */

#if defined(_WIN32)
#include <windows.h>                        /* VirtualAlloc / VirtualFree     */
#else
#include <sys/mman.h>                       /* mmap / madvise / munmap        */
#endif
#include <pthread.h>                        /* HW model thread                */
#include <sched.h>                          /* sched_yield                    */
/* ============================= TYPEDEFS =================================== */

/** Emulated memory region configuration structure */
typedef struct
{
    uintptr_t   BaseAddr;   /**< Region start address (MCU address)   */
    size_t      Size;       /**< Region size in bytes                 */
    const char *Name;       /**< Region name used in error messages   */
}   regMem_RegionConfig_t;


/** Region mapping state enumeration */
typedef enum
{
    REGMEM_REGION_UNMAPPED = 0u, /**< Region is not mapped */
    REGMEM_REGION_MAPPED         /**< Region is mapped     */
}   regMem_RegionState_t;


/** HW model thread state enumeration */
typedef enum
{
    REGMEM_MODEL_INACTIVE = 0u, /**< Model thread is not running */
    REGMEM_MODEL_ACTIVE         /**< Model thread is running     */
}   regMem_ModelState_t;

/* ======================= FORWARD DECLARATIONS ============================= */

static regMem_RequestState_t regMem_Map_Region      ( regMem_RegionId_t regionId );
static regMem_RequestState_t regMem_Clear_Region    ( regMem_RegionId_t regionId );
static regMem_RequestState_t regMem_Unmap_Region    ( regMem_RegionId_t regionId );
static void *                regMem_ModelThread      ( void *arg );

/* ========================= SYMBOLIC CONSTANTS ============================= */

/** Start of peripheral address space of Cortex-M (non-secure alias) */
#define REGMEM_PERIPH_BASE              ( 0x40000000u )

/** Size of peripheral address space incl. secure alias (0x40000000..0x5FFFFFFF) */
#define REGMEM_PERIPH_SIZE              ( 0x20000000u )

/** Start of Cortex-M private peripheral bus (SysTick, NVIC, SCB, ...) */
#define REGMEM_PPB_BASE                 ( 0xE0000000u )

/** Size of Cortex-M private peripheral bus */
#define REGMEM_PPB_SIZE                 ( 0x00100000u )

/** HW model cycles finished before \ref RegMem_Set_ModelActive returns */
#define REGMEM_MODEL_STARTUP_CYCLES     ( 2u )

#if !defined(_WIN32) && !defined(MAP_FIXED_NOREPLACE)
/** Linux < 4.17 headers: flag is then used only as hint, result is checked */
#define MAP_FIXED_NOREPLACE             ( 0x100000 )
#endif

/* ============================== MACROS ==================================== */

/* ========================= EXPORTED VARIABLES ============================= */

/* ========================== LOCAL VARIABLES =============================== */

static const regMem_RegionConfig_t  regMem_RegionConf[ REGMEM_REGION_CNT ] =
{
    { .BaseAddr = REGMEM_PERIPH_BASE, .Size = REGMEM_PERIPH_SIZE, .Name = "PERIPH" },
    { .BaseAddr = REGMEM_PPB_BASE,    .Size = REGMEM_PPB_SIZE,    .Name = "PPB"    },
    { .BaseAddr = REGMEM_SRAM_BASE,   .Size = REGMEM_SRAM_SIZE,   .Name = "SRAM"   }
};


static regMem_RegionState_t         regMem_RegionState[ REGMEM_REGION_CNT ] =
{
    REGMEM_REGION_UNMAPPED,
    REGMEM_REGION_UNMAPPED,
    REGMEM_REGION_UNMAPPED
};


/** HW model callback executed by model thread */
static regMem_ModelCallback_t       regMem_ModelCallback = NULL;

/** HW model thread state (written by test thread, read by model thread) */
static volatile regMem_ModelState_t regMem_ModelState    = REGMEM_MODEL_INACTIVE;

/** HW model thread */
static pthread_t                    regMem_ModelThreadId;

/** Count of finished HW model cycles (written by model thread, read by test thread) */
static volatile uint32_t            regMem_ModelCycleCnt = 0u;

/* ======================== EXPORTED FUNCTIONS ============================== */

/**
 * \brief Maps all emulated regions at their MCU addresses.
 *
 * \note  Called automatically before `main()`. Already mapped regions are skipped.
 *
 * \return Function processing state. Returns \ref REGMEM_REQUEST_OK if all regions
 *         are mapped. Otherwise returns \ref REGMEM_REQUEST_ERROR.
 */
regMem_RequestState_t RegMem_Init( void )
{
    regMem_RequestState_t retState = REGMEM_REQUEST_OK;

    for( uint32_t regionId = 0u; REGMEM_REGION_CNT > regionId; regionId++ )
    {
        if( REGMEM_REGION_UNMAPPED == regMem_RegionState[ regionId ] )
        {
            regMem_RequestState_t mapState = regMem_Map_Region( (regMem_RegionId_t)regionId );

            if( REGMEM_REQUEST_OK != mapState )
            {
                retState = REGMEM_REQUEST_ERROR;
            }
            else
            {
                /* Region mapped */
            }
        }
        else
        {
            /* Region already mapped */
        }
    }

    return ( retState );
}


/**
 * \brief Sets all emulated registers to zero.
 *
 * \note  Shall be called in `setUp()` of every test using registers.
 *
 * \pre   Regions are mapped (\ref RegMem_Init); otherwise \ref REGMEM_REQUEST_ERROR.
 *
 * \return Function processing state. Returns \ref REGMEM_REQUEST_OK if request
 *         was processed without problems. Otherwise returns \ref REGMEM_REQUEST_ERROR.
 */
regMem_RequestState_t RegMem_Reset( void )
{
    regMem_RequestState_t retState = REGMEM_REQUEST_OK;

    /* HW model of previous test is stopped before registers are cleared */
    (void)RegMem_Set_ModelInactive();

    for( uint32_t regionId = 0u; REGMEM_REGION_CNT > regionId; regionId++ )
    {
        regMem_RequestState_t clearState = regMem_Clear_Region( (regMem_RegionId_t)regionId );

        if( REGMEM_REQUEST_OK != clearState )
        {
            retState = REGMEM_REQUEST_ERROR;
        }
        else
        {
            /* Region cleared */
        }
    }

    return ( retState );
}


/**
 * \brief Unmaps all emulated regions.
 *
 * \return Function processing state. Returns \ref REGMEM_REQUEST_OK if request
 *         was processed without problems. Otherwise returns \ref REGMEM_REQUEST_ERROR.
 */
regMem_RequestState_t RegMem_Deinit( void )
{
    regMem_RequestState_t retState = REGMEM_REQUEST_OK;

    (void)RegMem_Set_ModelInactive();

    for( uint32_t regionId = 0u; REGMEM_REGION_CNT > regionId; regionId++ )
    {
        regMem_RequestState_t unmapState = regMem_Unmap_Region( (regMem_RegionId_t)regionId );

        if( REGMEM_REQUEST_OK != unmapState )
        {
            retState = REGMEM_REQUEST_ERROR;
        }
        else
        {
            /* Region unmapped */
        }
    }

    return ( retState );
}


/**
 * \brief Starts HW model - the callback is called repeatedly from background
 *        thread until \ref RegMem_Set_ModelInactive or \ref RegMem_Reset.
 *
 * \param modelCallback [in]: HW model callback, see \ref regMem_ModelCallback_t. Must not be NULL.
 *
 * \return Function processing state. Returns \ref REGMEM_REQUEST_OK if the model
 *         thread is running. Otherwise returns \ref REGMEM_REQUEST_ERROR.
 */
regMem_RequestState_t RegMem_Set_ModelActive( regMem_ModelCallback_t modelCallback )
{
    regMem_RequestState_t retState = REGMEM_REQUEST_ERROR;

    /* Only one model can run */
    (void)RegMem_Set_ModelInactive();

    if( NULL != modelCallback )
    {
        regMem_ModelCallback = modelCallback;
        regMem_ModelCycleCnt = 0u;
        regMem_ModelState    = REGMEM_MODEL_ACTIVE;

        const int createState = pthread_create( &regMem_ModelThreadId, NULL, regMem_ModelThread, NULL );

        if( 0 == createState )
        {
            /* Thread start can take longer than the busy-wait timeout of the
             * module under test (eg. on loaded Windows host) - the model shall
             * be running already when the tested function is called. */
            while( REGMEM_MODEL_STARTUP_CYCLES > regMem_ModelCycleCnt )
            {
                (void)sched_yield();
            }

            retState = REGMEM_REQUEST_OK;
        }
        else
        {
            regMem_ModelState = REGMEM_MODEL_INACTIVE;
            retState          = REGMEM_REQUEST_ERROR;
        }
    }
    else
    {
        retState = REGMEM_REQUEST_ERROR;
    }

    return ( retState );
}


/**
 * \brief Stops HW model thread (no effect if the model is not running).
 *
 * \return Function processing state. Returns \ref REGMEM_REQUEST_OK if the model
 *         thread is not running after the call. Otherwise returns \ref REGMEM_REQUEST_ERROR.
 */
regMem_RequestState_t RegMem_Set_ModelInactive( void )
{
    regMem_RequestState_t retState = REGMEM_REQUEST_OK;

    if( REGMEM_MODEL_ACTIVE == regMem_ModelState )
    {
        regMem_ModelState = REGMEM_MODEL_INACTIVE;

        const int joinState = pthread_join( regMem_ModelThreadId, NULL );

        if( 0 == joinState )
        {
            retState = REGMEM_REQUEST_OK;
        }
        else
        {
            retState = REGMEM_REQUEST_ERROR;
        }

        regMem_ModelCallback = NULL;
    }
    else
    {
        /* Model is not running */
    }

    return ( retState );
}

/* ========================== LOCAL FUNCTIONS =============================== */

/**
 * \brief HW model thread - calls model callback until the model is stopped.
 *
 * \param arg [in]: Unused
 *
 * \return Always NULL.
 */
static void * regMem_ModelThread( void *arg )
{
    (void)arg;

    while( REGMEM_MODEL_ACTIVE == regMem_ModelState )
    {
        regMem_ModelCallback();

        regMem_ModelCycleCnt++;

        (void)sched_yield();
    }

    return ( NULL );
}

/**
 * \brief Maps regions before `main()` so that static initializers of the code
 *        under test and the first test already see valid memory.
 */
__attribute__((constructor)) static void regMem_AutoInit( void )
{
    regMem_RequestState_t initState = RegMem_Init();

    if( REGMEM_REQUEST_OK != initState )
    {
        fprintf( stderr, "RegMem: register memory emulation could not be mapped.\n" );
        exit( EXIT_FAILURE );
    }
    else
    {
        /* Emulation ready */
    }
}


/**
 * \brief Maps one region at its MCU address.
 *
 * \param regionId [in]: Region identification, value from \ref regMem_RegionId_t
 *
 * \return Function processing state. Returns \ref REGMEM_REQUEST_OK if the region
 *         is mapped exactly at the required address. Otherwise returns
 *         \ref REGMEM_REQUEST_ERROR.
 */
static regMem_RequestState_t regMem_Map_Region( regMem_RegionId_t regionId )
{
    regMem_RequestState_t retState = REGMEM_REQUEST_ERROR;

    if( REGMEM_REGION_CNT > regionId )
    {
        void * const reqAddr = (void *)regMem_RegionConf[ regionId ].BaseAddr;
        const size_t size    = regMem_RegionConf[ regionId ].Size;

#if defined(_WIN32)
        void *mapAddr = VirtualAlloc( reqAddr, size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE );
#else
        void *mapAddr = mmap( reqAddr, size, PROT_READ | PROT_WRITE,
                              MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE | MAP_FIXED_NOREPLACE, -1, 0 );

        if( MAP_FAILED == mapAddr )
        {
            mapAddr = NULL;
        }
        else
        {
            /* Mapping created, address is checked below */
        }
#endif

        if( reqAddr == mapAddr )
        {
            regMem_RegionState[ regionId ] = REGMEM_REGION_MAPPED;
            retState = REGMEM_REQUEST_OK;
        }
        else
        {
            fprintf( stderr, "RegMem: region %s (0x%08lX, 0x%08lX bytes) is not available.\n",
                     regMem_RegionConf[ regionId ].Name,
                     (unsigned long)regMem_RegionConf[ regionId ].BaseAddr,
                     (unsigned long)size );

            if( NULL != mapAddr )
            {
                /* Kernel ignored the address hint, release the wrong mapping */
#if defined(_WIN32)
                (void)VirtualFree( mapAddr, 0u, MEM_RELEASE );
#else
                (void)munmap( mapAddr, size );
#endif
            }
            else
            {
                /* Nothing mapped */
            }

            retState = REGMEM_REQUEST_ERROR;
        }
    }
    else
    {
        retState = REGMEM_REQUEST_ERROR;
    }

    return ( retState );
}


/**
 * \brief Sets whole region to zero without touching every page.
 *
 * \pre   Region is mapped; otherwise \ref REGMEM_REQUEST_ERROR.
 *
 * \param regionId [in]: Region identification, value from \ref regMem_RegionId_t
 *
 * \return Function processing state. Returns \ref REGMEM_REQUEST_OK if request
 *         was processed without problems. Otherwise returns \ref REGMEM_REQUEST_ERROR.
 */
static regMem_RequestState_t regMem_Clear_Region( regMem_RegionId_t regionId )
{
    regMem_RequestState_t retState = REGMEM_REQUEST_ERROR;

    if( ( REGMEM_REGION_CNT    >  regionId                       ) &&
        ( REGMEM_REGION_MAPPED == regMem_RegionState[ regionId ] )    )
    {
        void * const addr = (void *)regMem_RegionConf[ regionId ].BaseAddr;
        const size_t size = regMem_RegionConf[ regionId ].Size;

#if defined(_WIN32)
        /* Decommitted pages are zero-filled on the next commit */
        BOOL  freeState = VirtualFree( addr, size, MEM_DECOMMIT );
        void *mapAddr   = VirtualAlloc( addr, size, MEM_COMMIT, PAGE_READWRITE );

        if( ( FALSE != freeState ) && ( addr == mapAddr ) )
#else
        /* Private anonymous pages are zero-filled on the next access */
        int adviseState = madvise( addr, size, MADV_DONTNEED );

        if( 0 == adviseState )
#endif
        {
            retState = REGMEM_REQUEST_OK;
        }
        else
        {
            retState = REGMEM_REQUEST_ERROR;
        }
    }
    else
    {
        retState = REGMEM_REQUEST_ERROR;
    }

    return ( retState );
}


/**
 * \brief Unmaps one region.
 *
 * \param regionId [in]: Region identification, value from \ref regMem_RegionId_t
 *
 * \return Function processing state. Returns \ref REGMEM_REQUEST_OK if the region
 *         is not mapped after the call. Otherwise returns \ref REGMEM_REQUEST_ERROR.
 */
static regMem_RequestState_t regMem_Unmap_Region( regMem_RegionId_t regionId )
{
    regMem_RequestState_t retState = REGMEM_REQUEST_ERROR;

    if( ( REGMEM_REGION_CNT    >  regionId                       ) &&
        ( REGMEM_REGION_MAPPED == regMem_RegionState[ regionId ] )    )
    {
        void * const addr = (void *)regMem_RegionConf[ regionId ].BaseAddr;

#if defined(_WIN32)
        BOOL freeState = VirtualFree( addr, 0u, MEM_RELEASE );

        if( FALSE != freeState )
#else
        int unmapState = munmap( addr, regMem_RegionConf[ regionId ].Size );

        if( 0 == unmapState )
#endif
        {
            regMem_RegionState[ regionId ] = REGMEM_REGION_UNMAPPED;
            retState = REGMEM_REQUEST_OK;
        }
        else
        {
            retState = REGMEM_REQUEST_ERROR;
        }
    }
    else if( REGMEM_REGION_CNT > regionId )
    {
        /* Region is not mapped, nothing to do */
        retState = REGMEM_REQUEST_OK;
    }
    else
    {
        retState = REGMEM_REQUEST_ERROR;
    }

    return ( retState );
}
