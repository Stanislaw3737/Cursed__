# Cursed Bootloader in Nim
import std/os
import std/strutils
import std/crc
import std/md5
import std/sequtils

# These run at NimScript interpret-time, not compile-time of the bootloader
let scriptPath = currentSourcePath()
let scriptContent = readFile(scriptPath)
let scriptChecksum = getMD5(scriptContent)

echo "[META] Building bootloader with checksum: ", scriptChecksum

# Generate bootloader source dynamically
proc generateBootloader(checksum: string): string = result = """
# Generated Bootloader - DO NOT EDIT DIRECTLY
# Source checksum: """ & checksum & """

import std/bitops
import std/strformat

# Memory map (adjust for your STM32)
const
  APP_START = 0x08004000
  BOOTLOADER_SIZE = 0x4000  # 16KB
  FLASH_BASE = 0x08000000

type
  BootConfig = object
    magic: uint32
    version: uint8
    checksum: array[16, uint8]
    app_crc: uint32

var config {.section: ".boot_config".}: BootConfig

proc initBootloader() =
  config.magic = 0xDEADBEEF
  config.version = 2
  for i in 0..15:
    config.checksum[i] = uint8(""" & $checksum.bytes().mapIt(it.ord).join(", ") & """[i])

proc verifyApplication(): bool =
  # Scan application region for valid stack pointer
  let sp = cast[ptr uint32](APP_START)[]
  let pc = cast[ptr uint32](APP_START + 4)[]
  
  result = (sp != 0) and ((pc and 0xFFF00000) == 0x20000000)

proc jumpToApplication() {.noinit, inline.} =
  let jumpAddr = (APP_START + 4).uint32
  let resetHandler = cast[proc(){.noreturn.}](jumpAddr)
  
  # Set stack pointer
  asm """
    ldr r0, [%0]
    mov sp, r0
  """ : [ "r" ](APP_START)
  
  resetHandler()

proc bootConfigChecksum(): uint32 =
  # CRC of the bootloader's config section
  var crc = 0xFFFFFFFF'u32
  let configPtr = cast[ptr uint32](addr config)
  for i in 0..<(sizeof(BootConfig) div 4):
    crc = crc xor configPtr[i]
    crc = crc xor (crc shl 16)
  return crc

proc main() {.exportc.} =
  initBootloader()
  
  echo "[Bootloader] Starting..."
  echo fmt"[Bootloader] Config checksum: {bootConfigChecksum():#x}"
  
  if verifyApplication():
    echo "[Bootloader] Valid app found, jumping..."
    jumpToApplication()
  else:
    echo "[Bootloader] No valid app, waiting for flash..."
    # UART receive logic here (truncated for sanity)
    while true:
      discard

when isMainModule:
  main()
"""

# Write the generated bootloader
let bootloaderPath = "generated_bootloader.nim"
writeFile(bootloaderPath, generateBootloader(scriptChecksum))
echo "[META] Generated bootloader: ", bootloaderPath

# Now compile it for STM32F103 (blue pill)
let compileCmd = "nim c -c --os:standalone --cpu:arm --gc:none " &
                 "--passC:-mthumb -mcpu=cortex-m3 " &
                 "--passL:-T stm32f103.ld " &
                 "-o:bootloader.elf " & bootloaderPath

echo "[META] Compiling: ", compileCmd
let ret = execCmdEx(compileCmd)

if ret.exitCode == 0:
  echo "[META] Success! Bootloader at bootloader.elf"
  echo "[META] Script checksum embedded in binary"
  
  # Optional: Convert to raw binary
  discard execCmdEx("arm-none-eabi-objcopy -O binary bootloader.elf bootloader.bin")
  echo "[META] Binary size: ", getFileSize("bootloader.bin"), " bytes"
  
  # The true cursed part - check if script changed vs last build
  if fileExists("last_build_hash.txt"):
    let lastHash = readFile("last_build_hash.txt").strip()
    if lastHash != scriptChecksum:
      echo "[META] [-] Script changed! Bootloader hash mismatch."
      echo "[META] Old: ", lastHash
      echo "[META] New: ", scriptChecksum
      echo "[META] Consider reflashing bootloader!"
  else:
    echo "[META] First build - no previous hash"
  
  writeFile("last_build_hash.txt", scriptChecksum)
else:
  echo "[META] Build failed: ", ret.output
  quit(1)

# Now the truly recursive part - if this script changed,
# the bootloader will refuse to jump to apps compiled
# with mismatched config sections

proc generateAppStub(): string = 
  # Generates application code that validates against the bootloader
  return """
# App stub that checks it's running with correct bootloader
import std/strformat

type BootConfig = object
  magic: uint32
  version: uint8
  checksum: array[16, uint8]
  app_crc: uint32

let bootloaderConfig {.importc: "config", nodecl.}: ptr BootConfig

proc main() {.exportc.} =
  if bootloaderConfig.magic != 0xDEADBEEF:
    while true: 
      discard  # Wrong bootloader, hang
  
  echo fmt"Running with bootloader version {bootloaderConfig.version}"
  
  # Your actual app here
  while true:
    asm """"nop"""
"""

# Write app stub for reference
writeFile("app_stub.nim", generateAppStub())
echo "[META] Generated app_stub.nim as reference"
