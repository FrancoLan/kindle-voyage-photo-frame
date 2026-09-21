.syntax unified
.arm
.global _start
.type _start, %function

/*
 * kindle-evgrab-cat DEVICE
 *
 * Opens a Linux evdev node, takes an exclusive EVIOCGRAB, and copies the
 * binary input_event stream to stdout.  This is a freestanding ARM Linux
 * program: it uses kernel syscalls directly and has no libc dependency.
 */
.section .text
_start:
    ldr     r0, [sp, #8]          /* argv[1] */
    cmp     r0, #0
    beq     exit_failure

    mov     r1, #0                /* O_RDONLY */
    mov     r2, #0
    mov     r7, #5                /* sys_open */
    svc     #0
    cmp     r0, #0
    blt     exit_failure
    mov     r4, r0                /* evdev fd */

    mov     r0, r4
    ldr     r1, evio_grab
    mov     r2, #1
    mov     r7, #54               /* sys_ioctl */
    svc     #0
    cmp     r0, #0
    blt     close_failure

    sub     sp, sp, #16           /* one 32-bit ARM input_event */

read_event:
    mov     r0, r4
    mov     r1, sp
    mov     r2, #16
    mov     r7, #3                /* sys_read */
    svc     #0
    cmp     r0, #0
    beq     release_success
    bgt     read_ok
    cmn     r0, #4                /* -EINTR */
    beq     read_event
    b       release_failure

read_ok:
    mov     r5, r0                /* bytes left to write */
    mov     r6, sp

write_event:
    mov     r0, #1                /* stdout */
    mov     r1, r6
    mov     r2, r5
    mov     r7, #4                /* sys_write */
    svc     #0
    cmp     r0, #0
    ble     release_failure
    sub     r5, r5, r0
    add     r6, r6, r0
    cmp     r5, #0
    bne     write_event
    b       read_event

release_success:
    mov     r5, #0
    b       release

release_failure:
    mov     r5, #1

release:
    mov     r0, r4
    ldr     r1, evio_grab
    mov     r2, #0
    mov     r7, #54               /* sys_ioctl */
    svc     #0
    b       close_with_status

close_failure:
    mov     r5, #1

close_with_status:
    mov     r0, r4
    mov     r7, #6                /* sys_close */
    svc     #0
    mov     r0, r5
    b       exit_now

exit_failure:
    mov     r0, #1

exit_now:
    mov     r7, #1                /* sys_exit */
    svc     #0

.align 2
evio_grab:
    .word   0x40044590            /* _IOW('E', 0x90, int) */

.size _start, .-_start
