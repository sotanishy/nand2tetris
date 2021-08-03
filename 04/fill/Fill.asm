// This file is part of www.nand2tetris.org
// and the book "The Elements of Computing Systems"
// by Nisan and Schocken, MIT Press.
// File name: projects/04/Fill.asm

// Runs an infinite loop that listens to the keyboard input.
// When a key is pressed (any key), the program blackens the screen,
// i.e. writes "black" in every pixel;
// the screen should remain fully black as long as the key is pressed. 
// When no key is pressed, the program clears the screen, i.e. writes
// "white" in every pixel;
// the screen should remain fully clear as long as no key is pressed.

(LOOP)
    @KBD
    D=M
    @BLACK
    D;JNE
    @color
    M=0
    @FILL
    0;JMP
(BLACK)
    @color
    M=-1
(FILL)
    @i
    M=0
    @SCREEN
    D=A
    @loc
    M=D
(LOOP2)
    @i
    D=M
    @8192 // 256*512/16
    D=D-A
    @BREAK
    D;JEQ
    @color
    D=M
    @loc
    A=M
    M=D
    @i
    M=M+1
    @loc
    M=M+1
    @LOOP2
    0;JMP
(BREAK)
    @LOOP
    0;JMP
