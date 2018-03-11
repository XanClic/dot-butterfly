#!/usr/bin/ruby

# I have forgotten what 'pc' stands for (pseudo-C maybe?), but 'sbc' stands for
# "Struct Byte Code".
#
# So this script translates some extremely simple language that looks a bit like
# C into SBC assembly.
#
# Code is read from stdin, assembly is written to stdout; this file takes one
# file argument which describes more complex parts of the language syntax in
# BNF.


def die(msg)
    $stderr.puts(msg)
    exit 1
end


desc = ARGV[0]

desc = IO.readlines(desc).map { |l|
    l.strip
}.reject { |l|
    l.empty?
}.map { |l|
    res = l.split(/\s+:=\s+/)
    res[1] = res[1].split(' ').map { |p|
        if p[0] == "'"
            [:string, eval(p)]
        else
            [:symbol, p]
        end
    }

    res
}

desc_hash = {}
desc.each do |d|
    desc_hash[d[0]] = [] unless desc_hash[d[0]]
    desc_hash[d[0]] << d[1]
end

def syntax_apply_statement(desc, symbol, statement)
    if symbol == 'IDENTIFIER'
        match = /^[a-zA-Z_][a-zA-Z_0-9.]*/.match(statement)
        if !match
            return nil
        end
        id = match[0]
        return [['IDENTIFIER', id], statement[id.length..-1]]
    elsif symbol == 'ICONSTANT'
        match = /^(0x[0-9a-fA-F]+|[0-9]+)/.match(statement)
        if !match
            return nil
        end
        c = match[0]
        return [['ICONSTANT', c], statement[c.length..-1]]
    elsif symbol == 'FCONSTANT'
        match = /^[0-9]*\.[0-9]*(e[+-]?[0-9]+)?/.match(statement)
        if !match
            return nil
        end
        c = match[0]
        return [['FCONSTANT', c], statement[c.length..-1]]
    elsif symbol == 'SCONSTANT'
        if statement[0] != '"'
            return nil
        end
        i = 1
        while statement[i]
            if statement[i] == '\\'
                i += 1
            elsif statement[i] == '"'
                break
            end
            i += 1
        end
        if !statement[i]
            return nil
        end
        return [['SCONSTANT', statement[0..i]], statement[i+1..-1]]
    elsif symbol == 'BLOCK'
        return [['BLOCK'], statement]
    elsif symbol == 'MERGE_BLOCK'
        return [['MERGE_BLOCK'], statement]
    end

    if !desc[symbol]
        die("Undefined symbol #{symbol}")
    end

    desc[symbol].each do |way|
        lstatement = statement.dup
        match = true

        res = [symbol]

        way.each do |element|
            if element[0] == :string
                if lstatement.start_with?(element[1])
                    lstatement = lstatement[element[1].length..-1].strip
                else
                    match = false
                    break
                end
            elsif element[0] == :symbol
                subtree, lstatement = syntax_apply_statement(desc, element[1], lstatement)
                if !subtree
                    match = false
                    break
                end
                lstatement.strip!
                res << subtree
            else
                die("Unknown element type #{element[0]}")
            end
        end

        if match
            return [res, lstatement]
        end
    end

    return nil
end

def fill_in_block(tree, symbol, block)
    tree.each do |subtree|
        if subtree[0] == symbol && subtree.length == 1
            subtree[1] = block
            return true
        end
    end
    tree.each do |subtree|
        if subtree.kind_of?(Array)
            if fill_in_block(subtree, symbol, block)
                return true
            end
        end
    end
    return false
end

