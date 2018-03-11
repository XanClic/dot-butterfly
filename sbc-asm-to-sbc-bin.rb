#!/usr/bin/ruby

# This script translates SBC (Struct Byte Code) assembly code to its binary
# representation.
#
# Assembly is read from stdin, binary code is written to stdout.

labels = {}
jumps = {}

out = $stdout
$stdin.readlines().each do |line|
    line.strip!
    next if line.empty?

    next if line[0] == '#'

    mnemonic = /^\S+/.match(line)[0]
    args = /\s(.+)$/.match(line)
    args = args[1].strip if args

    if mnemonic[-1] == ':'
        label = mnemonic[0..-2]
        if labels[label]
            $stderr.puts("Label #{label} defined twice")
            exit 1
        end
        labels[label] = out.tell
        next
    end

    case mnemonic
    when 'stop'
        out.write([0x00].pack('C'))

    when 'f2le'
        out.write([0x01, 0x00].pack('CC'))

    when 'f2be'
        out.write([0x01, 0x01].pack('CC'))


    when 'lic'
        if args == '$LOC'
            out.write([0x14].pack('C'))
        else
            out.write([0x10, Integer(args)].pack('CQ<'))
        end

    when 'lfc'
        out.write([0x11, Float(args)].pack('CE'))

    when 'lsc'
        str = eval(args)
        out.write([0x12, str.length].pack('CQ<') + str)

    when 'flu64'
        out.write([0x18, 0x00].pack('CC'))
    when 'fli64'
        out.write([0x18, 0x01].pack('CC'))
    when 'flu32'
        out.write([0x18, 0x02].pack('CC'))
    when 'fli32'
        out.write([0x18, 0x03].pack('CC'))
    when 'flu16'
        out.write([0x18, 0x04].pack('CC'))
    when 'fli16'
        out.write([0x18, 0x05].pack('CC'))
    when 'flu8'
        out.write([0x18, 0x06].pack('CC'))
    when 'fli8'
        out.write([0x18, 0x07].pack('CC'))

    when 'flf64'
        out.write([0x19, 0x00].pack('CC'))
    when 'flf32'
        out.write([0x19, 0x01].pack('CC'))

    when 'flsutf8null'
        out.write([0x1a, 0x00].pack('CC'))
    when 'flsutf8sized'
        out.write([0x1a, 0x01].pack('CC'))
    when 'flsasciinull'
        out.write([0x1a, 0x02].pack('CC'))
    when 'flsasciisized'
        out.write([0x1a, 0x03].pack('CC'))

    when 'sli'
        out.write([0x1c].pack('C'))
    when 'slf'
        out.write([0x1d].pack('C'))
    when 'sls'
        out.write([0x1e].pack('C'))

    when 'osu'
        out.write([0x28, 0x00, Integer(args)].pack('CCC'))
    when 'osi'
        out.write([0x28, 0x01, Integer(args)].pack('CCC'))

    when 'osf'
        out.write([0x29, 0x00].pack('CC'))

    when 'oss'
        out.write([0x2a, 0x00].pack('CC'))

    when 'oh0'
        out.write([0x2b, 0x00].pack('CC'))
    when 'oh1'
        out.write([0x2b, 0x01].pack('CC'))
    when 'oh2'
        out.write([0x2b, 0x02].pack('CC'))
    when 'oh3'
        out.write([0x2b, 0x03].pack('CC'))
    when 'oh4'
        out.write([0x2b, 0x04].pack('CC'))
    when 'oh5'
        out.write([0x2b, 0x05].pack('CC'))
    when 'oh6'
        out.write([0x2b, 0x06].pack('CC'))
    when 'oh7'
        out.write([0x2b, 0x07].pack('CC'))

    when 'ssi'
        out.write([0x2c].pack('C'))

    when 'ssf'
        out.write([0x2d].pack('C'))

    when 'sss'
        out.write([0x2e].pack('C'))


    when 'iswap'
        out.write([0x80].pack('C'))

    when 'idup'
        out.write([0x81].pack('C'))

    when 'idrop'
        out.write([0x82].pack('C'))

    when 'ineg'
        out.write([0x83].pack('C'))

    when 'iadd'
        out.write([0x84].pack('C'))

    when 'iand'
        out.write([0x85].pack('C'))


    when 'jmp'
        jumps[args] = [] unless jumps[args]
        jumps[args] << out.tell

        out.write([0xe0, 0].pack('Cq<'))

    when 'jz'
        jumps[args] = [] unless jumps[args]
        jumps[args] << out.tell

        out.write([0xe1, 0].pack('Cq<'))

    when 'jnz'
        jumps[args] = [] unless jumps[args]
        jumps[args] << out.tell

        out.write([0xe2, 0].pack('Cq<'))

    when 'jnn'
        jumps[args] = [] unless jumps[args]
        jumps[args] << out.tell

        out.write([0xe3, 0].pack('Cq<'))


    when 'panic'
        out.write([0xff].pack('C'))


    else
        $stderr.puts("Unknown instruction #{line}")
        exit 1
    end
end


jumps.each do |label, positions|
    if !labels[label]
        $stderr.puts("Label #{label} undefined")
        exit 1
    end

    positions.each do |position|
        out.seek(position + 1)
        out.write([labels[label] - position].pack('q<'))
    end
end
