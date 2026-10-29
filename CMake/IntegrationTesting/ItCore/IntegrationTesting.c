/**
 * \author Mr.Nobody
 * \file IntegrationTesting.c
 * \ingroup IntegrationTesting
 * \brief Integration testing on target - execution of test cases and results.
 *
 * Every boot executes one test case (or one stage of the test case expecting
 * reset) and resets the target by system reset, so every test case starts from
 * reset state of the core and peripherals:
 *
 *   boot -> test set entry point -> IntegrationTesting_Run -> ItTarget_Init
 *        -> mailbox open -> evaluation of the interrupted test case
 *        -> test case [TestIndex] -> TestIndex++ -> system reset
 *        -> ... -> all test cases done -> summary -> State DONE -> busy loop
 *
 * With INTEGRATION_TEST_COVERAGE the counters of the gcov instrumentation of the code under
 * test sum up all test cases (IntegrationTesting_Coverage.h) and are serialized for the host
 * after the last one.
 *
 * Test case interrupted by reset is evaluated after the reset:
 *  - fault handler      - failure is reported by the handler, next test case
 *  - host abort command - blocked test case, failure, next test case
 *  - expected reset     - the same test case is executed again (TestStage + 1)
 *  - other reset        - unexpected reset, failure
 *
 * The framework does not contain any target specific code. Initialization,
 * fault handlers and system reset are provided by the test set through the
 * target interface (IntegrationTesting_Target.h).
 */

/* ============================= INCLUDES =================================== */
#include "IntegrationTesting.h"             /* Self include                   */
#include "IntegrationTesting_Target.h"      /* Target interface (test set)    */
#include "unity.h"                          /* Unity testing framework        */
#include "stdatomic.h"                      /* Memory barriers                */
#include "stddef.h"                         /* offsetof                       */
#if defined(IT_COVERAGE)
#include "IntegrationTesting_Coverage.h"    /* Code coverage (gcov)           */
#endif
/* ============================= TYPEDEFS =================================== */

/* ======================= FORWARD DECLARATIONS ============================= */

static void integrationTesting_MailboxOpen      ( void );
static void integrationTesting_MailboxInit      ( integrationTesting_Session_t session );
static void integrationTesting_CheckInterrupted ( void );
static void integrationTesting_RunCase          ( void );
static void integrationTesting_NextCase         ( void );
static void integrationTesting_Reset            ( void );
static void integrationTesting_MailboxFlush     ( void );
static void integrationTesting_Finish           ( void );
static void integrationTesting_PutCaseFail      ( void );
static void integrationTesting_PutLineStart     ( void );
static void integrationTesting_PutString        ( const char* text );
static void integrationTesting_PutDec           ( uint32_t value );
static void integrationTesting_PutHex           ( uint32_t value );
static void integrationTesting_Idle             ( void );

/* ========================= SYMBOLIC CONSTANTS ============================= */

/** Count of hexadecimal digits of 32-bit value */
#define IT_HEX_DIGIT_CNT                    ( 8u )

/** Bits of one hexadecimal digit */
#define IT_HEX_DIGIT_BITS                   ( 4u )

/** Mask of one hexadecimal digit */
#define IT_HEX_DIGIT_MASK                   ( 0xFu )

/** Count of decimal digits of 32-bit value */
#define IT_DEC_DIGIT_CNT                    ( 10u )

/** Base of decimal numbers */
#define IT_DEC_BASE                         ( 10u )

/** Test function name used for failures outside of any test case */
#define IT_CORE_NAME                        "IntegrationTesting"

/** Size of the widest ECC word of a RAM [B] (64-bit ECC word of STM32H7 AXI SRAM) - alignment of the mailbox */
#define IT_RAM_ECC_WORD_SIZE                ( 8u )

/** Count of ECC words of \ref IT_RAM_ECC_WORD_SIZE of the mailbox header (the header is 12 words - 6 ECC words) */
#define IT_MAILBOX_HEADER_ECC_WORDS         ( offsetof( integrationTesting_Mailbox_t, Output ) / IT_RAM_ECC_WORD_SIZE )

/* ============================== MACROS ==================================== */

/* ========================= EXPORTED VARIABLES ============================= */

/**
 * Result mailbox read by host. Located in ".noinit" - not initialized by the
 * startup code, content is kept over system reset between the test cases.
 */
