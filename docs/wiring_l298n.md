# Wiring: Nexys A7-100T to an L298N motor driver module

Used by `rtl/top_motor.v` and `constraints/nexys_a7_motor.xdc`.

**Do all wiring with the FPGA board and the motor supply switched off.**

## Connections

| From | To | Note |
| --- | --- | --- |
| Nexys Pmod JA pin 1 (FPGA pin C17) | L298N **ENA** | PWM speed signal. Remove the ENA jumper cap on the module first. |
| Nexys Pmod JA pin 2 (FPGA pin D18) | L298N **IN1** | Direction input |
| Nexys Pmod JA pin 3 (FPGA pin E18) | L298N **IN2** | Direction input |
| Nexys Pmod JA pin 5 | L298N **GND** | Common ground. Required. |
| Motor | L298N **OUT1** and **OUT2** | |
| Motor supply + | L298N **12V** terminal | Use a supply slightly above the motor's rated voltage |
| Motor supply - | L298N **GND** | Same GND terminal as the Nexys ground wire |

Pmod layout (12-pin header): pins 1 to 4 and 7 to 10 are signals, pins 5 and 11 are GND,
pins 6 and 12 are 3.3 V. Confirm against the Pmod diagram in the Nexys A7 reference manual.

## Rules

- Never connect the Pmod 3.3 V pin to the L298N.
- Never power the motor from the FPGA board.
- FPGA pins are 3.3 V. Never feed 5 V signals into them.
- The L298N drops about 2 V, so the motor sees less than the supply voltage.
- If the module has a 5V-EN jumper, leave it on for motor supplies up to about 12 V.

## Power-up checklist

1. Program the board with the motor supply still disconnected.
2. Set SW14 up (enable) and move SW[7:0]. The LEDs should follow the switches.
3. Connect the motor supply and start with a small speed.
4. The red CPU RESET button forces the PWM output low (emergency stop).

## Switch controls (`top_motor.v`)

| Switch | Function |
| --- | --- |
| SW[7:0] | Speed, 0 to 255 |
| SW14 | Enable. Off = motor stopped. |
| SW15 | Direction |

## Documents

- [Nexys A7 resources](https://digilent.com/reference/programmable-logic/nexys-a7/start)
- [Digilent master constraints file](https://github.com/Digilent/digilent-xdc/blob/master/Nexys-A7-100T-Master.xdc)
- L298 datasheet from STMicroelectronics (search "L298 datasheet ST")
