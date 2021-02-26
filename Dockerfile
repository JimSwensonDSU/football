FROM ubuntu

RUN apt-get update && apt-get install -y nasm gcc gcc-multilib make less groff-base

COPY football.sh /
COPY football.asm /
COPY Makefile /
COPY field.txt /
COPY football.6 /

RUN cd / && make

ENTRYPOINT ["/football.sh"]
