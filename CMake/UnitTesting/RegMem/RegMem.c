/**
 * \author Mr.Nobody
 * \file RegMem.c
 * \ingroup UnitTesting
 * \brief Register memory emulation for host based unit tests.
 *
 */

/* Register names of ucontext_t (REG_EFL, REG_ERR) */
#if !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

/* ============================= INCLUDES =================================== */
#include "RegMem.h"                         /* Self include                   */
#include "stddef.h"                         /* Standard definitions           */
#include "stdio.h"                          /* Error reporting                */
#include "stdlib.h"                         /* Process termination            */
#include "string.h"                         /* strcmp                         */

#if defined(_WIN32)
#include <windows.h>                        /* VirtualAlloc / VirtualFree     */
#else
#include <sys/mman.h>                       /* mmap / madvise / munmap        */
#include <unistd.h>                         /* sysconf                        */
#if defined(__linux__)
#include <sys/resource.h>                   /* setpriority                    */
#include <sys/syscall.h>                    /* SYS_gettid                     */
#include <signal.h>                         /* Write trap handlers            */
#include <ucontext.h>                       /* Trap flag of the interrupted code */
#endif
#endif
#include <pthread.h>                        /* HW model thread                */
#include <sched.h>                          /* sched_yield                    */
#include <stdbool.h>                        /* bool                           */

/**
 * Synchronous HW model (write trap) needs to single step the trapped store -
 * x86-64 trap flag, Linux (signals) and Windows (vectored exception handler).
 * Other hosts use the HW model thread.
 */
#if ( defined(__linux__) && defined(__x86_64__) ) || ( defined(_WIN32) && ( defined(__x86_64__) || defined(_M_X64) ) )
#define REGMEM_TRAP_SUPPORTED               ( 1 )
#endif
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
static regMem_RequestState_t regMem_Start_ModelThread( regMem_ModelCallback_t modelCallback );
static regMem_ModelMode_t    regMem_Select_ModelMode ( void );
static bool                  regMem_Is_DebuggerAttached( void );
static bool                  regMem_Is_EmulatedRegister( uintptr_t addr );
#if defined(REGMEM_TRAP_SUPPORTED)
static bool                  regMem_Trap_Probe       ( void );
static regMem_RequestState_t regMem_Trap_Arm         ( void );
static void                  regMem_Trap_Disarm      ( void );
static void                  regMem_Trap_RunModel    ( bool regionsOpen );
static void                  regMem_Trap_ProbeModel  ( void );
static regMem_RequestState_t regMem_Trap_Install     ( void );
#if defined(_WIN32)
static regMem_RequestState_t regMem_Trap_Protect     ( DWORD protection );
static void                  regMem_Win_Close_Pages  ( void );
#else
static regMem_RequestState_t regMem_Trap_Protect     ( int protection );
#endif
#endif

/* ========================= SYMBOLIC CONSTANTS ============================= */

/** Name of the environment variable selecting the HW model implementation (sync / thread / auto) */
#define REGMEM_MODEL_MODE_ENV           ( "REGMEM_MODEL_MODE" )

/** Last word of the peripheral region - written by the start-up probe of the write trap */
#define REGMEM_PROBE_ADDR               ( REGMEM_PERIPH_BASE + REGMEM_PERIPH_SIZE - 4u )

/** Trap flag of the x86 flags register - the CPU stops after the next instruction */
#define REGMEM_EFLAGS_TF                ( 0x100u )

/** Write bit of the x86 page fault error code */
#define REGMEM_PF_ERR_WRITE             ( 0x2u )

/** Count of pages unprotected at once for a trapped store and the model reaction (Windows) */
#define REGMEM_STEP_PAGES_MAX           ( 64u )

/** Size of the pages protected one by one (Windows) */
#define REGMEM_PAGE_SIZE                ( 4096u )

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

/** Count of logical processors from which the HW model thread spins (higher priority on Windows) */
#define REGMEM_MODEL_SPIN_MIN_CPUS      ( 2u )

#if defined(__linux__)
/** Nice value requested for the HW model thread (not permitted without privileges - ignored then) */
#define REGMEM_MODEL_NICE               ( -5 )
#endif

