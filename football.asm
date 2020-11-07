;
; football
;
; Jim Swenson
; Jim.Swenson@trojans.dsu.edu
;
; An implementation of the handheld Mattel Electronic Football game.
;
; https://www.handheldmuseum.com/Mattel/FB.htm
;
;
; This implementation is based on the remake.
;
;   - Field length and width are set via the boardstr definition.
;     See the comments with boardstr for details.
;     Note that MAX_FIELD_WIDTH, MAX_FIELD_LENGTH, MAX_DEFENSE
;     set some hard upper limits.  These may be adjusted to
;     support larger values.
;
;     Original game: length 9, width 3.
;     Remake game: length 10, width 3.
;
;   - Supports running backwards, but not behind the line
;     of scrimmage.  Original supported only forward.
;
;   - Supports kick (punt or field goal)
;
;   - Instead of sound, a splash screen is used to communicate
;     game events.
;
;   - No "ST"/"SC" keys needed as in remake/original.  Instead, all
;     pertinent game stats are always displayed.  Enter is used
;     to enable the next play.
;
;   - As in the original, initiating any movement will start
;     the play.
;
;   - A debug screen is available to show various game variables.
;
; This code also contains a local implementation of printf.
; See the comments in printf for details and which format
; strings are supported.
;
; NOTE:
; - Linux system calls are used for file open, close,
;   read, and write operations.
; - libc functions are used for:
;     sleeps: usleep
;     STDIN settings: fcntl
;     terminal settings: tcsetattr, tcgetattr
;
;
; Ideas for game improvements:
; - implement random fumbles on a tackle
; - color
; - sound/beep
;

;
; Values for system/library calls
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
%define	ICANON		2
%define	ISIG		1
%define	TCSAFLUSH	2

%define F_GETFL		3
%define F_SETFL		4

;
; Game constants
;
%define	OFFENSE_CHAR	'O'	; character for offensive player
%define	DEFENSE_CHAR	'X'	; character for defensive players

; See boardstr for field layout and player positioning
%define MAX_FIELD_WIDTH		9	; max number of player positions across the width of the field
%define MAX_FIELD_LENGTH	15	; max number of player positions along the length of the field
%define	MAX_DEFENSE		11	; max number of defenders

%define	TOUCHDOWN_PTS	7	; points for a touchdown
%define	FIELDGOAL_PTS	3	; points for a field goal
%define	FIELDPOS	20	; starting field position
%define	FIELDGOAL_MIN	70	; min fieldpos to attempt a field goal
%define	FIELDGOAL_PCT	75	; percent success rate for hitting a field goal
%define	MIN_PUNT	20	; minimum punt distance
%define	MAX_PUNT	60	; maximum punt distance
%define	GAME_TIME	150	; length of a quarter

; input keys
%define KEY_UP		'w'
%define KEY_DOWN	's'
%define KEY_LEFT	'a'
%define KEY_RIGHT	'd'
%define	KEY_KICK	'k'
%define	KEY_QUIT	'Q'	; uppercase to avoid accidential hits
%define	KEY_ENTER	0x0a
%define	KEY_DEBUG	'v'	; toggle debug mode
%define KEY_CTRLC	0x03

%define TICK		100000	; 1/10th of a second
%define TIMER_COUNTER	10	; Number of ticks between decrementing timeremaining
%define DEFENSE_COUNTER	16	; Number of ticks between moving defense


segment .data

	msg_touchdown		db	"!!! TOUCHDOWN !!!!", 0
	msg_fieldgoalgood	db	"!!! FIELD GOAL !!!!", 0
	msg_fieldgoalmiss	db	"FIELD GOAL MISSED", 0
	msg_tackle		db	"TACKLED", 0
	msg_punt		db	"PUNTED", 0
	msg_gameover		db	"GAME OVER - Hit Enter or ", KEY_QUIT, 0
	msg_abort		db	"CAUGHT CTRL-C.  GAME OVER, MAN!", 0

	init_field_failure_fmt	db	"init_field() failed with return %d", 10, 0

segment .bss
	; save terminal/stdin settings
	save_termios		resb	60
	save_c_lflag		resb	4
	save_stdin_flags	resb	4

	; game state
	abort		resd	1
	hardquit	resd	1
	gameover	resd	1
	down		resd	1
	fieldpos	resd	1
	lineofscrimmage	resd	1
	yardstogo	resd	1
	homescore	resd	1
	visitorscore	resd	1
	quarter		resd	1
	timeremaining	resd	1
	direction	resd	1	; 1 = right, -1 = left
	possession	resd	1	; 1 = home, -1 = visitor
	skilllevel	resd	1	; skill level, 0-5.  0 = easy, 5 = hard

	requireenter	resd	1	; 1 = yes, 0 = no
	playrunning	resd	1	; 1 = yes, 0 = no
	tackle		resd	1	; 1 = yes, 0 = no
	punt		resd	1	; 1 = yes, 0 = no
	fieldgoal	resd	1	; 1 = yes, 0 = no

	; location of players
	offense		resd	2		; X, Y
	defense		resd	2 * MAX_DEFENSE	; N sets of X,Y

	; Offset to each player field position
	playpos		resd	MAX_FIELD_LENGTH * MAX_FIELD_WIDTH
	playpos_num	resd	1

	field_length	resd	1	; determined playfield field length
	field_width	resd	1	; determined playfield field width

	; starting positions for offense and defense
	offense_start	resd	2
	offense_num	resd	1
	defense_start	resd	2 * MAX_DEFENSE
	defense_num	resd	1

	; counters
	defense_counter	resd	1
	timer_counter	resd	1

	; debug_on - displays state variables
	debug_on		resd	1	; 1 = yes, 0 = no

segment .text
	global  main
	extern	usleep
	extern  fcntl, tcsetattr, tcgetattr

main:
	push	ebp
	mov		ebp, esp
	; ********** CODE STARTS HERE **********

	call	hidecursor
	call	terminal_raw_mode
	call	run_game
	call	terminal_restore_mode
	call	showcursor

	; *********** CODE ENDS HERE ***********
	mov		eax, 0
	mov		esp, ebp
	pop		ebp
	ret

