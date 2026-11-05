/**
 * \author Mr.Nobody
 * \file IntegrationTesting_Core.h
 * \ingroup IntegrationTesting
 * \brief Integration testing on target - halts of the core by the debug probe (handler per core, AB#2331).
 *
 * The host polls the mailbox by probe-rs trace, a halt of the core by a probe session in the middle of a test case
 * loses the data of a running transfer. The framework waits for the halts of the probe sessions of the host outside
 * the test cases (IntegrationTesting.c). Their detection depends on the core, one handler per core is compiled
 * (by the predefined macro of the architecture of the compiler):
 *
 *  - IntegrationTesting_CoreArmv7m.c - Cortex-M4, Cortex-M7: the probe halts the core on the attach and on the end
 *    of a probe session, detected by the sticky flag DFSR.HALTED
 *  - IntegrationTesting_CoreArmv8m.c - Cortex-M33: the same halts, DFSR.HALTED stays cleared (STM32H533) - detected
 *    by the sticky flag DHCSR.S_RESTART_ST
 */

#ifndef INTEGRATIONTESTING_INTEGRATIONTESTING_CORE_H
#define INTEGRATIONTESTING_INTEGRATIONTESTING_CORE_H

#ifdef __cplusplus
 extern "C" {
#endif /* __cplusplus */

/* ============================= INCLUDES =================================== */
#include "stdint.h"                         /* Standard types                 */
/* ============================= TYPEDEFS =================================== */

/* ========================= SYMBOLIC CONSTANTS ============================= */

/* ========================= EXPORTED MACROS ================================ */

/* ========================= EXPORTED VARIABLES ============================= */

/* ======================== EXPORTED FUNCTIONS ============================== */

void IntegrationTesting_Core_ClearHalted    ( void );
void IntegrationTesting_Core_WaitHalted     ( uint32_t waitLoops );

#ifdef __cplusplus
}
#endif /* __cplusplus */

#endif /* INTEGRATIONTESTING_INTEGRATIONTESTING_CORE_H */