#if !defined(_WIN32) && !defined(MAP_FIXED_NOREPLACE)
#if defined(__APPLE__)
/** macOS has no such flag (mmap() rejects the Linux value): the address is only a hint, result is checked */
#define MAP_FIXED_NOREPLACE             ( 0 )
#else
/** Linux < 4.17 headers: flag is then used only as hint, result is checked */
#define MAP_FIXED_NOREPLACE             ( 0x100000 )
#endif /* __APPLE__ */
#endif

#if defined(__APPLE__)
/** File descriptor of an anonymous mapping (mmap) */
#define REGMEM_MMAP_ANONYMOUS_FD        ( -1 )

/** File offset of an anonymous mapping (mmap) */
#define REGMEM_MMAP_ANONYMOUS_OFFSET    ( 0 )
#endif /* __APPLE__ */

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

/** Implementation of the active HW model (none when no model is active) */
static regMem_ModelMode_t           regMem_ActiveMode    = REGMEM_MODEL_MODE_NONE;

#if defined(REGMEM_TRAP_SUPPORTED)

/** Write trap is armed - the emulated registers are write protected */
static volatile int                 regMem_TrapArmed     = 0;

/** A trapped store is being single stepped (between the access violation and the trap exception) */
static volatile int                 regMem_TrapStepping  = 0;

/** The model callback is running (stores of the model are not trapped) */
static volatile int                 regMem_ModelRunning  = 0;

/** Count of model calls of the start-up probe */
static volatile uint32_t            regMem_ProbeCnt      = 0u;

#if defined(_WIN32)

/** Handle of the vectored exception handler */
static PVOID                        regMem_VehHandle     = NULL;

/** Pages unprotected for the trapped store and for the stores of the model */
static uintptr_t                    regMem_StepPages[ REGMEM_STEP_PAGES_MAX ];

/** Count of used items of \ref regMem_StepPages */
static uint32_t                     regMem_StepPageCnt   = 0u;

/** Whole emulated registers are unprotected (\ref regMem_StepPages overflow) */
static bool                         regMem_WholeOpen     = false;

#else

/** Signal actions replaced by the write trap */
static struct sigaction             regMem_OldSegvAction;
static struct sigaction             regMem_OldTrapAction;

#endif /* _WIN32 */

#endif /* REGMEM_TRAP_SUPPORTED */

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
 * \brief Starts HW model - the callback reacts on the stores to the emulated registers.
 *
 * \details Synchronous mode (default on x86-64 Linux / Windows): the callback is called once here
 *          and then in the thread of the code under test right after every store to the emulated
 *          peripheral / private peripheral bus registers (the registers are write protected, the
 *          store is single stepped), until \ref RegMem_Set_ModelInactive or \ref RegMem_Reset.
 *          The reaction of the model depends on the executed stores only, not on the speed or
 *          the load of the host.
 *          Thread mode (other hosts, debugger attached, REGMEM_MODEL_MODE=thread): the callback is
 *          called repeatedly from a background thread.
 *
 * \param modelCallback [in]: HW model callback, see \ref regMem_ModelCallback_t. Must not be NULL.
 *
 * \return Function processing state. Returns \ref REGMEM_REQUEST_OK if the model is active.
 *         Otherwise returns \ref REGMEM_REQUEST_ERROR.
 */
regMem_RequestState_t RegMem_Set_ModelActive( regMem_ModelCallback_t modelCallback )
{
    regMem_RequestState_t retState = REGMEM_REQUEST_ERROR;

    /* Only one model can run */
    (void)RegMem_Set_ModelInactive();

    if( NULL != modelCallback )
    {
#if defined(REGMEM_TRAP_SUPPORTED)
        if( REGMEM_MODEL_MODE_SYNC == regMem_Select_ModelMode() )
        {
            regMem_ModelCallback = modelCallback;
            regMem_ModelCycleCnt = 0u;

            /* Registers are not protected yet - initial evaluation of the model */
            modelCallback();
            regMem_ModelCycleCnt++;

            retState = regMem_Trap_Arm();

            if( REGMEM_REQUEST_OK == retState )
            {
                regMem_ActiveMode = REGMEM_MODEL_MODE_SYNC;
            }
            else
            {
                regMem_Trap_Disarm();
                regMem_ModelCallback = NULL;
            }
        }
        else
#endif
        {
            retState = regMem_Start_ModelThread( modelCallback );
        }
    }
    else
    {
        retState = REGMEM_REQUEST_ERROR;
    }

    return ( retState );
}


