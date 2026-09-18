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
# Ported from dav1d src/riscv/64/ipred.S (cfl_pred_8bpc_rvv), commit
# 362bc1138228390a0a521ecf3af18b23c6afeb9e. Only change: the Zba
# "sh1add a5, t0, a5" (ac += vl * sizeof(int16_t)) is lowered to
# slli+add using scratch register t1, which is free throughout this
# function (t0 already holds the just-computed vl and is still needed
# right after, so t1 rather than t0 is used as the scratch).
#
# Ara-support flags to confirm against the dispatcher before assembling:
# vwmul.vx (widening signed multiply), vssra.vi (rounding shift, uses
# vxrm - set to round-to-nearest-even via csrw vxrm,zero at entry,
# matching upstream), vnclipu.wi (x2).

cfl_pred_mock_r:
    csrw vxrm, zero
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
