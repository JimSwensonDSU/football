;%define CLEARRIGHT	0x1b, "[K"

;
; Defines used throughout
;
%define	SYS_read	0x03
%define SYS_write	0x04
%define	SYS_open	0x05
%define	SYS_close	0x06

%define STDIN		0
%define STDOUT		1

%define	O_RDONLY	0
%define O_NONBLOCK	2048

%define	ECHO		8
%define ICANNON		2
%define	TCSAFLUSH	2

%define F_GETFL		3
%define F_SETFL		4

%define TICK		100000	; 1/10th of a second
%define TIMER_COUNTER	10	; Number of ticks between decrementing timeremaining

%define NUM_DEFENSE	5


segment .data

segment .bss
	save_termios	resb	60
	save_c_lflag	resb	4

	; game state
	gameover	resd	1
	down		resd	1
	fieldpos	resd	1
	yardstogo	resd	1
	homescore	resd	1
	visitorscore	resd	1
	quarter		resd	1
	timeremaining	resd	1
	direction	resd	1	; 1 = right, -1 = left
	possession	resd	1	; 1 = home, -1 = visitor

	hitenter	resd	1	; 1 = yes, 0 = no
	playrunning	resd	1	; 1 = yes, 0 = no
	tackle		resd	1	; 1 = yes, 0 = no
	lineofscrimmage	resd	1

	; location of players
	offense		resd	2		; X, Y
	defense		resd	2*NUM_DEFENSE	; N sets of X,Y

	; counters
	timer_counter	resd	1

segment .text
	global  asm_main
	extern	fcntl
	extern	getchar
	extern	usleep
	extern  tcsetattr, tcgetattr

asm_main:
	push	ebp
	mov		ebp, esp
	; ********** CODE STARTS HERE **********

	call	terminal_raw_mode
	call	newgame
	call	terminal_restore_mode

	; *********** CODE ENDS HERE ***********
	mov		eax, 0
	mov		esp, ebp
	pop		ebp
	ret

;------------------------------------------------------------------------------
;
; newgame()
;
newgame:
	enter	0, 0
	call	initgame
	call	clearscreen
	call	drawboard

	eventloop:
		call	drawboard

		push	TICK
		call	usleep
		add	esp, 4

		call	process_input

		cmp	DWORD [gameover], 1
		je	end_game

		call	decrement_timeremaining

		call	update_game_state

		jmp	eventloop


	end_game:

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void initgame()
;
; Initialize all settings for a new game.
;
initgame:
	enter	0, 0

	mov	DWORD [gameover], 0
	mov	DWORD [down], 1
	mov	DWORD [fieldpos], 20
	mov	DWORD [yardstogo], 10
	mov	DWORD [homescore], 0
	mov	DWORD [visitorscore], 0
	mov	DWORD [quarter], 1
	mov	DWORD [timeremaining], 150

	mov	DWORD [hitenter], 0
	mov	DWORD [playrunning], 0
	mov	DWORD [tackle], 0
	mov	DWORD [lineofscrimmage], 20

	mov	DWORD [direction], 1
	mov	DWORD [possession], 1

	mov	DWORD [timer_counter], TIMER_COUNTER

	call	init_player_positions

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void init_player_positions()
;
init_player_positions:
	enter	0, 0

	cmp	DWORD [direction], 1
	jne	right_to_left

	left_to_right:
	mov	DWORD [offense], 0
	mov	DWORD [offense + 4], 1

	;mov	DWORD [defense],      3
	mov	DWORD [defense],      1
	mov	DWORD [defense + 4],  0

	mov	DWORD [defense + 8],  3
	mov	DWORD [defense + 12], 1

	mov	DWORD [defense + 16], 3
	mov	DWORD [defense + 20], 2

	mov	DWORD [defense + 24], 5
	mov	DWORD [defense + 28], 1

	mov	DWORD [defense + 32], 8
	mov	DWORD [defense + 36], 1

	jmp	leave_init_player_positions


	right_to_left:
	mov	DWORD [offense], 9
	mov	DWORD [offense + 4], 1

	;mov	DWORD [defense],      6
	mov	DWORD [defense],      8
	mov	DWORD [defense + 4],  0

	mov	DWORD [defense + 8],  6
	mov	DWORD [defense + 12], 1

	mov	DWORD [defense + 16], 6
	mov	DWORD [defense + 20], 2

	mov	DWORD [defense + 24], 4
	mov	DWORD [defense + 28], 1

	mov	DWORD [defense + 32], 1
	mov	DWORD [defense + 36], 1


	leave_init_player_positions:

	leave
	ret