def syntax_apply(desc, pp_src)
    tree = []

    last_was_block = false

    i = 0
    while i < pp_src.length
        if pp_src[i].kind_of?(Array)
            die('Block without prefix is not allowed')
        end
        if !pp_src[i].kind_of?(String)
            die('Internal error')
        end
        if pp_src[i + 1].kind_of?(Array)
            line = pp_src[i].strip

            merge_block = last_was_block
            if merge_block
                subtree, post = syntax_apply_statement(desc, 'PRE_MERGE_BLOCK',
                                                       line)
                if !subtree || !post.empty?
                    merge_block = false
                end
            end
            if !merge_block
                subtree, post = syntax_apply_statement(desc, 'PRE_BLOCK', line)
                if !subtree || !post.empty?
                    die("Syntax error (pre-block): #{line}")
                end
            end
            block = syntax_apply(desc, pp_src[i + 1])
            if !block
                die("Syntax error in block after: #{line}")
            end
            if !fill_in_block(subtree, 'BLOCK', block)
                die("Could not find BLOCK rule for: #{line}")
            end
            if merge_block
                if !fill_in_block(tree[-1], 'MERGE_BLOCK', subtree)
                    die("Could not find MERGE_BLOCK rule before: #{line}")
                end
            else
                tree << subtree
            end

            last_was_block = true
            i += 2
        else
            line = pp_src[i].strip
            if line.empty?
                i += 1
                next
            end
            subtree, post = syntax_apply_statement(desc, 'STATEMENT', line)
            if !subtree || !post.empty?
                die("Syntax error (statement): “#{line}")
            end
            tree << subtree

            last_was_block = false
            i += 1
        end
    end

    return tree
end

$counter = 0
$vars = {}
$varcounter = {
    integer: 0,
    float: 0,
    string: 0
}

def transform_function(name, params)
    case name
    when 'oh0', 'oh1', 'oh2', 'oh3', 'oh4', 'oh5', 'oh6', 'oh7'
        if params.length != 1
            die("Invalid usage: #{name}(name: string)")
        end
        params[0] + [name]
    when 'fli8', 'flu8', 'fli16', 'flu16', 'fli32', 'flu32', 'fli64', 'flu64', 'flsutf8null', 'flsasciinull'
        if params.length != 1
            die("Invalid usage: #{name}(position: integer)")
        end
        params[0] + [name]
    when 'flsutf8sized', 'flsasciisized'
        if params.length != 2
            die("Invalid usage: #{name}{position: integer, length: integer)")
        end
        params[0] + params[1] + [name]
    when 'osi', 'osu'
        if params.length != 4
            die("Invalid usage: #{name}(base: integer constant, name: string, data: integer, position: integer)")
        end
        if params[0].length != 1 || !params[0][0].start_with?('lic ')
            die("Invalid usage: #{name}(base: integer constant, name: string, data: integer, position: integer)")
        end
        base = Integer(params[0][0][3..-1].strip)
        params[3] + params[2] + params[1] + [name + ' ' + base.to_s]
    when 'oss'
        if params.length != 3
            die("Invalid usage: #{name}(name: string, data: string, position: integer)")
        end
        params[2] + params[1] + params[0] + [name]
    when 'f2le', 'f2be'
        if params.length != 0
            die("Invalid usage: #{name}()")
        end
        [name]
    else
        die("Unknown function #{name}")
    end
end

def function_type(name)
    type = {
        'oh0' => :integer,
        'oh1' => :integer,
        'oh2' => :integer,
        'oh3' => :integer,
        'oh4' => :integer,
        'oh5' => :integer,
        'oh6' => :integer,
        'oh7' => :integer,
        'fli8' => :integer,
        'flu8' => :integer,
        'fli16' => :integer,
        'flu16' => :integer,
        'fli32' => :integer,
        'flu32' => :integer,
        'fli64' => :integer,
        'flu64' => :integer,
        'flsutf8null' => :string,
        'flsutf8sized' => :string,
        'flsasciinull' => :string,
        'flsasciisized' => :string,
        'osi' => :nil,
        'osu' => :nil,
        'oss' => :nil,
        'f2le' => :nil,
        'f2be' => :nil,
    }[name]
    if !type
        die("Unknown function #{name}")
    end
    type
end

def reserved_identifier(name)
    {
        '_LOC' => true
    }[name] ? true : false
end