/**
 * \brief Stops HW model (no effect if the model is not active).
 *
 * \return Function processing state. Returns \ref REGMEM_REQUEST_OK if the model
 *         is not active after the call. Otherwise returns \ref REGMEM_REQUEST_ERROR.
 */
regMem_RequestState_t RegMem_Set_ModelInactive( void )
{
    regMem_RequestState_t retState = REGMEM_REQUEST_OK;

#if defined(REGMEM_TRAP_SUPPORTED)
    if( REGMEM_MODEL_MODE_SYNC == regMem_ActiveMode )
    {
        regMem_Trap_Disarm();
        regMem_ModelCallback = NULL;
        regMem_ActiveMode    = REGMEM_MODEL_MODE_NONE;
    }
    else
#endif
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
        regMem_ActiveMode    = REGMEM_MODEL_MODE_NONE;
    }
    else
    {
        /* Model is not running */
    }

    return ( retState );
}

/**
 * \brief Lets the HW model react on the current register values (n times).
 *
 * \details Synchronous mode: the model callback is called cycleCnt times in the calling thread.
 *          Thread mode: waits until the model thread finishes whole cycles started after the call.
 *          The cycle running at the call may have started before the last register write of
 *          the caller (it works with an older register snapshot), so cycleCnt + 1 cycles are
 *          awaited. Intended for stubs called by the module under test in its busy-wait delays.
 *          A model which is not active is not waited for.
 *
 * \param cycleCnt [in]: Count of model cycles
 *
 * \return Always \ref REGMEM_REQUEST_OK.
 */
regMem_RequestState_t RegMem_Wait_ModelCycles( uint32_t cycleCnt )
{
#if defined(REGMEM_TRAP_SUPPORTED)
    if( REGMEM_MODEL_MODE_SYNC == regMem_ActiveMode )
    {
        for( uint32_t cycleIdx = 0u; cycleCnt > cycleIdx; cycleIdx++ )
        {
            regMem_Trap_RunModel( false );
        }
    }
    else
#endif
    {
        /* Caller's register write must be visible to the model thread before the cycle count is taken -
         * a store may otherwise be reordered after the load (store buffer) */
        __atomic_thread_fence( __ATOMIC_SEQ_CST );

        const uint32_t startCnt = regMem_ModelCycleCnt;

        while( ( REGMEM_MODEL_ACTIVE == regMem_ModelState ) &&
               ( ( cycleCnt + 1u ) > ( regMem_ModelCycleCnt - startCnt ) ) )
        {
            (void)sched_yield();
        }
    }

    return ( REGMEM_REQUEST_OK );
}


/**
 * \brief Lets the HW model react on the current register values once.
 *
 * \details For a model input which is not a register (eg. a variable of the test changed after the
 *          last store to the registers), the model does not react on it by itself in the synchronous
 *          mode. When the function returns, the model has evaluated the state at the call.
 *
 * \return Always \ref REGMEM_REQUEST_OK.
 */
regMem_RequestState_t RegMem_Step_Model( void )
{
    if( REGMEM_MODEL_MODE_SYNC == regMem_ActiveMode )
    {
        (void)RegMem_Wait_ModelCycles( 1u );
    }
    else
    {
        (void)RegMem_Wait_ModelCycles( 0u );
    }

    return ( REGMEM_REQUEST_OK );
}


/**
 * \brief Returns the implementation of the active HW model.
 *
 * \return \ref REGMEM_MODEL_MODE_SYNC (write trap), \ref REGMEM_MODEL_MODE_THREAD (background
 *         thread) or \ref REGMEM_MODEL_MODE_NONE (no model is active).
 */
