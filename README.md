
# Cursed Bootloader in Nim

A **self-modifying, source-aware bootloader** for STM32F103 (Blue Pill) that embeds its own build script's MD5 checksum into the generated binary. If the bootloader source script changes, the generated bootloader's config section changes — breaking compatibility with applications compiled against the old version.

> ⚠️ **Cursed aspects:**
> - The bootloader's binary includes the hash of the **script that generated it**
> - Changing the script changes the bootloader's config struct layout/values
> - Apps compiled against one bootloader version may not run on another
> - The build process is recursive and stateful (remembers last build hash)

---

## How It Works

1. `cursed.nim` runs as a **NimScript** (interpreted at build time)
2. It computes its **own MD5 checksum**
3. It generates `generated_bootloader.nim` with that checksum embedded
4. It compiles that generated bootloader for STM32F103
5. It remembers the last build hash — warns if the script changed
6. It also generates `app_stub.nim` as a reference for writing compatible apps

**Result:** The bootloader binary contains a fingerprint of the exact script version that built it.

---

## Requirements

- [Nim](https://nim-lang.org/) compiler (≥ 1.6)
- `arm-none-eabi` toolchain (GCC, objcopy)
- STM32F103 linker script (`stm32f103.ld`)

---

## Build

```bash
nim c -r cursed.nim
```

Or run directly as a script:

```bash
nim e cursed.nim
```

---

## Output

| File | Description |
|------|-------------|
| `generated_bootloader.nim` | Intermediate bootloader source |
| `bootloader.elf` | Bootloader ELF for debugging |
| `bootloader.bin` | Raw binary for flashing |
| `last_build_hash.txt` | Stores last script checksum |
| `app_stub.nim` | Application template with compatibility check |

---

## Memory Map (STM32F103)

| Region | Address | Size |
|--------|---------|------|
| Bootloader | `0x08000000` | 16KB |
| Application | `0x08004000` | ~48KB |

---

## Bootloader Config Section

```nim
type BootConfig = object
  magic: uint32        # 0xDEADBEEF
  version: uint8       # = 2
  checksum: array[16, uint8]  # MD5 of cursed.nim
  app_crc: uint32      # Reserved for app validation
```

---

## Why This Is Cursed

| Property | Normal Bootloader | This Bootloader |
|----------|------------------|-----------------|
| Determinate build | ✅ Same input → same binary | ❌ Binary changes if script changes |
| App compatibility | Fixed ABI | Depends on script checksum |
| Self-reference | ❌ None | ✅ Binary contains script's hash |
| Build reproducibility | ✅ Easy | ❌ Requires matching exact script version |
| Sanity | ✅ High | ❌ Questionable |

---

## When To Use This

**Never in production.** This is a meta-programming horror show, useful for:

- Demoing Nim's compile-time/NimScript capabilities
- Understanding binary-level configuration structs
- Exploring cursed embedded systems patterns
- Confusing your colleagues

---

## License

Unlicense / Do Whatever You Want (but why would you)
