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
      self.send("op_#{code[0]}".to_sym, code[1], code[2])
      @pc += 1
    end
  end

  private
  def op_ld(opr1, opr2)
    @reg.a = @mem.get(@reg.p)
  end

  def op_st(opr1, opr2)
    @mem.set(@reg.p, @reg.a)
  end

  def op_inc(opr1, opr3)
    case opr1
    when :a;  @reg.a += 1
    when :p;  @reg.p += 1
    end
  end

  def op_dec(opr1, opr2)
    case opr1
    when :a;  @reg.a -= 1
    when :p;  @reg.p -= 1
    end
  end

  def op_add(opr1, opr2)
    case opr1
    when :a;  @reg.a += opr2
    when :p;  @reg.p += opr2
    end
  end

  def op_sub(opr1, opr2)
    case opr1
    when :a;  @reg.a -= opr2
    when :p;  @reg.p -= opr2
    end
  end

  def op_jmp(opr1, opr2)
    @pc = opr1 - 1
  end

  def op_jz(opr1, opr2)
    @pc = opr1 - 1 if @reg.a == 0
  end

  def op_out(opr1, opr2)
    case opr1
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

  class LoopManager
    def initialize
      @count = 0
    end

    def newloop
      @count += 1
    end

    def begin_label
      "loop_begin_#{@count}"
    end

    def end_label
      "loop_end_#{@count}"
    end
  end

  def initialize(&getproc)
    @loop = LoopManager.new
    @getproc = getproc
    @cmds = []; @insts = []
  end 

  def parse
    while (cmd = nextcmd) != nil
      code = BFCMD[cmd]
      parse_cmd(code) if code != nil
    end
    resolve_label(optimize(@insts))
  end

  def optimize(inputs)
    do_optimize(do_optimize(inputs))
  end

  def do_optimize(inputs)
    def optld(inputs, index)
      inst0 = inputs[index]

      if inst0[0] == :ld
        i = 1
        loop do
          if (instx = inputs[index + i]) != nil
            break if instx[0] == :ld
            break if instx[0] == :jmp || instx[0] == :jz
            return if instx[1] == :a
          end
          i += 1
        end
        inst0[0] = :label
        inst0[1] = :nop
      end
    end

    def optseq(inputs, index, op, rop)
      inst0 = inputs[index]; opr = inst0[1]

      if inst0[0] == op
        i = 1
        loop do
          if (instx = inputs[index + i]) != nil
            break if instx[0] != op || instx[1] != opr
            instx[0] = :label
            instx[1] = :nop
          end
          i += 1
        end

        if i > 1
          inst0[0] = rop
          inst0[2] = i
        end
      end
    end

    inputs.each_with_index do |inst0, index|
      inst1 = inputs[index + 1]
      inst2 = inputs[index + 2]

      if inst1 != nil
        if inst0[0] == :ld && inst1[0] == :st
          inst1[0] = :label; inst1[1] = :nop
        end

        if inst0[0] == :st && inst1[0] == :ld
          inst0[0] = :label; inst0[1] = :nop
          inst1[0] = :label; inst1[1] = :nop
        end
      end

      optld(inputs, index)
      optseq(inputs, index, :inc, :add)
      optseq(inputs, index, :dec, :sub)
    end

    inputs.delete_if {|x| x[1] == :nop }
    inputs
  end

  def resolve_label(inputs)
    label_pos = {}

    index = 0
    while index < inputs.size
      inst = inputs[index]
      if inst[0] == :label
        label_pos[inst[1]] = index
        inputs.delete_at(index)
      else
        index += 1
      end
    end

    inputs.each do |inst|
      case inst[0]
      when :jmp, :jz
        pos = label_pos[inst[1]]
        inst[1] = pos
      end
    end
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
      @insts << [ :st,     nil ]
      @insts << [ :inc,    :p  ]
      @insts << [ :ld,     nil ]
    when :decp
      @insts << [ :st,     nil ]
      @insts << [ :dec,    :p  ]
      @insts << [ :ld,     nil ]
    when :plus
      @insts << [ :inc,    :a  ]
    when :minus
      @insts << [ :dec,    :a  ]
    when :output
      @insts << [ :out,    :a  ]

    when :input
      raise "input is not supported"

    when :loop_begin
      @loop.newloop
      @insts << [ :label,  @loop.begin_label ]
      @insts << [ :jz,     @loop.end_label ]

    when :loop_end
      @insts << [ :jmp,    @loop.begin_label ]
      @insts << [ :label,  @loop.end_label ]
    end
  end
end

def getcommands
  line = ARGF.gets
  return nil if line == nil
  return line.split(//)
end

def dump_insts(insts)
  insts.each_with_index do |inst, addr|
    printf("%4u   ", addr); p inst
  end
  puts ""
end

parser = BfParser.new { getcommands }
insts = parser.parse

dump_insts(insts)

BfVM.new(insts).run
puts ""