regMem_ModelMode_t RegMem_Get_ModelMode( void )
{
    return ( regMem_ActiveMode );
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
    bool modelSpin = false;

    (void)arg;

#if defined(_WIN32)
    /* The module under test waits for the flags set by the model in a busy loop of a limited
     * count of iterations. A model thread which is not scheduled for longer than the loop
     * takes (the host runs other processes) causes a timeout of the tested function. On a host
     * with more processors the model therefore runs at a higher priority and spins -
     * sched_yield() would hand the processor to any ready thread, also of a lower priority,
     * for a whole quantum. */
    SYSTEM_INFO sysInfo;

    GetSystemInfo( &sysInfo );

    const DWORD cpuCnt = sysInfo.dwNumberOfProcessors;

    if( REGMEM_MODEL_SPIN_MIN_CPUS <= cpuCnt )
    {
        (void)SetThreadPriority( GetCurrentThread(), THREAD_PRIORITY_HIGHEST );
        modelSpin = true;
    }
    else
    {
        /* Single processor host - the model yields the processor to the test thread */
    }
#else
    /* Same reasoning as on Windows: sched_yield() on a loaded Linux host (parallel builds and
     * tests on the agent) gives the model a processor too rarely for the limited busy loops of
     * the tested module. On a host with more processors the model spins, so it is ready as soon
     * as it gets a processor, and asks for a better nice value (ignored without privileges). */
    const long cpuCnt = sysconf( _SC_NPROCESSORS_ONLN );

    if( ( 0 < cpuCnt ) && ( (long)REGMEM_MODEL_SPIN_MIN_CPUS <= cpuCnt ) )
    {
#if defined(__linux__)
        (void)setpriority( PRIO_PROCESS, (id_t)syscall( SYS_gettid ), REGMEM_MODEL_NICE );
#endif
        modelSpin = true;
    }
    else
    {
        /* Single processor host - the model yields the processor to the test thread */
    }
#endif /* _WIN32 */

    while( REGMEM_MODEL_ACTIVE == regMem_ModelState )
    {
        regMem_ModelCallback();

        regMem_ModelCycleCnt++;

        /* The next cycle must not read the registers before the cycle count is visible to the waiting
         * thread (store -> load reordering), see RegMem_Wait_ModelCycles */
        __atomic_thread_fence( __ATOMIC_SEQ_CST );

        if( true == modelSpin )
        {
#if defined(_WIN32)
            YieldProcessor();
#elif defined(__x86_64__) || defined(__i386__)
            __builtin_ia32_pause();
#elif defined(__aarch64__)
            __asm__ __volatile__( "yield" );
#else
            /* Plain spin */
#endif
        }
        else
        {
            (void)sched_yield();
        }
    }

    return ( NULL );
}

/**
 * \brief Starts the HW model thread (the model runs in the background).
 *
 * \param modelCallback [in]: HW model callback. Must not be NULL.
 *
 * \return Function processing state. Returns \ref REGMEM_REQUEST_OK if the model
 *         thread is running. Otherwise returns \ref REGMEM_REQUEST_ERROR.
 */
static regMem_RequestState_t regMem_Start_ModelThread( regMem_ModelCallback_t modelCallback )
{
    regMem_RequestState_t retState = REGMEM_REQUEST_ERROR;

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

        regMem_ActiveMode = REGMEM_MODEL_MODE_THREAD;
        retState          = REGMEM_REQUEST_OK;
    }
    else
    {
        regMem_ModelState = REGMEM_MODEL_INACTIVE;
        retState          = REGMEM_REQUEST_ERROR;
    }

    return ( retState );
}


/**
 * \brief Selects the implementation of the HW model for the model being started.
 *
 * \details Environment variable REGMEM_MODEL_MODE: "thread" - HW model thread, "sync" - write trap
 *          (also with a debugger attached), anything else (auto) - write trap unless a debugger is
 *          attached (the debugger stops on the exceptions of the trap). The write trap is used only
 *          if the start-up probe confirmed that it works on the host.
 *
 * \return \ref REGMEM_MODEL_MODE_SYNC or \ref REGMEM_MODEL_MODE_THREAD.
 */
static regMem_ModelMode_t regMem_Select_ModelMode( void )
{
    regMem_ModelMode_t mode = REGMEM_MODEL_MODE_THREAD;

#if defined(REGMEM_TRAP_SUPPORTED)
    const char * const env         = getenv( REGMEM_MODEL_MODE_ENV );
    const bool         forceThread = ( ( NULL != env ) && ( 0 == strcmp( env, "thread" ) ) );
    const bool         forceSync   = ( ( NULL != env ) && ( 0 == strcmp( env, "sync"   ) ) );

    if( false == forceThread )
    {
        if( ( true == forceSync ) || ( false == regMem_Is_DebuggerAttached() ) )
        {
            if( true == regMem_Trap_Probe() )
            {
                mode = REGMEM_MODEL_MODE_SYNC;
            }
            else
            {
                /* Write trap does not work on this host - HW model thread */
            }
        }
        else
        {
            /* Debugger attached - HW model thread */
        }
    }
    else
    {
        /* HW model thread requested */
    }
#endif

    return ( mode );
}