def transform_identifier(name)
    if reserved_identifier(name)
        case name
        when '_LOC'
            ['lic     $LOC']
        else
            die("Missing transformation for reserved identifier #{name}")
        end
    else
        var = $vars[name]
        if var
            [
                "lic     #{var[:pos]}",
                var[:type] == :integer ? 'sli' :
                var[:type] == :float   ? 'slf' :
                                         'sls'
            ]
        else
            die("Unbound identifier #{name}")
        end
    end
end

def identifier_type(name)
    if reserved_identifier(name)
        case name
        when '_LOC'
            :integer
        else
            die("Missing type transformation for reserved identifier #{name}")
        end
    else
        var = $vars[name]
        if var
            var[:type]
        else
            die("Unbound identifier #{name}")
        end
    end
end

def transform_condition(condition, invert)
    die('Condition is not a condition') unless condition[0] == 'condition'

    condition = condition[1]
    cmp = condition[0]
    if cmp == 'rhs'
        return transform_condition(['condition',
                                    ['condition_ne',
                                     condition[1],
                                     ['rhs',
                                      ['left_hand_rhs',
                                       ['constant',
                                        ['ICONSTANT',
                                         '0']]]]]],
                                   invert)
    end

    if invert
        cmp = case cmp
        when 'condition_eq'; 'condition_ne'
        when 'condition_ne'; 'condition_eq'
        when 'condition_ge'; 'condition_lt'
        when 'condition_gt'; 'condition_le'
        when 'condition_le'; 'condition_gt'
        when 'condition_lt'; 'condition_ge'
        else
            die("Unknown condition type #{cmp}")
        end
    end

    lhs_t = transform_type(condition[1])
    rhs_t = transform_type(condition[2])
    if lhs_t != rhs_t
        die("Cannot compare #{lhs_t} and #{rhs_t}")
    elsif lhs_t != :integer
        die("Cannot compare #{lhs_t}")
    end

    lhs_c = transform_constant(condition[1])
    rhs_c = transform_constant(condition[2])

    negate_first = false
    negate_second = false
    negate_either = false
    offset_first = 0

    case cmp
    when 'condition_eq', 'condition_ne'
        negate_either = true
    when 'condition_ge'
        negate_second = true
    when 'condition_gt'
        negate_second = true
        offset_first = -1
    when 'condition_le'
        negate_first = true
    when 'condition_lt'
        negate_first = true
        offset_first = 1
    else
        die("Unknown comparison #{cmp}")
    end

    if negate_either
        if lhs_c
            negate_first = true
        else
            negate_second = true
        end
    end

    if offset_first != 0
        if lhs_c
            lhs_c += offset_first
            offset_first = 0
        elsif rhs_c
            rhs_c -= offset_first
            offset_first = 0
        end
    end

    if negate_first && lhs_c
        lhs_c = -lhs_c
        negate_first = false
    end
    if negate_second && rhs_c
        rhs_c = -rhs_c
        negate_second = false
    end

    drop_iadd = false

    compare = []

    if lhs_c
        compare << "lic     #{lhs_c}"
    else
        compare += transform(condition[1])
    end
    if offset_first != 0
        compare << "lic     #{offset_first}"
        compare << "iadd"
    end
    if negate_first
        compare << 'ineg'
    end

    if rhs_c
        if rhs_c == 0
            die('Internal error') if negate_second
            drop_iadd = true
        else
            compare << "lic     #{rhs_c}"
        end
    else
        compare += transform(condition[2])
    end
    if negate_second
        compare << 'ineg'
    end

    compare << 'iadd' unless drop_iadd

    jump = case cmp
           when 'condition_eq'
               'jz'
           when 'condition_ne'
               'jnz'
           else
               'jnn'
           end

    [compare, jump]
end

