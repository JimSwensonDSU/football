NAME=football
AS = /home/jswenson/nasm-2.15.05/nasm
ASFLAGS = -f elf -F dwarf
CC = gcc
CFLAGS = -m32

all: $(NAME)

clean:
	rm -rf $(NAME) $(NAME).o $(NAME).lst

$(NAME).lst: $(NAME).asm
	$(AS) $(ASFLAGS) -g -l $(NAME).lst $(NAME).asm

$(NAME): $(NAME).asm
	$(AS) $(ASFLAGS) -g -o $(NAME).o $(NAME).asm
	$(CC) $(CFLAGS) -g -o $(NAME) $(NAME).o