/**
 * \brief Checks if a debugger is attached to the process.
 *
 * \return true if a debugger is attached. Otherwise false.
 */
static bool regMem_Is_DebuggerAttached( void )
{
    bool attached = false;

#if defined(_WIN32)
    attached = ( FALSE != IsDebuggerPresent() );
#elif defined(__linux__)
    FILE * const status = fopen( "/proc/self/status", "r" );

    if( NULL != status )
    {
        char line[ 128 ];

        while( NULL != fgets( line, (int)sizeof( line ), status ) )
        {
            int tracerPid = 0;

            if( 1 == sscanf( line, "TracerPid: %d", &tracerPid ) )
            {
                attached = ( 0 != tracerPid );
                break;
            }
            else
            {
                /* Other line of the status file */
            }
        }

        (void)fclose( status );
    }
    else
    {
        /* Status not readable - no debugger assumed */
    }
#endif

    return ( attached );
}


/**
 * \brief Checks if the address is in the emulated peripheral or private peripheral bus registers.
 *
 * \param addr [in]: Checked address
 *
 * \return true if the address belongs to the emulated registers. Otherwise false.
 */
static bool regMem_Is_EmulatedRegister( uintptr_t addr )
{
    bool isRegister = false;

    for( uint32_t regionId = 0u; REGMEM_REGION_SRAM > regionId; regionId++ )
    {
        const uintptr_t baseAddr = regMem_RegionConf[ regionId ].BaseAddr;

        if( ( baseAddr <= addr ) && ( ( baseAddr + regMem_RegionConf[ regionId ].Size ) > addr ) )
        {
            isRegister = true;
        }
        else
        {
            /* Other region */
        }
    }

    return ( isRegister );
}


#if defined(REGMEM_TRAP_SUPPORTED)

/**
 * \brief Model of the start-up probe of the write trap - counts its calls.
 */
static void regMem_Trap_ProbeModel( void )
{
    regMem_ProbeCnt++;
}


/**
 * \brief Calls the HW model callback (synchronous mode).
 *
 * \details The callback runs in the thread of the code under test. Its stores to the emulated
 *          registers are not trapped. The registers are write protected again afterwards.
 *
 * \param regionsOpen [in]: The registers are already unprotected by the caller (trap handler on
 *                          Linux). Not used on Windows (the pages are unprotected on demand).
 */
static void regMem_Trap_RunModel( bool regionsOpen )
{
    regMem_ModelCallback_t const modelCallback = regMem_ModelCallback;

#if defined(_WIN32)
    (void)regionsOpen;
#else
    if( false == regionsOpen )
    {
        (void)regMem_Trap_Protect( PROT_READ | PROT_WRITE );
    }
    else
    {
        /* Registers are unprotected */
    }
#endif

    if( NULL != modelCallback )
    {
        regMem_ModelRunning = 1;
        modelCallback();
        regMem_ModelRunning = 0;
        regMem_ModelCycleCnt++;
    }
    else
    {
        /* No model */
    }

    if( 0 != regMem_TrapArmed )
    {
#if defined(_WIN32)
        regMem_Win_Close_Pages();
#else
        (void)regMem_Trap_Protect( PROT_READ );
#endif
    }
    else
    {
        /* Trap is not armed */
    }
}


/**
 * \brief Start-up probe of the write trap - a store is made with a counting model, the model has
 *        to be called exactly once (the host executes the single step).
 *
 * \return true if the write trap works on the host. Otherwise false (reported once to stderr).
 */
static bool regMem_Trap_Probe( void )
{
    static int probeState = 0;      /* 0 - not probed, 1 - works, -1 - does not work */

    if( 0 == probeState )
    {
        probeState = -1;

        if( REGMEM_REQUEST_OK == regMem_Trap_Install() )
        {
            regMem_ModelCallback = regMem_Trap_ProbeModel;
            regMem_ProbeCnt      = 0u;

            if( REGMEM_REQUEST_OK == regMem_Trap_Arm() )
            {
                *(volatile uint32_t *)(uintptr_t)REGMEM_PROBE_ADDR = 0x55AA55AAu;
            }
            else
            {
                /* Registers are not protectable */
            }

            regMem_Trap_Disarm();
            regMem_ModelCallback = NULL;

            *(volatile uint32_t *)(uintptr_t)REGMEM_PROBE_ADDR = 0u;

            if( 1u == regMem_ProbeCnt )
            {
                probeState = 1;
            }
            else
            {
                /* The store did not call the model once */
            }
        }
        else
        {
            /* Handlers not installed */
        }

        if( 1 != probeState )
        {
            fprintf( stderr, "RegMem: write trap of the HW model does not work on this host, the HW model runs in a thread.\n" );
        }
        else
        {
            /* Write trap available */
        }
    }
    else
    {
        /* Already probed */
    }

    return ( 1 == probeState );
}