;------------------------------------------------------------------------------
;
; void run_game()
;
run_game:
	enter	0, 0

	push	eax

	call	init_field
	cmp	eax, 0
	je	continue_init

	push	eax
	push	init_field_failure_fmt
	call	printf
	add	esp, 8
	jmp	run_game_done


	continue_init:
		call	init_game
		call	clearscreen

	gameloop:
		call	drawboard

		cmp	DWORD [abort], 1
		je	run_game_abort

		cmp	DWORD [hardquit], 1
		je	run_game_done

		cmp	DWORD [gameover], 1
		je	end_game

		push	TICK
		call	usleep
		add	esp, 4

		call	process_input

		call	move_defense

		call	decrement_timeremaining

		call	update_game_state

		jmp	gameloop


	end_game:
		push	msg_gameover
		call	drawsplash
		add	esp, 4
		call	wait_for_enter

		cmp	DWORD [hardquit], 1
		je	run_game_done

		; initialize a new game.  Carry over these settings:
		;
		; - skilllevel
		; - debug_on

		push	DWORD [skilllevel]
		push	DWORD [debug_on]
		call	init_game
		pop	eax
		mov	DWORD [debug_on], eax
		pop	eax
		mov	DWORD [skilllevel], eax
		jmp	gameloop


	run_game_abort:
		push	msg_abort
		call	drawsplash
		add	esp, 4


	run_game_done:

	pop	eax

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void init_game()
;
; Initialize all settings for a new game.
;
init_game:
	enter	0, 0

	mov	DWORD [abort], 0
	mov	DWORD [hardquit], 0
	mov	DWORD [gameover], 0
	mov	DWORD [down], 1
	mov	DWORD [fieldpos], FIELDPOS
	mov	DWORD [lineofscrimmage], FIELDPOS
	mov	DWORD [yardstogo], 10
	mov	DWORD [homescore], 0
	mov	DWORD [visitorscore], 0
	mov	DWORD [quarter], 1
	mov	DWORD [timeremaining], GAME_TIME

	mov	DWORD [requireenter], 0
	mov	DWORD [playrunning], 0
	mov	DWORD [tackle], 0
	mov	DWORD [punt], 0
	mov	DWORD [fieldgoal], 0

	mov	DWORD [direction], 1
	mov	DWORD [possession], 1

	mov	DWORD [skilllevel], 0

	mov	DWORD [timer_counter], TIMER_COUNTER
	call	reset_defense_counter

	mov	DWORD [debug_on], 0

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

	push	eax
	push	ecx


	left_to_right:
	mov	eax, DWORD [offense_start]	; offense_startX
	mov	DWORD [offense], eax		; offenseX
	mov	eax, DWORD [offense_start + 4]	; offense_startY
	mov	DWORD [offense + 4], eax	; offenseY

	mov	ecx, DWORD [defense_num]
	init_defense:
		mov	eax, DWORD [defense_start + 8*ecx - 8]	; defense_startX
		mov	DWORD [defense + 8*ecx - 8], eax	; defenseX
		mov	eax, DWORD [defense_start + 8*ecx - 4]	; defense_startY
		mov	DWORD [defense + 8*ecx - 4], eax	; defenseY
		loop	init_defense

	cmp	DWORD [direction], 1
	je	leave_init_player_positions


	; Flip all the X positions for right to left
	right_to_left:

	; Offense
	mov	eax, DWORD [offense]	; offenseX
	neg	eax
	add	eax, DWORD [field_length]
	dec	eax
	mov	DWORD [offense], eax

	; Defense
	mov	ecx, DWORD [defense_num]
	flip_defense:
		mov	eax, DWORD [defense + 8*ecx - 8]	; defenseX
		neg	eax
		add	eax, DWORD [field_length]
		dec	eax
		mov	DWORD [defense + 8*ecx - 8], eax
		loop	flip_defense


	leave_init_player_positions:

	pop	ecx
	pop	eax

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

	cmp	DWORD [timeremaining], 0	; don't decrement below 0
	je	leave_decrement_timeremaining
	dec	DWORD [timeremaining]

	leave_decrement_timeremaining:
	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void reset_defense_counter()
;
; Resets the defense counter, taking skilllevel into account
;
reset_defense_counter:
	enter	0, 0

	push	eax

	mov	eax, DEFENSE_COUNTER
	sub	eax, DWORD [skilllevel]
	sub	eax, DWORD [skilllevel]
	sub	eax, DWORD [skilllevel]
	mov	DWORD [defense_counter], eax

	pop	eax

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void update_game_state()
;
; Checks for field goal, punt, touchdown, and tackle.
;
update_game_state:
	enter	0, 0

	push	eax


	;
	; check for a field goal
	;
	; - attempt the field goal
	; - if good, update score
	; - draw the board, to reflect updated score
	; - display the good/miss splash screen
	; - pause until user hits enter
	; - update game state
	;
	state_fieldgoal:
		cmp	DWORD [fieldgoal], 1
		jne	state_punt

		; Perform field goal attempt
		mov	DWORD [fieldgoal], 0
		call	do_fieldgoal	; eax = result of field goal

		cmp	eax, 0
		je	state_fieldgoal_miss

		; Field goal was good
		state_fieldgoal_good:
		push	FIELDGOAL_PTS
		call	score
		add	esp, 4
		call	drawboard
		push	msg_fieldgoalgood
		jmp	state_fieldgoal_splash

		; Field goal missed
		state_fieldgoal_miss:
		push	msg_fieldgoalmiss
		jmp	state_fieldgoal_splash

		state_fieldgoal_splash:
		call	drawsplash
		add	esp, 4

		; Wait until user hits enter
		call	wait_for_enter

		;
		; Update game state
		;
		; good - other team starts at FIELDPOS
		; miss - other team starts at fieldpos
		;
		mov	DWORD [fieldpos], FIELDPOS
		mov	DWORD [lineofscrimmage], FIELDPOS
		mov	DWORD [down], 1
		mov	DWORD [yardstogo], 10
		call	switch_team
		call	init_player_positions

		; good
		cmp	eax, 1
		jmp	state_end_of_quarter

		; miss
		mov	eax, 100
		sub	eax, DWORD [fieldpos]
		mov	DWORD [fieldpos], eax
		mov	DWORD [lineofscrimmage], eax

		jmp	state_end_of_quarter


	;
	; check for a punt
	;
	; - perform the punt
	; - update game state
	; - draw the board, to reflect all updates
	; - display the punt splash screen
	; - pause until user hits enter
	;
	state_punt:
		cmp	DWORD [punt], 1
		jne	state_touchdown

		; Perform punt
		mov	DWORD [punt], 0
		call	do_punt		; eax = new fieldpos

		; update game state
		mov	DWORD [fieldpos], eax
		mov	DWORD [lineofscrimmage], eax
		mov	DWORD [down], 1
		mov	DWORD [yardstogo], 10
		call	switch_team
		call	init_player_positions

		; draw the board
		call	drawboard

		; show punt splash screen
		push	msg_punt
		call	drawsplash
		add	esp, 4

		; Wait until user hits enter
		call	wait_for_enter

		jmp	state_end_of_quarter


	;
	; check for a touchdown
	;
	; - display the "touchdown" splash screen
	; - increment offense score by 7
	; - pause here until they hit enter
	; - switch home/visitor possession
	; - switch direction
	; - set field state
	;      fieldpos = FIELDPOS
	;      lineofscrimmage = FIELDPOS
	;      down = 1
	;      yards to go = 10

	state_touchdown:
		cmp	DWORD [fieldpos], 100
		jl	state_tackle

		; It's a touchdown
		mov	DWORD [playrunning], 0

		; Increment score
		push	TOUCHDOWN_PTS
		call	score
		add	esp, 4

		call	drawboard
		push	msg_touchdown
		call	drawsplash
		add	esp, 4

		; Wait until user hits enter
		call	wait_for_enter

		; Switch to other team
		mov	DWORD [fieldpos], FIELDPOS
		mov	DWORD [lineofscrimmage], FIELDPOS
		mov	DWORD [down], 1
		mov	DWORD [yardstogo], 10

		call	switch_team

		call	init_player_positions

		jmp	state_end_of_quarter


	;
	; check for a tackle
	;
	; - display the "tackle" splash screen
	; - update line of scrimmage, yards to go, and down
	; - if yards to go <= 0, update down to 1 and yards to go to 10, otherwise down++
	; - if down >= 5
	;      switch home/visitor
	;      switch direction
	;      fieldpos = 100 - fieldpos
	;      down = 1
	;      yards to go = 10

	state_tackle:
		cmp	DWORD [tackle], 1
		jne	state_something_else

		; It's a tackle
		call	drawboard

		push	msg_tackle
		call	drawsplash
		add	esp, 4

		; Wait until user hits enter
		call	wait_for_enter

		; update field position
		mov	DWORD [tackle], 0
		mov	eax, DWORD [fieldpos]
		sub	eax, DWORD [lineofscrimmage]	; eax = gain
		sub	DWORD [yardstogo], eax

		; first down?
		cmp	DWORD [yardstogo], 0
		jle	first_down

		inc	DWORD [down]

		; turnover?
		cmp	DWORD [down], 4
		jg	turnover

		; not a turnover
		mov	eax, DWORD [fieldpos]
		mov	DWORD [lineofscrimmage], eax
		call	init_player_positions
		jmp	state_end_of_quarter
	

		; They made a first down
		first_down:
			mov	eax, DWORD [fieldpos]
			mov	DWORD [lineofscrimmage], eax
			mov	DWORD [down], 1
			mov	DWORD [yardstogo], 10
			call	init_player_positions
			jmp	state_end_of_quarter

		; Turnover
		turnover:
			call	switch_team

			mov	eax, 100
			sub	eax, DWORD [fieldpos]
			mov	DWORD [fieldpos], eax
			mov	DWORD [lineofscrimmage], eax

			mov	DWORD [down], 1
			mov	DWORD [yardstogo], 10
			call	init_player_positions
			jmp	state_end_of_quarter
	

		; Placeholder for additional functionality ...
		state_something_else:
			jmp	state_end_of_quarter



	; Check if quarter is over if a play is not running
	state_end_of_quarter:

		cmp	DWORD [playrunning], 1
		je	leave_update_game_state

		cmp	DWORD [timeremaining], 0
		jg	leave_update_game_state


		; Done with quarter
		inc	DWORD [quarter]

		cmp	DWORD [quarter], 4
		jg	state_game_over

		cmp	DWORD [quarter], 3
		je	state_second_half

		; Moving to 2nd or 4th quarter
		;   - switch direction
		;   - possession, fieldpos, lineofscrimmage, down, yardstogo remain same
		;   - reset timeremaining
		state_second_or_forth_quarter:
			mov	eax, DWORD [direction]
			neg	eax
			mov	DWORD [direction], eax
			mov	DWORD [timeremaining], GAME_TIME
			mov	DWORD [timer_counter], TIMER_COUNTER
			call	reset_defense_counter
			call	init_player_positions
			jmp	leave_update_game_state

		; Moving to 3rd quarter
		;   - visitor possession (possession = -1)
		;   - direction = 1
		;   - fieldpos = FIELDPOS
		;   - lineofscrimmage = FIELDPOS
		;   - down = 1
		;   - yardstogo = 10
		state_second_half:
			mov	DWORD [down], 1
			mov	DWORD [fieldpos], FIELDPOS
			mov	DWORD [yardstogo], 10
			mov	DWORD [timeremaining], GAME_TIME
			mov	DWORD [lineofscrimmage], FIELDPOS
			mov	DWORD [direction], 1
			mov	DWORD [possession], -1
			mov	DWORD [timer_counter], TIMER_COUNTER
			call	reset_defense_counter
			call	init_player_positions
			jmp	leave_update_game_state

		state_game_over:
			mov	DWORD [gameover], 1
			mov	DWORD [quarter], 4
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
segment .data

	; Player movement table
	;
	; Rows of the form:
	;
	;    key, deltaX, deltaY
	;
	;    key - key to press
	; deltaX - change to offenseX
	; deltaY - change to offenseY
	;
	; Using DWORD for each of arithmetic.
	;
	move_table	dd	KEY_UP,		0,	-1
			dd	KEY_DOWN,	0,	1
			dd	KEY_DOWN,	0,	1
			dd	KEY_RIGHT,	1,	0
			dd	KEY_LEFT,	-1,	0
			dd	0

