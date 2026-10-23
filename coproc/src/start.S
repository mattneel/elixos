/*
 * Entry of the coprocessor firmware (docs/notes/coproc-firmware.md).
 *
 * U-Boot's `boot_baremetal` (K230) or QEMU's reset vector (virt, -bios none)
 * enters the image's first byte in M-mode, with no stack and interrupts in
 * an unknown state. Set up the trap vector, the FPU (the code is built for
 * lp64d), gp and the stack, zero .tbss and .bss, then hand over to C.
 */
	.section .text.start, "ax"
	.globl _start
_start:
	csrw	mie, zero
	csrci	mstatus, 0x8			/* MIE */
	la	t0, coproc_trap_entry
	csrw	mtvec, t0
	li	t0, 0x2000			/* mstatus.FS = Initial */
	csrs	mstatus, t0
	fscsr	zero
	.option push
	.option norelax
	la	gp, __global_pointer$
	.option pop
	la	sp, __stack_top

	la	a0, __bss_start
	la	a1, __bss_end
1:	bgeu	a0, a1, 2f
	sd	zero, 0(a0)
	addi	a0, a0, 8
	j	1b
2:
	call	coproc_start
3:	wfi
	j	3b

/*
 * Any trap is fatal: nothing in the firmware expects one (interrupts stay
 * globally disabled; wfi only waits for a pending timer). Report it on the
 * console and park.
 */
	.balign 4
	.globl coproc_trap_entry
coproc_trap_entry:
	csrr	a0, mcause
	csrr	a1, mepc
	csrr	a2, mtval
	mv	a3, ra
	mv	a4, sp
	la	sp, __stack_top
	call	coproc_trap
4:	wfi
	j	4b