__attribute__((section(".noinit"), aligned(IT_RAM_ECC_WORD_SIZE)))
integrationTesting_Mailbox_t integrationTesting_Mailbox;

/* ========================== LOCAL VARIABLES =============================== */

/* ======================== EXPORTED FUNCTIONS ============================== */

/**
 * \brief Executes one test case (see file description) and resets the target.
 *
 * Called by the entry point of the test firmware (provided by the test set).
 * When all test cases are executed, the summary is stored and the end of
 * execution is signaled to host. The function never returns.
 */
void IntegrationTesting_Run( void )
{
#if defined(IT_COVERAGE)
    /* The counters of the gcov instrumentation are kept over the resets between the test cases,
       they are cleared once - when a new test session starts (the mailbox is not valid yet) */
    if( IT_MAILBOX_MAGIC != integrationTesting_Mailbox.Magic )
    {
        IntegrationTesting_Coverage_Clear();
    }
#endif

    ItTarget_Init();

    integrationTesting_MailboxOpen();

    integrationTesting_CheckInterrupted();

    const integrationTesting_State_t state = integrationTesting_Mailbox.State;
    const uint32_t                   index = integrationTesting_Mailbox.TestIndex;

    if( IT_STATE_RUNNING != state )
    {
        /* Tests are finished, reset of MCU (debugger, button) keeps the results */
    }
    else if( integrationTesting_TestCount > index )
    {
        integrationTesting_RunCase();

        integrationTesting_Reset();
    }
    else
    {
        integrationTesting_Finish();
    }

    integrationTesting_Idle();
}


/**
 * \brief Reports fault as failure of the actual test case and continues by
 *        the next test case. Called by fault handlers of the test set.
 *
 * Output: "<file>:<line>:<test>:FAIL: <faultName> <Name>=0x<Value> ...".
 * Fault outside of test case (test framework itself) finishes the execution.
 * The function never returns.
 *
 * \param faultName   [in]: Name of the fault (eg. "HardFault")
 * \param faultRegs   [in]: Registers printed with the fault (NULL if faultRegCnt is 0)
 * \param faultRegCnt [in]: Count of registers in faultRegs
 */
void IntegrationTesting_ReportFault( const char* faultName, const integrationTesting_FaultReg_t* faultRegs, uint32_t faultRegCnt )
{
    const integrationTesting_CasePhase_t casePhase = integrationTesting_Mailbox.CasePhase;

    if( IT_CASE_IDLE != casePhase )
    {
        integrationTesting_PutCaseFail();
    }
    else
    {
        integrationTesting_PutLineStart();
        integrationTesting_PutString( integrationTesting_TestFile );
        integrationTesting_PutString( ":0:" IT_CORE_NAME ":FAIL: " );
    }

    if( 0 != faultName )
    {
        integrationTesting_PutString( faultName );
    }
    else
    {
        integrationTesting_PutString( "Fault" );
    }

    for( uint32_t regIdx = 0u; ( 0 != faultRegs ) && ( faultRegCnt > regIdx ); regIdx++ )
    {
        integrationTesting_PutString( " " );
        integrationTesting_PutString( faultRegs[ regIdx ].Name );
        integrationTesting_PutString( "=" );
        integrationTesting_PutHex( faultRegs[ regIdx ].Value );
    }

    integrationTesting_PutString( "\n" );

    if( IT_CASE_IDLE != casePhase )
    {
        integrationTesting_Mailbox.Failures++;
        integrationTesting_NextCase();
        integrationTesting_Reset();
    }
    else
    {
        /* Test framework is broken - results so far are reported */
        integrationTesting_Mailbox.State = IT_STATE_FINISHED;
    }

    integrationTesting_Idle();
}


/**
 * \brief Stores one character of Unity output into the mailbox.
 *
 * \note Used as UNITY_OUTPUT_CHAR. Characters over the buffer size are dropped,
 *       host detects the overflow by Length equal to Size.
 *
 * \param character [in]: Character to store
 */
void IntegrationTesting_PutChar( int character )
{
    const uint32_t length = integrationTesting_Mailbox.Length;

    if( IT_OUTPUT_SIZE > length )
    {
        integrationTesting_Mailbox.Output[ length ] = (char)character;
        integrationTesting_Mailbox.Length           = length + 1u;
    }
    else
    {
        /* Buffer is full - character is dropped */
    }
}