process_input:
	enter	0, 0

	push	eax
	push	ebx

	; Check for input
	call	get_key
	cmp	al, -1
	je	leave_process_input


	;
	; Check for skill level change
	;
	check_skill_level:
		cmp	al, '0'
		jl	check_debug
		cmp	al, '5'
		jg	check_debug
		and	eax, 0x000000ff
		sub	al, '0'
		mov	DWORD [skilllevel], eax
		jmp	leave_process_input


	;
	; Checking for debug toggle
	;
	check_debug:
		cmp	al, KEY_DEBUG
		jne	check_quit
		mov	eax, 1
		sub	eax, DWORD [debug_on]
		mov	DWORD [debug_on], eax
		jmp	leave_process_input


	;
	; Checking for quit
	;
	check_quit:
		cmp	al, KEY_QUIT
		jne	check_ctrlc
		mov	DWORD [gameover], 1
		mov	DWORD [hardquit], 1
		mov	DWORD [requireenter], 0
		jmp	leave_process_input


	;
	; Checking for ctrl-c
	;
	check_ctrlc:
		cmp	al, KEY_CTRLC
		jne	check_enter
		mov	DWORD [abort], 1
		mov	DWORD [gameover], 1
		mov	DWORD [hardquit], 1
		mov	DWORD [requireenter], 0
		jmp	leave_process_input


	;
	; Checking for Enter
	;
	check_enter:
		cmp	DWORD [requireenter], 1
		jne	check_movement

		cmp	al, KEY_ENTER
		jne	leave_process_input
		mov	DWORD [requireenter], 0
		jmp	leave_process_input


	;
	; Checking for offense movement
	;
	check_movement:
	lea	ebx, [move_table - 12]
	movement_loop:
		add	ebx, 12
		cmp	DWORD [ebx], 0	; end of table
		je	movement_loop_end

		cmp	BYTE [ebx], al
		jne	movement_loop

		; found the key
		mov	DWORD [playrunning], 1

		push	DWORD [ebx + 8]	; deltaY
		push	DWORD [ebx + 4]	; deltaX
		call	move_offense
		add	esp, 8
		jmp	leave_process_input
	movement_loop_end:



	; Check for a kick (punt or fieldgoal)
	;
	; - To allow, must be 4th down and no play running.
	; - if fieldpos >= FIELDGOAL_MIN, try a fieldgoal, otherwise a punt
	;
	check_KICK:
		cmp	al, KEY_KICK
		jne	leave_process_input

		; Must be 4th down
		cmp	DWORD [down], 4
		jne	leave_process_input

		; Cannot be a play running
		cmp	DWORD [playrunning], 0
		jne	leave_process_input

		; Are they within field goal range?
		cmp	DWORD [fieldpos], FIELDGOAL_MIN
		jge	try_field_goal

		try_punt:
		mov	DWORD [punt], 1
		jmp	leave_process_input

		try_field_goal:
		mov	DWORD [fieldgoal], 1
		jmp	leave_process_input


	leave_process_input:

	pop	ebx
	pop	eax

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void wait_for_enter()
;
; Loop until user hits enter
;
wait_for_enter:
	enter	0, 0

	mov	DWORD [requireenter], 1

	wait_for_enter_loop:
		call	process_input
		cmp	DWORD [requireenter], 1
		je	wait_for_enter_loop

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; int do_fieldgoal()
;
; Attempt a field goal, with a FIELDGOAL_PCT success rate.
;
; Return: 1 - good, 0 - miss
;
do_fieldgoal:
	enter	0, 0

	; Check for field goal good/miss
	push	100
	call	random
	add	esp, 4
	cmp	eax, FIELDGOAL_PCT
	jge	fieldgoal_miss

	; Field goal was good
	fieldgoal_good:
		mov	eax, 1
		jmp	leave_do_fieldgoal

	; Field goal missed
	fieldgoal_miss:
		mov	eax, 1
		jmp	leave_do_fieldgoal

	leave_do_fieldgoal:

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; int do_punt()
;
; Generates a random int between MIN_PUNT and MAX_PUNT
; Returns new fieldpos, checking for a touchback.
;
; Return: new fieldpos
;
do_punt:
	enter	0, 0

	;
	; Random punt distance between MIN_PUNT and MAX_PUNT
	;
	mov	eax, MAX_PUNT
	sub	eax, MIN_PUNT
	inc	eax
	push	eax
	call	random		; eax : 0 .. (MAX_PUNT - MIN_PUNT)
	add	esp, 4
	add	eax, MIN_PUNT	; eax : MIN_PUNT .. MAX_PUNT

	;
	; Calculate new field position, checking for a touchback.
	;
	add	eax, DWORD [fieldpos]
	cmp	eax, 100
	jl	punt_calc_new_fieldpos

	; It was a touchback
	mov	eax, 100
	sub	eax, FIELDPOS

	punt_calc_new_fieldpos:
	neg	eax
	add	eax, 100

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void move_offense(int deltaX, int deltaY)
;
; Move the offense by deltaX, deltaY.
; Takes "direction" into account.
; Checks for a tackle.
;
move_offense:
	enter	12, 0

	; Arguments:
	; [ebp + 12] : deltaY
	; [ebp + 8]  : deltaX
	;
	; Local vars:
	; [ebp - 4]   : save offenseX
	; [ebp - 8]   : save offenseY
	; [ebp - 12]  : save fieldpos

	push	eax
	push	ebx
	push	ecx
	push	edx


	; Save current offense and fieldpos
	mov	eax, DWORD [offense]		; offens X
	mov	DWORD [ebp - 4], eax

	mov	eax, DWORD [offense + 4]	; offenseY
	mov	DWORD [ebp - 8], eax

	mov	eax, DWORD [fieldpos]		; fieldpos
	mov	DWORD [ebp - 12], eax


	; Calculate new field position based on direction and deltaX
	update_offense_pos_x:
		mov	eax, DWORD [direction]
		mul	DWORD [ebp + 8]		; deltaX
		add	eax, DWORD [fieldpos]	; eax = new field position

		; Don't allow move before line of scrimmage
		cmp	eax, DWORD [lineofscrimmage]
		jl	update_offense_pos_y

		; Don't allow move past the goal line
		cmp	eax, 100
		jg	update_offense_pos_y

		; X move is ok
		mov	DWORD [fieldpos], eax

		; Update the offenseX position as well
		mov	eax, DWORD [ebp + 8]	; eax = deltaX
		add	eax, DWORD [offense]	; eax = offenseX + deltaX
		mov	ebx, DWORD [field_length]
		add	eax, ebx		; eax = field_length + offenseX + deltaX
		; Get eax % field_length
		xor	edx, edx
		div	ebx
		mov	DWORD [offense], edx	; new offenseX position


	update_offense_pos_y:
		mov	eax, DWORD [ebp + 12]		; eax = deltaY
		add	eax, DWORD [offense + 4]	; eax = offenseY + deltaY

		; Can't move above field
		cmp	eax, 0
		jl	check_for_tackle

		; Can't move below field
		cmp	eax, DWORD [field_width]
		jge	check_for_tackle

		; Y move is ok
		mov	DWORD [offense + 4], eax	; new offenseY position


	;
	; Check if offense on same spot as a defender.  If so, it's a tackle, and
	; we should restore the saved values for offense and fieldpos.
	;
	check_for_tackle:

		mov	DWORD [tackle], 0

		mov	eax, DWORD [offense]		; offenseX
		mov	ebx, DWORD [offense + 4]	; offens Y
		mov	ecx, DWORD [defense_num]

		check_tackle:
			cmp	eax, DWORD [defense + 8*ecx - 8]	; defense X
			jne	next_check_tackle
			cmp	ebx, DWORD [defense + 8*ecx - 4]	; defense Y
			jne	next_check_tackle
			mov	DWORD [tackle], 1

			next_check_tackle:
			loop	check_tackle


		; Tacked?
		cmp	DWORD [tackle], 1
		jne	leave_move_offense

		; Offense player is tackled
		mov	DWORD [playrunning], 0

		; restore the saved values for offense and fieldpos
		mov	eax, DWORD [ebp - 4]		; offenseX
		mov	DWORD [offense], eax

		mov	eax, DWORD [ebp - 8]		; offenseY
		mov	DWORD [offense + 4], eax

		mov	eax, DWORD [ebp - 12]		; fieldpos
		mov	DWORD [fieldpos], eax


	leave_move_offense:

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
; void move_defense()
;
; Move defense players.
;
move_defense:
	enter	20, 0

	; Local vars:
	; [ebp - 4]   : defenseX
	; [ebp - 8]   : defenseY
	; [ebp - 12]  : defender to move
	; [ebp - 16]  : deltaX
	; [ebp - 20]  : deltaY

	push	eax
	push	ebx
	push	ecx
	push	edx

	; Must be a play running
	cmp	DWORD [playrunning], 0
	je	leave_move_defense

	; Counter for how often we'll move a defender
	dec	DWORD [defense_counter]
	jnz	leave_move_defense
	call	reset_defense_counter


	; Move defense
	;
	; - Pick one defender at random to move.
	; - Defenders want to move towards the offense.
	; - Will either move one space in X or Y position.


	; Randomly pick one defender
	push	DWORD [defense_num]
	call	random
	add	esp, 4
	mov	DWORD [ebp - 12], eax

	; save that defender's current position
	mov	ebx, DWORD [defense + 8*eax]
	mov	DWORD [ebp - 4], ebx		; defenseX
	mov	ebx, DWORD [defense + 8*eax + 4]
	mov	DWORD [ebp - 8], ebx		; defenseY


	; Calculate deltaX, deltaY to offense
	calc_deltaX:
		mov	eax, DWORD [offense]	; offenseX
		cmp	eax, DWORD [ebp - 4]	; defenseX
		je	equalX
		jg	greaterX
		mov	DWORD [ebp - 16], 1		; defender to right of offense
		jmp	calc_deltaY

		equalX:
			mov	DWORD [ebp - 16], 0	; defender even with offense
			jmp	calc_deltaY

		greaterX:
			mov	DWORD [ebp - 16], -1	; defender to left of offense

	calc_deltaY:
		mov	eax, DWORD [offense + 4]	; offenseY
		cmp	eax, DWORD [ebp - 8]		; defenseY
		je	equalY
		jg	greaterY
		mov	DWORD [ebp - 20], 1		; defender below offense
		jmp	pick_move

		equalY:
			mov	DWORD [ebp - 20], 0 	; defender even with offense
			jmp	pick_move

		greaterY:
			mov	DWORD [ebp - 20], -1	; defender above offense


	;
	; If only one of deltaX, deltaY is non-zero, use the non-zero.
	; Otherwise pick at random.
	;
	pick_move:
		cmp	DWORD [ebp - 16], 0	; deltaX
		je	moveY

		cmp	DWORD [ebp - 20], 0	; deltaY
		je	moveX

		; Pick at random between using deltaX or deltaY
		push	2
		call	random
		add	esp, 4
		cmp	eax, 0
		je	moveY
		jmp	moveX

	; Move defender in X direction
	moveX:
		mov	eax, DWORD [ebp - 4]	; defenseX
		sub	eax, DWORD [ebp - 16]	; deltaX
		mov	DWORD [ebp - 4], eax
		jmp	check_move

	; Move defender in Y direction
	moveY:
		mov	eax, DWORD [ebp - 8]	; defense Y
		sub	eax, DWORD [ebp - 20]	; deltaY
		mov	DWORD [ebp - 8], eax
		jmp	check_move


	; If defender would be on same location as offense, then it is a tackle.
	check_move:
		mov	eax, DWORD [offense]	; offenseX
		cmp	eax, DWORD [ebp - 4]	; defenseX
		jne	not_a_tackle

		mov	eax, DWORD [offense + 4]	; offenseY
		cmp	eax, DWORD [ebp - 8]		; defenseY
		jne	not_a_tackle


	; Tackle
	; We don't update the real defense position for this case.
	mov	DWORD [tackle], 1
	mov	DWORD [playrunning], 0
	jmp	leave_move_defense


	; Was not a tackle.
	; Make sure defender not trying to move on top of another defender.
	; If not, then update defender's position, otherwise ignore the move.
	not_a_tackle:
		mov	ebx, 1	; move ok?
		mov	ecx, DWORD [defense_num]

		not_a_tackle_loop:
			mov	eax, DWORD [defense + 8*ecx - 8]; A defender X pos
			cmp	eax, DWORD [ebp - 4]		; defenseX
			jne	next_defender

			mov	eax, DWORD [defense + 8*ecx - 4]; A defender Y pos
			cmp	eax, DWORD [ebp - 8]		; defenseY
			jne	next_defender

			mov	ebx, 0	; move not ok
			next_defender:
			loop	not_a_tackle_loop

		; If ebx != 1, then move not ok
		cmp	ebx, 1
		jne	leave_move_defense

		; Defender move was ok, so update that defender's position for real.
		mov	eax, DWORD [ebp - 12]		; which defender
		mov	ebx, DWORD [ebp - 4]		; defenseX
		mov	DWORD [defense + 8*eax], ebx	; update defender X pos
		mov	ebx, DWORD [ebp - 8]		; defenseY
		mov	DWORD [defense + 8*eax + 4], ebx; update defender Y pos


	leave_move_defense:

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
; void score(int n)
;
; Add n to team with possession.
;
score:
	enter	0, 0

	push	eax

	; Arguments:
	; [ebp + 8]  : n

	mov	eax, DWORD [ebp + 8]	; eax = n

	cmp	DWORD [possession], 1	; who has the ball
	jne	score_visitor

	; Home team score
	score_home:
	add	DWORD [homescore], eax
	jmp	leave_score;

	; Visitor team score
	score_visitor:
	add	DWORD [visitorscore], eax


	leave_score:

	pop	eax

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void switch_team()
;
; Inverts direction and possession
switch_team:
	enter	0, 0

	push	eax

	mov	eax, DWORD [possession]
	neg	eax
	mov	DWORD [possession], eax

	mov	eax, DWORD [direction]
	neg	eax
	mov	DWORD [direction], eax

	pop	eax

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void drawsplash(char *s)
;
; Draw a splash screen with given message s.
; Will center the message.
;
%define	MAX_S_LEN	31
segment .data