#if defined(_WIN32)

/**
 * \brief Sets the protection of all emulated registers (peripherals, private peripheral bus).
 *
 * \param protection [in]: Windows page protection (PAGE_READONLY / PAGE_READWRITE)
 *
 * \return \ref REGMEM_REQUEST_OK if the protection was changed. Otherwise \ref REGMEM_REQUEST_ERROR.
 */
static regMem_RequestState_t regMem_Trap_Protect( DWORD protection )
{
    regMem_RequestState_t retState = REGMEM_REQUEST_OK;

    for( uint32_t regionId = 0u; REGMEM_REGION_SRAM > regionId; regionId++ )
    {
        DWORD oldProtection = 0u;

        if( FALSE == VirtualProtect( (void *)regMem_RegionConf[ regionId ].BaseAddr,
                                     regMem_RegionConf[ regionId ].Size, protection, &oldProtection ) )
        {
            retState = REGMEM_REQUEST_ERROR;
        }
        else
        {
            /* Protection changed */
        }
    }

    return ( retState );
}


/**
 * \brief Unprotects the page of a store (of the code under test or of the model).
 *
 * \details Only the page is unprotected - the protection of whole region is slow on Windows.
 *
 * \param addr [in]: Address of the store
 */
static void regMem_Win_Open_Page( uintptr_t addr )
{
    const uintptr_t page = addr & ~(uintptr_t)( REGMEM_PAGE_SIZE - 1u );
    bool            known = regMem_WholeOpen;

    for( uint32_t pageIdx = 0u; ( false == known ) && ( regMem_StepPageCnt > pageIdx ); pageIdx++ )
    {
        known = ( page == regMem_StepPages[ pageIdx ] );
    }

    if( false == known )
    {
        if( REGMEM_STEP_PAGES_MAX > regMem_StepPageCnt )
        {
            DWORD oldProtection = 0u;

            (void)VirtualProtect( (void *)page, REGMEM_PAGE_SIZE, PAGE_READWRITE, &oldProtection );
            regMem_StepPages[ regMem_StepPageCnt ] = page;
            regMem_StepPageCnt++;
        }
        else
        {
            /* The model writes many pages - all registers are unprotected until the model ends */
            (void)regMem_Trap_Protect( PAGE_READWRITE );
            regMem_WholeOpen = true;
        }
    }
    else
    {
        /* Page is already unprotected */
    }
}


/**
 * \brief Protects the pages unprotected by \ref regMem_Win_Open_Page again.
 */
static void regMem_Win_Close_Pages( void )
{
    if( true == regMem_WholeOpen )
    {
        (void)regMem_Trap_Protect( PAGE_READONLY );
        regMem_WholeOpen = false;
    }
    else
    {
        for( uint32_t pageIdx = 0u; regMem_StepPageCnt > pageIdx; pageIdx++ )
        {
            DWORD oldProtection = 0u;

            (void)VirtualProtect( (void *)regMem_StepPages[ pageIdx ], REGMEM_PAGE_SIZE, PAGE_READONLY, &oldProtection );
        }
    }

    regMem_StepPageCnt = 0u;
}


/**
 * \brief Vectored exception handler of the write trap.
 *
 * \details Store to the protected register: the page is unprotected and the trap flag is set, so
 *          the CPU executes the store and raises EXCEPTION_SINGLE_STEP right after it. There the
 *          model is called and the pages are protected again. A store of the model itself (to
 *          another page) only unprotects its page.
 *
 * \param info [in]: Exception information
 *
 * \return EXCEPTION_CONTINUE_EXECUTION for the exceptions of the trap. Otherwise
 *         EXCEPTION_CONTINUE_SEARCH.
 */