/**
 * \brief Returns stage of the actual test case.
 *
 * Stage is 0 when the test case is started, every expected reset (see
 * \ref IntegrationTesting_Set_ResetExpected) increments it and the test case
 * is executed again. Test case expecting reset selects its part by the stage:
 *
 * \code
 * void It_Iwdg_Timeout_ResetsMcu( void )
 * {
 *     if( 0u == IntegrationTesting_Get_Stage() )
 *     {
 *         IntegrationTesting_Set_ResetExpected();
 *         ... start watchdog, wait ...
 *         TEST_FAIL_MESSAGE( "Reset did not occur" );
 *     }
 *     else
 *     {
 *         ... check reset source (target specific, test set) ...
 *     }
 * }
 * \endcode
 *
 * \return Stage of the actual test case
 */
integrationTesting_Stage_t IntegrationTesting_Get_Stage( void )
{
    return ( integrationTesting_Mailbox.TestStage );
}


/**
 * \brief Marks that the actual test case expects reset of the MCU.
 *
 * After the next reset the test case is executed again with incremented stage
 * (\ref IntegrationTesting_Get_Stage) instead of reporting unexpected reset.
 * The mark is valid until the end of the test case or the next reset.
 *
 * \note Reset source flags are target specific - the test case checking the
 *       reset source clears them itself before the reset.
 */
void IntegrationTesting_Set_ResetExpected( void )
{
    integrationTesting_Mailbox.CasePhase = IT_CASE_RESET_EXPECTED;

    /* The mark has to survive the reset of the test case */
    integrationTesting_MailboxFlush();
}

/* ========================== LOCAL FUNCTIONS =============================== */

/**
 * \brief Opens the mailbox after reset - continues or starts the test session.
 *
 * Host writes \ref IT_MAILBOX_START into Magic before reset to start new test
 * session. Valid mailbox continues the session. Other content (power-on,
 * debugging without host, SRAM erased on reset) starts local session - host
 * detects it as the mailbox not kept over reset.
 */
static void integrationTesting_MailboxOpen( void )
{
    const uint32_t magic = integrationTesting_Mailbox.Magic;

    if( IT_MAILBOX_MAGIC == magic )
    {
        /* Session continues after reset */
    }
    else if( IT_MAILBOX_START == magic )
    {
        integrationTesting_MailboxInit( IT_SESSION_HOST );
    }
    else
    {
        integrationTesting_MailboxInit( IT_SESSION_LOCAL );
    }
}


/**
 * \brief Initializes the mailbox for new test session.
 *
 * \param session [in]: Origin of the session, value from \ref integrationTesting_Session_t
 */
static void integrationTesting_MailboxInit( integrationTesting_Session_t session )
{
    integrationTesting_Mailbox.Length    = 0u;
    integrationTesting_Mailbox.Size      = IT_OUTPUT_SIZE;
    integrationTesting_Mailbox.Session   = session;
    integrationTesting_Mailbox.Command   = IT_COMMAND_NONE;
    integrationTesting_Mailbox.TestIndex = 0u;
    integrationTesting_Mailbox.TestCount = integrationTesting_TestCount;
    integrationTesting_Mailbox.TestStage = 0u;
    integrationTesting_Mailbox.CasePhase = IT_CASE_IDLE;
    integrationTesting_Mailbox.Failures  = 0u;
    integrationTesting_Mailbox.Ignored   = 0u;
    integrationTesting_Mailbox.State     = IT_STATE_RUNNING;

    /* Header is complete before the mailbox is marked valid */
    atomic_thread_fence( memory_order_seq_cst );

    integrationTesting_Mailbox.Magic     = IT_MAILBOX_MAGIC;
}


/**
 * \brief Evaluates the test case interrupted by reset of the MCU.
 *
 * Abort by host and unexpected reset are reported as failure of the test case
 * and the execution continues by the next one. Expected reset executes the
 * same test case again in the next stage.
 */