splashstr	db	10
		db	10
		db	10
		db	10
		db	10
		db	"   ---------------------------------------------    ", 10
		db	"   |||   |   |   |   |   |   |   |   |   |   |||    ", 10
		db	"\  ||-   -                               -   -||  / ", 10
		db	" | |||   |               *               |   ||| |  ", 10
		db	"/  ||-   -                               -   -||  \ ", 10
		db	"   |||   |   |   |   |   |   |   |   |   |   |||    ", 10
		db	"   ---------------------------------------------    ", 10
		db	10, 10, 10, 10, 10, 10, 10, 10, 10
		db	0
drawsplash:
	enter	12, 0

	pusha

	; Arguments:
	; [ebp + 8] : s
	;
	; Local vars:
	; [ebp - 4]  : Location of the * in the splashstr
	; [ebp - 8]  : Length of s / 2
	; [ebp - 12] : Length of s

	; Find address of the center of the message line (search for *)
	mov	edi, splashstr
	mov	ecx, 0FFFFFFFFh
	mov	al, '*'
	cld
	repnz	scasb
	dec	edi

	; edi points to the * in splashstr
	mov	DWORD [ebp - 4], edi

	; Calculate length of s
	mov	edi, [ebp + 8]
	mov	ecx, MAX_S_LEN+1
	xor	al, al
	cld
	repnz	scasb
	mov	edx, MAX_S_LEN
	sub	edx, ecx	; edx = length of s
	mov	DWORD [ebp - 12], edx
	mov	ecx, edx
	shr	ecx, 1		; ecx = length of s / 2
	mov	DWORD [ebp - 8], ecx

	; Copy s into the splashstr
	mov	esi, [ebp + 8]
	mov	edi, [ebp - 4]
	sub	edi, [ebp - 8]
	mov	ecx, edx
	cld
	rep	movsb

	; print the splash screen
	call	homecursor
	push	splashstr
	call	printf
	add	esp, 4

	; restore splashstr
	mov	edi, DWORD [ebp - 4]
	sub	edi, DWORD [ebp - 8]
	mov	ecx, DWORD [ebp - 12]
	mov	al, ' '
	cld
	rep	stosb
	mov	edi, DWORD [ebp - 4]
	mov	BYTE [edi], '*'

	popa

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void drawboard()
;
; Draw the playing board
;
segment .data

