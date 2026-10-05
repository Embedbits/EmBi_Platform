/**
 * \author Mr.Nobody
 * \file unity_config.h
 * \ingroup IntegrationTesting
 * \brief Unity configuration of integration test firmware (UNITY_INCLUDE_CONFIG_H).
 *
 * Unity output is stored into the result mailbox (IntegrationTesting.c).
 */

#ifndef INTEGRATIONTESTING_UNITY_CONFIG_H
#define INTEGRATIONTESTING_UNITY_CONFIG_H

/** Output of one character of Unity report */
#define UNITY_OUTPUT_CHAR( a )                      IntegrationTesting_PutChar( a )

/** Declaration of output function (used by unity_internals.h) */
#define UNITY_OUTPUT_CHAR_HEADER_DECLARATION        IntegrationTesting_PutChar( int )

#endif /* INTEGRATIONTESTING_UNITY_CONFIG_H */