;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void decrement_timeremaining()
;
; Decrement the game clock
;
decrement_timeremaining:
	enter	0, 0

	cmp	DWORD [playrunning], 0
	je	leave_decrement_timeremaining

	dec	DWORD [timer_counter]
	jnz	leave_decrement_timeremaining
	mov	DWORD [timer_counter], TIMER_COUNTER

	cmp	DWORD [timeremaining], 0
	je	leave_decrement_timeremaining
	dec	DWORD [timeremaining]

	leave_decrement_timeremaining:
	leave
	ret
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void update_game_state()
;
update_game_state:
	enter	0, 0

	push	eax

	;
	; check for a touchdown
	;
	; For a touchdown:
	; - display the "touchdown" splash screen
	; - increment offense score by 7
	; - pause here until they hit enter
	; - switch home/visitor possession
	; - switch direction
	; - set field state
	;      fieldpos = 20
	;      down = 1
	;      yards to go = 10
	;      offense

	state_touchdown:
	cmp	DWORD [fieldpos], 100
	jl	state_tackle
	mov	DWORD [hitenter], 1
	cmp	DWORD [possession], 1
	jne	touchdown_visitor
	touchdown_home:
	add	DWORD [homescore], 7
	jmp	touchdown_next;
	touchdown_visitor:
	add	DWORD [visitorscore], 7
	touchdown_next:
	call	drawboard
	call	drawtouchdown
	state_touchdown_loop:
	call	process_input
	cmp	DWORD [hitenter], 1
	je	state_touchdown_loop

	mov	DWORD [fieldpos], 20
	mov	DWORD [down], 1
	mov	DWORD [yardstogo], 10

	mov	eax, DWORD [possession]
	neg	eax
	mov	DWORD [possession], eax

	mov	eax, DWORD [direction]	; direction
	neg	eax
	mov	DWORD [direction], eax

	call	init_player_positions

	jmp	leave_update_game_state


	;
	; check for a tackle
	;
	; For a tackle:
	; - display the "tackle" splash screen
	; - update line of scrimmage, yards to go, and down
	; - if yards to go <= 0, update down to 1 and yards to go to 10
	; - if down >= 5
	;      switch home/visitor
	;      switch direction
	;      fieldpos = 100 - fieldpos
	;      down = 1
	;      yards to go = 10
	state_tackle:
	cmp	DWORD [tackle], 1
	jne	leave_update_game_state
	mov	DWORD [hitenter], 1
	call	drawboard
	call	drawtackle
	state_tackle_loop:
	call	process_input
	cmp	DWORD [hitenter], 1
	je	state_tackle_loop
	mov	DWORD [tackle], 0
	jmp	leave_update_game_state

	leave_update_game_state:
	pop	eax

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void process_input()
;
; Process input from user.
;
process_input:
	enter	0, 0

	call	get_key
	cmp	al, -1
	je	leave_process_input



	cmp	DWORD [hitenter], 1
	je	check_enter

	;
	; w, a, s, d - offense player movement
	;
	check_w:
	cmp	al, 'w'
	jne	check_s
	push	-1
	push	0
	jmp	call_move_offense

	check_s:
	cmp	al, 's'
	jne	check_d
	push	1
	push	0
	jmp	call_move_offense

	check_d:
	cmp	al, 'd'
	jne	check_a
	push	0
	push	1
	jmp	call_move_offense

	check_a:
	cmp	al, 'a'
	jne	check_enter
	push	0
	push	-1
	jmp	call_move_offense

	call_move_offense:
	mov	DWORD [playrunning], 1
	call	move_offense
	add	esp, 8
	jmp	leave_process_input


	check_enter:
	cmp	al, 10
	jne	check_q
	mov	DWORD [hitenter], 0
	jmp	leave_process_input


	check_q:
	cmp	al, 'q'
	jne	leave_process_input
	mov	DWORD [gameover], 1
	jmp	leave_process_input



	leave_process_input:
	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void move_offense(int deltaX, int deltaY)