;
; boardstr
;
; This fmt string contains the entire game display, with printf
; format specifiers for various game stats and inputs, etc.
;
; The actual playing field is marked with the labels
; playfield_begin and playfield_end.  Within the playfied,
; each possible player position is marked with *, O, or D.
;
; O indicates the starting position for the offense.
; D indicates the starting position for each defensive
; player.
;
; The playfing field size may be changed within the bounds
; of MAX_FIELD_WIDTH and MAX_FIELD_LENGTH.  It must be
; rectangular; i.e. each row has the same number of columns
; of player positions.  The init_field() function attempts
; to enforce this.
;
; The corresponding layout for splashstr in drawsplash should
; match the layout of the playing field.
;
boardstr	db	"                                                    ", 10
		db	"            %c HOME: %d%d   %c VISITOR: %d%d              ", 10
		db	"                                                    ", 10
		db	"   --------------                 --------------    ", 10
		db	"   | QUARTER: %d |                 | TIME: %d%d.%d |    ", 10
playfield_begin	db	"   ---------------------------------------------    ", 10
		db	"   ||| * | * | * | D | * | * | * | * | * | * |||    ", 10
		db	"\  ||-   -   -   -   -   -   -   -   -   -   -||  / ", 10
		db	" | ||| O | * | * | D | * | D | * | * | D | * ||| |  ", 10
		db	"/  ||-   -   -   -   -   -   -   -   -   -   -||  \ ", 10
		db	"   ||| * | * | * | D | * | * | * | * | * | * |||    ", 10
playfield_end	db	"   ---------------------------------------------    ", 10
		db	"   ---------------------------------------------    ", 10
		db	"   | DOWN: %d | FIELDPOS: %d%d%c | YARDS TO GO: %d%d |    ", 10
		db	"   ---------------------------------------------    ", 10
		db	"                                                    ", 10
		db	"     Movement: %c=UP  %c=LEFT  %c=DOWN  %c=RIGHT        ", 10
		db	"         Kick: %c (only on 4th down)                 ", 10
		db	"         Quit: %c                                    ", 10
		db	"                                                    ", 10
		db	"     Hit Enter after each play                      ", 10
		db	"     Hit %c to toggle debug display                  ", 10
		db	10
		db	0x1b, "[0J" ; clear to end of screen
		db	0

playposstr	db	" %d,%d", 0

debugstr	db	10
		db	"                                                    ", 10
		db	"   State Variables       Hit 0 - 5 to change skill: ", 10
		db	" -------------------                                ", 10
		db	"          tackle: %d      0 - sarcastaball          ", 10
		db	"     playrunning: %d      3 - challenging           ", 10
		db	"    requireenter: %d      5 - hurt me plenty        ", 10
		db	"        fieldpos: %d                                ", 10
		db	" lineofscrimmage: %d                                ", 10
		db	"      possession: %d                                ", 10
		db	"       direction: %d                                ", 10
		db	"      skilllevel: %d                                ", 10
		db	"    field_length: %d                                ", 10
		db	"     field_width: %d                                ", 10
		db	"     defense_num: %d                                ", 10
		db	0

