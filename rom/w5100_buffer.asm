;The MIT License
;
;Copyright (c) 2008 Dylan Smith
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
.include	"w5100_defs.inc"
.include	"sysvars.inc"
.include	"sockdefs.inc"

; Copy from rx buffer and copy into txbuffer.
; These routines assume 2K buffers for both tx and rx (so they don't bother
; ANDing the low order of RX_MASK and TX_MASK ... so if you've changed the
; buffer size, this is probably why it broke)
; The buffers get mapped into page area A (0x1000 - 0x1FFF). On entry
; it is assumed the register area is already mapped into page area A.
;
; These are low level routines and should really only be getting called by
; the socket library. Call directly at your own risk - the call address
; is likely to change with every firmware revision!
;
; Finally, a reminder: W5100 hardware registers are BIG endian.
;
; F_copyrxbuf:
; Copy the receive buffer to a location in memory. 
; On entry:	H  = high order address of register area for socket.
;		DE = destination to move buffer contents
;		BC = size of destination buffer
; On return	BC = bytes copied
; Unchanged	IX, IY, shadow registers
.text
.globl F_copyrxbuf
F_copyrxbuf:
	; check whether page A is being used.
	; (note: will use page B if this is the case)
	call F_checkpageA

	; Set de to the number of bytes that have been received.
	push de

	; note that if the interrupt register has been checked,
	; RX_RSR should logically be nonzero, but there seems to be
	; a race condition in the W5100 where we can get here after
	; checking the RX interrupt flag but RSR is still zero.
	; The datasheet doesn't of course guarantee that the socket
	; is actually ready to read even if the interrupt is set :-)
.testzero1:
	ld l, Sn_RX_RSR0 % 256	; (hl) = RSR's MSB
	ld d, (hl)
	inc l
	ld e, (hl)
	ld a, d
	or e
	jr nz, .continue1

	; note that if there's a buffer to unload, unload it. Only
	; check for RST when there's no data pending.
	ld l, Sn_IR % 256	; point hl at the IR, test for CONNRESET
	bit BIT_IR_DISCON, (hl)
	jp nz, J_resetbypeer_pop
	jr .testzero1

.continue1:
	; check whether it exceeds the buffer. If so just use value of
	; BC as number of bytes to copy. If not, use the RSR as number
	; of bytes to copy.
	ld a, b			; MSB of length of our buffer
	cp d			; MSB of RSR
	jr c, .findoffset1	; RSR > buffer
	jr nz, .setlen1		; RSR < buffer, set actual length to RSR
	ld a, c			; LSB of RSR
	cp e			; LSB of length of our buffer
	jr c, .findoffset1	; RSR > buffer len

	; BC now should equal actual size to copy
.setlen1:
	ld b, d
	ld c, e

	; de = offset when were are done here.
.findoffset1:
	ld l, Sn_RX_RD0 % 256	; RX read pointer register for socket
	ld a, (hl)		; MSB of RX offset
	and gSn_RX_MASK / 256	; mask with 0x07
	ld d, a
	inc l
	ld e, (hl)

	; page in the correct bit of W5100 buffer memory
.setpage1:
	ld (v_sockptr), hl	; Save the current socket register pointer
	ld a, h
	sub Sn_MR / 256		; derive socket number
	bit 1, a		; upper page or lower page?
	jr nz, .upperpage1
	ld a, RX_LWRDATAPAGE	; W5100 phys. address 0x6000
	call F_setpageA
	jr .willitblend1
.upperpage1:
	ld a, RX_UPRDATAPAGE	; W5100 phys. address 0x7000
	call F_setpageA

	; Does the circular buffer wrap around?
.willitblend1:
	dec bc			; ...to1 check for >, not >=
	ld h, d			; not ex hl, de because we need to preserve it
	ld l, e
	add hl, bc
	inc bc			; undo previous dec
	ld a, h
	cp 0x08			; Does copy go over 2k boundary?
	jp p, .wrappedcopy1	; The circular buffer wraps.

	; A straight copy from the W5100 buffer to our memory.
.straightcopy1:
	ld hl, (v_sockptr)	; retrieve socket register pointer
	call F_getbaseaddr	; hl now = source address
	pop de			; retrieve destination address
	ld (v_copylen), bc	; preserve length
	ldir			; copy buffer contents

