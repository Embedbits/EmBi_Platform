/**
 * \author Mr.Nobody
 * \file IntegrationTesting_CoreArmv7m.c
 * \ingroup IntegrationTesting
 * \brief Integration testing on target - halts of the core by the debug probe, Cortex-M4 / Cortex-M7 (AB#2331).
 *
 * The probe (probe-rs) halts the core on the attach of a probe session and on its end for about 30 ms each. Every
 * halt sets the sticky flag HALTED of the Debug Fault Status Register (DFSR), the flag is cleared by writing 1 (a mark
 * in the FPB is not usable: Cortex-M7 does not keep a disabled comparator, probe-rs disables the FPB at the end of a
 * session).
 */

#if defined(__ARM_ARCH_7EM__)

/* ============================= INCLUDES =================================== */
#include "IntegrationTesting_Core.h"        /* Self include                   */
#include "stdint.h"                         /* Standard types                 */
#include "stdatomic.h"                      /* Memory barriers                */
/* ============================= TYPEDEFS =================================== */

/* ======================= FORWARD DECLARATIONS ============================= */

/* ========================= SYMBOLIC CONSTANTS ============================= */

/** Debug Fault Status Register (DFSR) and its sticky flag HALTED */
#define IT_DFSR_ADDR                        ( 0xE000ED30u )
#define IT_DFSR_HALTED                      ( 0x00000001u )

/* ============================== MACROS ==================================== */

/* ========================= EXPORTED VARIABLES ============================= */

/* ========================== LOCAL VARIABLES =============================== */

/* ======================== EXPORTED FUNCTIONS ============================== */

/**
 * \brief Clears the sticky flag of a halt of the core by the debugger (DFSR.HALTED).
 */
void IntegrationTesting_Core_ClearHalted( void )
{
    *(volatile uint32_t *)IT_DFSR_ADDR = IT_DFSR_HALTED;

    /* The flag is cleared before the mailbox writes the host reacts to */
    atomic_thread_fence( memory_order_seq_cst );
}


/**
 * \brief Waits for a halt of the core by the probe after \ref IntegrationTesting_Core_ClearHalted (DFSR.HALTED).
 *
 * \param waitLoops [in]: Longest wait [loop passes], then the execution continues (a lost halt must not block)
 */
void IntegrationTesting_Core_WaitHalted( uint32_t waitLoops )
{
    for( uint32_t loopIdx = 0u; waitLoops > loopIdx; loopIdx++ )
    {
        const uint32_t dfsr = *(volatile const uint32_t *)IT_DFSR_ADDR;

        if( 0u != ( IT_DFSR_HALTED & dfsr ) )
        {
            break;
        }
        else
        {
            /* No halt yet */
        }
    }
}

/* ========================== LOCAL FUNCTIONS =============================== */

/* =============================== TASKS ==================================== */

#endif /* __ARM_ARCH_7EM__ */
