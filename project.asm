;%define	PADLEFT	"     "
;%define CLEARRIGHT	0x1b, "[K"

segment .data

segment .bss

segment .text
	global  asm_main

asm_main:
	push	ebp
	mov		ebp, esp
	; ********** CODE STARTS HERE **********

	call	newgame

	; *********** CODE ENDS HERE ***********
	mov		eax, 0
	mov		esp, ebp
	pop		ebp
	ret

; newgame()
;
; Local vars:
;
; LOCAL_DOWN
; LOCAL_FIELDPOS
; LOCAL_YARDSTOGO
; LOCAL_HOME
; LOCAL_TIME
; LOCAL_VISITOR
; LOCAL_QUARTER
; LOCAL_PLAYER_LOC_X
; LOCAL_PLAYER_LOC_Y
; LOCAL_DEFENDER1_LOC_X
; LOCAL_DEFENDER1_LOC_Y
; LOCAL_DEFENDER2_LOC_X
; LOCAL_DEFENDER2_LOC_Y
; LOCAL_DEFENDER3_LOC_X
; LOCAL_DEFENDER3_LOC_Y
; LOCAL_DEFENDER4_LOC_X
; LOCAL_DEFENDER4_LOC_Y
; LOCAL_DEFENDER5_LOC_X
; LOCAL_DEFENDER5_LOC_Y
newgame:
	enter	0, 0
	call	clearscreen
	call	drawboard
	leave
	ret


; drawboard()
;
; Draw the playing board


segment .data

boardstr	db	10
		db	"   ---------------------------------------------    ", 10
		db	"   |||   |   |   |   |   |   |   |   |   |   |||    ", 10
		db	"\  ||-   -   -   -   -   -   -   -   -   -   -||  / ", 10
		db	" | |||   |   |   |   |   |   |   |   |   |   ||| |  ", 10
		db	"/  ||-   -   -   -   -   -   -   -   -   -   -||  \ ", 10
		db	"   |||   |   |   |   |   |   |   |   |   |   |||    ", 10
		db	"   ---------------------------------------------    ", 10
		db	10
		db	"   ---------------------------------------------    ", 10
		db	"   | DOWN: 9 | FIELDPOS: 99> | YARDS TO GO: 99 |    ", 10
		db	"   ---------------------------------------------    ", 10
		db	"   | HOME: 99 | VISITOR: 99 |                       ", 10
		db	"   -------------------------------------            ", 10
		db	"   | QUARTER: 9 | TIME REMAINING: 99.9 |            ", 10
		db	"   -------------------------------------            ", 10
		db	0




drawboard:
	enter	0, 0
	call	homecursor
	push	boardstr
	call	printf
	add	esp, 4
	leave
	ret

;
; clearscreen()
;
; Clear the screen

segment .data

	clearstr	db	0x1b, "[2J", 0

clearscreen:
	enter	0, 0

	push	clearstr
	call	printf
	add	esp, 4

	leave
	ret


;
; homecursor()
;
; Home the cursor

segment .data

	homestr	db	0x1b, "[f", 0

homecursor:
	enter	0, 0

	push	homestr
	call	printf
	add	esp, 4

	leave
	ret




;
; int random(unsigned int x)
;
; Returns: A random number between 0 and x-1

%define	SYS_read	0x03
%define	SYS_open	0x05
%define	SYS_close	0x06

%define	READ_ONLY	0


segment .data

	urandom	db	"/dev/urandom", 0