static void integrationTesting_CheckInterrupted( void )
{
    const integrationTesting_CasePhase_t casePhase = integrationTesting_Mailbox.CasePhase;
    const integrationTesting_Command_t   command   = integrationTesting_Mailbox.Command;

    if( IT_CASE_IDLE == casePhase )
    {
        /* No test case was interrupted */
    }
    else if( IT_COMMAND_ABORT == command )
    {
        integrationTesting_PutCaseFail();
        integrationTesting_PutString( "Timeout - test case blocked, aborted by host (stage " );
        integrationTesting_PutDec( integrationTesting_Mailbox.TestStage );
        integrationTesting_PutString( ")\n" );

        integrationTesting_Mailbox.Failures++;
        integrationTesting_NextCase();
    }
    else if( IT_CASE_RESET_EXPECTED == casePhase )
    {
        /* Expected reset - the test case continues by next stage */
        integrationTesting_Mailbox.TestStage++;
    }
    else
    {
        integrationTesting_PutCaseFail();
        integrationTesting_PutString( "Unexpected reset (stage " );
        integrationTesting_PutDec( integrationTesting_Mailbox.TestStage );
        integrationTesting_PutString( ")\n" );

        integrationTesting_Mailbox.Failures++;
        integrationTesting_NextCase();
    }

    integrationTesting_Mailbox.Command = IT_COMMAND_NONE;
}


/**
 * \brief Executes the actual test case (one stage) by Unity.
 *
 * Unity prints the result line "<file>:<line>:<test>:PASS|FAIL|IGNORE", its
 * counters are valid for one boot only - totals are kept in the mailbox.
 */
static void integrationTesting_RunCase( void )
{
    const integrationTesting_TestCase_t * const testCase = &integrationTesting_TestCases[ integrationTesting_Mailbox.TestIndex ];

    UnityBegin( integrationTesting_TestFile );

    /* Test case may change the phase to "reset expected" */
    integrationTesting_Mailbox.CasePhase = IT_CASE_RUNNING;

    UnityDefaultTestRun( testCase->Func, testCase->Name, (int)testCase->Line );

    if( 0u != Unity.TestFailures )
    {
        integrationTesting_Mailbox.Failures++;
    }
    else if( 0u != Unity.TestIgnores )
    {
        integrationTesting_Mailbox.Ignored++;
    }
    else
    {
        /* Test case passed */
    }

    integrationTesting_NextCase();
}


/**
 * \brief Finishes the actual test case, the next boot executes the next one.
 */
static void integrationTesting_NextCase( void )
{
    integrationTesting_Mailbox.CasePhase = IT_CASE_IDLE;
    integrationTesting_Mailbox.TestStage = 0u;
    integrationTesting_Mailbox.TestIndex++;
}


/**
 * \brief Resets the target before the next test case (test set implementation).
 */
static void integrationTesting_Reset( void )
{
    /* Mailbox is written before the reset */
    atomic_thread_fence( memory_order_seq_cst );

    integrationTesting_MailboxFlush();

    ItTarget_SystemReset();
}


/**
 * \brief Completes the writes of the mailbox in the RAM before a reset of the MCU.
 *
 * RAM with ECC per 64-bit word (STM32H7 AXI SRAM, RM0468 "Error code correction": a write narrower than the
 * ECC word is not really written to the SRAM when a reset occurs): TestIndex was lost over the reset between the
 * test cases on STM32H723 (32-bit writes, also when written twice). Every ECC word of the header and the ECC word
 * with the end of the output are written again with their own value by one 64-bit access each (a complete ECC
 * word). Layout and content of the mailbox are unchanged (host interface); on a RAM without this behavior the
 * words are only written again.
 */
static void integrationTesting_MailboxFlush( void )
{
    volatile uint64_t * const mailboxEccWords = (volatile uint64_t *)&integrationTesting_Mailbox;
    const uint32_t            outputLength    = integrationTesting_Mailbox.Length;
    uint32_t                  outputEccWord   = 0u;

    atomic_thread_fence( memory_order_seq_cst );

    for( uint32_t eccWordIdx = 0u; IT_MAILBOX_HEADER_ECC_WORDS > eccWordIdx; eccWordIdx++ )
    {
        const uint64_t value = mailboxEccWords[ eccWordIdx ];

        mailboxEccWords[ eccWordIdx ] = value;
    }

    if( 0u < outputLength )
    {
        /* ECC word with the last character of the output (Output starts at an ECC word boundary) */
        outputEccWord = ( ( outputLength - 1u ) / IT_RAM_ECC_WORD_SIZE ) + IT_MAILBOX_HEADER_ECC_WORDS;

        const uint64_t value = mailboxEccWords[ outputEccWord ];

        mailboxEccWords[ outputEccWord ] = value;
    }
    else
    {
        /* No output yet */
    }

    atomic_thread_fence( memory_order_seq_cst );
}


/**
 * \brief Stores summary (as UnityEnd) and signals the end of execution to host.
 */
