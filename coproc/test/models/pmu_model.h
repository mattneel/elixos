/*
 * Test model of the K230 PMU's power-key events and outputs (registers as
 * LilyGO's Linux power-key driver names them, 0064-input-k230-pmu-pwrkey.patch
 * 90-150): the key's edge event (INT_STATE bit 9) is raised when the key
 * moves the way INT_DETECT_TYP[18:16] waits for (rising 1 on a press,
 * falling 3 on a release) and detection is enabled (INT_DETECT_EN bit 9),
 * and cleared through INT_DETECT_CLR (0x40); the power is cut when the
 * software register (SYSCTRL bit 0, OUT0) drops to 0 while OUT0 follows it
 * (OUT_EVENT_CTRL bit 4). The PMU comes up with OUT0 and OUT1 high and its
 * isolation (PWR + 0x158 bit 5) set.
 */
#ifndef PMU_MODEL_H
#define PMU_MODEL_H

void pmu_model_attach(void);
/* The key goes down (1) or up (0). */
void pmu_model_key(int pressed);
/* Whether the main supply was cut. */
int pmu_model_cut(void);

#endif