;
; Move the offense by deltaX, deltaY.  Will check for a tackle.
;
move_offense:
	enter	12, 0

	; [ebp + 12] : deltaY
	; [ebp + 8]  : deltaX
	;
	; [ebp - 4]   : save offense X
	; [ebp - 8]   : save offense Y
	; [ebp - 12]  : save fieldpos

	push	eax
	push	ebx
	push	ecx
	push	edx


	; Save current offense and fieldpos
	mov	eax, DWORD [offense]		; offense X
	mov	DWORD [ebp - 4], eax

	mov	eax, DWORD [offense + 4]	; offense Y
	mov	DWORD [ebp - 8], eax

	mov	eax, DWORD [fieldpos]		; fieldpos
	mov	DWORD [ebp - 12], eax


	mov	ebx, 10

	update_offense_pos_x:
	mov	eax, DWORD [direction]
	mul	DWORD [ebp + 8]
	add	eax, DWORD [fieldpos]

	cmp	eax, DWORD [lineofscrimmage]
	jl	update_offense_pos_y	; Can't move before line of scrimmage

	cmp	eax, 100
	jg	update_offense_pos_y	; Can't move past goal line

	mov	DWORD [fieldpos], eax

	mov	eax, 1
	mul	DWORD [ebp + 8]
	add	eax, DWORD [offense]
	add	eax, ebx
	xor	edx, edx
	div	ebx
	mov	DWORD [offense], edx


	update_offense_pos_y:
	mov	eax, DWORD [ebp + 12]
	add	eax, DWORD [offense + 4]
	cmp	eax, 0
	jl	leave_move_offense
	cmp	eax, 2
	jg	leave_move_offense
	mov	DWORD [offense + 4], eax


	leave_move_offense:


	; Check if offense on same spot as a defender.  If so, it's a tackle, and
	; we should restore the saved values for offense and fieldpos.

	mov	DWORD [tackle], 0

	mov	eax, DWORD [offense]		; offense X
	mov	ebx, DWORD [offense + 4]	; offense Y
	mov	ecx, NUM_DEFENSE
	check_tackle:
	cmp	eax, DWORD [defense + 8*ecx - 8]	; defense X
	jne	next_check_tackle
	cmp	ebx, DWORD [defense + 8*ecx - 4]	; defense Y
	jne	next_check_tackle
	mov	DWORD [tackle], 1
	next_check_tackle:
	loop	check_tackle


	cmp	DWORD [tackle], 1
	jne	move_offense_done
	mov	DWORD [playrunning], 0
	mov	DWORD [hitenter], 1

	; restore the saves values for offense and fieldpos

	mov	eax, DWORD [ebp - 4]		; offense X
	mov	DWORD [offense], eax

	mov	eax, DWORD [ebp - 8]		; offense Y
	mov	DWORD [offense + 4], eax

	mov	eax, DWORD [ebp - 12]		; fieldpos
	mov	DWORD [fieldpos], eax


	move_offense_done:

	pop	edx
	pop	ecx
	pop	ebx
	pop	eax

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void drawtouchdown()
;

segment .data

touchdownstr	db	"   ---------------------------------------------    ", 10
		db	"   |||   |   |   |   |   |   |   |   |   |   |||    ", 10
		db	"\  ||-   -                               -   -||  / ", 10
		db	" | |||   |       !!! TOUCHDOWN !!!!      |   ||| |  ", 10
		db	"/  ||-   -                               -   -||  \ ", 10
		db	"   |||   |   |   |   |   |   |   |   |   |   |||    ", 10
		db	"   ---------------------------------------------    ", 10
drawtouchdown:
	enter	0, 0
	call	homecursor
	push	touchdownstr
	call	printf
	add	esp, 4
	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void drawtackle()
;

segment .data

tacklestr	db	"   ---------------------------------------------    ", 10
		db	"   |||   |   |   |   |   |   |   |   |   |   |||    ", 10
		db	"\  ||-   -                               -   -||  / ", 10
		db	" | |||   |            TACKLED            |   ||| |  ", 10
		db	"/  ||-   -                               -   -||  \ ", 10
		db	"   |||   |   |   |   |   |   |   |   |   |   |||    ", 10
		db	"   ---------------------------------------------    ", 10
drawtackle:
	enter	0, 0
	call	homecursor
	push	tacklestr
	call	printf
	add	esp, 4
	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void drawboard()
;
; Draw the playing board


segment .data

