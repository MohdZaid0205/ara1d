.text
    .balign 4
    .global ipred_v_mock_r
    .type ipred_v_mock_r, @function

# void ipred_v_mock_r(uint8_t *dst, int32_t stride, 
#                     const uint8_t *topleft, int width, int height)
#
# Register Mapping:
# a0 = dst
# a1 = stride
# a2 = topleft
# a3 = width
# a4 = height

ipred_v_mock_r:
    addi a2, a2, 1                      # topleft + 1 to point to top neighbors
    
    # Try processing the whole width with 1 vector register (LMUL=1)
    vsetvli t0, a3, e8, m1, ta, ma
    bne t0, a3, slow_path               # If width > available VLEN, go to slow path

fast_path:
    # Entire row fits in the register. Unroll by 2 rows.
    add t1, a0, a1                      # t1 = dst + stride (pointer to 2nd row)
    vle8.v v4, (a2)                     # Load the entire top row into v4
    slli t3, a1, 1                      # t3 = stride * 2 (for pointer math)

fast_loop:
    vse8.v v4, (a0)                     # Store to row N
    add a0, a0, t3                      # dst += 2 * stride
    
    vse8.v v4, (t1)                     # Store to row N+1
    add t1, t1, t3                      # t1 += 2 * stride
    
    addi a4, a4, -2                     # height -= 2 (Assumes height is always even)
    bnez a4, fast_loop                  # Loop until all rows are done
    ret

slow_path:
    # Row doesn't fit in LMUL=1. Try grouping 2 registers (LMUL=2).
    vsetvli t0, a3, e8, m2, ta, ma
    beq t0, a3, fast_path               # If it fits now, jump back up!

column_loop:
    # Process in vertical slices (chunks of VLEN)
    vle8.v v4, (a2)                     # Load a chunk of the top row
    mv t2, a0                           # temp dst pointer for this slice
    mv t1, a4                           # temp height counter

row_loop:
    vse8.v v4, (t2)                     # Store chunk to current row
    add t2, t2, a1                      # move to next row
    addi t1, t1, -1                     # decrement row counter
    bnez t1, row_loop                   # Loop over all rows for this slice

    # Advance pointers for the next vertical slice
    sub a3, a3, t0                      # width -= processed elements
    add a2, a2, t0                      # topleft += processed elements
    add a0, a0, t0                      # dst += processed elements
    
    bnez a3, column_loop                # Loop until the entire width is copied
ret