.completerx1:
	ld a, REGPAGE		; Registers are in W5100 physmem 0x0000
	call F_setpageA
	ld hl, (v_sockptr)	; retrieve socket pointer
	ld l, Sn_RX_RD0 % 256	; point it at MSB of bytes read register.
	ld d, (hl)		; d = MSB
	inc l
	ld e, (hl)		; e = LSB
	ld bc, (v_copylen)	; retrieve length copied
	ex de, hl
	add hl, bc		; hl = new RX_RD pointer
	ex de, hl
	ld (hl), e		; copy LSB
	dec l
	ld (hl), d		; copy MSB, RX_RD now set.
	ld l, Sn_CR % 256	; (hl) = socket command register
	ld (hl), S_CR_RECV	; tell hardware that receive is complete
	ld a, (v_buf_pgb)	; check to see whether to re-page area B
	and a			; zero?
	jp nz, F_setpageB	; yes - restore page B and return.
	ret			; no, return.

	; The circular buffer wraps around, leading to a slightly
	; more complicated copy.
	; Stack contains the destination address
	; BC contains length to copy
	; DE contains offset
.wrappedcopy1:
	ld (v_copylen), bc	; save length
	ld hl, 0x0800		; the highest offset you can have
	sbc hl, de		; hl = how many bytes before we hit the end
	ld (v_copied), hl	; save it
	ld hl, (v_sockptr)	; retrieve socket register ptr
	call F_getbaseaddr	; hl is now source address
	pop de			; destination buffer now in DE
	ld bc, (v_copied)	; first chunk length now in BC
	ldir			; copy chunk
	ld a, h			; roll HL back 0x0800
	sub 0x08
	ld h, a
	push hl			; save new address
	ld bc, (v_copied)	; bytes copied so far
	ld hl, (v_copylen)	; total bytes to copy
	sbc hl, bc		; hl = remaining bytes
	ld b, h
	ld c, l
	pop hl			; retrieve address
	ldir			; transfer remainder
	jr .completerx1		; done

;============================================================================
; F_copytxbuf:
; Copy the receive buffer to a location in memory, set hardware registers
; to send the buffer contents. 
; On entry:	H  = high order address of register area for socket.
;		DE = source buffer to copy to hardware
;		BC = size of source buffer
; On return	BC = bytes copied
; Unchanged	IX, IY, shadow registers
;
; Notes: If sending >2k of data, data should only be fed into this routine
; in chunks of <=2k a time or it'll hang. The socket library's send() 
; call should do this.
.globl F_copytxbuf
F_copytxbuf:
	; check whether page A is being used.
	; (note: will use page B if this is the case)
	call F_checkpageA

.waitformsb2:
	ld l, Sn_IR % 256	; point hl at the IR, test for CONNRESET
	bit BIT_IR_DISCON, (hl)
	jp nz, J_resetbypeer
	ld l, Sn_TX_FSR0 % 256	; point hl at free space register
	ld a, b			; MSB of argment
	cp (hl)			; compare with FSR
	jr c, .getoffset2	; definitely enough free space
	jr nz, .waitformsb2	; Buffer MSB > FSR MSB
				; Buffer MSB = FSR MSB, check LSB value
.waitforlsb2:
	ld l, Sn_IR % 256	; point hl at the IR, test for CONNRESET
	bit BIT_IR_DISCON, (hl)
	jp nz, J_resetbypeer
	ld l, Sn_TX_FSR1 % 256	; point hl at free space register
	ld a, (hl)		; get LSB of FSR
	cp c			; and compare with LSB of passed value
	jr c, .waitforlsb2	; if C > (hl) wait until it's not.

.getoffset2:
	ld (v_sockptr), hl	; save the socket register pointer
	ld (v_copylen), bc	; save the buffer length
	push de			; save the source buffer pointer
	ld l, Sn_TX_WR0 % 256	; (hl) = TX write register offset MSB
	ld a, (hl)
	and gSn_TX_MASK / 256	; and 0x07 - 2k buffers
	ld d, a			; high order of offset in d
	inc l
	ld e, (hl)		; de = offset

	; page in the correct bit of W5100 buffer memory. TX buffer for
	; socket 0 and 1 in page 0x0104 and for 2 and 3 in 0x0105, mapping
	; socket 0 and 2 to 0x1000, 1 and 3 to 0x1800.
.setpage2:
	ld a, h
	sub Sn_MR / 256		; derive socket number
	bit 1, a		; upper page or lower page?
	jr nz, .upperpage2
	ld a, TX_LWRDATAPAGE	; W5100 phys. address 0x4000
	call F_setpageA
	jr .willitblend2
.upperpage2:
	ld a, TX_UPRDATAPAGE	; W5100 phys. address 0x5000
	call F_setpageA

	; add de (offset) and bc (length) and see if it's >0x0800, in
	; which case buffer copy needs to wrap.
