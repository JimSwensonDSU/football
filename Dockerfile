FROM ubuntu

COPY football.sh football.asm Makefile field.txt football.6 /

RUN apt-get update && apt-get install -y nasm gcc gcc-multilib make less groff-base && cd / && make

ENTRYPOINT ["/football.sh"]
