NAME=football
SHAREDIR = /home/jswenson/pcasm/linux-ex
AS = /home/jswenson/nasm-2.15.05/nasm
ASFLAGS = -f elf -F dwarf
CC = gcc
CFLAGS = -m32

all: $(NAME)

clean:
	rm -rf $(NAME) $(NAME).o $(NAME).lst

$(NAME).lst: $(NAME).asm
	$(AS) -I$(SHAREDIR)/ $(ASFLAGS) -g -l $(NAME).lst $(NAME).asm

$(NAME): $(NAME).asm
	$(AS) -I$(SHAREDIR)/ $(ASFLAGS) -g -o $(NAME).o $(NAME).asm
	$(CC) $(CFLAGS) -g -o $(NAME) $(NAME).o $(SHAREDIR)/driver.c $(SHAREDIR)/asm_io.o
