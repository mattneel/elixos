/* The little-core image is a flat binary entered at its first byte. */
ENTRY(_start)

SECTIONS
{
	. = LOAD_ADDR;
	.text : {
		KEEP(*(.text.start))
		*(.text .text.*)
	}
	.rodata : { *(.rodata .rodata.*) }
	/DISCARD/ : { *(.note*) *(.comment) *(.riscv.attributes) *(.eh_frame*) }
}