random:
	enter	4, 0

	; save ebx, ecx, edx
	push	ebx
	push	ecx
	push	edx

	; Open /dev/urandom
	mov	eax, SYS_open
	mov	ebx, urandom
	mov	ecx, 0
	mov	edx, READ_ONLY
	int	0x80

	; eax = file descriptor
	; if eax < 0, error

	; Read 4 bytes
	mov	ebx, eax
	mov	eax, SYS_read
	lea	ecx, [ebp - 4]
	mov	edx, 4
	int	0x80

	; eax = # bytes read.  Should be 4.

	; Close /dev/urandom
	mov	eax, SYS_close
	int	0x80

	; eax should be 0

	; Compute [ebp - 4] % [ebp + 8]
	mov	eax, DWORD [ebp - 4]
	xor	edx, edx
	mov	ebx, DWORD [ebp + 8]
	div	ebx
	mov	eax, edx

	; restore ebx, ecx, edx
	pop	edx
	pop	ecx
	pop	ebx

	leave

	ret


; printf(char *format, ...)
;
; A simple implementation of printf(), supporting the following:
;
; %s - print a NULL terminated string for the char* argument.
; %c - print a character for a char argument.
; %% - print a literal percent sign.
; %d - print a signed integer for a 4 byte int argument.
; %u - print an unsigned integer for a 4 byte unsigned int argument.
;
; Two custom options for handling an arbitrary number of bytes per int:
;
; %D#\d+# - signed integer of the specified number of bytes
; %U#\d+# - unsigned integer of the specified number of bytes
;
; Supports 1 - MAX_BYTES byte ints.  To extend to more bytes:
;
; - Update the MAX_BYTES define to the new number.
; - Add entries to the digits table for the additional numbers of bytes.
; - Update the powers table to include the powers of 10 up to the maximum
;   number of digits.
;
; Return: none


; Defines for arguments
%define ARG_FORMAT	[ebp + 8]
%define ARG_1		[ebp + 12]

; Defines for local variables
%define LOCAL_PRTG	[ebp - 3 ]
%define LOCAL_OUTC	[ebp - 4 ]
%define LOCAL_I		[ebp - 8 ]
%define LOCAL_J		[ebp - 12]
%define	LOCAL_BYTES	[ebp - 16]

segment .data

%define MAX_BYTES 16
%define MIN_BYTES 1

; Max number of digits in an N byte integer.  0<= N <=16
digits db 0x00, 0x00, 0x00, 0x00
       db 0x03, 0x00, 0x00, 0x00 ; 1 byte = 3 digits
       db 0x05, 0x00, 0x00, 0x00 ; 2 bytes = 5 digits
       db 0x08, 0x00, 0x00, 0x00 ; 3 bytes = 8 digits
       db 0x0a, 0x00, 0x00, 0x00 ; 4 bytes = 10 digits
       db 0x0d, 0x00, 0x00, 0x00 ; 5 bytes = 13 digits
       db 0x0f, 0x00, 0x00, 0x00 ; 6 bytes = 15 digits
       db 0x11, 0x00, 0x00, 0x00 ; 7 bytes = 17 digits
       db 0x14, 0x00, 0x00, 0x00 ; 8 bytes = 20 digits
       db 0x16, 0x00, 0x00, 0x00 ; 9 bytes = 22 digits
       db 0x19, 0x00, 0x00, 0x00 ; 10 bytes = 25 digits
       db 0x1b, 0x00, 0x00, 0x00 ; 11 bytes = 27 digits
       db 0x1d, 0x00, 0x00, 0x00 ; 12 bytes = 29 digits
       db 0x20, 0x00, 0x00, 0x00 ; 13 bytes = 32 digits
       db 0x22, 0x00, 0x00, 0x00 ; 14 bytes = 34 digits
       db 0x25, 0x00, 0x00, 0x00 ; 15 bytes = 37 digits
       db 0x27, 0x00, 0x00, 0x00 ; 16 bytes = 39 digits

