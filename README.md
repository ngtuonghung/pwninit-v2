# pwninit

Python CLI to automate CTF pwn challenge setup, based on [pwninit](https://github.com/io12/pwninit).

## Features

- Downloads matching dynamic linkers (`ld.so`) and required libraries (`libpthread`, `libm`, etc.).
- Resolves library dependencies, including non-libc6 packages like `libcrypto`, `libssl`, `libseccomp`, `libcap`, and `libz`.
- Downloads debug symbols and unstrips libraries.
- Caches `.deb` archives in `~/.cache/pwninit/` and `./lib/`.
- Patches binaries with local library paths using direct byte replacement or `patchelf`.
- Fetches and extracts glibc source code via `pwnsrc` for source-level debugging in GDB.
- Supports Ubuntu and Debian glibc packages.

## Requirements

Linux or WSL, and Python 3.10+.

Install the system packages:

```bash
sudo apt install -y binutils elfutils patchelf
```

`bin/pwninit` creates `.venv/` and installs the Python packages on its first run. Put `bin/` on your `PATH`, or define aliases with the absolute path of your clone:

```bash
git clone git@github.com:ngtuonghung/pwninit-v2.git ~/pwninit-v2

alias pwninit="$HOME/pwninit-v2/bin/pwninit"
alias pwnsrc="$HOME/pwninit-v2/bin/pwnsrc"
```

## Usage

### pwninit

Run `pwninit` in the directory containing the target binary and libc:

```bash
pwninit
```

Specify inputs directly if needed:

```bash
pwninit --bin ./chall --libc ./libc.so.6 --ld ./ld-linux-x86-64.so.2
```

Options:
- `-b, --bin <file>`: Binary to patch.
- `--libc <file>`: Target libc.
- `--ld <file>`: Target interpreter.
- `-nu, --no-unstrip`: Skip unstripping debug symbols.
- `-np, --no-patch`: Skip patching the binary.
- `--use-patchelf`: Patch using `patchelf` instead of direct byte replacement.
- `-l, --libs <dir>`: Directory to store resolved libraries.
- `-o, --output <file>`: Output path for patched binary (defaults to `<bin>_patched`).

All artifacts (fetched libraries, symlinks, `<bin>_patched`) are written next to the binary, so running `pwninit --bin /path/to/chall` from any working directory is safe.

Success means exit code 0 and a `<bin>_patched` file next to the binary. A statically linked binary returns 0 without producing one. Run `./<bin>_patched` to verify.

### pwnsrc

Download and extract glibc source files for GDB source stepping. Run `pwnsrc` in the directory containing the libc:

```bash
# Download glibc source archive for the local libc
pwnsrc

# Extract specific source files
pwnsrc --files malloc.c
pwnsrc --files glibc-2.31/malloc/malloc.c
```

Options:
- `--libc <file>`: Target libc.
- `-s, --source <file>`: Existing glibc source archive, skipping the download.
- `-f, --files <name...>`: Source files to extract.

## Notes

- Run the patched binary, `./<bin>_patched`, to verify it works before writing the exploit. With pwntools: `process("./<bin>_patched")`, never the original binary.
- Keep the generated `ld`/`libc` symlinks and fetched libraries next to the binary; they are the relative paths the patch points at.
- No exploit script is generated. Write `solve.py` yourself.
- Non-libc dependencies (libcrypto, libseccomp, ...) are resolved automatically from the binary's `NEEDED` entries.
- If a run fails on a missing system package, the log contains the install command. Run it once as root, then retry.

## Tests

Run the test suite (no network required):

```bash
make test
```

End-to-end tests build hermetic fixtures (fake deb cache, gcc-compiled binaries) in temp directories. An optional real-network suite runs only when `PWNINIT_E2E_REAL=1` is set:

```bash
make test-real
```

## Configuration

Edit `src/config.py` to change defaults:
- `PATCHED_BINARY_SUFFIX`: Suffix for patched binaries (default: `_patched`).

## Patching methods

`pwninit` provides two patching methods:

1. **Direct byte replacement (default)**: Overwrites `PT_INTERP` and `DT_NEEDED` entries in the ELF string table with shorter relative symlink paths (`./ld`, `./libc`). This preserves original section offsets and file layout.
2. **Patchelf (`--use-patchelf`)**: Uses `patchelf` to set the interpreter, replace library names, and inject `$ORIGIN:.` into `DT_RPATH`.

## Examples

### Initializing a standard challenge

```bash
$ ls
chall  libc.so.6
$ readelf -Wd ./chall | grep NEEDED
 0x0000000000000001 (NEEDED)             Shared library: [libc.so.6]
 0x0000000000000001 (NEEDED)             Shared library: [libpthread.so.0]
$ pwninit
[*] bin: chall (arch = 'amd64')
[*] libc: libc.so.6
[*] libc version: (Ubuntu GLIBC 2.31-0ubuntu9.2) stable release version 2.31.

[*] Resolving library dependencies recursively (cache: '/home/user/.cache/pwninit')...
[*] Fetching 'libpthread.so.0' from https://archive.ubuntu.com/ubuntu/pool/main/g/glibc/libc6_2.31-0ubuntu9.2_amd64.deb
[+] Successfully fetched 'libpthread.so.0'
[*] Fetching 'ld-linux-x86-64.so.2' from https://archive.ubuntu.com/ubuntu/pool/main/g/glibc/libc6_2.31-0ubuntu9.2_amd64.deb (cached)
[+] Successfully fetched 'ld-linux-x86-64.so.2'

[*] Finding stripped libraries to unstrip
[*] Unstripping 'libc.so.6', 'libpthread.so.0', 'ld-linux-x86-64.so.2'
[*] Fetching debug symbols from https://archive.ubuntu.com/ubuntu/pool/main/g/glibc/libc6-dbg_2.31-0ubuntu9.2_amd64.deb
[+] Successfully unstripped 'libc.so.6'
[+] Successfully unstripped 'libpthread.so.0'
[+] Successfully unstripped 'ld-linux-x86-64.so.2'

[*] Patching binary manually
[*] Symlinking './ld' -> 'ld-linux-x86-64.so.2'
[*] Symlinking './libc' -> 'libc.so.6'
[*] Symlinking './libpthread' -> 'libpthread.so.0'
[+] Successfully wrote patched binary to 'chall_patched'
$ ls
chall  chall_patched  ld  ld-linux-x86-64.so.2  libc  libc.so.6  libpthread  libpthread.so.0
```

### Challenge requiring OpenSSL (`libcrypto.so.1.1`)

```bash
$ ls
chall  libc.so.6
$ readelf -Wd ./chall | grep NEEDED
 0x0000000000000001 (NEEDED)             Shared library: [libcrypto.so.1.1]
 0x0000000000000001 (NEEDED)             Shared library: [libc.so.6]
$ pwninit
[*] bin: chall (arch = 'amd64')
[*] libc: libc.so.6
[*] libc version: (Ubuntu GLIBC 2.27-3ubuntu1) stable release version 2.27.

[*] Resolving library dependencies recursively (cache: '/home/user/.cache/pwninit')...

[*] Fetching 'libcrypto.so.1.1' from https://launchpadlibrarian.net/.../libssl1.1_1.1.1-1ubuntu2.1~18.04.23_amd64.deb
[+] Successfully fetched 'libcrypto.so.1.1'
[*] Fetching 'libdl.so.2' from https://archive.ubuntu.com/.../libc6_2.27-3ubuntu1_amd64.deb
[+] Successfully fetched 'libdl.so.2'
[*] Fetching 'libpthread.so.0' from https://archive.ubuntu.com/.../libc6_2.27-3ubuntu1_amd64.deb (cached)
[+] Successfully fetched 'libpthread.so.0'
[*] Fetching 'ld-linux-x86-64.so.2' from https://archive.ubuntu.com/.../libc6_2.27-3ubuntu1_amd64.deb (cached)
[+] Successfully fetched 'ld-linux-x86-64.so.2'

[*] Patching transitive deps in 'libcrypto.so.1.1'
[*] Symlinking './libdl' -> 'libdl.so.2'
[*] Symlinking './libpthread' -> 'libpthread.so.0'

[*] Finding stripped libraries to unstrip
[*] Unstripping 'libcrypto.so.1.1', 'libdl.so.2', 'libpthread.so.0', 'ld-linux-x86-64.so.2'
...

[*] Patching binary manually
[*] Symlinking './ld' -> 'ld-linux-x86-64.so.2'
[*] Symlinking './libcrypto' -> 'libcrypto.so.1.1'
[*] Symlinking './libc' -> 'libc.so.6'
[+] Successfully wrote patched binary to 'chall_patched'
```

### Fetching glibc source code

```bash
$ ls
dd1  libc-2.23.so
$ pwnsrc
[*] libc: libc-2.23.so
[*] libc version: (Ubuntu GLIBC 2.23-0ubuntu10) stable release version 2.23, by Roland McGrath et al.
[*] Fetching glibc source from https://archive.ubuntu.com/ubuntu/pool/universe/g/glibc/glibc-source_2.23-0ubuntu10_all.deb
[+] Successfully written glibc-source to 'glibc-source-2.23.tar.xz'
$ ls
dd1  glibc-source-2.23.tar.xz  libc-2.23.so
$ pwnsrc --files malloc.c
[*] libc: libc-2.23.so
[*] libc version: (Ubuntu GLIBC 2.23-0ubuntu10) stable release version 2.23, by Roland McGrath et al.

[*] glibc source: glibc-source-2.23.tar.xz
[*] Finding source code files
[+] Successfully extracted 'malloc.c'
$ ls
dd1  glibc-source-2.23.tar.xz  libc-2.23.so  malloc.c
```