static LONG CALLBACK regMem_Trap_VehHandler( PEXCEPTION_POINTERS info )
{
    PEXCEPTION_RECORD record   = info->ExceptionRecord;
    PCONTEXT          context  = info->ContextRecord;
    LONG              retState = EXCEPTION_CONTINUE_SEARCH;

    if( ( EXCEPTION_ACCESS_VIOLATION == record->ExceptionCode ) &&
        ( 0 != regMem_TrapArmed                               ) &&
        ( 2u <= record->NumberParameters                      ) &&
        ( 1u == record->ExceptionInformation[ 0 ]             ) &&
        ( true == regMem_Is_EmulatedRegister( (uintptr_t)record->ExceptionInformation[ 1 ] ) ) )
    {
        regMem_Win_Open_Page( (uintptr_t)record->ExceptionInformation[ 1 ] );

        if( 0 == regMem_ModelRunning )
        {
            regMem_TrapStepping = 1;
            context->EFlags    |= REGMEM_EFLAGS_TF;
        }
        else
        {
            /* Store of the model - no step, the model is not called for it */
        }

        retState = EXCEPTION_CONTINUE_EXECUTION;
    }
    else if( ( EXCEPTION_SINGLE_STEP == record->ExceptionCode ) &&
             ( 0 != regMem_TrapStepping                       ) )
    {
        context->EFlags    &= ~(DWORD)REGMEM_EFLAGS_TF;
        regMem_TrapStepping = 0;

        regMem_Trap_RunModel( true );

        retState = EXCEPTION_CONTINUE_EXECUTION;
    }
    else
    {
        /* Not an exception of the trap */
    }

    return ( retState );
}


/**
 * \brief Installs the exception handler of the write trap (once).
 *
 * \return \ref REGMEM_REQUEST_OK if the handler is installed. Otherwise \ref REGMEM_REQUEST_ERROR.
 */
static regMem_RequestState_t regMem_Trap_Install( void )
{
    if( NULL == regMem_VehHandle )
    {
        regMem_VehHandle = AddVectoredExceptionHandler( 1u, regMem_Trap_VehHandler );
    }
    else
    {
        /* Already installed */
    }

    return ( ( NULL != regMem_VehHandle ) ? REGMEM_REQUEST_OK : REGMEM_REQUEST_ERROR );
}


/**
 * \brief Write protects the emulated registers.
 *
 * \return \ref REGMEM_REQUEST_OK if the registers are protected. Otherwise \ref REGMEM_REQUEST_ERROR.
 */
static regMem_RequestState_t regMem_Trap_Arm( void )
{
    regMem_TrapArmed   = 1;
    regMem_StepPageCnt = 0u;
    regMem_WholeOpen   = false;

    return ( regMem_Trap_Protect( PAGE_READONLY ) );
}


/**
 * \brief Removes the write protection of the emulated registers.
 */
static void regMem_Trap_Disarm( void )
{
    regMem_TrapArmed    = 0;
    regMem_TrapStepping = 0;
    regMem_ModelRunning = 0;

    (void)regMem_Trap_Protect( PAGE_READWRITE );

    regMem_StepPageCnt  = 0u;
    regMem_WholeOpen    = false;
}

#else /* Linux */

/**
 * \brief Sets the protection of all emulated registers (peripherals, private peripheral bus).
 *
 * \param protection [in]: PROT_READ (write trap) or PROT_READ | PROT_WRITE
 *
 * \return \ref REGMEM_REQUEST_OK if the protection was changed. Otherwise \ref REGMEM_REQUEST_ERROR.
 */
static regMem_RequestState_t regMem_Trap_Protect( int protection )
{
    regMem_RequestState_t retState = REGMEM_REQUEST_OK;

    for( uint32_t regionId = 0u; REGMEM_REGION_SRAM > regionId; regionId++ )
    {
        if( 0 != mprotect( (void *)regMem_RegionConf[ regionId ].BaseAddr,
                           regMem_RegionConf[ regionId ].Size, protection ) )
        {
            retState = REGMEM_REQUEST_ERROR;
        }
        else
        {
            /* Protection changed */
        }
    }

    return ( retState );
}


/**
 * \brief SIGSEGV handler of the write trap.
 *
 * \details Store to the protected register: the registers are unprotected and the trap flag is
 *          set, so the CPU executes the store and raises SIGTRAP right after it. Any other
 *          fault gets the previous action of the signal (the fault repeats).
 *
 * \param signalId [in]: Signal number
 * \param info     [in]: Signal information (faulting address)
 * \param context  [in,out]: Interrupted context (registers)
 */
