;The MIT License
;
;Copyright (c) 2009 Dylan Smith
;
;Permission is hereby granted, free of charge, to any person obtaining a copy
;of this software and associated documentation files (the "Software"), to deal
;in the Software without restriction, including without limitation the rights
;to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;copies of the Software, and to permit persons to whom the Software is
;furnished to do so, subject to the following conditions:
;
;The above copyright notice and this permission notice shall be included in
;all copies or substantial portions of the Software.
;
;THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
;THE SOFTWARE.
.include	"ctrlchars.inc"

; English strings
.data
.globl STR_basicinit
.globl STR_basinsterr
.globl STR_nomem
.globl STR_sockerr
.globl STR_closeerr
.globl STR_nobuferr
.globl STR_fileerr
.globl STR_direrr
STR_basicinit:	defb	"BASIC streams support initialized",NEWLINE,0
STR_basinsterr:	defb	"BASIC streams initialization failed",NEWLINE,0
STR_nomem:	defb	"Out of memory pages",0
STR_sockerr:	defb	"Socket error",0
STR_closeerr:	defb	"Could not close socket",0
STR_nobuferr:	defb	"Out of buffers",0
STR_fileerr:	defb	"Error opening file",0
STR_direrr:	defb	"Error opening directory",0