drawboard:
	enter	0, 0

	push	eax
	push	ebx
	push	ecx
	push	edx


	;
	; draw players into the boardstr
	;
	push	DWORD [offense + 4]	; offenseY
	push	DWORD [offense]		; offenseX
	call	get_player_offset
	add	esp, 8
	mov	BYTE [eax], OFFENSE_CHAR

	mov	ecx, DWORD [defense_num]
	draw_defense:
		push	DWORD [defense + 8*ecx - 4]	; defender Y
		push	DWORD [defense + 8*ecx - 8]	; defender X
		call	get_player_offset
		add	esp, 8
		mov	BYTE [eax], DEFENSE_CHAR
		loop	draw_defense


	; Used for modulus arithmetic when 2 or more digits
	mov	ebx, 10

	;
	; For drawing the board, the printf() function is used.
	;
	; Push all the parameters ...
	;

	; Keys
	push	KEY_DEBUG
	push	KEY_QUIT
	push	KEY_KICK
	push	KEY_RIGHT
	push	KEY_DOWN
	push	KEY_LEFT
	push	KEY_UP

	; yards to go : 2 digits
	;
	; If yards to go extends into endzone, then truncate
	;
	mov	eax, DWORD [yardstogo]
	mov	ecx, DWORD [lineofscrimmage]
	add	ecx, DWORD [yardstogo]
	cmp	ecx, 100
	jle	push_yards_to_go
	mov	eax, 100
	sub	eax, DWORD [lineofscrimmage]

	push_yards_to_go:
	xor	edx, edx
	div	ebx
	push	edx
	push	eax

	; field position : 2 digits and the side indicator
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

	; down : 1 digit
	push	DWORD [down]

	; time remaining : 3 digits
	xor	edx, edx
	mov	eax, DWORD [timeremaining]
	div	ebx
	push	edx
	xor	edx, edx
	div	ebx
	push	edx
	push	eax

	; quarter : 1 digit
	push	DWORD [quarter]


	; visitor score : 2 digits
	xor	edx, edx
	mov	eax, DWORD [visitorscore]
	div	ebx
	push	edx
	push	eax

	; visitor possession : 1 character
	cmp	DWORD [possession], -1
	je	is_visitor_possession
	push	' '
	jmp	push_home_score
	is_visitor_possession:
	push	'*'

	; home score : 2 digits
	push_home_score:
	xor	edx, edx
	mov	eax, DWORD [homescore]
	div	ebx
	push	edx
	push	eax

	; home possession : 1 character
	cmp	DWORD [possession], 1
	je	is_home_possession
	push	' '
	jmp	print_the_board
	is_home_possession:
	push	'*'


	print_the_board:
	call	homecursor
	push	boardstr
	call	printf
	add	esp, 96


	; restore the boardstr
	call	clear_playpos


	;
	; Debug info
	;
	cmp	DWORD [debug_on], 1
	jne	leave_drawboard


	;
	; Player positions
	;

	; offense
	push	DWORD [offense + 4]	; offenseY
	push	DWORD [offense]		; offenseX
	push	playposstr
	call	printf
	add	esp, 12

	; defense
	mov	ecx, DWORD [defense_num]
	push_defense_pos:
		push	ecx
		push	DWORD [defense + 8*ecx-4]	; defenseX
		push	DWORD [defense + 8*ecx-8]	; defenseX
		push	playposstr
		call	printf
		add	esp, 12
		pop	ecx
		loop	push_defense_pos

	;
	; state info
	;
	push	DWORD [defense_num]
	push	DWORD [field_width]
	push	DWORD [field_length]
	push	DWORD [skilllevel]
	push	DWORD [direction]
	push	DWORD [possession]
	push	DWORD [lineofscrimmage]
	push	DWORD [fieldpos]
	push	DWORD [requireenter]
	push	DWORD [playrunning]
	push	DWORD [tackle]

	push	debugstr
	call	printf
	add	esp, 48



	leave_drawboard:

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
; int init_field()
;
; Scans through the playfield to detemine all the field length,
; field width, location of all player positions, starting location
; of offense, starting locations of all defense, and number of
; defense.
;
; Return: 0 - success, non 0 - failure
;
;         1 - More than 1 offensive player on playfield
;         2 - Exceeded MAX_DEFENSE defensive players on playfield
;         3 - Exceeded MAX_FIELD_WIDTH
;         4 - Exceeded MAX_FIELD_LENGTH
;         5 - No offensive players on playfield
;         6 - No defensive players on playfield
;         7 - field_length = 0
;         8 - field_width = 0
;         9 - playpos_num != field_length * field_width
;        10 - too many player positions on a field row
;
init_field:
	enter	12, 0

	; Local Vars:
	; [ebp - 4]  : set to 1 when we have a player position on the current line
	; [ebp - 8]  : column

	push	ecx
	push	edx
	push	esi
	push	edi

	mov	esi, playfield_begin
	mov	DWORD [field_length], 0
	mov	DWORD [field_width], 0
	mov	DWORD [playpos_num], 0
	mov	DWORD [offense_num], 0
	mov	DWORD [defense_num], 0
	mov	DWORD [ebp - 4], 0	; no player pos seen yet
	mov	DWORD [ebp - 8], -1	; column

	init_field_next:
		inc	esi
		cmp	esi, playfield_end
		jge	init_field_done

		cmp	BYTE [esi], '*'		; player position
		je	init_field_add_playpos

		cmp	BYTE [esi], 'O'		; offense position
		je	init_field_add_offense

		cmp	BYTE [esi], 'D'		; defense position
		je	init_field_add_defense

		cmp	BYTE [esi], 10
		je	init_field_newline

		jmp	init_field_next


		init_field_add_offense:
			mov	eax, 1
			cmp	DWORD [offense_num], 1	; only 1 offense allowed
			je	leave_init_field

			mov	eax, DWORD [ebp - 8]		; column
			inc	eax
			mov	DWORD [offense_start], eax	; offenseX start

			mov	eax, DWORD [field_width]
			mov	DWORD [offense_start + 4], eax	; offenseY start

			inc	DWORD [offense_num]

			jmp	init_field_add_playpos


		init_field_add_defense:
			mov	eax, 2
			cmp	DWORD [defense_num], MAX_DEFENSE	; limit MAX_DEFENSE defenders
			je	leave_init_field

			mov	ecx, DWORD [defense_num]

			mov	eax, DWORD [ebp - 8]			; column
			inc	eax
			mov	DWORD [defense_start + 8*ecx], eax	; defenseX start

			mov	eax, DWORD [field_width]
			mov	DWORD [defense_start + 8*ecx + 4], eax	; defenseX start

			inc	DWORD [defense_num]

			jmp	init_field_add_playpos


		init_field_newline:
			mov	DWORD [ebp - 8], -1	; reset column
			cmp	DWORD [ebp - 4], 0	; Did we see a player pos on this line?
			je	init_field_next		; No player pos on this line

			mov	eax, 3
			cmp	DWORD [field_width], MAX_FIELD_WIDTH	; limit MAX_FIELD_WIDTH
			je	leave_init_field

			inc	DWORD [field_width]
			mov	DWORD [ebp - 4], 0	; reset player pos seen flag

			jmp	init_field_next


		init_field_add_playpos:
			inc	DWORD [ebp - 8]		; increment column
			mov	DWORD [ebp - 4], 1	; we have now seen a player pos on this line

			cmp	DWORD [field_width], 0
			jg	add_the_playpos

			; On first field row, so still determining field_length
			mov	eax, 4
			cmp	DWORD [field_length], MAX_FIELD_LENGTH	; limit MAX_FIELD_LENGTH
			je	leave_init_field

			inc	DWORD [field_length]

			add_the_playpos:
				; Check if too many player pos on this field row
				mov	eax, DWORD [ebp - 8]		; column
				cmp	eax, DWORD [field_length]
				mov	eax, 10
				jge	leave_init_field

				mov	edi, DWORD [playpos_num]
				shl	edi, 2
				add	edi, playpos
				mov	[edi], esi	; playpos[playpos_num] = esi
				inc	DWORD [playpos_num]
				jmp	init_field_next


	init_field_done:
		; Need to have 1 offense
		mov	eax, 5
		cmp	DWORD [offense_num], 1
		jne	leave_init_field

		; Need to have at least 1 defense
		mov	eax, 6
		cmp	DWORD [defense_num], 1
		jl	leave_init_field

		; Check that field_length > 0
		mov	eax, 7
		cmp	DWORD [field_length], 0
		je	leave_init_field

		; Check that field_width > 0
		mov	eax, 8
		cmp	DWORD [field_width], 0
		je	leave_init_field

		; Check that playpos_num = field_length * field_width
		mov	eax, DWORD [field_length]
		mov	ecx, DWORD [field_width]
		mul	ecx
		sub	eax, DWORD [playpos_num]
		cmp	eax, 0
		mov	eax, 9
		jne	leave_init_field
		

		; blank out all the playpos on the playfield
		call	clear_playpos

		mov	eax, 0


	leave_init_field:

	pop	edi
	pop	esi
	pop	edx
	pop	ecx

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void clear_playpos()
;
; blank out all the playpos on the playfield
;
clear_playpos:
	enter	0, 0
	push	ecx

	mov	ecx, DWORD [playpos_num]
	clear_playpos_loop:
		mov	edi, DWORD [playpos + 4*ecx - 4]
		mov	BYTE [edi], ' '
		loop	clear_playpos_loop

	pop	ecx
	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; int get_player_offset(int X, int Y)
