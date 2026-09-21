.syntax unified
.arm
.global _start
.type _start, %function

/* Minimal X11 client: grab keyboard/pointer and emit navigation commands. */
.section .text
_start:
    b       .Lprogram_start

.align 2
x_socket_address:
    .hword  1
    .asciz  "/tmp/.X11-unix/X0"

.align 2
x_setup_request:
    .byte   0x6c, 0
    .hword  11, 0, 0, 0, 0

.align 2
.Lprogram_start:
    sub     sp, sp, #4096
    mov     r11, #20              /* diagnostic exit stage: socket */

    mov     r0, #1                /* AF_UNIX */
    mov     r1, #1                /* SOCK_STREAM */
    mov     r2, #0
    movw    r7, #281              /* ARM sys_socket */
    svc     #0
    cmp     r0, #0
    blt     exit_failure
    mov     r4, r0
    mov     r11, #21              /* connect */

    mov     r0, r4
    adr     r1, x_socket_address
    mov     r2, #20
    movw    r7, #283              /* ARM sys_connect */
    svc     #0
    cmp     r0, #0
    blt     close_failure
    mov     r11, #22              /* X11 setup */

    mov     r0, r4
    adr     r1, x_setup_request
    mov     r2, #12
    bl      .Lwrite_full
    cmp     r0, #0
    blt     close_failure

    mov     r0, r4
    add     r1, sp, #64
    mov     r2, #8
    bl      .Lread_full
    cmp     r0, #0
    blt     close_failure
    ldrb    r0, [sp, #64]
    cmp     r0, #1
    bne     close_failure

    ldrh    r7, [sp, #70]
    lsl     r7, r7, #2
    cmp     r7, #3072
    bhi     close_failure
    mov     r0, r4
    add     r1, sp, #128
    mov     r2, r7
    bl      .Lread_full
    cmp     r0, #0
    blt     close_failure

    add     r6, sp, #128
    ldr     r8, [r6, #4]          /* first resource id for our X client */
    ldrh    r0, [r6, #16]
    add     r0, r0, #3
    bic     r0, r0, #3
    ldrb    r1, [r6, #21]
    add     r0, r0, r1, lsl #3
    add     r0, r0, #32
    add     r0, r6, r0
    ldr     r5, [r0]              /* first screen root window */
    mov     r11, #23              /* keyboard grab */

    /* GrabKeyboard(owner_events=false, modes=Async). */
    add     r6, sp, #32
    mov     r0, #0
    str     r0, [r6, #0]
    str     r0, [r6, #4]
    str     r0, [r6, #8]
    str     r0, [r6, #12]
    mov     r0, #31
    strb    r0, [r6, #0]
    mov     r0, #4
    strh    r0, [r6, #2]
    str     r5, [r6, #4]
    mov     r0, #1
    strb    r0, [r6, #12]
    strb    r0, [r6, #13]
    mov     r0, r4
    mov     r1, r6
    mov     r2, #16
    bl      .Lwrite_full
    cmp     r0, #0
    blt     close_failure
    mov     r0, r4
    add     r1, sp, #256
    mov     r2, #32
    bl      .Lread_full
    cmp     r0, #0
    blt     close_failure
    ldrb    r0, [sp, #256]
    cmp     r0, #1
    bne     close_failure
    ldrb    r0, [sp, #257]
    cmp     r0, #0                /* GrabSuccess */
    bne     close_failure
    mov     r11, #24              /* pointer grab */

    /* GrabPointer(ButtonPressMask, owner_events=false, modes=Async). */
    mov     r0, #0
    str     r0, [r6, #0]
    str     r0, [r6, #4]
    str     r0, [r6, #8]
    str     r0, [r6, #12]
    str     r0, [r6, #16]
    str     r0, [r6, #20]
    mov     r0, #26
    strb    r0, [r6, #0]
    mov     r0, #6
    strh    r0, [r6, #2]
    str     r5, [r6, #4]
    mov     r0, #4
    strh    r0, [r6, #8]
    mov     r0, #1
    strb    r0, [r6, #10]
    strb    r0, [r6, #11]
    mov     r0, r4
    mov     r1, r6
    mov     r2, #24
    bl      .Lwrite_full
    cmp     r0, #0
    blt     close_failure
    mov     r0, r4
    add     r1, sp, #256
    mov     r2, #32
    bl      .Lread_full
    cmp     r0, #0
    blt     close_failure
    ldrb    r0, [sp, #256]
    cmp     r0, #1
    bne     close_failure
    ldrb    r0, [sp, #257]
    cmp     r0, #0
    bne     close_failure
    mov     r11, #25              /* fullscreen shield window */

    /*
     * Create an override-redirect InputOutput window with no background.
     * It clips repainting from the native UI below it, while direct FBInk
     * framebuffer writes remain visible.  cvm can stay alive to generate
     * the Voyage's round PagePress event.
     */
    mov     r0, #0
    str     r0, [r6, #0]
    str     r0, [r6, #4]
    str     r0, [r6, #8]
    str     r0, [r6, #12]
    str     r0, [r6, #16]
    str     r0, [r6, #20]
    str     r0, [r6, #24]
    str     r0, [r6, #28]
    str     r0, [r6, #32]
    mov     r0, #1                /* CreateWindow */
    strb    r0, [r6, #0]
    mov     r0, #9
    strh    r0, [r6, #2]
    str     r8, [r6, #4]
    str     r5, [r6, #8]
    movw    r0, #1072
    strh    r0, [r6, #16]
    movw    r0, #1448
    strh    r0, [r6, #18]
    mov     r0, #1                /* InputOutput */
    strh    r0, [r6, #22]
    mov     r0, #512              /* CWOverrideRedirect */
    str     r0, [r6, #28]
    mov     r0, #1
    str     r0, [r6, #32]
    mov     r0, r4
    mov     r1, r6
    mov     r2, #36
    bl      .Lwrite_full
    cmp     r0, #0
    blt     close_failure

    mov     r0, #0
    str     r0, [r6, #0]
    str     r0, [r6, #4]
    mov     r0, #8                /* MapWindow */
    strb    r0, [r6, #0]
    mov     r0, #2
    strh    r0, [r6, #2]
    str     r8, [r6, #4]
    mov     r0, r4
    mov     r1, r6
    mov     r2, #8
    bl      .Lwrite_full
    cmp     r0, #0
    blt     close_failure

    mov     r0, #0
    str     r0, [r6, #0]
    mov     r0, #43               /* GetInputFocus: synchronization reply */
    strb    r0, [r6, #0]
    mov     r0, #1
    strh    r0, [r6, #2]
    mov     r0, r4
    mov     r1, r6
    mov     r2, #4
    bl      .Lwrite_full
    cmp     r0, #0
    blt     close_failure

shield_sync_read:
    mov     r0, r4
    add     r1, sp, #256
    mov     r2, #32
    bl      .Lread_full
    cmp     r0, #0
    blt     close_failure
    ldrb    r0, [sp, #256]
    cmp     r0, #0
    beq     close_failure         /* X protocol error */
    cmp     r0, #1
    bne     shield_sync_read      /* ignore Expose/other events */

    mov     r11, #26              /* event loop */
    mov     r9, #512              /* bounded diagnostic packet count */

event_loop:
    mov     r0, r4
    add     r1, sp, #256
    mov     r2, #32
    bl      .Lread_full
    cmp     r0, #0
    blt     close_failure
    cmp     r9, #0
    beq     .Ldecode_event
    sub     r9, r9, #1
    mov     r0, #2                /* stderr is the binary diagnostic file */
    add     r1, sp, #256
    mov     r2, #32
    bl      .Lwrite_full
.Ldecode_event:
    ldrb    r0, [sp, #256]
    and     r0, r0, #0x7f
    cmp     r0, #2
    beq     key_press
    cmp     r0, #4
    beq     button_press
    b       event_loop

key_press:
    ldrb    r0, [sp, #257]
    cmp     r0, #117
    beq     emit_next
    cmp     r0, #112
    beq     emit_previous
    b       event_loop            /* ignore unrelated keys */

emit_next:
    mov     r0, #1
    adr     r1, command_next
    mov     r2, #5
    bl      .Lwrite_full
    b       check_output

emit_previous:
    mov     r0, #1
    adr     r1, command_previous
    mov     r2, #9
    bl      .Lwrite_full
    b       check_output

button_press:
    /* Split the touchscreen into two confirmation targets. */
    add     r1, sp, #256
    ldrh    r0, [r1, #24]        /* event_x: packet offset 24 */
    movw    r1, #536
    cmp     r0, r1
    blo     emit_touch_left

emit_touch_right:
    mov     r0, #1
    adr     r1, command_touch_right
    mov     r2, #12
    bl      .Lwrite_full
    b       check_output

emit_touch_left:
    mov     r0, #1
    adr     r1, command_touch_left
    mov     r2, #11
    bl      .Lwrite_full

check_output:
    cmp     r0, #0
    blt     close_failure
    b       event_loop

.align 2
command_next:
    .ascii  "next\n"
command_previous:
    .ascii  "previous\n"
command_touch_left:
    .ascii  "touch-left\n"
command_touch_right:
    .ascii  "touch-right\n"
.align 2

.Lread_full:
    push    {r8, r9, r10, lr}
    mov     r10, r0
    mov     r8, r1
    mov     r9, r2
read_more:
    cmp     r9, #0
    beq     io_success
    mov     r0, r10
    mov     r1, r8
    mov     r2, r9
    mov     r7, #3
    svc     #0
    cmp     r0, #0
    beq     io_failure
    bgt     read_progress
    cmn     r0, #4
    beq     read_more
    b       io_failure
read_progress:
    add     r8, r8, r0
    sub     r9, r9, r0
    b       read_more

.Lwrite_full:
    push    {r8, r9, r10, lr}
    mov     r10, r0
    mov     r8, r1
    mov     r9, r2
write_more:
    cmp     r9, #0
    beq     io_success
    mov     r0, r10
    mov     r1, r8
    mov     r2, r9
    mov     r7, #4
    svc     #0
    cmp     r0, #0
    ble     io_failure
    add     r8, r8, r0
    sub     r9, r9, r0
    b       write_more

io_success:
    mov     r0, #0
    pop     {r8, r9, r10, pc}

io_failure:
    mvn     r0, #0
    pop     {r8, r9, r10, pc}

close_failure:
    mov     r0, r4
    mov     r7, #6
    svc     #0

exit_failure:
    mov     r0, r11
    mov     r7, #1
    svc     #0

.size _start, .-_start
