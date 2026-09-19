.text
    .balign 4
    .global ipred_paeth_mock_r
    .type ipred_paeth_mock_r, @function

# void ipred_paeth_mock_r(uint8_t *dst, int32_t stride,
#                          const uint8_t *topleft, int width, int height)
#
# Register Mapping:
# a0 = dst
# a1 = stride
# a2 = topleft
# a3 = width
# a4 = height
#
# Ported from dav1d src/riscv/64/ipred.S (ipred_paeth_8bpc_rvv), commit
# 362bc1138228390a0a521ecf3af18b23c6afeb9e. No Zba/Zbb instructions are
# actually used in this routine (the "ext=\"v,zba\"" tag on the upstream
# function is a no-op for this particular body), so the only change here
# is stripping the function/endfunc macros - the instruction sequence
# below is byte-for-byte identical to upstream.
#
# Ara-support flags to confirm against the dispatcher before assembling
# (see plan): vmmv.m, vzext.vf4, masked vneg.v, vmslt.vx, vmsleu.vv,
# vmsgtu.vv, vmand.mm, vmerge.vxm, vwaddu.vx, vwsub.vx.

ipred_paeth_mock_r:
    csrw vxrm, zero
    li t0, 0
    mv t3, a2
    lbu t1, (a2)
    addi a6, a2, -1
    addi a2, a2, 1
1:
    lbu t2, (a6)
    mv t3, a3
2:
    sub t5, a3, t3
    add t5, a2, t5
    vsetvli t6, t3, e8, m1, ta, ma
    vle8.v v2, (t5)
    vwaddu.vx v4, v2, t2
    vsetvli zero, zero, e16, m2, ta, ma
    vwsub.vx v8, v4, t1

    vsetvli zero, zero, e32, m4, ta, mu
    vzext.vf4 v24, v2
    vsub.vx v12, v8, t1
    vmslt.vx v0, v12, zero
    vneg.v v12, v12, v0.t
    vsub.vx v16, v8, t2
    vmslt.vx v0, v16, zero
    vneg.v v16, v16, v0.t
    vsub.vv v20, v8, v24
    vmslt.vx v0, v20, zero
    vneg.v v20, v20, v0.t

    sub t5, a3, t3
    vmsleu.vv v4, v16, v20
    vmsleu.vv v24, v16, v12
    vmsgtu.vv v0, v20, v12
    vmand.mm v28, v4, v24

    vsetvli zero, zero, e8, m1, ta, ma
    vmerge.vxm v8, v2, t1, v0
    vmmv.m v0, v28
    add t5, a0, t5
    sub t3, t3, t6
    vmerge.vxm v4, v8, t2, v0

    vse8.v v4, (t5)

    bnez t3, 2b

    addi a4, a4, -1
    addi a6, a6, -1
    add a0, a0, a1
    bnez a4, 1b
    ret
