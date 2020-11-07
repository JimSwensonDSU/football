NAME=football
NAME5x10=$(NAME)5x10
AS = /home/jswenson/nasm-2.15.05/nasm
ASFLAGS = -f elf -F dwarf
CC = gcc
CFLAGS = -m32

all: $(NAME) $(NAME5x10)

clean:
	rm -rf $(NAME) $(NAME).o $(NAME).lst $(NAME5x10) $(NAME5x10).o $(NAME5x10).lst

$(NAME).lst: $(NAME).asm
	$(AS) $(ASFLAGS) -g -l $(NAME).lst $(NAME).asm

$(NAME5x10).lst: $(NAME5x10).asm
	$(AS) $(ASFLAGS) -g -l $(NAME5x10).lst $(NAME5x10).asm

$(NAME): $(NAME).asm
	$(AS) $(ASFLAGS) -g -o $(NAME).o $(NAME).asm
	$(CC) $(CFLAGS) -g -o $(NAME) $(NAME).o

$(NAME5x10): $(NAME5x10).asm
	$(AS) $(ASFLAGS) -g -o $(NAME5x10).o $(NAME5x10).asm
	$(CC) $(CFLAGS) -g -o $(NAME5x10) $(NAME5x10).o