boardstr	db	"   ---------------------------------------------    ", 10
		db	"   |||   |   |   |   |   |   |   |   |   |   |||    ", 10
		db	"\  ||-   -   -   -   -   -   -   -   -   -   -||  / ", 10
		db	" | |||   |   |   |   |   |   |   |   |   |   ||| |  ", 10
		db	"/  ||-   -   -   -   -   -   -   -   -   -   -||  \ ", 10
		db	"   |||   |   |   |   |   |   |   |   |   |   |||    ", 10
		db	"   ---------------------------------------------    ", 10
		db	"                                                    ", 10
		db	"   ---------------------------------------------    ", 10
		db	"   | DOWN: %d | FIELDPOS: %d%d%c | YARDS TO GO: %d%d |    ", 10
		db	"   ---------------------------------------------    ", 10
		db	"   | HOME: %d%d | VISITOR: %d%d |                       ", 10
		db	"   -------------------------------------            ", 10
		db	"   | QUARTER: %d | TIME REMAINING: %d%d.%d |            ", 10
		db	"   -------------------------------------            ", 10
		db	"                                                    ", 10
		db	" State Variables                                    ", 10
		db	" tackle: %d                                         ", 10
		db	" playrunning: %d                                    ", 10
		db	" hitenter: %d                                       ", 10
		db	0

drawboard:
	enter	4*(1+NUM_DEFENSE), 0

	; Local vars for saving the player offsets, so we can restore
	; those characters in the boardstr after printing.
	;
	; [ebp - 4]  : offense
	; [ebp - 8]  : defender 1
	; [ebp - 12] : defender 2
	; .
	; .
	; .

	push	eax
	push	ebx
	push	ecx
	push	edx


	; draw players into the boardstr
	lea	ebx, [ebp - 4]
	push	DWORD [offense + 4]		; offense Y
	push	DWORD [offense]			; offense X
	call	calc_player_offset
	add	esp, 8
	mov	[ebx], eax			; save offset to local var
	mov	BYTE [boardstr + eax], 'X'

	mov	ecx, NUM_DEFENSE
	draw_defense:
	sub	ebx, 4
	push	DWORD [defense + 8*ecx - 4]	; defender Y
	push	DWORD [defense + 8*ecx - 8]	; defender X
	call	calc_player_offset
	add	esp, 8
	mov	DWORD [ebx], eax			; save offset to local var
	mov	BYTE [boardstr + eax], 'O'
	loop	draw_defense



	call	homecursor

	mov	ebx, 10

	; some state info
	push	DWORD [hitenter]
	push	DWORD [playrunning]
	push	DWORD [tackle]

	; time remaining
	xor	edx, edx
	mov	eax, DWORD [timeremaining]
	div	ebx
	push	edx
	xor	edx, edx
	div	ebx
	push	edx
	push	eax

	; quarter
	push	DWORD [quarter]

	; visitor score
	xor	edx, edx
	mov	eax, DWORD [visitorscore]
	div	ebx
	push	edx
	push	eax

	; home score
	xor	edx, edx
	mov	eax, DWORD [homescore]
	div	ebx
	push	edx
	push	eax

	; yards to go
	xor	edx, edx
	mov	eax, DWORD [yardstogo]
	div	ebx
	push	edx
	push	eax

	; field position
	xor	edx, edx
	mov	eax, DWORD [fieldpos]
	cmp	eax, 50
	je	side_midfield
	jl	side_offense
	jg	side_defense

	side_midfield:
	push	' '
	jmp	pushfield

	side_offense:
	cmp	DWORD [direction], 0
	jl	side_offense_2
	side_offense_1:
	push	'<'
	jmp	pushfield
	side_offense_2:
	push	'>'
	jmp	pushfield

	side_defense:
	neg	eax
	add	eax, 100
	cmp	DWORD [direction], 0
	jl	side_defense_2
	side_defense_1:
	push	'>'
	jmp	pushfield
	side_defense_2:
	push	'<'
	jmp	pushfield

	pushfield:
	div	ebx
	push	edx
	push	eax

	; down
	push	DWORD [down]


	push	boardstr
	call	printf
	add	esp, 72



	; restore the boardstr
	mov	ebx, ebp
	mov	ecx, 1+NUM_DEFENSE
	restore_board:
	sub	ebx, 4
	mov	eax, DWORD [ebx]
	mov	BYTE [boardstr + eax], ' '
	loop	restore_board


	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; int calc_player_offset(int X, int Y)