;
; Get the byte offset in boardstr for a player at position X,Y
;
; Return: the byte offset
;
get_player_offset:
	enter	0, 0

	; Arguments:
	; [ebp + 12] : Y
	; [ebp + 8]  : X

	push	ebx

	; playpos + 4*((Y*field_length) + X)
	mov	eax, DWORD [field_length]
	mov	ebx, DWORD [ebp + 12]
	mul	ebx
	add	eax, DWORD [ebp + 8]
	shl	eax, 2
	add	eax, playpos
	mov	eax, DWORD [eax]

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
;
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
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void homecursor()
;
; Home the cursor
;
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
; void hidecursor()
;
; Hide the cursor
;
segment .data

	hidestr	db	0x1b, "[?25l", 0

hidecursor:
	enter	0, 0

	push	hidestr
	call	printf
	add	esp, 4

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void showcursor()
;
; Hide the cursor
;
segment .data

	showstr	db	0x1b, "[?25h", 0

showcursor:
	enter	0, 0

	push	showstr
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
; Return: A random number between 0 and x-1
;
segment .data

	urandom	db	"/dev/urandom", 0

random:
	enter	4, 0

	; Arguments:
	; [ebp + 8] : x
	;
	; Local vars:
	; [ebp - 4] : Hold int read from /dev/urandom

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
	mov	eax, DWORD [ebp - 4]	; int read
	xor	edx, edx
	mov	ebx, DWORD [ebp + 8]	; x
	div	ebx
	mov	eax, edx

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
;
; Return: read character on success.
;         otherwise, -1
;
get_key:
	enter	4, 0

	; Local vars:
	; [ebp - 4] : Read char

	push	ebx
	push	ecx
	push	edx

	; Read 1 byte from stdin
	mov	eax, SYS_read
	mov	ebx, STDIN
	lea	ecx, [ebp - 4]
	mov	edx, 1
	int	0x80

	mov	eax, DWORD [ebp - 4]
	and	eax, 0x000000ff

	pop	edx
	pop	ecx
	pop	ebx

	leave
	ret
;
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void terminal_raw_mode()
;
; Put terminal into raw mode - disable ECHO and ICANON
; Also disabling SIGINT action on Ctrl-C - disable ISIG
; Set STDIN to non-blocking reads.
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
	xor	eax, ICANON
	xor	eax, ISIG
	and	DWORD [save_termios + 12], eax
	push	save_termios	; address of struct termios
	push	TCSAFLUSH
	push	STDIN
	call	tcsetattr
	add	esp, 12

	; get current stdin flags
	; flags = fcntl(stdin, F_GETFL, 0)
	push	0
	push	F_GETFL
	push	STDIN
	call	fcntl
	add	esp, 12
	mov	DWORD [save_stdin_flags], eax	; save flags

	; set non-blocking mode on stdin
	; fcntl(stdin, F_SETFL, flags | O_NONBLOCK)
	push	DWORD [save_stdin_flags]
	or	DWORD [esp], O_NONBLOCK
	push	F_SETFL
	push	STDIN
	call	fcntl
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
; Restore original STDIN flags.
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

	; restore stdin flags
	; fcntl(stdin, F_SETFL, flags)
	push	DWORD [save_stdin_flags]
	push	F_SETFL
	push	STDIN
	call	fcntl
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
; A local buffer of size BUFFER_SIZE bytes is used to hold the resulting
; print string.  The buffer is outputted whenever it fills.
;
; Supports 1 - MAX_BYTES byte ints.  To extend to more bytes:
;
; - Update the MAX_BYTES define to the new number.
; - Add entries to the digits table for the additional numbers of bytes.
; - Update the powers table to include the powers of 10 up to the maximum
;   number of digits.
; - See the end of this code for a C program that may be used to
;   generate the new tables.
;
; Return: none


; Size to reserve for a local print buffer
%define BUFFER_SIZE	1000

; Defines for arguments
%define ARG_FORMAT	[ebp + 8]
%define ARG_1		[ebp + 12]

; Defines for local variables
%define LOCAL_PRTG	[ebp - 3 ]
%define LOCAL_OUTC	[ebp - 4 ]
%define LOCAL_I		[ebp - 8 ]
%define LOCAL_J		[ebp - 12]
%define	LOCAL_BYTES	[ebp - 16]
%define	LOCAL_BUFFN	[ebp - 20]
%define	LOCAL_BUFF	[ebp - 20 - BUFFER_SIZE]

segment .data


; --- CUT HERE powers.c output ---
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
; --- CUT HERE powers.c output ---

printf:
	push	ebp
	mov	ebp, esp

	; Move esp to LOCAL_BUFFN
	lea	esp, LOCAL_BUFFN

	; Space on the stack for LOCAL_BUFF is based on BUFFER_SIZE.

	; Use LOCAL_BUFFN to temporarily save value of eax
	mov	DWORD LOCAL_BUFFN, eax

	; Round BUFFER_SIZE up to a multiple of 4 (DWORD boundary)
	mov	eax, BUFFER_SIZE
	add	eax, 3
	shr	eax, 2
	shl	eax, 2

	; Reserve space for LOCAL_BUFF on the stack
	sub	esp, eax

	; Restore eax
	mov	eax, DWORD LOCAL_BUFFN


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
	; ebp - 20  LOCAL_BUFFN :     int buffn - Numer of bytes in the print buffer.
	; ebp - ?   LOCAL_BUFF  :   char buff[] - Print buffer.  BUFFER_SIZE bytes
	;                                         below LOCAL_BUFFN.

	; esi : will step through each character of the format string
	; edi : will step through each subsequent argument on the stack


	pushf
	pusha

	mov	esi, ARG_FORMAT		; esi points to format string
	dec	esi
	lea	edi, ARG_1		; edi will point to each subsequent argument

	mov	DWORD LOCAL_BUFFN, 0


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
		push	DWORD [edi]	; edi points to the char
		call	printf_buffer_mgmt
		add	esp, 4

		add	edi, 4		; Move edi to next argument
		jmp	printf_toploop


	; print a string
	printf_string:
		; Copy the string over to LOCAL_BUFF

		push	edi		; Save edi, since needed for scasb
		mov	edi, [edi]	; Point edi to the string itself.

		printf_string_loop:
			cmp	BYTE [edi], 0
			je	printf_string_loop_end

			push	DWORD [edi]	; edi points to the char
			call	printf_buffer_mgmt
			add	esp, 4

			inc	edi
			jmp	printf_string_loop

			
		printf_string_loop_end:
		pop	edi		; restore edi
		add	edi, 4		; Move edi to next argument
		jmp	printf_toploop


	; print character at esi
	printf_char_literal:
		push	DWORD [esi]	; esi points to the char
		call	printf_buffer_mgmt
		add	esp, 4

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

		push	DWORD LOCAL_OUTC	; LOCAL_OUTC has the char
		call	printf_buffer_mgmt
		add	esp, 4

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

			push	DWORD LOCAL_OUTC	; LOCAL_OUTC has the char
			call	printf_buffer_mgmt
			add	esp, 4

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

		push	DWORD LOCAL_OUTC	; LOCAL_OUTC has the char
		call	printf_buffer_mgmt
		add	esp, 4

		jmp	printf_toploop


	printf_endloop:

	; Check for anything left in the print buffer
	cmp	DWORD LOCAL_BUFFN, 0
	je	printf_done

	; Print the buffer
	mov	eax, SYS_write	; syscall
	mov	ebx, STDOUT	; fd
	lea	ecx, LOCAL_BUFF
	mov	edx, DWORD LOCAL_BUFFN
	int	0x80

	printf_done:
	popa
	popf

	mov	esp, ebp
	pop	ebp
	ret

	;
	; void printf_buffer_mgmt(char c)
	;
	; Mini routine for adding a char to the print buffer
	; and printing the buffer if full.  Created to avoid
	; code duplication.
	;
	; esp + 4 will point to the char.
	;
	; Caller needs to save, eax, ebx, ecx, edx as needed.
	;
	printf_buffer_mgmt:
		cmp	DWORD LOCAL_BUFFN, BUFFER_SIZE
		jl	printf_buffer_mgmt_add

		; buffer already full.  Print it and clear it.
		mov	eax, SYS_write	; syscall
		mov	ebx, STDOUT	; fd
		lea	ecx, LOCAL_BUFF
		mov	edx, DWORD LOCAL_BUFFN
		int	0x80
		mov	DWORD LOCAL_BUFFN, 0

		printf_buffer_mgmt_add:
			lea	eax, LOCAL_BUFF
			add	eax, DWORD LOCAL_BUFFN	; eax points to new char location in buffer
			mov	bl, BYTE [esp + 4]	; esp points to the char
			mov	BYTE [eax], bl		; copy the character to the buffer
			inc	DWORD LOCAL_BUFFN	; increment buffer byte count

		ret
