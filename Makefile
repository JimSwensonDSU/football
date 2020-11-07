NAME=football
NAME5x10=$(NAME)5x10
NAME7x15=$(NAME)7x15
AS = /home/jswenson/nasm-2.15.05/nasm
ASFLAGS = -f elf -F dwarf
CC = gcc
CFLAGS = -m32

all: $(NAME) $(NAME5x10) $(NAME7x15)

clean:
	rm -rf $(NAME) $(NAME).o $(NAME).lst $(NAME5x10) $(NAME5x10).o $(NAME5x10).lst $(NAME7x15) $(NAME7x15).o $(NAME7x15).lst

$(NAME).lst: $(NAME).asm
	$(AS) $(ASFLAGS) -g -l $(NAME).lst $(NAME).asm

$(NAME5x10).lst: $(NAME5x10).asm
	$(AS) $(ASFLAGS) -g -l $(NAME5x10).lst $(NAME5x10).asm

$(NAME7x15).lst: $(NAME7x15).asm
	$(AS) $(ASFLAGS) -g -l $(NAME7x15).lst $(NAME7x15).asm

$(NAME): $(NAME).asm
	$(AS) $(ASFLAGS) -g -o $(NAME).o $(NAME).asm
	$(CC) $(CFLAGS) -g -o $(NAME) $(NAME).o

$(NAME5x10): $(NAME5x10).asm
	$(AS) $(ASFLAGS) -g -o $(NAME5x10).o $(NAME5x10).asm
	$(CC) $(CFLAGS) -g -o $(NAME5x10) $(NAME5x10).o

$(NAME7x15): $(NAME7x15).asm
	$(AS) $(ASFLAGS) -g -o $(NAME7x15).o $(NAME7x15).asm
	$(CC) $(CFLAGS) -g -o $(NAME7x15) $(NAME7x15).o