;
; Calculate byte offset in boardstr for a player at position X,Y
;
calc_player_offset:
	enter	4, 0

	; [ebp + 12] : Y
	; [ebp + 8]  : X

	push	ebx
	push	edx

	; Offset to offense position is 60 + Y*106 + X*4
	mov	eax, DWORD [ebp + 12]
	mov	ebx, 106
	mul	ebx
	mov	DWORD [ebp - 4], eax

	mov	eax, DWORD [ebp + 8]
	mov	ebx, 4
	mul	ebx
	add	eax, DWORD [ebp - 4]
	add	eax, 60

	pop	edx
	pop	ebx

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void clearscreen()
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


;------------------------------------------------------------------------------
;
; void homecursor()
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
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; unsigned int random(unsigned int x)
;
; Returns: A random number between 0 and x-1

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
	mov	edx, O_RDONLY
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
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; char get_key()
;
; Reads STDIN for a single character input.
; Returns: read character on success.
;          otherwise, -1
;
get_key:
	enter	8, 0

	; [ebp - 4] : Save STDIN flags
	; [ebp - 8] : Read char

	; single int used to hold flags
	; single character (aligned to 4 bytes) return
	sub		esp, 8

	; get current stdin flags
	; flags = fcntl(stdin, F_GETFL, 0)
	push	0
	push	F_GETFL
	push	STDIN
	call	fcntl
	add	esp, 12

	mov	DWORD [ebp-4], eax	; save flags

	; set non-blocking mode on stdin
	; fcntl(stdin, F_SETFL, flags | O_NONBLOCK)
	push	DWORD [ebp - 4]
	or	DWORD [esp], O_NONBLOCK
	push	F_SETFL
	push	STDIN
	call	fcntl
	add	esp, 12

	call	getchar
	mov	DWORD [ebp - 8], eax

	; restore flags
	; fcntl(stdin, F_SETFL, flags)
	push	DWORD [ebp - 4]
	push	F_SETFL
	push	STDIN
	call	fcntl
	add	esp, 12

	mov	eax, DWORD [ebp-8]

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void terminal_raw_mode()
;
; Put terminal into raw mode - disable ECHO and ICANON
;
terminal_raw_mode:
	enter	0, 0

	push	eax

	; get the current stdin struct termios
	; tcgetattr(STDIN_FILENO, &orig_termios);
	push	save_termios	; address of struct termios
	push	STDIN
	call	tcgetattr
	add	esp, 8

	; save the c_lflag element of struct termios for later restoration
	mov	eax, DWORD [save_termios + 12]
	mov	DWORD [save_c_lflag], eax


	; disable ECHO and ICANON
	; tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_termios);
	mov	eax, 0xffffffff
	xor	eax, ECHO
	xor	eax, ICANNON
	and	DWORD [save_termios + 12], eax
	push	save_termios	; address of struct termios
	push	TCSAFLUSH
	push	STDIN
	call	tcsetattr
	add	esp, 12

	pop	eax

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void terminal_restore_mode()
;
; Restore original terminal settings.
;
terminal_restore_mode:
	enter	0, 0

	push	eax

	; restore the c_lflag element of struct termios
	mov	eax, DWORD [save_c_lflag]
	mov	DWORD [save_termios + 12], eax

	; restore term settings to original
	; tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_termios);
	push	save_termios	; address of struct termios
	push	TCSAFLUSH
	push	STDIN
	call	tcsetattr
	add	esp, 12

	pop	eax

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void printf(char *format, ...)
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

	enter	16, 0
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
		mov	eax, SYS_write	; syscall
		mov	ebx, STDOUT	; fd
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

		mov	eax, SYS_write
		mov	ebx, STDOUT
		mov	ecx, [edi]	; point to string to print
		int	0x80

		add	edi, 4		; Move edi to next argument
		jmp	printf_toploop


	; print character at esi
	printf_char_literal:
		mov	eax, SYS_write	; syscall
		mov	ebx, STDOUT	; fd
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
		mov	eax, SYS_write	; syscall
		mov	ebx, STDOUT	; fd
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

			mov	eax, SYS_write	; syscall
			mov	ebx, STDOUT	; fd
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

		mov	eax, SYS_write	; syscall
		mov	ebx, STDOUT	; fd
		lea	ecx, LOCAL_OUTC	; outchar
		mov	edx, 1		; length = 1
		int	0x80

		jmp	printf_toploop


	printf_endloop:
	popa
	popf
	leave
	ret
;
;------------------------------------------------------------------------------
