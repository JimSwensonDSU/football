# football

Jim Swenson
Jim.Swenson@trojans.dsu.edu

football is an implementation of the 1977 handheld Mattel Electronic Football game written in 32 bit x86 assembly code.

https://www.handheldmuseum.com/Mattel/FB.htm

Assemble using nasm https://www.nasm.us/

The code uses no libc function and instead leverages Linux syscalls.

## INSTRUCTIONS FOR DOCKER

With Docker installed, you can build and run football without needing to
have a working Linux instance or even cloning the repo.

Note: Enable the WSL 2 engine in Docker Desktop for this.

### Build an image named "football":
```
  docker build -t football https://github.com/JimSwensonDSU/football.git
```

### Run the game:
```
  docker run --rm -it football
```

To run using the separate "field.txt" field:
```
  docker run --rm -it football field.txt
```

To view the man page:
```
  docker run --rm -it football man
```
(Note that "less" style paging is used when viewing the man page.)

### To build an even smaller image based on busybox:
```
  docker build -t football -f Dockerfile_busybox https://github.com/JimSwensonDSU/football.git
```
Note that this image will not have the man page available.
