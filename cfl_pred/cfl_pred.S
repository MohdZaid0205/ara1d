.text
    .balign 4
    .global cfl_pred_mock_r
    .type cfl_pred_mock_r, @function

# void cfl_pred_mock_r(uint8_t *dst, int32_t stride, int width, int height,
#                       int dc, const int16_t *ac, int alpha)
#
# Register Mapping:
# a0 = dst
# a1 = stride
# a2 = width
# a3 = height
# a4 = dc
# a5 = ac
# a6 = alpha
#
# Ported from dav1d src/riscv/64/ipred.S (cfl_pred_8bpc_rvv).


cfl_pred_mock_r:
    csrw vxrm, zero
    li t5, 255                          # added: upper clip bound (see change 3)
1:
    li t2, 0
    mv t3, a2
2:
    vsetvli t0, t3, e16, m2, ta, ma
    add t4, a0, t2
    vle16.v v0, (a5)
    slli t1, t0, 1
    add a5, t1, a5                      # was: sh1add a5, t0, a5

    vwmul.vx v4, v0, a6
    vsetvli zero, zero, e32, m4, ta, mu
    vneg.v v8, v4
    vmslt.vx v0, v4, x0
    vmax.vv v12, v8, v4
    vssra.vi v16, v12, 6
    vneg.v v16, v16, v0.t
    vadd.vx v20, v16, a4
    vmax.vx v0, v20, zero
    vmin.vx v0, v0, t5                  # added: explicit clip to 255 (see change 3)
    csrwi vxrm, 2                       # rdn (truncate) for the shift-0 narrowing
    vsetvli zero, zero, e16, m2, ta, ma
    vnclipu.wi v4, v0, 0
    vsetvli zero, zero, e8, m1, ta, ma
    vnclipu.wi v0, v4, 0
    csrwi vxrm, 0                       # restore rnu for the next vssra
    vse8.v v0, (t4)
    add t2, t0, t2
    sub t3, t3, t0
    bnez t3, 2b
    addi a3, a3, -1
    add a0, a0, a1

    bnez a3, 1b
    ret
