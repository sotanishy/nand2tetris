// This file is part of www.nand2tetris.org
// and the book "The Elements of Computing Systems"
// by Nisan and Schocken, MIT Press.
// File name: projects/04/Mult.asm

// Multiplies R0 and R1 and stores the result in R2.
// (R0, R1, R2 refer to RAM[0], RAM[1], and RAM[2], respectively.)
//
// This program only needs to handle arguments that satisfy
// R0 >= 0, R1 >= 0, and R0*R1 < 32768.

    @R2
    M=0
    @i
    M=0
    @j
    M=1
    @R1
    D=M
    @x
    M=D
(LOOP)
    @i
    D=M
    @16
    D=D-A
    @END
    D;JEQ
    @R0
    D=M
    @j
    D=D&M
    @SKIP
    D;JEQ
    @x
    D=M
    @R2
    M=M+D
(SKIP)
    @i
    M=M+1
    @j
    D=M
    M=M+D
    @x
    D=M
    M=M+D
    @LOOP
    0;JMP
(END)
    @END
    0;JMP

// i = 0
// j = 1
// while i < 16:
//     if R1 & j:
//         ans += x
//     i += 1
//     j <<= 1
//     x <<= 1