; Table of powers of 10 for 16 byte integers.
powers db 0x00,0x00,0x00,0x00,0x40,0x22,0x8a,0x09,0x7a,0xc4,0x86,0x5a,0xa8,0x4c,0x3b,0x4b ; 10^38
       db 0x00,0x00,0x00,0x00,0xa0,0x36,0xf4,0x00,0xd9,0x46,0xda,0xd5,0x10,0xee,0x85,0x07 ; 10^37
       db 0x00,0x00,0x00,0x00,0x10,0x9f,0x4b,0xb3,0x15,0x07,0xc9,0x7b,0xce,0x97,0xc0,0x00 ; 10^36
       db 0x00,0x00,0x00,0x00,0xe8,0x8f,0x87,0x2b,0x82,0x4d,0xc7,0x72,0x61,0x42,0x13,0x00 ; 10^35
       db 0x00,0x00,0x00,0x00,0x64,0x8e,0x8d,0x37,0xc0,0x87,0xad,0xbe,0x09,0xed,0x01,0x00 ; 10^34
       db 0x00,0x00,0x00,0x00,0x0a,0x5b,0xc1,0x38,0x93,0x8d,0x44,0xc6,0x4d,0x31,0x00,0x00 ; 10^33
       db 0x00,0x00,0x00,0x00,0x81,0xef,0xac,0x85,0x5b,0x41,0x6d,0x2d,0xee,0x04,0x00,0x00 ; 10^32
       db 0x00,0x00,0x00,0x80,0x26,0x4b,0x91,0xc0,0x22,0x20,0xbe,0x37,0x7e,0x00,0x00,0x00 ; 10^31
       db 0x00,0x00,0x00,0x40,0xea,0xed,0x74,0x46,0xd0,0x9c,0x2c,0x9f,0x0c,0x00,0x00,0x00 ; 10^30
       db 0x00,0x00,0x00,0xa0,0xca,0x17,0x72,0x6d,0xae,0x0f,0x1e,0x43,0x01,0x00,0x00,0x00 ; 10^29
       db 0x00,0x00,0x00,0x10,0x61,0x02,0x25,0x3e,0x5e,0xce,0x4f,0x20,0x00,0x00,0x00,0x00 ; 10^28
       db 0x00,0x00,0x00,0xe8,0x3c,0x80,0xd0,0x9f,0x3c,0x2e,0x3b,0x03,0x00,0x00,0x00,0x00 ; 10^27
       db 0x00,0x00,0x00,0xe4,0xd2,0x0c,0xc8,0xdc,0xd2,0xb7,0x52,0x00,0x00,0x00,0x00,0x00 ; 10^26
       db 0x00,0x00,0x00,0x4a,0x48,0x01,0x14,0x16,0x95,0x45,0x08,0x00,0x00,0x00,0x00,0x00 ; 10^25
       db 0x00,0x00,0x00,0xa1,0xed,0xcc,0xce,0x1b,0xc2,0xd3,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^24
       db 0x00,0x00,0x80,0xf6,0x4a,0xe1,0xc7,0x02,0x2d,0x15,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^23
       db 0x00,0x00,0x40,0xb2,0xba,0xc9,0xe0,0x19,0x1e,0x02,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^22
       db 0x00,0x00,0xa0,0xde,0xc5,0xad,0xc9,0x35,0x36,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^21
       db 0x00,0x00,0x10,0x63,0x2d,0x5e,0xc7,0x6b,0x05,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^20
       db 0x00,0x00,0xe8,0x89,0x04,0x23,0xc7,0x8a,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^19
       db 0x00,0x00,0x64,0xa7,0xb3,0xb6,0xe0,0x0d,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^18
       db 0x00,0x00,0x8a,0x5d,0x78,0x45,0x63,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^17
       db 0x00,0x00,0xc1,0x6f,0xf2,0x86,0x23,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^16
       db 0x00,0x80,0xc6,0xa4,0x7e,0x8d,0x03,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^15
       db 0x00,0x40,0x7a,0x10,0xf3,0x5a,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^14
       db 0x00,0xa0,0x72,0x4e,0x18,0x09,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^13
       db 0x00,0x10,0xa5,0xd4,0xe8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^12
       db 0x00,0xe8,0x76,0x48,0x17,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^11
       db 0x00,0xe4,0x0b,0x54,0x02,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^10
       db 0x00,0xca,0x9a,0x3b,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^9
       db 0x00,0xe1,0xf5,0x05,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^8
       db 0x80,0x96,0x98,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^7
       db 0x40,0x42,0x0f,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^6
       db 0xa0,0x86,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^5
       db 0x10,0x27,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^4
       db 0xe8,0x03,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^3
       db 0x64,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^2
       db 0x0a,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^1
       db 0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; 10^0

