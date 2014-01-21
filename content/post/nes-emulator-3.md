---
title: "Writing an NES emulator in Go, Part 3"
description: "Working out how to start writing an NES emulator, continued"
date: "2014-01-20"
categories: ["programming"]
tags: ["go","emulation"]
slug: "writing-an-nes-emulator-in-go-part-3"
---

I'm writing an NES emulator in Go and writing posts about it as I go
along.  If you haven't read them yet, go check out the
[first](/post/writing-an-nes-emulator-in-go-part-1) and
[second](/post/writing-an-nes-emulator-in-go-part-2) post.

## Package Layout

I've been trying to implement each major NES component as a reuseable
module.  Each module is stored in a separate GitHub repository.
Here's the layout I'm using right now:

* `m65go2` - [GitHub](https://github.com/nwidger/m65go2/) - The
  MOS 6502 CPU.  Defines the `M6502` type.

* `rp2ago3` - [GitHub](https://github.com/nwidger/rp2ago3/) - The
  RP2A03 CPU (a MOS 6502 chip plus an APU) used in the NES.  Embeds an
  `M6502` instance from the `m65go2` package along with a new `APU`
  type to form a new `RP2A03` type.

* `rp2cgo2` - [GitHub](https://github.com/nwidger/rp2cgo2/) - The
  RP2C02 PPU used in the NES.

Once everything is implemented, I will create a fourth package called
something clever like `nintengo` which combines `RP2A03` and `RP2C02`
instances to form a full NES.

Here's a diagram for how it all fits together:

``` no-highlight
+---------------------+
|       RP2A03     	  |
| +-------+ +-------+ |
| | M6502 | |  APU  | |
| +-------+ +-------+ |
+---------------------+
                |
               /
---Clock------*
21.477272Mhz   \
                |
+---------------------+
|                  	  |
|       RP2C02        |
|                     |
+---------------------+
```

## Clock Divisors

The `rp2ago3` package must divide the 21.477272Mhz external clock
signal by twelve internally to produce the 1.789773Mhz signal used by
the M6502/APU chips.  To do this, I created a `Clocker` interface
which implements the methods of `Clock`, the basic clock type I
created for the `m65go2` package:

``` go
// Represents a clock signal for an IC.  Once a Clock is started, it
// maintains a 'ticks' counters which is incremented at a specific
// interval.
type Clocker interface {
	// Returns the current value of the Clocker's ticks counter.
	Ticks() uint64

	// Starts the clock
	Start() (ticks uint64)

	// Stops the clock
	Stop()

	// Blocks the calling thread until the given tick has arrived.
	// Returns immediately if the clock has already passed the
	// given tick.
	Await(tick uint64) (ticks uint64)
}
```

Obviously, the base `Clock` type implements this interface.  Next, I
created a `Divider` type which gets passed a `Clocker` instance and
divisor on creation:

``` go
// Returns a pointer to a new DividerCLock which divides the tick rate
// of 'master' Clocker by 'divisor'.
func NewDivider(master Clocker, divisor uint64) *Divider {
	return &Divider{divisor: divisor, master: master}
}
```

`Divider` implements its own version of `Start`, `Stop` and `Await`
which use the base clock but ensure the module using a `Divider` will
only see a tick after every Nth tick from the base clock:

``` go
func (clock *Divider) Ticks() uint64 {
	return clock.master.Ticks() / clock.divisor
}

func (clock *Divider) Start() (ticks uint64) {
	return clock.master.Start() / clock.divisor
}

func (clock *Divider) Stop() {
	clock.master.Stop()
}

func (clock *Divider) Await(tick uint64) (ticks uint64) {
	return clock.master.Await(tick*clock.divisor) / clock.divisor
}
```

When I create a new `RP2A03` instance, I create a `Divider` instance
to divide the base clock passed into `NewRP2A03`:

``` go
func NewRP2A03(mem *MappedMemory, clock m65go2.Clocker, divisor uint64) *RP2A03 {
    ...
	divider := m65go2.NewDivider(clock, divisor)
	cpu := m65go2.NewM6502(mem, divider)
	apu := NewAPU(divider)
	...
	return &RP2A03{memory: mem, M6502: cpu, APU: apu, clock: divider}
}
```

## Memory Maps

I struggled for a while trying to figure how best to implement the
memory mapped I/O used on the NES.  Since the MOS 6502 has no I/O
lines into it, both the APU and PPU must map their internal registers
into the 6502's address space.  The solution I wound up using is very
simple, but seems to be working so far.

The `m65go2` package defines the `Memory` interface:

``` go
// Represents the RAM memory available to the 6502 CPU.  Stores 8-bit
// values using a 16-bit address for a total of 65,536 possible 8-bit
// values.
type Memory interface {
	Reset()                                             // Sets all memory locations to zero
	Fetch(address uint16) (value uint8)                 // Returns the value stored at the given memory address
	Store(address uint16, value uint8) (oldValue uint8) // Stores the value at the given memory address
}
```

The `rp2ago3` package defines the `MappedMemory` type which implements
the `Memory` interface:

``` go
type MappedMemory struct {
	maps map[uint16]m65go2.Memory
	m65go2.Memory
}
```

The second field `m65go2.Memory` does not have a name since it is an
"anonymous" or "embedded" field in Go parlance.  When a field is
declared without a name it is "embedded" meaning the new type
automatically gains the functions implemented by the embedded type
without the tedium of having to add a bunch of wrapper methods like
this:

``` go
func (parent MyParentType) myFunction() {
        parent.embeddedField.myFunction()
}
```

Since Go provides interfaces but not classes with the ability to
extend an existing class, embedding gets you halfway there by letting
you create a new type that automatically implements all methods (and
therefore all interfaces) provided by the embedded type.

Anyways, the `maps` field in the `MappedMemory` struct stores the
addresses in memory which are mapped elsewhere.  For each mapped
address, we store a `Memory` instance.  When `Fetch` or `Store` is
called on the `MappedMemory` instance, we first check if the address
is mapped to another `Memory` instance and pass it off, otherwise we
call the appropriate method of the embedded `Memory` instance:

``` go
func (mem *MappedMemory) Fetch(address uint16) (value uint8) {
	if mmap, ok := mem.maps[address]; ok {
		return mmap.Fetch(address)
	}

	return mem.Memory.Fetch(address)
}

func (mem *MappedMemory) Store(address uint16, value uint8) (oldValue uint8) {
	if mmap, ok := mem.maps[address]; ok {
		return mmap.Store(address, value)
	}

	return mem.Memory.Store(address, value)
}
```

The end result is that when I create a new `RP2A03` CPU instance, I
can map the APU's registers to the appropriate addresses in memory:

``` go
func NewRP2A03(mem *MappedMemory, clock m65go2.Clocker, divisor uint64) *RP2A03 {
    ...
	apu := NewAPU(divider)

	// APU memory maps
	mem.AddMap([]uint16{
		0x4000, 0x4001, 0x4002, 0x4003, 0x4004,
		0x4005, 0x4006, 0x4007, 0x4008, 0x400a,
		0x400b, 0x400c, 0x400e, 0x400f, 0x4010,
		0x4011, 0x4012, 0x4013, 0x4015, 0x4017,
	}, apu)

	return &RP2A03{memory: mem, M6502: cpu, APU: apu, clock: divider}
}
```

Now, any `Fetch` or `Store` calls for those addresses will be
redirected to the `Fetch` or `Store` methods implemented by `APU`.
These methods know which addresses map to which registers,
i.e. `0x4000-0x4003` maps to the pulse 1 channel registers.

## Package Visibility

When I initially began work on the emulator, I had a single Go
package.  Now that there are three separate packages I need to put
more thought into what fields/symbols of a package are exported.  In
Go, only exported fields/symbols are visible outside of a package.  Go
really only has
[one rule](http://golang.org/ref/spec#Exported_identifiers) that
determines what gets exported: capitalize it.

``` go
type notExportedType struct { } // not exported
type ExportedType struct { }    // exported

type OtherExportedType struct {
        ExportedInt     int     // exported
		notExportedBool bool    // not exported
}

func notExportedFunc() { }      // not exported
func ExportedFunction() { }     // exported
```

I spent some time going through the types I had created and modifying
their fields/methods to be exported where I deemed appropriate.  Some
obvious ones were exporting `M6502`'s `Register` and `Memory` fields,
since an external program trying to use the module would probably find
it convenient to actually be able to read/write the CPU's registers
and access its memory.

## Decimal Mode

I'm not sure why I felt the need to add decimal mode support to the
`m65go2` package, but I added it for completeness anyways.  The MOS
6502 supported an alternative form of addition/subtraction for the
`ADC` (addition with carry) and `SBC` (subtraction with carry)
instructions in which arguments are expected to be in packed binary
coded decimal (BCD) form instead of the normal one's compliment
representation.

Under normal binary arithmetic, you would expect to get results like
this:

``` no-hightlight
0x45 + 0x25 = 0x6a
```

whereas if you're in decimal mode and using BCD values, you get
results like this:

``` no-hightlight
0x45 + 0x25 = 0x70
```

In decimal mode, the CPU interprets each argument as a byte
representing a two digit number in base ten, where each digit is
stored using 4-bits.

I referenced [lib6502](http://www.piumarta.com/software/lib6502/)'s
implementation of BCD arithmetic and relied on it pretty heavily to
get things working.  Of course, there are probably plenty of bugs
remaining.  But it doesn't matter too much since the RP2A03 CPU used
in the NES didn't support decimal mode, apparently to
[avoid patent payments](https://en.wikipedia.org/wiki/Nintendo_Entertainment_System_technical_specifications#Central_processing_unit).

## NES Test ROM

In one of the previous posts I lamented not being able to get a test
ROM running in my emulator.  I persevered and did eventually get the
`nestest` test program from
[this page](http://wiki.nesdev.com/w/index.php/Emulator_tests) to run.
I added it to the `m65go2` repository along with the expected output
and
[this text file](https://github.com/nwidger/m65go2/blob/master/test-roms/nestest.txt).
From the file:

``` no-highlight
This here is a pretty much all inclusive test suite for a NES CPU.
It was designed to test almost every combination of flags, instructions,
and registers. Some of these tests are very difficult, and so far,
Nesten and Nesticle failed it. Nintendulator passes, as does a real
NES (naturally). I haven't tested it with any more emualtors yet.
```

The only issue in using the test program was the question of how to
validate it.  The file comes with
[the expected debug output from Nintendulator](https://github.com/nwidger/m65go2/blob/master/test-roms/nestest.log),
but it would be incredibly tedious to go through line by line and make
sure my emulator places the same values in memory and modifies each
register correctly for each instruction.  How can I integrate this
test program into the rest of my `go test` unit tests?  The road I
went down was replicating the debug output inside my emulator to match
what Nintendulator produces.  For each instruction, Nintendulator
prints a line like this:

``` no-highlight
*- instruction address (PC register)
|
|     *- opcode + args
|     |
|     |         *- mneumonic + decoded args
|     |         |
|     |         |                               *- pre-execution registers
|     |         |                               |
C000  4C F5 C5  JMP $C5F5                       A:00 X:00 Y:00 P:24 SP:FD
```

After perhaps three days of work the emulator now produces the same
output as Nintendulator, passes each test and implements all of the
unofficial opcodes tested by the program.  In go, an "example" test
function can be associated with an expected output that `go test` will
verify when running the test.  I created an example test which runs
the test program and put the Nintendulator log contents as the
expected output.

``` go
func ExampleRom() {
	Setup()

	cpu.DisableDecimalMode()

	cpu.Registers.P = 0x24
	cpu.Registers.SP = 0xfd
	cpu.Registers.PC = 0xc000

	cpu.Memory.(*BasicMemory).load("test-roms/nestest.nes")

	cpu.Memory.Store(0x4004, 0xff)
	cpu.Memory.Store(0x4005, 0xff)
	cpu.Memory.Store(0x4006, 0xff)
	cpu.Memory.Store(0x4007, 0xff)
	cpu.Memory.Store(0x4015, 0xff)

	cpu.decode.enabled = true

	cpu.Run()

	Teardown()

	// Output:
	// C000  4C F5 C5  JMP $C5F5                       A:00 X:00 Y:00 P:24 SP:FD
	// C5F5  A2 00     LDX #$00                        A:00 X:00 Y:00 P:24 SP:FD
	// C5F7  86 00     STX $00 = 00                    A:00 X:00 Y:00 P:26 SP:FD
	// C5F9  86 10     STX $10 = 00                    A:00 X:00 Y:00 P:26 SP:FD
	// C5FB  86 11     STX $11 = 00                    A:00 X:00 Y:00 P:26 SP:FD
	// C5FD  20 2D C7  JSR $C72D                       A:00 X:00 Y:00 P:26 SP:FD
	...
}
```

All the work was definitely worth as it makes me much more confident
that most things are implemented correctly.

## Up Next

Now that the CPU has been fairly well tested, it's time to move on.  I
still need to implement the RP2C02, the PPU used in the NES, so that
will be my next step.
