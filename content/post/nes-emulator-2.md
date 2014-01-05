---
title: "Writing an NES emulator in Go, Part 2"
description: "Working out how to start writing an NES emulator, continued"
date: "2014-01-04"
categories: ["programming"]
tags: ["go","emulation"]
slug: "writing-an-nes-emulator-in-go-part-2"
---

I'm writing an NES emulator in Go and writing posts about it as I go
along.  If you haven't read it yet, the first post can be
[found here](/post/writing-an-nes-emulator-in-go-part-1).

## Progress

I've made significant progress on the 6502 code.  All of the
instructions have been implemented and the emulator executes each
instruction in the correct number of cycles, keeping in step with the
external clock signal.  You can look at the code at the GitHub
repository [here](https://github.com/nwidger/65go2).

## Timing

The `Clock` type hasn't changed very much since the first post.

``` go

type Clock struct {
	rate     time.Duration
	ticks    uint64
	ticker   *time.Ticker
	stopChan chan int
	waiting  map[uint64][]chan int
}
```

The major change is that the clock now maintains a `ticks` field which
counts the number of cycles elapsed since the clock was started.  The
clock's `start` method kicks off the `maintainTime` function in a new
goroutine.  The new goroutine performs two functions:

* Increment `ticks` whenever the ticker fires.

* Wake up any other threads waiting for a specific tick to arrive.

``` go
func (clock *Clock) maintainTime() {
	for {
		select {
		case <-clock.stopChan:
			clock.ticker = nil
			return
		case _ = <-clock.ticker.C:
			clock.ticks++

			if Ca, ok := clock.waiting[clock.ticks]; ok {
				for _, C := range Ca {
					C <- 1
				}

				delete(clock.waiting, clock.ticks)
			}
		}
	}
}
```

The `waiting` field maps ticker values to a slice of channels used to
signal other threads waiting for that particular clock tick to arrive
(a slice in Go is an array which grows and shrinks dynamically).

In CPU's `Execute` method, after an opcode executes it returns the
number of cycles to wait for.  We first multiply this by the CPU clock
divisor of twelve (the master clock runs at 21.477272Mhz but the CPU
divides that by twelve to run at 1.789773Mhz) and then wait for this
many cycles past the current tick using the clock's `await` method:

``` go
func (cpu *Cpu) Execute() (cycles uint16, error error) {
	ticks := cpu.clock.ticks

	// fetch
	opcode := OpCode(cpu.memory.fetch(cpu.registers.PC))
	inst, ok := cpu.instructions[opcode]

	if !ok {
		return 0, BadOpCodeError(opcode)
	}

	// execute
	cpu.registers.PC++
	cycles = inst.exec(cpu)

	// count cycles
	cpu.clock.await(ticks + uint64(cycles*cpu.divisor))

	return cycles, nil
}
```

The clock's `await` method is very simple.  If the tick we want hasn't
arrived yet, we append a new buffered channel to the entry in the
`waiting` map for the tick we want and then try to read from the
channel (that's what `<-C` is doing) which will cause us to block.
When `maintainTime` arrives at our tick, it will write an integer into
the channel thus waking us up and allowing us to return to the
`Execute` frame.

``` go
func (clock *Clock) await(tick uint64) uint64 {
	if clock.ticks < tick {
		C := make(chan int, 1)
		clock.waiting[tick] = append(clock.waiting[tick], C)
		<-C
	}

	return clock.ticks
}
```

## Unit Testing in Go

I used Go's unit testing framework to write tests for each
instruction.  Unit testing is provided in Go using the
[testing](http://golang.org/pkg/testing/) package and the
[go test](http://golang.org/cmd/go/#hdr-Test_packages) command.
There's a short explanation about it
[here](http://golang.org/doc/code.html#Testing).  You can take a peek
at the tests
[here](https://github.com/nwidger/65go2/blob/master/instructions_test.go)
if you want.

To test each instruction in my 6502 emulator, I first created a new
file `instructions_test.go` (the `go test` command runs all tests in
files that end with `_test.go`).  For each instruction, I wrote at
least one test as a function with a signature like `func
TestLdaImmediate(t *testing.T)`.  The `go test` command runs all
functions with the signature `func TestXXX(t *testing.T)`.

Since I needed to setup/teardown the CPU and clock for each test, I
wrote a pair of functions to do this:

``` go
package _65go2

import (
	"testing"
	"time"
)

const rate time.Duration = 46 * time.Nanosecond // 21.477272Mhz
const divisor = 12

var cpu *Cpu

func Setup() {
	clock := NewClock(rate)
	cpu = NewCpu(NewBasicMemory(), divisor, clock)
	cpu.Reset()
	go clock.start()
}

func Teardown() {
	cpu.clock.stop()
}
```

Each test function calls `Setup`/`Teardown` at the beginning/end of
each test to ensure everything starts at a well-known state:

``` go
func TestLdaImmediate(t *testing.T) {
	Setup()

	cpu.registers.PC = 0x0100

	cpu.memory.store(0x0100, 0xa9)
	cpu.memory.store(0x0101, 0xff)

	cpu.Execute()

	if cpu.registers.A != 0xff {
		t.Error("Register A is not 0xff")
	}

	Teardown()
}

func TestLdaZeroPage(t *testing.T) {
	Setup()

	cpu.registers.PC = 0x0100

	cpu.memory.store(0x0100, 0xa5)
	cpu.memory.store(0x0101, 0x84)
	cpu.memory.store(0x0084, 0xff)

	cpu.Execute()

	if cpu.registers.A != 0xff {
		t.Error("Register A is not 0xff")
	}

	Teardown()
}
```

Failing a test is easy, just call `t.Error`, passing it a reason
string.

The unit tests ensure a number of things about each instruction:

* The instruction modifies the appropriate memory addresses or
  registers

* The bits of status register `P` are set/cleared correctly

* The instruction executes in the correct number of clock cycles

* Many instructions have multiple opcodes, each using a different
  addressing mode.  There is a test for each opcode to ensure it
  really uses that addressing mode correctly.

All in all there are about 270 tests total.  Whenever I make a change
to the codebase, I can be fairly confident that I haven't broken
anything major by running the unit tests:

``` no-highlight
macros:65go2 nwidger$ go test
PASS
ok  	github.com/nwidger/65go2	0.815s
```

I found the code coverage tool very useful while writing my tests.
This feature works by writing a coverage profile to disk when `go
test` is run.

``` no-highlight
macros:65go2 nwidger$ go test -coverprofile=coverage.out
PASS
coverage: 89.9% of statements
ok  	github.com/nwidger/65go2	0.830s
```

Later, `go tool cover` can use a coverage profile to display coverage
information either as a simple textfile or an HTML page.  The textfile
format is a simple table with percentages for each function:

``` no-highlight
macros:65go2 nwidger$ go tool cover -func=coverage.out
github.com/nwidger/65go2/cpu.go:		absoluteIndexedAddress	100.0%
github.com/nwidger/65go2/cpu.go:		indexedIndirectAddress	100.0%
github.com/nwidger/65go2/cpu.go:		indirectIndexedAddress	100.0%
github.com/nwidger/65go2/cpu.go:		Lda			66.7%
github.com/nwidger/65go2/cpu.go:		Ldx			66.7%
github.com/nwidger/65go2/cpu.go:		Ldy			66.7%
```

The HTML page shows the code coverage of your tests in an extremely
visual manner.

``` no-highlight
go tool cover -html=coverage.out
```

You can see example output of `go tool cover -html` on
[this page](/html/coverage.html).  You can select the file to view
from the pull-down at the top-left of the page.

## Test Programs

I also tried running a
[6502 functional test program](http://2m5.de/6502_Emu/6502_functional_tests.zip)
inside my emulator but kept running into problems.  The documentation
says the `PC` register should be set to `$1000` but after looking at
the test image in a hex editor (thanks
[hexl-mode](https://www.gnu.org/software/emacs/manual/html_node/emacs/Editing-Binary-Files.html))
that location contains an illegal opcode.  Furthermore, after
comparing the assembler file with the assembled binary image, it's
clear that some of the absolute addresses in `JMP` instructions are
off but 4-10 bytes.  Either way, I was unable to get the test program
to run without encountering an illegal opcode and crashing.
Fortunately, I did get it to run enough to at least assure me that the
basic fetch/execute cycle works properly.  I may go back and try to
get a test program running, as it would give me even greater assurance
that everything is implemented correctly.

## Up Next

The next big implementation job is to start implementing the PPU
(Picture Processing Unit) used in the NES, which is a 2C02 chip.  The
PPU has eight registers which are mapped into the CPU's address space
between `$2000` and `$2007`.  I have a feeling I still have a lot of
reading to do before I'll understand how the PPU works enough to start
implementing it.  I'm still on the fence about how to do the memory
mapping, but I have some ideas.