def transform_constant(tree)
    case tree[0]
    when 'PRE_BLOCK', 'PRE_MERGE_BLOCK', 'BLOCK', 'MERGE_BLOCK'
        nil
    when 'pre_block_if', 'pre_merge_block_elsif', 'pre_merge_block_else'
        nil
    when 'pre_block_while'
        nil
    when 'STATEMENT'
        transform_constant(tree[1])
    when 'rhs', 'left_hand_rhs', 'constant'
        transform_constant(tree[1])
    when 'function_call'
        nil
    when 'ICONSTANT'
        Integer(tree[1])
    when 'FCONSTANT'
        Float(tree[1])
    when 'SCONSTANT'
        eval tree[1]
    when 'assignment'
        die('Bad assignment') unless tree[2][0] == 'rhs'
        transform_constant(tree[2][1])
    when 'IDENTIFIER'
        nil
    when 'condition'
        nil
    else
        die("No constant transformation rule for #{tree[0]}")
    end
end

def transform_type(tree)
    if !tree
        return :nil
    end

    case tree[0]
    when 'PRE_BLOCK', 'PRE_MERGE_BLOCK', 'BLOCK', 'MERGE_BLOCK'
        :nil
    when 'pre_block_if', 'pre_merge_block_elsif', 'pre_merge_block_else'
        :nil
    when 'pre_block_while'
        :nil
    when 'STATEMENT'
        transform_type(tree[1])
    when 'rhs', 'left_hand_rhs', 'paren_rhs', 'constant'
        transform_type(tree[1])
    when 'function_call'
        die('Bad function call') unless tree[1][0] == 'IDENTIFIER'
        func_name = tree[1][1]
        function_type(func_name)
    when 'ICONSTANT'
        :integer
    when 'FCONSTANT'
        :float
    when 'SCONSTANT'
        :string
    when 'assignment'
        die('Bad assignment') unless tree[2][0] == 'rhs'
        transform_type(tree[2][1])
    when 'IDENTIFIER'
        identifier_type(tree[1])
    when 'condition'
        :boolean
    when 'add', 'sub', 'and'
        t1 = transform_type(tree[1])
        t2 = transform_type(tree[2])
        if t1 != t2
            die("Cannot #{tree[0]} #{t1} and #{t2}")
        end
        t1
    else
        die("No type transformation rule for #{tree[0]}")
    end
end