static void regMem_Trap_SegvHandler( int signalId, siginfo_t * info, void * context )
{
    ucontext_t * const uc      = (ucontext_t *)context;
    const bool         isWrite = ( 0u != ( (uint64_t)uc->uc_mcontext.gregs[ REG_ERR ] & REGMEM_PF_ERR_WRITE ) );

    if( ( 0 != regMem_TrapArmed                                         ) &&
        ( 0 == regMem_TrapStepping                                      ) &&
        ( true == isWrite                                               ) &&
        ( true == regMem_Is_EmulatedRegister( (uintptr_t)info->si_addr ) )    )
    {
        (void)regMem_Trap_Protect( PROT_READ | PROT_WRITE );

        regMem_TrapStepping = 1;
        uc->uc_mcontext.gregs[ REG_EFL ] |= (greg_t)REGMEM_EFLAGS_TF;
    }
    else
    {
        (void)sigaction( signalId, &regMem_OldSegvAction, NULL );
    }
}


/**
 * \brief SIGTRAP handler of the write trap - the single step after the trapped store.
 *
 * \param signalId [in]: Signal number
 * \param info     [in]: Signal information
 * \param context  [in,out]: Interrupted context (registers)
 */
static void regMem_Trap_TrapHandler( int signalId, siginfo_t * info, void * context )
{
    ucontext_t * const uc = (ucontext_t *)context;

    (void)info;

    if( 0 != regMem_TrapStepping )
    {
        uc->uc_mcontext.gregs[ REG_EFL ] &= ~(greg_t)REGMEM_EFLAGS_TF;
        regMem_TrapStepping = 0;

        regMem_Trap_RunModel( true );
    }
    else
    {
        /* Trap which does not belong to the write trap - previous action of the signal */
        (void)sigaction( signalId, &regMem_OldTrapAction, NULL );
        (void)raise( signalId );
    }
}


/**
 * \brief Installs the signal handlers of the write trap (once).
 *
 * \return \ref REGMEM_REQUEST_OK if the handlers are installed. Otherwise \ref REGMEM_REQUEST_ERROR.
 */
static regMem_RequestState_t regMem_Trap_Install( void )
{
    static bool installed = false;

    if( false == installed )
    {
        struct sigaction action;

        memset( &action, 0, sizeof( action ) );
        action.sa_flags = SA_SIGINFO;
        (void)sigemptyset( &action.sa_mask );

        action.sa_sigaction = regMem_Trap_SegvHandler;

        if( 0 == sigaction( SIGSEGV, &action, &regMem_OldSegvAction ) )
        {
            action.sa_sigaction = regMem_Trap_TrapHandler;

            if( 0 == sigaction( SIGTRAP, &action, &regMem_OldTrapAction ) )
            {
                installed = true;
            }
            else
            {
                (void)sigaction( SIGSEGV, &regMem_OldSegvAction, NULL );
            }
        }
        else
        {
            /* Handler not installed */
        }
    }
    else
    {
        /* Already installed */
    }

    return ( ( true == installed ) ? REGMEM_REQUEST_OK : REGMEM_REQUEST_ERROR );
}


/**
 * \brief Write protects the emulated registers.
 *
 * \return \ref REGMEM_REQUEST_OK if the registers are protected. Otherwise \ref REGMEM_REQUEST_ERROR.
 */
static regMem_RequestState_t regMem_Trap_Arm( void )
{
    regMem_TrapArmed = 1;

    return ( regMem_Trap_Protect( PROT_READ ) );
}


/**
 * \brief Removes the write protection of the emulated registers.
 */
static void regMem_Trap_Disarm( void )
{
    regMem_TrapArmed    = 0;
    regMem_TrapStepping = 0;
    regMem_ModelRunning = 0;

    (void)regMem_Trap_Protect( PROT_READ | PROT_WRITE );
}

#endif /* _WIN32 */

#endif /* REGMEM_TRAP_SUPPORTED */


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
#elif defined(__APPLE__)
        /* madvise( MADV_DONTNEED ) does not zero anonymous pages on macOS - the region is
         * replaced by a new zero-filled anonymous mapping at the same address */
        void *mapAddr = mmap( addr,
                              size,
                              PROT_READ | PROT_WRITE,
                              MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE | MAP_FIXED,
                              REGMEM_MMAP_ANONYMOUS_FD,
                              REGMEM_MMAP_ANONYMOUS_OFFSET );

        if( addr == mapAddr )
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
