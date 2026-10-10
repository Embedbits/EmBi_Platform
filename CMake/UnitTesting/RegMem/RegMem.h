/**
 * \author Mr.Nobody
 * \file RegMem.h
 * \ingroup UnitTesting
 * \brief Register memory emulation for host based unit tests.
 *
 * The module maps host RAM at the same addresses the MCU uses for peripherals
 * (0x40000000..0x5FFFFFFF) and for the Cortex-M private peripheral bus
 * (0xE0000000..0xE00FFFFF). Code under test and the ST LL/CMSIS headers are
 * compiled unchanged, every access to `RCC`, `GPIOA`, `SCB`, ... lands in the
 * emulated memory. Tests can preset register values (eg. ready flags set by HW)
 * and check values written by the code under test.
 *
 * The regions are mapped automatically before `main()` is executed. Every test
 * shall call \ref RegMem_Reset in `setUp()` to start from zeroed registers.
 *
 * \note The emulated memory is plain RAM. Registers with side effects (BSRR,
 *       write-1-to-clear flags, read-only status bits) do not behave as HW. The
 *       test shall preset the register state the code under test expects.
 *       Sequences where HW reacts on a write (enable -> ready flag) can be
 *       emulated by HW model running in background thread
 *       (\ref RegMem_Set_ModelActive). Such tests shall be registered with
 *       RUN_SERIAL option, so the model thread is scheduled without delay.
 */

#ifndef UNITTESTING_REGMEM_H
#define UNITTESTING_REGMEM_H

#ifdef __cplusplus
extern "C" {
#endif

/* ============================= INCLUDES =================================== */
#include "stdint.h"                         /* Standard integer types         */
/* ============================= TYPEDEFS =================================== */

/** Enumeration used to signal request processing state */
typedef enum
{
    REGMEM_REQUEST_ERROR = 0u, /**< Processing request failed  */
    REGMEM_REQUEST_OK          /**< Processing request succeed */
}   regMem_RequestState_t;


/**
 * \brief HW model callback type.
 *
 * Called repeatedly from background thread while the model is active. Emulates
 * HW reaction on register writes (eg. copies RCC->CR HSEON to HSERDY). The
 * callback shall be short and shall not call Unity assertions.
 */
typedef void ( *regMem_ModelCallback_t )( void );


/** Enumeration of emulated memory regions */
typedef enum
{
    REGMEM_REGION_PERIPH = 0u, /**< Peripherals (secure and non-secure alias) */
    REGMEM_REGION_PPB,         /**< Cortex-M private peripheral bus (SCB, NVIC) */
    REGMEM_REGION_SRAM,        /**< SRAM (0x20000000) - DMA descriptors and buffers
                                    with 32-bit addresses, see \ref REGMEM_SRAM_BASE */
    REGMEM_REGION_CNT          /**< Count of emulated regions */
}   regMem_RegionId_t;

/* ========================= SYMBOLIC CONSTANTS ============================= */

/**
 * Start of emulated SRAM. Data which MCU code stores as 32-bit address (DMA
 * linked-list nodes, DMA buffers) shall be placed here by tests, host variables
 * are above 4 GB on 64-bit host. Cleared by \ref RegMem_Reset.
 */
#define REGMEM_SRAM_BASE                ( 0x20000000u )

/** Size of emulated SRAM */
#define REGMEM_SRAM_SIZE                ( 0x00200000u )

/* ========================= EXPORTED MACROS ================================ */

/** Pointer of required type to emulated SRAM at byte offset */
#define REGMEM_SRAM_PTR( type, offset )     ( (type *)(uintptr_t)( REGMEM_SRAM_BASE + (uint32_t)( offset ) ) )

/* ========================= EXPORTED VARIABLES ============================= */

/* ======================== EXPORTED FUNCTIONS ============================== */

regMem_RequestState_t   RegMem_Init         ( void );
regMem_RequestState_t   RegMem_Reset        ( void );
regMem_RequestState_t   RegMem_Deinit       ( void );

regMem_RequestState_t   RegMem_Set_ModelActive  ( regMem_ModelCallback_t modelCallback );
regMem_RequestState_t   RegMem_Set_ModelInactive( void );
regMem_RequestState_t   RegMem_Wait_ModelCycles ( uint32_t cycleCnt );

#ifdef __cplusplus
}
#endif

#endif /* UNITTESTING_REGMEM_H */
