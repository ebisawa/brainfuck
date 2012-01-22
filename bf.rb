#!/usr/bin/env ruby
require 'pp'

# >   Increment the pointer.
# <   Decrement the pointer.
# +   Increment the byte at the pointer.
# -   Decrement the byte at the pointer.
# .   Output the byte at the pointer.
# ,   Input a byte and store it in the byte at the pointer.
# [   Jump forward past the matching ] if the byte at the pointer is zero.
# ]   Jump backward to the matching [ unless the byte at the pointer is zero.

class BfVM
  class VRegs
    attr_accessor :a, :p

    def initialize
      @a = 0; @p = 0
    end
  end

  class VMem
    MAX_SIZE = 30000

    def initialize
      @memory = []
    end

    def get(addr)
      raise "out of memory range" if addr < 0 || addr >= MAX_SIZE
      @memory[addr] = 0 if @memory[addr] == nil
      @memory[addr]
    end

    def set(addr, value)
      raise "out of memory range" if addr < 0 || addr >= MAX_SIZE
      @memory[addr] = value
    end
  end

  def initialize(insts)
    @reg = VRegs.new
    @mem = VMem.new
    @pc = 0
    @insts = insts
  end

  def run
    loop do
      code = @insts[@pc]
      return if code == nil
      self.send("op_#{code[0]}".to_sym, code[1])
      @pc += 1
    end
  end

  private
  def op_ld(opr)
    @reg.a = @mem.get(@reg.p)
  end

  def op_st(opr)
    @mem.set(@reg.p, @reg.a)
  end

  def op_inc(opr)
    case opr
    when :a;  @reg.a += 1
    when :p;  @reg.p += 1
    end
  end

  def op_dec(opr)
    case opr
    when :a;  @reg.a -= 1
    when :p;  @reg.p -= 1
    end
  end

  def op_jmp(opr)
    @pc = opr - 1
  end

  def op_jz(opr)
    @pc = opr - 1 if @mem.get(@reg.p) == 0
  end

  def op_out(opr)
    case opr
    when :a;  v = @reg.a
    when :p;  v = @reg.p
    end

    print v.chr
    STDOUT.flush
  end
end

class BfParser
  BFCMD = {
    '>' => :incp,
    '<' => :decp,
    '+' => :plus,
    '-' => :minus,
    '.' => :output,
    ',' => :input,
    '[' => :loop_begin,
    ']' => :loop_end,
  }

  def initialize(&getproc)
    @getproc = getproc
    @cmds = []; @insts = []

    @loop_begin_addr = nil    
  end 

  def parse
    while (cmd = nextcmd) != nil
      code = BFCMD[cmd]
      parse_cmd(code) if code != nil
    end
    @insts
  end

  private
  def nextcmd
    @cmds = @getproc.call if @cmds.size == 0
    return nil if @cmds == nil
    @cmds.shift
  end

  def parse_cmd(code)
    case code
    when :incp
      @insts << [ :inc,    :p  ]
    when :decp
      @insts << [ :dec,    :p  ]
    when :plus
      @insts << [ :ld,     nil ]
      @insts << [ :inc,    :a  ]
      @insts << [ :st,     nil ]
    when :minus
      @insts << [ :ld,     nil ]
      @insts << [ :dec,    :a  ]
      @insts << [ :st,     nil ]
    when :output
      @insts << [ :ld,     nil ]
      @insts << [ :out,    :a  ]

    when :input
      raise "input is not supported"

    when :loop_begin
      @loop_begin_addr = @insts.size
      @insts << [ :ld,     nil ]
      @insts << [ :jz,     :pending ]

    when :loop_end
      @insts << [ :jmp,    @loop_begin_addr ]

      @loop_begin_addr = nil
      rewrite_loop_end_addr(@insts.size)
    end
  end

  def rewrite_loop_end_addr(end_addr)
    index = @insts.size - 1
    while index > 0
      inst = @insts[index]
      if inst[0] == :jz && inst[1] == :pending
        inst[1] = end_addr
        return
      end
      index -= 1
    end
  end
end

def getcommands
  line = ARGF.gets
  return nil if line == nil
  return line.split(//)
end

parser = BfParser.new { getcommands }
insts = parser.parse

BfVM.new(insts).run
puts ""
