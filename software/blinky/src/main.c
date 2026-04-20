/*
 * blinky - Timer-based LED Blink Application
 * VestaRV Firmware
 * 
 * Uses TIMER0 CMP0 output to toggle P2.0 (T0CMP0 pin) as fast as possible
 */

#include <stdint.h>
#include "MemoryMap.h"

int main(void) {
    // Configure P3.0 as output for T0CMP0 (Timer0 Compare 0 output)
    // GPIO2 peripheral (base 0x4800) controls Port 3 pins
    // P3SEL.P0 = 1 to enable T0CMP0 peripheral function
    // P3DIR.P0 = 1 to set as output
    
    // Write full register values instead of individual bitfields
    GPIO2->SEL.value = 0x01;   // Select T0CMP0 peripheral function on P3.0
    GPIO2->DIR.value = 0x01;   // Set P3.0 as output
    
    // Configure TIMER0 for fastest possible toggling
    TIMER0->CMP0.value = 1;        // Toggle at count 1 (minimum for toggling)
    TIMER0->CMP2.value = 2;        // Reset counter at 2 (creates fastest toggle)
    
    // Configure timer control register:
    // - CMP0IH: CMP0 output toggles on each match
    // - CMP2RST: Counter resets at 2, creating continuous 0→1→0 count
    // - TEN: Enable timer
    // - DIV_1: No clock division (maximum speed)
    // - SSEL_SMCLK: Use system master clock
    TIMER0->CR.CMP0IH_ = 1;
    TIMER0->CR.CMP2RST_ = 1;
    TIMER0->CR.EN = 1;  // TEN becomes EN in struct
    TIMER0->CR.DIV_ = 0;  // DIV_1
    TIMER0->CR.SSEL_ = 2; // SSEL_SMCLK
    
    // Timer now toggles T0CMP0 output in hardware automatically
    // No CPU intervention - maximum possible speed!
    while(1) {
        // Infinite loop - hardware handles everything
    }
    
    return 0;
}
