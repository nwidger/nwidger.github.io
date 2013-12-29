---
title: "Writing an NES emulator in Go, Part 1"
description: "Working out how to start writing an NES emulator"
date: "2013-12-28"
categories: ["programming"]
tags: ["go","emulation"]
slug: "writing-an-nes-emulator-in-go-part-1"
---

## Motivation

I've decided to write my own NES emulator in Go.  I know that many,
many NES emulators have been written over the years
([at least one](https://github.com/scottferg/Fergulator/) written in
Go), but I've always wanted to try writing my own emulator after using
them for many years.  Plus it gives me a good reason to program in Go
some more.  I plan to do a post every so often as the emulator
progresses.  Hopefully I don't lose interest half-way through!  I'll
be putting the source code for the project up on
[this GitHub](https://github.com/nwidger/65go2) repository.

## Architecture

My first task is to write a simulator for the CPU used by the NES, the
MOS 6502.  The 6502 chip used in the NTSC NES runs at 1.789773Mhz, or
1,789,773 cycles per second.  The NES's 6502 does not support decimal
mode, meaning a few instructions don't need to be supported which is
goood.

The MOS 6502 is an 8-bit processor with 16-bit addresses
(little-endian, so it expects the least significant byte of each
16-bit address to be stored first in memory).  It has no I/O lines, so
any I/O registers must be mapped into the 16-bit address space.  A
full listing of the 6502's instruction set can be found
[here](http://www.obelisk.demon.co.uk/6502/registers.html) and
[here](http://www.6502.org/tutorials/6502opcodes.html).

## Registers

All registers are 8-bit unless otherwise noted.

* Accumulator (`A`) - The `A` register is used for all arithmetic and
  logic instructions.

* Index Register 1 & 2 (`X` & `Y`) - Registers `X` and `Y` are used
  for indirect addressing and also as counters/indexes.  `X` is used
  by certain instructions to save/restore the value of `P` using the
  stack.

* Stack Pointer (`SP`) - Stores the least-significant byte of the top
  of the stack.  The 6502's stack is hardwired to occupy `$0100` -
  `$01ff` with `SP` initalized to `$ff` at power-up.  If the value of
  `SP` is `$84` then the top of the stack is located at `$0184`.  The
  top of the stack moves downward in memory as values are pushed and
  upward as values are popped.

* Program Counter (`PC`) - The only 16-bit register on the 6502, `PC`
  points to the next instruction to execute.

* Processor Status (`P`) - The bits in `P` indicate the results of the
  last arithmetic and logic instructions as well as indicate if a
  break/interrupt instruction has just been executed.
  
    * Bit 0 - Carry Flag (`C`)
    * Bit 1 - Zero Flag (`Z`)
    * Bit 2 - Interrupt Disable (`I`)
    * Bit 3 - Decimal Mode (`D`)
    * Bit 4 - Break Command (`B`)
    * Bit 5 - -UNUSED-
    * Bit 6 - Overflow Flag (`O`)
    * Bit 7 - Negative Flag (`N`)

More information on the 6502's registers can be found
[here](http://www.obelisk.demon.co.uk/6502/registers.html).

## Memory Map

The 6502's memory layout is very simple.

* `$0000` - `$00ff` - Used by zero page addressing instructions.
   Instructions using zero page addressing only require an 8-bit
   address parameter.  The most-signficant 8-bits of the address are
   assumed to be `$00`.  This is done to save memory since the address
   requires half the space.

* `$0100` - `$01ff` - Reserved for the system stack.

* `$0200` - `$fff9` - Unspecified

* `fff$a` - `$fffb` - Contains address of non-maskable interrupt (NMI) handler

* `$fffc` - `$fffd` - Contains address of reset location

* `$fffe` - `$ffff` - Contains address of BRK/IRQ handler

## Implementation

Implementing the CPU is simply a matter of creating a representation
of the CPU's internals and input/output lines and then writing
functions which implement the 6502's instruction set.

### Memory

Memory can simply be a 65,536 (16-bit address bus, so `2^16`
addresses) element `uint8` array.  Reads/writes to memory merely get
and set elements in the array.  For now I will use a very simple
`BasicMemory` type to emulate the 6502's RAM:

``` go
type Memory interface {
	reset()
	fetch(address uint16) (value uint8)
	store(address uint16, value uint8) (oldValue uint8)
}

type BasicMemory [65536]uint8
```

In order to handle the memory mapping done by the NES, I will need to
create an `NESMemory` type which implements the `Memory` interface but
whose `fetch` and `store` functions understand the NES's memory
layout.  Specifically, a number of memory ranges are either mirrored
to other memory ranges, memory mapped to registers of the PPU (Picture
Processing Unit) and APU (Audio Processing Unit), or mapped to the
actual NES cartridge.  See
[here](http://wiki.nesdev.com/w/index.php/CPU_memory_map) for details.

### CPU

The `Cpu` type stores the 6502's registers and instruction table as
well as a clock input and a link off to memory:

``` go
type Status uint8

const (
	C Status = 1 << iota // carry flag
	Z                    // zero flag
	I                    // interrupt disable
	D                    // decimal mode
	B                    // break command
	_                    // -UNUSED-
	V                    // overflow flag
	N                    // negative flag
)

type Registers struct {
	A  uint8  // accumulator
	X  uint8  // index register X
	Y  uint8  // index register Y
	P  Status // processor status
	SP uint8  // stack pointer
	PC uint16 // program counter
}

type Cpu struct {
	clock        Clock
	registers    Registers
	memory       Memory
	instructions InstructionTable
}
```

### Fetch/Execute Cycle

The fetch/execute cycle of the emulator fetches the instruction at the
address stored in the `PC` register, looks up the opcode in its
instruction table and then executes it.  Each instruction should be in
charge of modifying the stack/registers/memory appropriately as well
as incrementing the `PC` register appropriately for the number of
parameters (or using the value of the parameters, in the case of
branching instructions).  Each instruction also needs to determine how
many clock cycles it should use up, since some instructions take
different number of clock cycles depending on their parameters.

``` go
func (cpu *Cpu) Execute() {
	// fetch
	opcode := OpCode(cpu.memory.fetch(cpu.registers.PC))
	inst, ok := cpu.instructions[opcode]

	if !ok {
		fmt.Printf("No such opcode 0x%x\n", opcode)
		os.Exit(1)
	}

	// execute, exec() returns number of cycles
	cycles := inst.exec(cpu)

	// count cycles
	for _ = range cpu.clock.ticker.C {
		cycles--

		if cycles == 0 {
			break
		}
	}
}
```

### Clock

One tricky point in the implementation is going to be timing.  For the
6502 to interact properly with other components of the NES such as the
PPU and APU, it must execute instructions in a specific amount of time
and stay in sync with the master clock.  According to the 6502
specification, each instruction takes a deterministic number of clock
cycles to execute.  Since it can probably be taken for granted that a
modern machine will be able to execute each instruction faster than a
real 6502 chip, the emulator will need to throttle the CPU to ensure
it does not execute too quickly.  I plan to look into Go's
[time](http://golang.org/pkg/time/) package, specifically the Ticker
data type, to implement the clock signal used by the 6502.  This is
definitely the part I'm worried about the most.

## Up Next

I have the basic architecture written, but so far I've only
implemented the `LDA` instruction.  After implementing the rest of the
instruction set I will need to write a number of unit tests to ensure
everything is working properly.  This should give me a chance to try
out Go's
[unit testing framework](http://golang.org/doc/code.html#Testing),
specifically Go 1.2's new
[test coverage](http://golang.org/doc/go1.2#cover) features (here's a
great [blog post](http://blog.golang.org/cover) about the feature).

## Resources

I've been using the following sites to help in implementing the 6502
and learn about the internals of the NES.

* [NESDev Wiki](http://wiki.nesdev.com/)
* [6502.org NMOS 6502 Opcodes](http://www.6502.org/tutorials/6502opcodes.html)
* [6502 Introduction](http://www.obelisk.demon.co.uk/6502/index.html)
