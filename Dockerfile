FROM ubuntu:latest as builder
COPY football.asm /
RUN apt-get update && apt-get install -y nasm gcc gcc-multilib
RUN nasm -f elf -F dwarf football.asm
RUN gcc -static -m32 -o football football.o


FROM alpine:latest
RUN apk --no-cache add groff
COPY football.sh field.txt football.6 /
COPY --from=builder /football /
ENTRYPOINT ["/football.sh"]
