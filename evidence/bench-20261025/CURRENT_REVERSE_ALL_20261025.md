# Four-channel current polarity diagnostic, 2026-10-25

User explicitly requested all Hall channels reversed and confirmed motor12V off. A separate paired profile is built with CURRENT_REVERSE=15 on both axes. Physical wiring remains M1 output/encoder1/C->CH1/B->CH2 and M2 output/encoder2/C->CH3/B->CH4. No PWM permutation, encoder direction or D/Q rotation is introduced.

The existing motor_current path subtracts each physical channel offset, applies its gain, negates scaled current according to the channel mask, checks raw overcurrent, reconstructs A from B/C and checks reconstructed overcurrent before saturation. Thus real PI feedback and telemetry both change sign. Absolute current guards are retained, as are nFAULT, watchdog, speed/feedback health and pair interlocks. The original masks and historical build folder remain available. M2 gains still copy M1 comparison values and are not independently calibrated for the replacement sensors.

Build: python motor_control/tools/build_paired.py --reverse-all-current
Output: motor_control/build/m1_m2_paired_reverse_all_20261025

Validation: dedicated all-four RTL test passes for zero calibration, six canonical phase signs and both raw/reconstructed trip preservation; two paired RTL tests pass for one-axis output enable, UART identity, one-time handoff and protection latching. 70 host tests pass. Parameter diff confirms CURRENT_REVERSE 0->15 is the sole axis parameter change. Download requires successful setup/hold 0/0 and matching bitstream hash. No powered motor result is implied by these offline checks.

Build passed: setup/hold violations0/0, source hashes unchanged. Downloaded SRAM SHA256 cbc4edd6c81f7ad7f88d4377680ff1175b0120b48c8594d5ce592f988326ae4a; programmer exit0 Finished. Powered test remains pending user confirmation. Evidence: motor_control/results/m1_m2_reverse_all_20261025.
## Powered result

User confirmed12V on for one sequential batch and subsequently confirmed12V off. M1 completed calibration and9.998s speed run: steady10ms mean30.0081rpm/std2.0192rpm, phase UART peak0.25732A, no protection fault. M1 fixed90 final25 Id+0.249209A/Iq-0.002285A; fixed0 Id+0.256465A/Iq+0.003672A. This supports reversed current polarity for the present M1 wiring in this bounded bench test.

M2 passed zero/static checks, but failed commissioning after fixed90(300ms) and fixed0(700ms); no speed run. Fault history0/1 only, no phase overcurrent bit0x010. Final25 fixed90 Id-0.018740A/Iq-0.005039A versus Id target+0.25A, Ud+0.125 ceiling; fixed0 Id+0.108906A/Iq+0.038496A, Ud+0.125/Uq-0.125 ceilings. Thus all-four inversion is not sufficient to repair M2. Remaining mapping, current-path continuity/polarity/gain and drive-output issues require isolation; this does not prove a sensor die or motor defect. X stop sent, no retry/clear. Full records and analysis under results/m1_m2_reverse_all_20261025/powered_batch.