; The largest 16 byte unsigned integer 0xffffffffffffffffffffffffffffffff
; would be 340282366920938463463374607431768211455 in decimal.
; 39 digits long.
;
; Useful site: https://www.rapidtables.com/convert/number/hex-to-decimal.html

printf:

	enter	16,0
	pushf
	pusha

	; ebp + 8 + 4n : nth argument
	; .
	; .
	; .
	; ebp + 16   : second argument
	; ebp + 12   : first argument
	; ebp + 8    : format
	; ebp + 4    : return address
	; ebp        : saved ebp
	;
	; Local vars
	; ebp - 3   LOCAL_PRTG  : bool printing - Set to 1 once we have started printing the int.  Used to suppress leading 0s.
	; ebp - 4   LOCAL_OUTC  :  char outchar - space to hold a character for printing the int.
	; ebp - 8   LOCAL_I     :         int i - loop counter
	; ebp - 12  LOCAL_J     :         int j - loop counter
	; ebp - 16  LOCAL_BYTES :     int bytes - Number of bytes for the int.

	; esi : will step through each character of the format string
	; edi : will step through each subsequent argument on the stack

	mov	esi, ARG_FORMAT		; esi points to format string
	dec	esi
	lea	edi, ARG_1		; edi will point to each subsequent argument


	printf_toploop:
	mov	DWORD LOCAL_BYTES, 4	; default to 4 byte integers

	inc	esi
	cmp	BYTE [esi], 0
	je	printf_endloop		; End of the format string

	cmp	BYTE [esi], '%'
	jne	printf_char_literal


	; Have a %, so check the next character in format

	inc	esi		; Move to next character

	cmp	BYTE [esi], 0
	je	printf_endloop		; End of format string

	cmp	BYTE [esi], '%'
	je	printf_char_literal

	cmp	BYTE [esi], 's'
	je	printf_string

	cmp	BYTE [esi], 'c'
	je	printf_char

	cmp	BYTE [esi], 'd'
	je	printf_int

	cmp	BYTE [esi], 'u'
	je	printf_uint

	cmp	BYTE [esi], 'D'
	je	printf_INT_or_UINT

	cmp	BYTE [esi], 'U'
	je	printf_INT_or_UINT

	jmp	printf_toploop	; Ignore any other unsupported % formats


	; print a character
	printf_char:
		mov	eax, 4		; 4 = SYS_WRITE
		mov	ebx, 1		; 1 = stdout
		mov	ecx, edi	; edi points to the char
		mov	edx, 1		; length 1
		int	0x80

		add	edi, 4		; Move edi to next argument
		jmp	printf_toploop


	; print a string
	printf_string:
		; Calculate length of string
		push	edi		; Save edi, since needed for scasb

		mov	edi, [edi]	; Point edi to the string itself.
		mov	ecx, 0FFFFFFFFh	; String length approach from text book, pages 112-113.
		xor	al, al		;
		cld			;
		repnz	scasb		;
		mov	edx, 0FFFFFFFEh	;
		sub	edx, ecx	; edx now holds the length of string

		pop	edi		; restore edi

		mov	eax, 4		; 4 = SYS_WRITE
		mov	ebx, 1		; 1 = stdout
		mov	ecx, [edi]	; point to string to print
		int	0x80

		add	edi, 4		; Move edi to next argument
		jmp	printf_toploop


	; print character at esi
	printf_char_literal:
		mov	eax, 4		; 4 = SYS_WRITE
		mov	ebx, 1		; 1 = stdout
		mov	ecx, esi	; esi points to the char
		mov	edx, 1		; length 1
		int	0x80

		jmp	printf_toploop


	; print an integer
	printf_INT_or_UINT:
		; Need to parse the # bytes values.
		; %[UD]#\d+#
		cmp	BYTE [esi+1], '#'
		jne	printf_toploop

		; Save the format char in cl
		mov	cl, BYTE [esi]

		inc	esi
		xor	eax, eax
		; scan until we find '#'.  Ignore any non-digits.
		UD_parse_next:
		inc	esi
		cmp	BYTE [esi], 0	; End of format string
		je	printf_endloop
		cmp	BYTE [esi], '#'
		je	UD_parse_done
		cmp	BYTE [esi], '0'
		jl	UD_parse_next
		cmp	BYTE [esi], '9'
		jg	UD_parse_next
		mov	ebx, 10
		mul	ebx
		xor	ebx, ebx
		add	bl, BYTE [esi]
		sub	bl, '0'
		add	eax, ebx
		jmp	UD_parse_next

		UD_parse_done:
		; Check MIN_BYTES <= eax <= MAX_BYTES
		cmp	eax, MIN_BYTES
		jl	printf_toploop
		cmp	eax, MAX_BYTES
		jg	printf_toploop

		mov	LOCAL_BYTES, eax	; bytes = eax
		cmp	cl, 'U'
		je	printf_uint

	printf_int:
		; Check high order byte for sign
		mov	eax, edi
		add	eax, LOCAL_BYTES
		dec	eax
		cmp	BYTE [eax], 0
		jge	printf_uint

		; For negative, print out a minus sign and convert to a positive for printing
		mov	BYTE LOCAL_OUTC, '-'	;  outchar = '-'
		mov	eax, 4		; 4 = SYS_WRITE
		mov	ebx, 1		; 1 = stdout
		lea	ecx, LOCAL_OUTC	; outchar
		mov	edx, 1		; length = 1
		int	0x80

		; Negate the argument on the stack.
		mov	eax, edi
		clc
		not	BYTE [eax]
		add	BYTE [eax], 1
		pushf
		mov	ecx, LOCAL_BYTES
		dec	ecx
		jz	printf_negate_endloop

                printf_negate_toploop:
                inc     eax
                not     BYTE [eax]
                popf
                adc     BYTE [eax], 0
                pushf
                loop    printf_negate_toploop

                printf_negate_endloop:

		popf

	printf_uint:
		mov	ebx, DWORD LOCAL_BYTES	; Look up in the digits table
		shl	ebx, 2			; how many digits are needed
		add	ebx, digits		; for LOCAL_BYTES many bytes.
		mov	eax, [ebx]
		mov	DWORD LOCAL_I, eax	; i = number of DIGITS

		; point ecx to the highest needed power of 10
		;
		; powers + (cols*rows) - (cols*i) = powers + cols*(rows-i)
		;   where cols = number of bytes per power of 10 (which is MAX_BYTES)
		;   and   rows = number of powers of 10, which is the last entry in the digits table.

		mov	ebx, MAX_BYTES
		shl	ebx, 2
		add	ebx, digits
		mov	eax, [ebx]		; eax = rows
		sub	eax, LOCAL_I		; eax = rows - i
		mov	ebx, MAX_BYTES
		mul	ebx			; eax = cols*(rows-i)
		add	eax, powers		; eax = powers + cols*(rows-i)

		mov	ecx, eax		; ecx points to highest power of 10 needed.

		mov	BYTE LOCAL_PRTG, 0	; printing = 0


		; Print the LOCAL_BYTES byte integer in num as a decimal
		; through repeated subtraction of powers of 10 to determine
		; each digit.
		;
		; Starting with the largest power of 10, each individual
		; byte of the power is subtracted from the corresponding
		; byte of the int argument, and the carry flag is used to
		; cascade into each byte the int.
		;
		; If the carry flag is set after the subtraction of the
		; last byte of the int, the operation is completed for that
		; particular power of 10.  The outchar is incremented
		; each time through the loop to obtain the digit.
		;
		; Since the process goes one subtraction "too far", the
		; power of 10 needs to be added back to the int once.
		;
		; Process is then repeated for the next smaller power of 10.
		;
		; Each calculated digit is outputted, with leading 0s
		; suppressed.
		;
		; ecx is maintained as a pointer into the powers of 10 table.

		printf_int_loop_digits:	; for i=DIGITS, i>0; i--
			mov	BYTE LOCAL_OUTC, 0x2f	; outchar = '/' (one char before a '0')

			; Subtract the current power of 10 (pointed to by ecx) until we overflow
			printf_int_loop_decrement_pow10:
				inc	BYTE LOCAL_OUTC	; increment outchar
				mov	ebx, edi	; point ebx to int argument
				clc
				pushf
				mov	eax, LOCAL_BYTES
				mov	LOCAL_J, eax		; j = LOCAL_BYTES
				printf_int_loop_bytes_1:	; for j=LOCAL_BYTES; j>0; j--
					mov	al, BYTE [ebx]
					popf
					sbb	al, BYTE [ecx]
					pushf
					mov	BYTE [ebx], al
					inc	ecx
					inc	ebx
					dec	DWORD LOCAL_J	; j--
					jnz	printf_int_loop_bytes_1
				sub	ecx, LOCAL_BYTES	; point ecx to first byte of this power
				popf
				jnc	printf_int_loop_decrement_pow10	; not done with this power yet

			; Add the power of 10 back in once
			clc
			pushf
			mov	ebx, edi	; point ebx to int argument
			mov	eax, LOCAL_BYTES
			mov	LOCAL_J, eax		; j = LOCAL_BYTES
			printf_int_loop_bytes_2:	; for j=LOCAL_BYTES; j>0; j--
				mov	al, BYTE [ebx]
				popf
				adc	al, BYTE [ecx]
				pushf
				mov	BYTE [ebx], al
				inc	ecx
				inc	ebx
				dec	DWORD LOCAL_J	; j--
				jnz	printf_int_loop_bytes_2

			; Point ecx to the next lower power of 10
			add	ecx, MAX_BYTES
			sub	ecx, LOCAL_BYTES

			popf


			; print the digit?
			cmp	BYTE LOCAL_PRTG, 1	; printing == 1
			je	printf_int_output

			cmp	BYTE LOCAL_OUTC, '0'	; outchar == '0'
			je	printf_int_skip		; Skip leadings 0s

			mov	BYTE LOCAL_PRTG, 1	; Set printing = 1


			printf_int_output:
			push	ecx		; save ecx (pointer into the powers of 10)

			mov	eax, 4		; 4 = SYS_WRITE
			mov	ebx, 1		; 1 = stdout
			lea	ecx, LOCAL_OUTC	; outchar
			mov	edx, 1		; length = 1
			int	0x80

			pop	ecx		; restore ecx


			printf_int_skip:
			dec	DWORD LOCAL_I	; i--
			jnz	printf_int_loop_digits


		; Move edi to next argument.  Need to round LOCAL_BYTES up to multiple of 4 (DWORD boundary)
		mov	eax, LOCAL_BYTES
		add	eax, 3
		shr	eax, 2
		shl	eax, 2
		add	edi, eax

		; If we haven't printed anything, the input int was a 0
		cmp	BYTE LOCAL_PRTG, 0	; printing == 0
		jne	printf_toploop

		mov	eax, 4		; 4 = SYS_WRITE
		mov	ebx, 1		; 1 = stdout
		lea	ecx, LOCAL_OUTC	; outchar
		mov	edx, 1		; length = 1
		int	0x80

		jmp	printf_toploop


	printf_endloop:
	popa
	popf
	leave
	ret
