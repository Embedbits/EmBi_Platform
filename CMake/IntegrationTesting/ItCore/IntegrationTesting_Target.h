/**
 * \author Mr.Nobody
 * \file IntegrationTesting_Target.h
 * \ingroup IntegrationTesting
 * \brief Integration testing on target - target interface implemented by every test set.
 *
 * The framework (ItCore) does not know the target - no MCU, BSP, MCAL or CPU
 * architecture specific code. Every test set implements this interface in its
 * own source (ItTarget_<Module>.c, created from the template by Setup scripts)
 * and initializes everything the tests need itself.
 *
 * Responsibilities of the test set:
 *  - entry point of the test firmware (eg. BspMain() called by StartUp), which
 *    calls \ref IntegrationTesting_Run
 *  - \ref ItTarget_Init - initialization executed on every boot (one test case
 *    per boot): fault handlers, debug freeze of used peripherals, clocks, ...
 *  - fault handlers, which pass the fault to \ref IntegrationTesting_ReportFault
 *  - \ref ItTarget_SystemReset - reset of the target between the test cases
 */

#ifndef INTEGRATIONTESTING_INTEGRATIONTESTING_TARGET_H
#define INTEGRATIONTESTING_INTEGRATIONTESTING_TARGET_H

#ifdef __cplusplus
 extern "C" {
#endif /* __cplusplus */

/* ======================== EXPORTED FUNCTIONS ============================== */

/**
 * \brief Initialization of the target executed on every boot before the
 *        evaluation of the test session (called by \ref IntegrationTesting_Run).
 *
 * \note Implemented by the test set.
 */
void ItTarget_Init          ( void );

/**
 * \brief Resets the target (all core and peripheral state, RAM section of the
 *        mailbox is kept). The function shall not return.
 *
 * \note Implemented by the test set.
 */
void ItTarget_SystemReset   ( void );

#ifdef __cplusplus
}
#endif /* __cplusplus */

#endif /* INTEGRATIONTESTING_INTEGRATIONTESTING_TARGET_H */