def transform(tree)
    if !tree
        return []
    end

    if tree[0].kind_of?(Array)
        return tree.map { |te|
            transform(te)
        }
    end

    case tree[0]
    when 'STATEMENT', 'PRE_BLOCK', 'PRE_MERGE_BLOCK'
        transform(tree[1])
    when 'BLOCK', 'MERGE_BLOCK'
        if tree[1] == nil
            die('Block missing')
        end
        transform(tree[1])
    when 'pre_block_if', 'pre_merge_block_elsif'
        counter = $counter
        $counter += 1

        cond_type = transform_type(tree[1])
        if cond_type != :boolean
            die("if condition needs to be boolean, but is #{cond_type}")
        end

        condition, jump = transform_condition(tree[1], true)

        trivial_else = tree[3].length == 1
        neg_target = trivial_else ? 'endif' : 'else'

        ret = condition +
                  ["%-3s #{neg_target}_#{counter}" % jump] +
                  transform(tree[2])
        if !trivial_else
            ret += ["jmp     endif_#{counter}"] +
                       ["else_#{counter}:"] +
                       transform(tree[3])
        end
        ret << "endif_#{counter}:"
        return ret
    when 'pre_merge_block_else'
        # No condition, so nothing to do here
        transform(tree[1])
    when 'pre_block_while'
        counter = $counter
        $counter += 1

        cond_type = transform_type(tree[1])
        if cond_type != :boolean
            die("while condition needs to be boolean, but is #{cond_type}")
        end

        condition, jump = transform_condition(tree[1], true)

        ["while_#{counter}:"] +
            condition +
            ["%-3s endwhile_#{counter}" % jump] +
            transform(tree[2]) +
            ["jmp     while_#{counter}"] +
            ["endwhile_#{counter}:"]
    when 'rhs', 'left_hand_rhs', 'paren_rhs', 'constant'
        transform(tree[1])
    when 'function_call'
        die('Bad function call') unless tree[1][0] == 'IDENTIFIER'
        func_name = tree[1][1]
        params = []
        subtree = tree[2]
        while subtree
            die("Bad function call") unless subtree[0] == 'function_call_parameters'
            params << transform(subtree[1])
            subtree = subtree[2]
        end

        transform_function(func_name, params)
    when 'ICONSTANT'
        ["lic     #{tree[1]}"]
    when 'FCONSTANT'
        ["lfc     #{tree[1]}"]
    when 'SCONSTANT'
        ["lsc     #{tree[1]}"]
    when 'IDENTIFIER'
        transform_identifier(tree[1])
    when 'assignment'
        die('Bad assignment') unless tree[1][0] == 'IDENTIFIER'
        die('Bad assignment') unless tree[2][0] == 'rhs'

        id = tree[1][1]
        rhs = tree[2][1]
        if reserved_identifier(id)
            die("Identifier #{id} is reserved")
        end

        type = transform_type(rhs)
        if type == :nil
            die("Cannot determine type of #{rhs.inspect}")
        end

        var = $vars[id]
        if var
            if var[:type] != type
                die("#{id} is of type #{var[:type]}, cannot assign value of type #{type}")
            end
        else
            pos = $varcounter[type]
            $varcounter[type] += 1
            $vars[id] = { type: type, pos: pos }
            var = $vars[id]
        end

        transform(rhs) +
            [
                "lic     #{var[:pos]}",
                type == :integer ? 'ssi' :
                type == :float   ? 'ssf' :
                                   'ssf'
            ]
    when 'add'
        t1 = transform_type(tree[1])
        t2 = transform_type(tree[2])
        if t1 != t2
            die("Cannot add #{t1} and #{t2}")
        end

        transform(tree[1]) + transform(tree[2]) +
            [t1 == :integer ? 'iadd' :
             t1 == :float   ? 'fadd' :
                              'scat']
    when 'sub'
        t1 = transform_type(tree[1])
        t2 = transform_type(tree[2])
        if t1 != t2 || t1 == :string
            die("Cannot sub #{t1} and #{t2}")
        end

        transform(tree[1]) + transform(tree[2]) +
            (t1 == :integer ? ['ineg', 'iadd'] :
                              ['fneg', 'fadd'])
    when 'and'
        t1 = transform_type(tree[1])
        t2 = transform_type(tree[2])
        if t1 != :integer || t2 != :integer
            die("Cannot add #{t1} and #{t2}")
        end

        transform(tree[1]) + transform(tree[2]) + ['iand']
    else
        die("No transformation rule for #{tree[0]}")
    end
end

input = $stdin.read().gsub(/\/\/.*$/, '').strip.gsub("\n", ' ').gsub("\r", ' ')

input_preprocessed = []
current_indices = [0]
in_string = nil
escaped = false

def cis_append(input_preprocessed, current_indices, str)
    c_arr = input_preprocessed
    current_indices[0..-2].each do |i|
        c_arr[i] = [] unless c_arr[i]
        c_arr = c_arr[i]
    end

    c_arr[current_indices[-1]] = '' unless c_arr[current_indices[-1]]
    c_arr[current_indices[-1]] += str
end

input.each_char do |chr|
    if chr == '\\' && in_string && !escaped
        cis_append(input_preprocessed, current_indices, chr)
        escaped = true
        next
    end

    if escaped && in_string
        cis_append(input_preprocessed, current_indices, chr)
        escaped = false
        next
    end

    if !in_string
        if chr == ';'
            cis_append(input_preprocessed, current_indices, chr)
            current_indices[-1] += 1
            next
        elsif chr == '{'
            current_indices[-1] += 1
            current_indices << 0
            next
        elsif chr == '}'
            current_indices.pop()
            current_indices[-1] += 1
            next
        end
    end

    cis_append(input_preprocessed, current_indices, chr)

    if chr == '"'
        in_string = !in_string
    end
end

tree = syntax_apply(desc_hash, input_preprocessed)
if !tree
    die('Syntax error somewhere in input (sorry for not being helpful)')
end

out = transform(tree)
puts out
