/*
 * The M30 "trivial image" for the K230's little core (ADR-102).
 *
 * U-Boot on the big core loads this flat binary into the reserved region and
 * releases the little core into it with `boot_baremetal 0 <addr> <size>`; the
 * core starts here in M-mode with caches off and no stack. It prints one line
 * on a UART that U-Boot has already configured, then parks:
 *
 *     elixos coproc: hello from the little core mhartid=0x... marchid=0x...
 *
 * mhartid and marchid answer two bring-up questions on first boot: whether
 * both cores read hart 0, and whether the C908's marchid is non-zero (the
 * kernel's T-Head MAE/CMO errata only match marchid 0).
 *
 * Build parameters (scripts/build-k230.sh), so the same code also runs on
 * QEMU's virt machine as a smoke test:
 *   UART_BASE   UART register base (K230 UART0: 0x91400000)
 *   UART_SHIFT  register stride shift (K230 DesignWare: 2, virt 16550: 0)
 *   UART_WORD   1 for 32-bit register access (K230), 0 for byte access
 */

#define UART_THR 0
#define UART_LSR (5 << UART_SHIFT)
#define LSR_THRE 0x20

	.section .text.start, "ax"
	.globl _start
_start:
	csrw	mie, zero
	li	s0, UART_BASE

	la	a0, banner
	call	puts
	csrr	a0, mhartid
	call	puthex
	la	a0, marchid_label
	call	puts
	csrr	a0, marchid
	call	puthex
	la	a0, newline
	call	puts

park:
	wfi
	j	park

/* puts(a0 = NUL-terminated string); clobbers a0, t0-t1, a2. */
puts:
	mv	a2, ra
1:	lbu	t0, 0(a0)
	beqz	t0, 2f
	call	putc
	addi	a0, a0, 1
	j	1b
2:	mv	ra, a2
	ret

/* puthex(a0) as 0x followed by 16 hex digits; clobbers a0-a4, t0-t2. */
puthex:
	mv	a4, ra
	mv	a3, a0
	li	t0, '0'
	call	putc
	li	t0, 'x'
	call	putc
	li	t2, 60
1:	srl	t0, a3, t2
	andi	t0, t0, 0xf
	addi	t0, t0, '0'
	li	t1, '9'
	ble	t0, t1, 2f
	addi	t0, t0, 'a' - '9' - 1
2:	call	putc
	addi	t2, t2, -4
	bgez	t2, 1b
	mv	ra, a4
	ret

/* putc(t0) on the UART at s0; clobbers t1. */
putc:
#if UART_WORD
1:	lw	t1, UART_LSR(s0)
#else
1:	lbu	t1, UART_LSR(s0)
#endif
	andi	t1, t1, LSR_THRE
	beqz	t1, 1b
#if UART_WORD
	sw	t0, UART_THR(s0)
#else
	sb	t0, UART_THR(s0)
#endif
	ret

	.section .rodata
banner:
	.asciz	"elixos coproc: hello from the little core mhartid="
marchid_label:
	.asciz	" marchid="
newline:
	.asciz	"\r\n"
