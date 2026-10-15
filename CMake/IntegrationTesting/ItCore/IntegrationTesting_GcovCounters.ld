/*
 * Author: Mr.Nobody
 * file:   IntegrationTesting_GcovCounters.ld
 * brief:  Counters of the gcov instrumentation kept over reset (integration tests with
 *         INTEGRATION_TEST_COVERAGE).
 *
 * Augmenting linker script (INSERT) added to the linker script of the project by
 * IntegrationTesting.cmake (-Wl,-T). Every test case runs after the reset of the MCU, which
 * clears ".bss", so the counters would be lost. The counters of gcov (zero initialized
 * variables __gcov0.<function>, section ".bss.__gcov0.<function>" with -fdata-sections) are
 * collected before ".bss" in a section which is not initialized by the startup code and
 * kept over reset like the section ".noinit" of the result mailbox. The symbols are used by
 * IntegrationTesting_Coverage.c, which clears the counters when a new test session starts.
 *
 * Requirement: the memory region RAM of the linker script of the project (Bsp/Linker).
 */

SECTIONS
{
    .gcov_counters ( NOLOAD ) : ALIGN( 8 )
    {
        __it_gcov_counters_start = .;
        *( .bss.__gcov0.* )
        . = ALIGN( 8 );
        __it_gcov_counters_end = .;
    } >RAM
}

INSERT BEFORE .bss;
