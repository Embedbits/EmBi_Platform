/*
 * Author: Mr.Nobody
 * file:   IntegrationTesting_GcovInfo.ld
 * brief:  Pointers to the gcov information of the instrumented objects (integration tests
 *         with INTEGRATION_TEST_COVERAGE).
 *
 * Augmenting linker script (INSERT) added to the linker script of the project by
 * IntegrationTesting.cmake (-Wl,-T). The instrumented objects (-fprofile-info-section)
 * place a pointer to their gcov information into the section ".gcov_info"; the linker
 * collects the pointers in a contiguous read-only block in FLASH after ".rodata" between
 * the symbols __gcov_info_start and __gcov_info_end (IntegrationTesting_Coverage.c).
 *
 * Requirement: the memory region FLASH of the linker script of the project (Bsp/Linker).
 */

SECTIONS
{
    .gcov_info : ALIGN( 4 )
    {
        __gcov_info_start = .;
        KEEP( *( .gcov_info ) )
        __gcov_info_end = .;
    } >FLASH
}

INSERT AFTER .rodata;
