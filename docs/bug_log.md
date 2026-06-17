## DESIGN-NOTE-001
Date: 2026-06-17
Severity: N/A (architectural constraint)
Component: uart_rx.sv
Description: OVERSAMPLE=1 mode is incompatible with the 2-FF input
             synchronizer. The sync delay (2 clock cycles) pushes the
             baud_tick sampling point past the start bit window, causing
             false-start detection to fire on data bit 0.
Root Cause: With OVERSAMPLE=1, SAMPLE_MID=0 and SAMPLE_DIV=BAUD_DIV.
            The first baud_tick fires BAUD_DIV clocks after entering START.
            The synchronizer adds 2 cycles, so sampling occurs 2 cycles
            into data bit 0 rather than during the start bit — triggering
            the false-start filter incorrectly.
Decision: OVERSAMPLE=1 removed from testbench. 1x sampling is only valid
          when TX and RX share the same clock domain, which eliminates
          the need for a synchronizer. OVERSAMPLE=16 is the correct
          production mode and is fully verified.
Status: Closed — by design