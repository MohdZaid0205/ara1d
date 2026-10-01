.text
    .balign 4
    .global ipred_smooth_h_mock_r
    .type ipred_smooth_h_mock_r, @function

# void ipred_smooth_h_mock_r(uint8_t *dst, int32_t stride,
#                             const uint8_t *topleft, int width, int height,
#                             int a, int max_width, int max_height)
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
# Ported from dav1d src/riscv/64/ipred.S (ipred_smooth_h_8bpc_rvv).

ipred_smooth_h_mock_r:
    csrwi vxrm, 2                # ARA FIX (upstream: csrw vxrm, zero)
    li t3, 128                   # ARA FIX (rounding constant for (x+128)>>8)
    la t0, dav1d_sm_weights
    add t1, t0, a3
    add t2, a2, a3
    lbu t2, (t2)
    addi a6, a2, -1
1:
    mv t6, a3

    lbu a7, (a6)
2:
    vsetvli t5, t6, e8, m1, ta, ma
    vle8.v v2, (t1)
    add t1, t1, t5

    vwmulu.vx v8, v2, a7

    vneg.v v12, v2
    vwmaccu.vx v8, t2, v12

    sub a5, a3, t6
    sub t6, t6, t5
    add a5, a5, a0
    vsetvli zero, zero, e16, m2, ta, ma   # ARA FIX
    vadd.vx v8, v8, t3                    # ARA FIX
    vsetvli zero, zero, e8, m1, ta, ma
    vnclipu.wi v0, v8, 8
    vse8.v v0, (a5)

    bnez t6, 2b

    sub t1, t1, a3
    add a0, a0, a1
    addi a4, a4, -1
    addi a6, a6, -1
    bnez a4, 1b

    ret
