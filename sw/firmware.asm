; firmware.asm - the program that runs on this project's own 16-bit CPU
;
; What it does:
;   1. Tells the PC it is ready by sending the letter 'R' over the UART.
;   2. Waits until the PC answers with the letter 'G' (go).
;   3. Repeats 12 times:
;        read one sample from the sensor over SPI
;        give it to the FIR filter and read back the smoothed value
;        use the smoothed value as the motor speed (PWM), as the audio sample (echo effect)
;        and as the length of the bar on the monitor (VGA)
;        keep a copy in RAM and send it to the PC over the UART
;   4. Sends the letter 'D' (done) and halts.
;
; Register conventions:
;   r0 = 0 (always)      r1 = raw sample       r2 = filtered sample    r3 = temporary
;   r4 = 1 (always)      r5 = RAM write index  r6 = samples left       r7 = 0x8000 (peripheral base)
;
; Peripheral offsets from r7:  +0 UART data   +1 UART status   +2 PWM duty   +3 SPI data
;                              +4 SPI status  +5 FIR in         +6 FIR out    +7 audio in
;                              +9 VGA level
; Comments start with a semicolon.

start:
        ldi   r0, 0
        ldi   r4, 1
        ldi   r5, 0
        ldi   r7, 0x00
        ldih  r7, 0x80            ; r7 = 0x8000

        ; ---- 1. send 'R' (ready) ----
        ldi   r1, 0x52            ; 'R'
wait_tx_r:
        ld    r3, [r7+1]          ; UART status
        and   r3, r3, r4          ; bit 0 = transmitter busy
        bne   r3, r0, wait_tx_r
        st    r1, [r7+0]          ; send

        ; ---- 2. wait for 'G' (go) from the PC ----
wait_go:
        ld    r3, [r7+1]
        shri  r3, r3, 1           ; bit 1 = a byte has been received
        and   r3, r3, r4
        beq   r3, r0, wait_go
        ld    r1, [r7+0]          ; read the received byte
        ldi   r3, 0x47            ; 'G'
        bne   r1, r3, wait_go     ; not 'G': keep waiting

        ; ---- 3. main loop: 12 samples ----
        ldi   r6, 12
sample_loop:
        ldi   r1, 0
        st    r1, [r7+3]          ; start an SPI transfer (the byte sent is not used)
wait_spi:
        ld    r3, [r7+4]
        and   r3, r3, r4          ; bit 0 = transfer in progress
        bne   r3, r0, wait_spi
        ld    r1, [r7+3]          ; r1 = raw sample from the sensor

        st    r1, [r7+5]          ; give it to the filter
        ld    r2, [r7+6]          ; r2 = filtered sample

        st    r2, [r7+2]          ; motor speed
        st    r2, [r7+7]          ; audio echo input
        st    r2, [r7+9]          ; bar length on the monitor
        st    r2, [r5+0]          ; keep a copy in RAM
        addi  r5, r5, 1

wait_tx_s:
        ld    r3, [r7+1]
        and   r3, r3, r4
        bne   r3, r0, wait_tx_s
        st    r2, [r7+0]          ; send the filtered sample to the PC

        addi  r6, r6, -1
        bne   r6, r0, sample_loop

        ; ---- 4. send 'D' (done) and stop ----
        ldi   r1, 0x44            ; 'D'
wait_tx_d:
        ld    r3, [r7+1]
        and   r3, r3, r4
        bne   r3, r0, wait_tx_d
        st    r1, [r7+0]
        halt