.willitblend2:
	dec bc			; ...to2 check for >, not >=
	ld h, d			; not ex hl, de because we need to preserve it
	ld l, e
	add hl, bc
	inc bc			; undo previous dec
	ld a, h
	cp 0x08			; Does copy go over 2k boundary?
	jp p, .wrappedcopy2	; The circular buffer wraps.

.straightcopy2:
	ld hl, (v_sockptr)	; restore socket pointer
	call F_getbaseaddr
	ex de, hl		; for LDIR
	pop hl			; get stacked source address
	ldir

.completetx2:
	ld a, REGPAGE		; registers in W5100 phys. 0x0000
	call F_setpageA
	ld hl, (v_sockptr)	; get the socket pointer back
	ld l, Sn_TX_WR0 % 256	; transmit register
	ld d, (hl)		; get MSB of TX_WR0
	inc l
	ld e, (hl)		; get LSB of TX_WR0
	ex de, hl		; swap into hl
	ld bc, (v_copylen)	; get length that was copied into the buffer
	add hl, bc		; new value of TX_WR0
	ex de, hl		; move to de
	ld (hl), e		; copy into TX_WR0
	dec l
	ld (hl), d
	ld l, Sn_CR % 256	; (hl) = command register
	ld (hl), S_CR_SEND	; update command register
	ld a, (v_buf_pgb)	; check to see whether to re-page area B
	and a			; zero?
	jp nz, F_setpageB	; yes - restore page B and return.
	ret			; no, return.

.wrappedcopy2:
	ld hl, 0x0800		; the highest offset you can have
	sbc hl, de		; hl = how many bytes before we hit the end
	ld (v_copied), hl	; save it
	ld hl, (v_sockptr)	; retrieve socket register ptr
	call F_getbaseaddr	; hl is now source address
	ex de, hl		; swap for LDIR
	pop hl			; get source address off stack
	ld bc, (v_copied)	; length of this chunk
	ldir			; transfer
	ld a, d			; roll de back
	sub 0x08		; 0x0800 bytes
	ld d, a
	push hl			; save current source buffer ptr
	ld bc, (v_copied)	; bytes copied so far
	ld hl, (v_copylen)	; total bytes to copy
	sbc hl, bc		; hl = remaining bytes
	ld b, h
	ld c, l
	pop hl			; retrieve source buffer ptr
	ldir			; transfer remainder
	jr .completetx2		; done

J_resetbypeer_pop:
	pop de
J_resetbypeer:
	ld a, (v_buf_pgb)	; check to see whether to re-page area B
	and a			; zero?
	call nz, F_setpageB	; yes - restore page B and return.
	ld a, ECONNRESET
	scf
	ret

;============================================================================
; F_getbaseaddr:
; This routine sets HL to the base address.
; On entry: 	de = offset
;		h  = high order of socket register address
; On exit:	hl = base address
.globl F_getbaseaddr
F_getbaseaddr:
	ld l, 0
	ld a, h
	sub Sn_BASE		; a = 0x10 for skt 0, 0x11 for skt 1, 0x12 etc. 
	and %00010001		; mask out all but bits 4 and 1

	; at this stage, a = 0x10 for skt 0, 0x11 for skt 1, 0x10 for skt 2
	; and 0x11 for skt 3. The entire W5100 receive buffer area for
	; all sockets is 8k, but we're only paging in 4k at at time at
	; 0x1000-0x1FFF, so the physical address should either end up
	; being 0x1000 (skt 0 and 2) or 0x1800 (skt 1 and 3)
	bit 0, a		; bit 0 set = odd numbered socket at 0x1800
	jr nz, .oddsock3
	ld h, a
	add hl, de		; hl = physical address
	ret
.oddsock3:
	add a, 0x07		; odd sockets are 0x18xx addresses	
	ld h, a
	add hl, de
	ret

;=========================================================================
; F_checkpageA
; On entry: DE = buffer start
.globl F_checkpageA
F_checkpageA:
	ld a, d
	and 0xF0		; mask off top 4 bits
	cp 0x10			; are we in 0x1000 - 0x1FFF?
	jr z, .swappages4	; yes, swap pages.
	xor a			; reset the sysvar
	ld (v_buf_pgb), a
	ret
.swappages4:
	ld a, d
	xor 0x30		; flip bits 4 and 5 to convert 0x1xxx to 0x2xxx
	ld d, a
	ld a, (v_pgb)		; get current page B
	ld (v_buf_pgb),a 	; save it
	ld a, (v_buf_pga)	; get page A value
	call F_setpageB		; page it in
	ret	

