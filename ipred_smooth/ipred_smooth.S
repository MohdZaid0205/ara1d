.text
    .balign 4
    .global ipred_smooth_mock_r
    .type ipred_smooth_mock_r, @function

# void ipred_smooth_mock_r(uint8_t *dst, int32_t stride,
#                           const uint8_t *topleft, int width, int height,
#                           int a, int max_width, int max_height)
#
# Register Mapping:
# a0 = dst
# a1 = stride
# a2 = topleft
# a3 = width
# a4 = height
# a5 = a           (unused by the routine; used as scratch)
# a6 = max_width   (unused by the routine; used as scratch)
# a7 = max_height  (unused by the routine; used as scratch)
#
# Ported from dav1d src/riscv/64/ipred.S (ipred_smooth_8bpc_rvv).


ipred_smooth_mock_r:
    csrwi vxrm, 2                # ARA FIX (upstream: csrw vxrm, zero)
    la t0, dav1d_sm_weights
    add t1, t0, a3
    add t2, a2, a3
    add t0, t0, a4
    lbu t2, (t2)
    sub t3, a2, a4
    addi a6, a2, -1
    addi a2, a2, 1
    lbu t3, (t3)
1:
    mv t6, a3

    lbu a7, (a6)
    lbu t4, (t0)
2:
    li a5, 256
    vsetvli t5, t6, e8, m1, ta, ma
    vle8.v v2, (t1)
    add t1, t1, t5
    vle8.v v4, (a2)
    add a2, a2, t5
    sub a5, a5, t4

    vwmulu.vx v8, v4, t4
    vsetvli zero, zero, e16, m2, ta, ma
    mul a5, a5, t3
    addi a5, a5, 128             # ARA FIX (half of the +256 rounding)

    vadd.vx v4, v8, a5
    vsetvli zero, zero, e8, m1, ta, ma
    vwmulu.vx v8, v2, a7

    vneg.v v12, v2
    vwmaccu.vx v8, t2, v12
    vsetvli zero, zero, e16, m2, ta, ma
    li a5, 128                   # ARA FIX (other half of the rounding)
    vadd.vx v8, v8, a5           # ARA FIX
    vwaddu.vv v12, v4, v8

    sub a5, a3, t6
    sub t6, t6, t5
    add a5, a5, a0
    vnclipu.wi v2, v12, 9
    vsetvli zero, zero, e8, m1, ta, ma
    vnclipu.wi v0, v2, 0
    vse8.v v0, (a5)

    bnez t6, 2b

    sub t1, t1, a3
    add a0, a0, a1
    sub a2, a2, a3
    addi a4, a4, -1
    addi t0, t0, 1
    addi a6, a6, -1
    bnez a4, 1b

    ret
