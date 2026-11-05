/**
 * \author Mr.Nobody
 * \file IntegrationTesting_CoreArmv8m.c
 * \ingroup IntegrationTesting
 * \brief Integration testing on target - halts of the core by the debug probe, Cortex-M33 (AB#2331).
 *
 * The probe (probe-rs) halts the core on the attach of a probe session and on its end for about 10 - 20 ms each, as on
 * Cortex-M4 / M7, but the sticky flag DFSR.HALTED stays cleared (measured on STM32H533). The exit of the core from the
 * halt sets the sticky flag S_RESTART_ST of the Debug Halting Control and Status Register (DHCSR), a read of DHCSR
 * clears it.
 */

#if defined(__ARM_ARCH_8M_MAIN__)

/* ============================= INCLUDES =================================== */
#include "IntegrationTesting_Core.h"        /* Self include                   */
#include "stdint.h"                         /* Standard types                 */
#include "stdatomic.h"                      /* Memory barriers                */
/* ============================= TYPEDEFS =================================== */

/* ======================= FORWARD DECLARATIONS ============================= */

/* ========================= SYMBOLIC CONSTANTS ============================= */

/** Debug Halting Control and Status Register (DHCSR) and its sticky flag S_RESTART_ST */
#define IT_DHCSR_ADDR                       ( 0xE000EDF0u )
#define IT_DHCSR_S_RESTART_ST               ( 0x04000000u )

/* ============================== MACROS ==================================== */

/* ========================= EXPORTED VARIABLES ============================= */

/* ========================== LOCAL VARIABLES =============================== */

/* ======================== EXPORTED FUNCTIONS ============================== */

/**
 * \brief Clears the sticky flag of an exit of the core from a halt by the debugger (DHCSR.S_RESTART_ST, cleared by
 *        the read).
 */
void IntegrationTesting_Core_ClearHalted( void )
{
    (void)*(volatile const uint32_t *)IT_DHCSR_ADDR;

    /* The flag is cleared before the mailbox writes the host reacts to */
    atomic_thread_fence( memory_order_seq_cst );
}


/**
 * \brief Waits for a halt of the core by the probe after \ref IntegrationTesting_Core_ClearHalted (DHCSR.S_RESTART_ST).
 *
 * \param waitLoops [in]: Longest wait [loop passes], then the execution continues (a lost halt must not block)
 */
void IntegrationTesting_Core_WaitHalted( uint32_t waitLoops )
{
    for( uint32_t loopIdx = 0u; waitLoops > loopIdx; loopIdx++ )
    {
        const uint32_t dhcsr = *(volatile const uint32_t *)IT_DHCSR_ADDR;

        if( 0u != ( IT_DHCSR_S_RESTART_ST & dhcsr ) )
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

#endif /* __ARM_ARCH_8M_MAIN__ */
