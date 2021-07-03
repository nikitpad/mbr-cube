    bits 16
    org 0x7c00

    ; initialize ds to 0
    xor bx, bx
    mov ds, bx
    ; initialize stack
    mov sp, 0x7c00
    ; initialize FPU
    fninit
    ; enter 320x200 256-color graphics mode (mode 13h)
    mov ax, 0x13
    int 0x10
    
    ; zero out a sector of the post-MBR storage in RAM, just in case it isn't zero
    xor ax, ax
    mov es, ax
    mov di, 0x7e00
    mov cx, 512
    rep stosb

frame:
    inc word [time_int]
    ; calculate sines and cosines for rotations,
    ; their angles are dependent on time
    fld dword [time1]
    fadd dword [time_inc]
    fst dword [time1]
    fsincos
    fstp dword [cos1]
    fstp dword [sin1]
    
    fld dword [time2]
    fadd dword [time_inc]
    fst dword [time2]
    fsincos
    fstp dword [cos2]
    fstp dword [sin2]
    
    ; clear z buffer (located at 0x30000 in physical memory)
    mov bx, 0x3000
    mov al, 0x7F
    mov es, bx
    xor di, di
    mov cx, 64000
    rep stosb
    
    ; clear pixel buffer (located at 0x20000 in physical memory)
    xor al, al
    mov bx, 0x2000
    mov es, bx
    xor di, di
    mov cx, 64000
    rep stosb
    mov bx, -50 + 1
    fld dword [time1]
    fsin
    fmul dword [z_detach_scale]
    fistp word [z_detach]
    mov cx, word [z_detach]
    ;shr cx, 4
    ;and cx, 15
    add cx, 50
    mov bp, 100 - 1
vertical:
    ; render each face as a quad in 3d space
    mov ax, -50 + 1
    mov dx, 100 - 1
horizontal:
    ; faces 1-4: do 4 90 degree rotations around x axis
    ; and render one pixel for each of 4 faces
    mov si, 4
.x_axis_loop:
    call plot_pixel
    xchg bx, cx
    neg bx
    dec si
    jnz .x_axis_loop
    ; render pixel for face 5
    mov si, 5
    ; rotate by 90 deg around y axis to get face 5's pixel position
    xchg ax, cx
    neg cx
    call plot_pixel
    ; render pixel for face 6
    mov si, 6
    ; rotate previous face by 180 deg around y axis
    ; to get this face's pixel position
    neg ax
    neg cx
    call plot_pixel
    ; do another 90 deg rotation around y axis
    ; to get back at face 1
    xchg ax, cx
    neg cx

    inc ax
    dec dx
    jnz horizontal
    inc bx
    dec bp
    jnz vertical
    
    ; copy 320*200 bytes from 0x20000 (our pixel buffer) => 0xA0000 (VGA memory)
    push ds
    mov ax, 0x2000
    mov ds, ax
    mov ax, 0xA000
    mov es, ax
    xor si, si
    xor di, di
    mov cx, 320*200
    rep movsb
    pop ds
    jmp frame

    ; warning:
    ; i'm not very experienced with x87 programming,
    ; so maybe this could be optimized
plot_pixel:
    pushad
    ; convert pixel positions to floats
    mov word [rotated_x], ax
    mov word [rotated_y], bx
    mov word [rotated_z], cx
    fild  word [rotated_x]
    fstp dword [rotated_x]
    fild  word [rotated_y]
    fstp dword [rotated_y]
    fild  word [rotated_z]
    fstp dword [rotated_z]

    ; perform x-axis rotation
    ; y2 = cos * y1 - sin * z1
    ; z2 = sin * y1 + cos * z1
    fld dword [sin1]
    fld dword [cos1]

    fld dword [rotated_y]
    fmul st0, st1
    fld dword [rotated_z]
    fmul st0, st3
    fsubp
    
    fld dword [rotated_y]
    fmul st0, st3
    fld dword [rotated_z]
    fmul st0, st3
    faddp
    
    fstp dword [rotated_z]
    fstp dword [rotated_y]
    
    fstp st0
    fstp st0
    
    ; perform y-axis rotation
    ; x2 = cos * x1 + sin * z1
    ; z2 = cos * z1 - sin * x1
    fld dword [sin2]
    fld dword [cos2]

    fld dword [rotated_x]
    fmul st0, st1
    fld dword [rotated_z]
    fmul st0, st3
    faddp
        
    fld dword [rotated_x]
    fmul st0, st3
    fld dword [rotated_z]
    fmul st0, st3
    fsubp
    
    ; convert our depth value to an integer that fits in a byte
    fld st0
    fmul dword [z_buffer_scale]
    fistp word [rotated_z]
    fadd dword [z_add]
    
    ; perform perspective projection
    fld dword [rotated_y]
    fdiv st0, st1
    fmul dword [screen_scale]
    fistp word [rotated_y]
    fdivp st1, st0
    fmul dword [screen_scale]
    fistp word [rotated_x]
    
    fstp st0
    fstp st0
    
    mov di, word [time_int]
    shr di, 4
    add si, di
    and si, 15
    ; get color of face from color table
    mov bl, byte [si+palette]
    mov si, word [rotated_x]
    mov di, word [rotated_y]
    ; center the position of the pixel
    add si, 320 / 2
    add di, 200 / 2
    ; check if the pixel's position is out of bounds
    cmp si, 320
    jge .skip
    test si, si
    js .skip
    cmp di, 200
    jge .skip
    test di, di
    js .skip
    
    ; pixel_index = y * 320 + x
    imul di, di, 320
    add di, si
    
    mov cx, 0x3000 ; Z-buffer segment
    mov si, 0x2000 ; pixel buffer segment
    
    ; check if the Z value of the pixel
    ; is greater than the one in the Z-buffer
    mov al, byte [rotated_z]
    mov es, cx
    cmp al, byte [es:di]
    ; if yes, don't draw the pixel
    jge .skip
    
    ; put new Z value into the Z-buffer
    mov byte [es:di], al
    mov es, si
    ; draw the pixel
    mov byte [es:di], bl

.skip:
    mov es, si
    popad
    ret

; --- variables ---

offset_y: dd 2.0
z_add: dd 300.0
z_buffer_scale: dd 1.2
screen_scale: dd 160.0
time2: dd 2.0
time_inc: dd 0.005
z_detach_scale: dd 15.0
palette:
    db 0x20, 0x22, 0x23, 0x25
    db 0x26, 0x27, 0x28, 0x2A
    db 0x2C, 0x2D, 0x2F, 0x30
    db 0x32, 0x34, 0x36, 0x37

times 510-$+$$ db 0
dw 0xaa55

time1: dd 0.0
sin1: dd 0.0
cos1: dd 0.0
sin2: dd 0.0
cos2: dd 0.0
rotated_x: dd 0.0
rotated_y: dd 0.0
rotated_z: dd 0.0
time_int: dw 0
z_detach: dw 0
