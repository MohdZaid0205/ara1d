.text
    .balign 4
    .global ipred_h_mock_r
    .type ipred_h_mock_r, @function

# void ipred_h_mock_r(uint8_t *dst, int32_t stride,
#                     const uint8_t *topleft, int width, int height)
#
# Register Mapping:
# a0 = dst
# a1 = stride
# a2 = topleft
# a3 = width
# a4 = height
#
# Ported from dav1d src/riscv/64/ipred.S (ipred_h_8bpc_rvv), commit
# 362bc1138228390a0a521ecf3af18b23c6afeb9e. Logic is byte-for-byte
# identical to upstream except: the Zba sh1add/sh2add ops (Ara has no
# Zba) are lowered to slli+add using scratch register t0, which is free
# throughout this function.
#
# height is assumed to be a multiple of 4 (dav1d never calls this with
# anything else - 4/8/16/32/64), matching the original's own assumption,
# not something "fixed" here.

ipred_h_mock_r:
    lw a7, -4(a2)
    vsetvli a6, a3, e8, m1, ta, ma
    li a5, 4
    beq a5, a4, 4f
    bgt a3, a6, 2f
1:
    srli a6, a7, 8
    vmv.v.x v4, a7
    lw a7, -8(a2)
    sub a4, a2, a4
    vmv.v.x v8, a6
    srli a5, a6, 8
    add t1, a1, a0
    srli a6, a7, 8
    vmv.v.x v12, a5
    srli a3, a5, 8
    slli t0, a1, 1
    add t2, t0, a0                      # was: sh1add t2, a1, a0
    srli a5, a7, 16
    vmv.v.x v16, a3
    slli t0, a1, 1
    add t3, t0, t1                      # was: sh1add t3, a1, t1
    addi a4, a4, 8
    srli a3, a7, 24

3:
    vse8.v v4, (t3)
    vmv.v.x v4, a7

    lw a7, -12(a2)
    addi a2, a2, -4
    slli t0, a1, 2
    add t3, t0, t3                      # was: sh2add t3, a1, t3

    vse8.v v8, (t2)
    vmv.v.x v8, a6
    srli a6, a7, 8
    slli t0, a1, 2
    add t2, t0, t2                      # was: sh2add t2, a1, t2

    vse8.v v12, (t1)
    vmv.v.x v12, a5
    srli a5, a7, 16
    slli t0, a1, 2
    add t1, t0, t1                      # was: sh2add t1, a1, t1

    vse8.v v16, (a0)
    vmv.v.x v16, a3
    srli a3, a7, 24
    slli t0, a1, 2
    add a0, t0, a0                      # was: sh2add a0, a1, a0

    bge a2, a4, 3b

    vse8.v v4, (t3)
    vse8.v v8, (t2)
    vse8.v v12, (t1)
    vse8.v v16, (a0)

    ret

4:
    srli a6, a7, 8

    vmv.v.x v4, a7
    add t1, a1, a0
    srli a5, a7, 16
    slli t0, a1, 1
    add t3, t0, t1                      # was: sh1add t3, a1, t1
    vmv.v.x v8, a6
    srli a3, a7, 24
    slli t0, a1, 1
    add t2, t0, a0                      # was: sh1add t2, a1, a0
    vse8.v v4, (t3)
    vmv.v.x v12, a5
    vse8.v v8, (t2)
    vmv.v.x v16, a3

    vse8.v v12, (t1)
    vse8.v v16, (a0)

    ret
2:
    vsetvli a6, a3, e8, m2, ta, ma
    ble a3, a6, 1b

    vsetvli a6, a3, e8, m4, ta, ma
    j 1b