;
;------------------------------------------------------------------------------

; powers.c
; C program for generating new tables for the printf function
; Paste output above between the "CUT HERE powers.c output" markers.

%if 0
// powers.c
//
// Building: gcc -o powers powers.c
//
// Usage: ./powers [bytes] > out
//
//        where bytes is the # of bytes to support
//
// Output: Generates new tables to include in the printf assembly code.
//
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_BYTES (10000)
#define MAX_DIGITS (3 * MAX_BYTES)

void hex2dec(char *hex, int dec[], int *digits);
void mul(int number[], int *digits, int base, int val);
void add(int number[], int *digits, int base, int val);
void outputdec(int dec[], int digits);
char* outputhex(int hex[], int digits, int bytes);


char out[MAX_BYTES*5+100];

int main(int argc, char *argv[])
{
   int dec[MAX_DIGITS+1];
   int decdigits;

   int hex[MAX_BYTES*2+1];
   int hexdigits;

   int inx;
   int powerdigits;

   int bytes = 4;

   char hex_string[MAX_BYTES*2 + 1];

   if (argc == 2)
   {
      bytes = atoi(argv[1]);
   }

   if (bytes > MAX_BYTES)
   {
      printf("Max bytes = %d\n", MAX_BYTES);
      exit(1);
   }


   printf("%%define MAX_BYTES %d\n", bytes);
   printf("%%define MIN_BYTES 1\n");
   printf("\n");


   // Generate digits table
   printf("; Max number of digits in an N byte integer.  0<= N <=%d\n", bytes);
   printf("digits db 0x00, 0x00, 0x00, 0x00");
   memset(hex_string,'\0',sizeof(hex_string));
   for (inx=0; inx<bytes; inx++)
   {
      strcat(hex_string, "ff");
      memset(dec, '\0', sizeof(dec));
      hex2dec(hex_string, dec, &decdigits);

      printf("\n       db ");
      printf("0x%02x, 0x%02x, 0x%02x, 0x%02x ; %d byte%s = %u digits", decdigits&0xff, (decdigits>>8)&0xff, (decdigits>>16)&0xff, (decdigits>>24)&0xff, inx+1, (inx>0)?"s":"", decdigits);
   }
   printf("\n");
   printf("\n");


   // Generate powers table
   // Outputting from highest number of digits to lowest (1)

   printf("; Table of powers of 10 for %d byte integers.\n", bytes);

   powerdigits = decdigits;

   while (powerdigits > 0)
   {
      memset(hex, '\0', sizeof(hex));
      hex[0] = 1;
      hexdigits = 1;

      for (inx=0; inx<powerdigits-1; inx++)
      {
         mul(hex, &hexdigits, 16, 10);
      }

      if (powerdigits == decdigits)
      {
         printf("powers db ");
      }
      else
      {
         printf("       db ");
      }
      printf(outputhex(hex, hexdigits, bytes));
      printf(" ; 10^%d\n", powerdigits-1);

      powerdigits--;
   }


   printf("\n; The largest %d byte unsigned integer 0x%s\n", bytes, hex_string);
   printf("; would be ");
   for (inx=decdigits-1; inx>=0; inx--) printf("%d", dec[inx]);
   printf(" in decimal.\n");
   printf("; %d digits long.\n", decdigits);
   printf(";\n");
   printf("; Useful site: https://www.rapidtables.com/convert/number/hex-to-decimal.html\n");
}

void hex2dec(char *hex, int dec[], int *digits)
{
   char *p;
   int val;

   *digits = 1;
   dec[0] = 0;

   for (p=hex; *p; p++)
   {
      mul(dec, digits, 10, 16);
      if ( (*p>='0') && (*p<='9') )
      {
         val = *p - '0';
      }
      if ( (*p>='a') && (*p<='f') )
      {
         val = *p - 'a' + 10;
      }
      if ( (*p>='A') && (*p<='F') )
      {
         val = *p - 'A' + 10;
      }
      add(dec, digits, 10, val);
   }
}

void mul(int number[], int *digits, int base, int val)
{
   int carry = 0;
   int inx = 0;

   carry = 0;
   do
   {
      number[inx] = val*number[inx] + carry;
      carry = number[inx]/base;
      number[inx] = number[inx] % base;
      inx++;
   } while ( (inx<*digits) || (carry!=0) );

   *digits = inx;
   if (*digits > MAX_DIGITS)
   {
      printf("\n\nExceeded MAX_DIGITS %d\n", MAX_DIGITS);
      exit(1);
   }
}

void add(int number[], int *digits, int base, int val)
{
   int carry = 0;
   int inx = 0;

   carry = 0;
   do
   {
      number[inx] += (val + carry);
      val = 0;
      carry = number[inx]/base;
      number[inx] = number[inx] % base;
      inx++;
   } while ( (inx<*digits) || (carry!=0) );

   *digits = inx;
   if (*digits > MAX_DIGITS)
   {
      printf("\n\nExceeded MAX_DIGITS %d\n", MAX_DIGITS);
      exit(1);
   }
}

void outputdec(int dec[], int digits)
{
   int inx;

   printf("Num: ");
   for (inx=digits-1; inx>=0; inx--)
   {
      printf("%d", dec[inx]);
   }
   printf(", Digits: %d\n", digits);
}

char* outputhex(int hex[], int digits, int bytes)
{
   int inx;

   char chars[] = {'0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'};

   memset(out, '\0', sizeof(out));

   for (inx=0; inx<digits; inx+=2)
   {
      sprintf(out+strlen(out), "0x%c%c", chars[hex[inx+1]], chars[hex[inx]]);
      bytes--;
      if (bytes > 0) sprintf(out+strlen(out), ",");
   }

   while (bytes > 0)
   {
      sprintf(out+strlen(out), "0x00");
      bytes--;
      if (bytes > 0) sprintf(out+strlen(out), ",");
   }

   return(out);
}
%endif
