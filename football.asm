;
; football
;
; Jim Swenson
; Jim.Swenson@trojans.dsu.edu
;
; An implementation of the Mattel Electronic Football game.
;
; This implementation is based on the remake.
;
;   - Field length is 10.  Original was 9 positions long.
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
;
; Ideas for improvement:
; - implement random fumbles on a tackle
; - support arbitary field width/length
; - support arbitrary number defenders (almost there apart from initial state)
; - Use ascii chart for layout of defense or Random defense placement?
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
%define ICANNON		2
%define	TCSAFLUSH	2

%define F_GETFL		3
%define F_SETFL		4

;
; Game constants
;
%define	OFFENSE_CHAR	'O'	; character for offensive player
%define	DEFENSE_CHAR	'X'	; character for defensive players

%define FIELD_WIDTH	3	; number of player positions across width of the field
%define	FIELD_LENGTH	10	; number of player positions along the length of the field
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
%define	KEY_ENTER	10
%define	KEY_DEBUG	'v'	; toggle debug mode

%define TICK		100000	; 1/10th of a second
%define TIMER_COUNTER	10	; Number of ticks between decrementing timeremaining
%define DEFENSE_COUNTER	16	; Number of ticks between moving defense

%define NUM_DEFENSE	5


segment .data

	msg_touchdown		db	"!!! TOUCHDOWN !!!!", 0
	msg_fieldgoalgood	db	"!!! FIELD GOAL !!!!", 0
	msg_fieldgoalmiss	db	"FIELD GOAL MISSED", 0
	msg_tackle		db	"TACKLED", 0
	msg_punt		db	"PUNTED", 0
	msg_gameover		db	"GAME OVER - Hit Enter or ", KEY_QUIT, 0

segment .bss
	; save terminal/stdin settings
	save_termios		resb	60
	save_c_lflag		resb	4
	save_stdin_flags	resb	4

	; game state
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
	defense		resd	2*NUM_DEFENSE	; N sets of X,Y

	; counters
	defense_counter	resd	1
	timer_counter	resd	1

	; debug_on - displays state variables
	debug_on		resd	1	; 1 = yes, 0 = no

segment .text
	global  asm_main
	extern	printf
	extern	usleep
	extern  fcntl, tcsetattr, tcgetattr

asm_main:
	push	ebp
	mov		ebp, esp
	; ********** CODE STARTS HERE **********

	call	terminal_raw_mode
	call	run_game
	call	terminal_restore_mode

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

	call	init_game
	call	clearscreen

	gameloop:
		call	drawboard

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
	mov	DWORD [offense], 0
	mov	DWORD [offense + 4], 1

	mov	DWORD [defense],      3
	mov	DWORD [defense + 4],  0

	mov	DWORD [defense + 8],  3
	mov	DWORD [defense + 12], 1

	mov	DWORD [defense + 16], 3
	mov	DWORD [defense + 20], 2

	mov	DWORD [defense + 24], 5
	mov	DWORD [defense + 28], 1

	mov	DWORD [defense + 32], 8
	mov	DWORD [defense + 36], 1


	cmp	DWORD [direction], 1
	je	leave_init_player_positions


	; Flip all the X positions for right to left
	right_to_left:

	; Offense
	mov	eax, DWORD [offense]	; offenseX
	neg	eax
	add	eax, FIELD_LENGTH
	dec	eax
	mov	DWORD [offense], eax

	; Defense
	mov	ecx, NUM_DEFENSE
	flip_defense:
		mov	eax, DWORD [defense + 8*ecx - 8]	; defenseX
		neg	eax
		add	eax, FIELD_LENGTH
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
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
;
; void reset_defense_count()
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
		call	do_punt		; eax = punt distance

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
		jne	check_enter
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
	jg	fieldgoal_miss

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
	push	eax
	call	random
	add	esp, 4
	add	eax, MIN_PUNT

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
		mov	ebx, FIELD_LENGTH
		add	eax, ebx		; eax = FIELDLENGTH + offenseX + deltaX
		; Get eax % FIELDLENGTH
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
		cmp	eax, FIELD_WIDTH
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
		mov	ecx, NUM_DEFENSE

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
	push	NUM_DEFENSE
	call	random
	add	esp, 4
	mov	DWORD [ebp - 12], eax

	; save that defender's current position
	mov	ebx, DWORD [defense + 8*eax]
	mov	DWORD [ebp - 4], ebx		; defenseX
	mov	ebx, DWORD [defense + 8*eax + 4]
	mov	DWORD [ebp - 8], ebx		; defenseX


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
		mov	ecx, NUM_DEFENSE

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

	; Local vars:
	; [ebp - 4]  : Location of the * in the splashstr
	; [ebp - 8]  : Length of s / 2
	; [ebp - 12] : Length of s

	; Find offset to the center of the message line (search for *)
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
	;mov	ecx, 0FFFFFFFFh
	mov	ecx, MAX_S_LEN+1
	xor	al, al
	cld
	repnz	scasb
	;mov	edx, 0FFFFFFFEh
	mov	edx, MAX_S_LEN
	sub	edx, ecx	; edx = length of s
	mov	DWORD [ebp - 12], edx
	mov	ecx, edx
	shr	ecx, 1		; ecx = length of s / 2
	mov	DWORD [ebp - 8], ecx

	; Copy s into the splashstr
	mov	esi, [ebp + 8]
	mov	edi, [ebp - 4]
	sub	edi, ecx
	mov	ecx, edx
	cld
	rep	movsb

	; print the splash screen
	call	hidecursor
	call	homecursor
	push	splashstr
	call	printf
	add	esp, 4
	call	showcursor

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