static void integrationTesting_Finish( void )
{
    const uint32_t failures = integrationTesting_Mailbox.Failures;

    integrationTesting_PutLineStart();
    integrationTesting_PutString( "-----------------------\n" );
    integrationTesting_PutDec( integrationTesting_Mailbox.TestCount );
    integrationTesting_PutString( " Tests " );
    integrationTesting_PutDec( failures );
    integrationTesting_PutString( " Failures " );
    integrationTesting_PutDec( integrationTesting_Mailbox.Ignored );
    integrationTesting_PutString( " Ignored \n" );

    if( 0u == failures )
    {
        integrationTesting_PutString( "OK\n" );
    }
    else
    {
        integrationTesting_PutString( "FAIL\n" );
    }

#if defined(IT_COVERAGE)
    /* Counters of all test cases are serialized for the host */
    IntegrationTesting_Coverage_Dump();
#endif

    /* All output is stored before the state is changed */
    atomic_thread_fence( memory_order_seq_cst );

    integrationTesting_Mailbox.State = IT_STATE_FINISHED;

    /* Results are kept over a later reset (debugger, button) */
    integrationTesting_MailboxFlush();
}


/**
 * \brief Prints beginning of failure line of the actual test case
 *        "<file>:<line>:<test>:FAIL: " (the same format as Unity).
 */
static void integrationTesting_PutCaseFail( void )
{
    const integrationTesting_TestCase_t * const testCase = &integrationTesting_TestCases[ integrationTesting_Mailbox.TestIndex ];

    integrationTesting_PutLineStart();
    integrationTesting_PutString( integrationTesting_TestFile );
    integrationTesting_PutString( ":" );
    integrationTesting_PutDec( testCase->Line );
    integrationTesting_PutString( ":" );
    integrationTesting_PutString( testCase->Name );
    integrationTesting_PutString( ":FAIL: " );
}


/**
 * \brief Starts new line of the output if the last line is not finished.
 */
static void integrationTesting_PutLineStart( void )
{
    const uint32_t length = integrationTesting_Mailbox.Length;

    if( ( 0u < length ) && ( IT_OUTPUT_SIZE >= length ) )
    {
        const char lastChar = integrationTesting_Mailbox.Output[ length - 1u ];

        if( '\n' != lastChar )
        {
            IntegrationTesting_PutChar( '\n' );
        }
        else
        {
            /* Line is finished */
        }
    }
    else
    {
        /* Output is empty */
    }
}


/**
 * \brief Prints zero terminated string.
 *
 * \param text [in]: String to print
 */
static void integrationTesting_PutString( const char* text )
{
    for( const char* textChar = text; '\0' != *textChar; textChar++ )
    {
        IntegrationTesting_PutChar( *textChar );
    }
}


/**
 * \brief Prints unsigned decimal number.
 *
 * \param value [in]: Number to print
 */
static void integrationTesting_PutDec( uint32_t value )
{
    char     digits[ IT_DEC_DIGIT_CNT ];
    uint32_t digitCnt = 0u;
    uint32_t rest     = value;

    do
    {
        digits[ digitCnt ] = (char)( '0' + ( rest % IT_DEC_BASE ) );
        rest              /= IT_DEC_BASE;
        digitCnt++;
    }
    while( 0u != rest );

    while( 0u < digitCnt )
    {
        digitCnt--;
        IntegrationTesting_PutChar( digits[ digitCnt ] );
    }
}


/**
 * \brief Prints 32-bit hexadecimal number "0xXXXXXXXX".
 *
 * \param value [in]: Number to print
 */
static void integrationTesting_PutHex( uint32_t value )
{
    static const char hexDigitLut[] = "0123456789ABCDEF";

    integrationTesting_PutString( "0x" );

    for( uint32_t digitIdx = IT_HEX_DIGIT_CNT; 0u < digitIdx; digitIdx-- )
    {
        const uint32_t digit = ( value >> ( ( digitIdx - 1u ) * IT_HEX_DIGIT_BITS ) ) & IT_HEX_DIGIT_MASK;

        IntegrationTesting_PutChar( hexDigitLut[ digit ] );
    }
}


/**
 * \brief Busy wait (no low power mode) - debug probe access stays available.
 */
static void integrationTesting_Idle( void )
{
    for( ;; )
    {
        /* Execution finished - host reads the mailbox */
    }
}


/* =============================== TASKS ==================================== */