boardstr	db	"                                                    ", 10
		db	"            %c HOME: %d%d   %c VISITOR: %d%d              ", 10
		db	"                                                    ", 10
		db	"   --------------                 --------------    ", 10
		db	"   | QUARTER: %d |                 | TIME: %d%d.%d |    ", 10
		db	"   ---------------------------------------------    ", 10
		db	"   |||   |   |   |   |   |   |   |   |   |   |||    ", 10
		db	"\  ||-   -   -   -   -   -   -   -   -   -   -||  / ", 10
		db	" | |||   |   |   |   |   |   |   |   |   |   ||| |  ", 10
		db	"/  ||-   -   -   -   -   -   -   -   -   -   -||  \ ", 10
		db	"   |||   |   |   |   |   |   |   |   |   |   |||    ", 10
		db	"   ---------------------------------------------    ", 10
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
		db	0x1b, "[0J" ; clear to end of screen
		db	0

debugstr	db	"                                                    ", 10
		db	"----------------------------------------------------", 10
		db	"                                                    ", 10
		db	"   State Variables       Hit 0 - 5 to change skill  ", 10
		db	" -------------------                                ", 10
		db	"          tackle: %d       0 - easy (default)       ", 10
		db	"     playrunning: %d       3 - challenging          ", 10
		db	"    requireenter: %d       5 - hurt me plenty       ", 10
		db	"        fieldpos: %d                                ", 10
		db	" lineofscrimmage: %d                                ", 10
		db	"      possession: %d                                ", 10
		db	"       direction: %d                                ", 10
		db	"      skilllevel: %d                                ", 10
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


	;
	; draw players into the boardstr
	;
	; Could combine offense and defense together here in one loop, but
	; that would then require that the offense and defense in .bss remain
	; in their current order.  So better to keep separate for clarity.
	;
	lea	ebx, [ebp - 4]		; ebx points to offense save slot
	push	DWORD [offense + 4]	; offenseY
	push	DWORD [offense]		; offenseX
	call	calc_player_offset
	add	esp, 8
	mov	[ebx], eax		; save offset to local var
	mov	BYTE [boardstr + eax], OFFENSE_CHAR

	mov	ecx, NUM_DEFENSE
	draw_defense:
		sub	ebx, 4
		push	DWORD [defense + 8*ecx - 4]	; defender Y
		push	DWORD [defense + 8*ecx - 8]	; defender X
		call	calc_player_offset
		add	esp, 8
		mov	DWORD [ebx], eax		; save offset to local var
		mov	BYTE [boardstr + eax], DEFENSE_CHAR
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
	call	hidecursor
	call	homecursor
	push	boardstr
	call	printf
	add	esp, 96



	; restore the boardstr
	mov	ebx, ebp
	mov	ecx, 1+NUM_DEFENSE
	restore_board:
	sub	ebx, 4
	mov	eax, DWORD [ebx]
	mov	BYTE [boardstr + eax], ' '
	loop	restore_board


	;
	; Debug info
	;
	cmp	DWORD [debug_on], 1
	jne	leave_drawboard


	; some state info
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
	add	esp, 36


	leave_drawboard:
	call	showcursor

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
; Return: the byte offset
;
calc_player_offset:
	enter	4, 0

	; Arguments:
	; [ebp + 12] : Y
	; [ebp + 8]  : X

	push	ebx
	push	edx

	; Offset to offense position is 335 + Y*106 + X*4
	mov	eax, DWORD [ebp + 12]
	mov	ebx, 106
	mul	ebx
	mov	DWORD [ebp - 4], eax

	mov	eax, DWORD [ebp + 8]
	mov	ebx, 4
	mul	ebx
	add	eax, DWORD [ebp - 4]
	add	eax, 335

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
	xor	eax, ICANNON
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
