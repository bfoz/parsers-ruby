require_relative 'grammar/repetition'

RSpec.shared_examples 'a grammar parser' do
    let(:parser) { described_class.new }

    include_examples "Grammar::Repetition"

    it 'must match a simple string' do
	parser.push 'abc'
	expect(parser.parse('abc')).to eq(['abc'])
    end

    it 'must match a simple regular expression' do
	parser.push(/abc/)
	expect(parser.parse('abc')).to eq(['abc'])
    end

    it 'must match a character range' do
	parser.push('a'..'z')
	expect(parser.parse('d')).to eq(['d'])
    end

    it 'must match nested unterminated lists with overlapping separators' do
	inner_repeat = Grammar::Concatenation.with(' ', 'a').any
	inner_list = Grammar::Concatenation.with('a', inner_repeat)
	outer_repeat = Grammar::Concatenation.with(' _ ', inner_list).any
	outer_list = Grammar::Concatenation.with(inner_list, outer_repeat)

	parser.push outer_list
	expect(parser.parse('a _ a')).to eq([outer_list.new(inner_list.new('a', [], location:0), [outer_repeat.grammar.new(' _ ', inner_list.new('a', [], location:4), location:1)], location:0)])
    end

    context 'Grammar::Alternation' do
	it 'must match an Alternation' do
	    klass = Grammar::Alternation.with('abc', 'def')
	    parser.push klass
	    expect(parser.parse('abc')).to eq([klass.new('abc', location:0)])
	    expect(parser.parse('def')).to eq([klass.new('def', location:0)])
	end

	it 'must greedily match an overlapping Alternation' do
	    klass = Grammar::Alternation.with('abc', 'abcd')
	    parser.push klass
	    expect(parser.parse('abcd')).to eq([klass.new('abcd', location:0)])
	end

	it 'must match an Alternation with nested Concatenations' do
	    abc_klass = Grammar::Concatenation.with('abc')
	    def_klass = Grammar::Concatenation.with('def')
	    klass = Grammar::Alternation.with(abc_klass, def_klass)
	    parser.push klass
	    expect(parser.parse('abc')).to eq([klass.new(abc_klass.new('abc', location:0), location:0)])
	    expect(parser.parse('def')).to eq([klass.new(def_klass.new('def', location:0), location:0)])
	end

	it 'must match an Alternation with nested Concatenations and Strings' do
	    abc_klass = Grammar::Concatenation.with('abc')
	    klass = Grammar::Alternation.with(abc_klass, 'def')
	    parser.push klass
	    expect(parser.parse('abc')).to eq([klass.new(abc_klass.new('abc', location:0), location:0)])
	    expect(parser.parse('def')).to eq([klass.new('def', location:0)])
	end

	it 'must match an empty string alternate' do
	    klass = Grammar::Alternation.with('abc', '')
	    parser.push klass
	    expect(parser.parse('xyz')).to eq([klass.new('')])
	end
    end

    context 'Grammar::Concatenation' do
	it 'must match a Concatenation' do
	    klass = Grammar::Concatenation.with('abc', 'def')
	    parser.push klass
	    expect(parser.parse('abcdef')).to eq([klass.new('abc', 'def', location:0)])
	end

	it 'must greedily match a Concatenation' do
	    klass = Grammar::Concatenation.with('a', 'bc', 'd')
	    parser.push klass
	    expect(parser.parse('abcd')).to eq([klass.new('a', 'bc', 'd', location:0)])
	end

	it 'must match a Concatenation with a nested Alternation' do
	    inner_klass = Grammar::Alternation.with('bcd', 'efg')
	    klass = Grammar::Concatenation.with('a', inner_klass, 'h')
	    parser.push klass
	    expect(parser.parse('abcdh')).to eq([klass.new('a', inner_klass.new('bcd', location:1), 'h', location:0)])
	end

	it 'must handle multiple levels of nesting' do
	    repeat_klass = Grammar::Concatenation.with('def')
	    klass = Grammar::Concatenation.with('abc', repeat_klass, 'z')
	    parser.push klass
	    expect(parser.parse('abcdefz')).to eq([klass.new('abc', repeat_klass.new('def', location:3), 'z', location:0)])
	end

	it 'must match a Concatenation with a nested boundary Alternation' do
	    bcd_efg = Grammar::Alternation.with('bcd', 'efg')
	    klass = Grammar::Concatenation.with('a', bcd_efg)
	    parser.push klass
	    expect(parser.parse('abcd')).to eq([klass.new('a', bcd_efg.new('bcd', location:1), location:0)])
	end

	it 'must match a Concatenation with a nested optional when the nested optional fails' do
	    optional_klass = Grammar::Concatenation.with(/[0-9]+/).optional
	    klass = Grammar::Concatenation.with('a', optional_klass, 'z')
	    parser.push klass
	    expect(parser.parse('az')).to eq([klass.new('a', nil, 'z')])
	end

	it 'must match a nested empty string' do
	    klass = Grammar::Concatenation.with('a', '', 'b')
	    parser.push klass
	    expect(parser.parse('ab')).to eq([klass.new('a', '', 'b')])
	end

	context 'Ignore' do
	    it 'must ignore the ignore-pattern' do
		klass = Grammar::Concatenation.with('abc', 'def', 'xyz', ignore:/ /)
		parser.push klass
		expect(parser.parse('abc def xyz')).to eq([klass.new('abc', 'def', 'xyz')])
	    end

	    it 'must ignore an optional ignore-pattern' do
		klass = Grammar::Concatenation.with('abc', 'def', ignore:Grammar::Repetition.any(','))
		parser.push klass
		expect(parser.parse('abc,def')).to eq([klass.new('abc', 'def')])
	    end

	    it 'must ignore an optional Regexp ignore-pattern' do
		klass = Grammar::Concatenation.with('abc', 'def', ignore:/,*/)
		parser.push klass
		expect(parser.parse('abc,def')).to eq([klass.new('abc', 'def')])
	    end

	    it 'must ignore an optional missing Regexp ignore-pattern' do
		klass = Grammar::Concatenation.with('abc', 'def', ignore:/,*/)
		parser.push klass
		expect(parser.parse('abcdef')).to eq([klass.new('abc', 'def')])
	    end

	    it 'must not ignore forever' do
		klass = Grammar::Concatenation.with('abc', 'def', ignore:/,*/)
		parser.push klass
		expect(parser.parse('abcxyz')).to eq(nil)
	    end

	    it 'must ignore before an any-repetition' do
		klass = Grammar::Concatenation.with('abc', Grammar::Repetition.with('xyz', maximum:nil, minimum:0, ignore:/\s*/), ignore:/\s*/)
		parser.push klass
		expect(parser.parse('abc xyz')).to eq([klass.new('abc', ['xyz'])])
	    end

	    it 'must ignore a trailing ignore after a repetition' do
		klass = Grammar::Concatenation.with('abc', Grammar::Repetition.with('xyz', maximum:nil, minimum:0, ignore:/\s*/), ignore:/\s*/)
		parser.push klass
		expect(parser.parse('abc xyz ')).to eq([klass.new('abc', ['xyz'])])
	    end

	    it 'must not ignore a leading ignore' do
		parser.push Grammar::Concatenation.with('abc', 'def', 'xyz', ignore:/ /)
		input = StringScanner.new(' abc def xyz')
		expect(parser.parse(input)).to be_nil
		expect(input.pos).to eq(0)
	    end
	end
    end

    context 'Grammar::Latch' do
	it 'must match a simple latch' do
	    latch = Grammar::Latch.with('abc')
	    klass = Grammar::Concatenation.with(latch, latch)
	    parser.push klass
	    expect(parser.parse('abcabc')).to eq([klass.new('abc', 'abc')])
	    expect(parser.parse('abcxyz')).to be_nil
	end

	it 'must match a latched Alternation' do
	    latch = Grammar::Latch.with(Grammar::Alternation.with('abc', 'xyz'))
	    klass = Grammar::Concatenation.with(latch, latch)
	    parser.push klass
	    expect(parser.parse('abcabc')).to eq([klass.new('abc', 'abc')])
	    expect(parser.parse('xyzxyz')).to eq([klass.new('xyz', 'xyz')])
	    expect(parser.parse('abcxyz')).to be_nil
	end

	it 'must match a nested latch in an outer context' do
	    latch = Grammar::Latch.with(Grammar::Alternation.with('abc', 'xyz'))
	    inner_klass = Grammar::Concatenation.with(latch, 'def')
	    outer_klass = Grammar::Concatenation.with(inner_klass, inner_klass, context:{latch => nil})
	    parser.push outer_klass
	    expect(parser.parse('abcdefabcdef')).to eq([outer_klass.new(inner_klass.new('abc', 'def'), inner_klass.new('abc', 'def'))])
	    expect(parser.parse('xyzdefxyzdef')).to eq([outer_klass.new(inner_klass.new('xyz', 'def'), inner_klass.new('xyz', 'def'))])
	    expect(parser.parse('abcdefxyzdef')).to be_nil
	end

	it 'must match a nested latch in an inner context' do
	    latch = Grammar::Latch.with(Grammar::Alternation.with('abc', 'xyz'))
	    inner_klass = Grammar::Concatenation.with(latch, latch, context:{latch => nil})
	    outer_klass = Grammar::Concatenation.with(inner_klass, inner_klass)
	    parser.push outer_klass
	    expect(parser.parse('abcabcxyzxyz')).to eq([outer_klass.new(inner_klass.new('abc', 'abc'), inner_klass.new('xyz', 'xyz'))])
	    expect(parser.parse('abcxyzabcxyz')).to be_nil
	end
    end

    context 'Grammar::Recursion' do
	it 'must match a center-recursive Concatenation' do
	    klass = Grammar::Recursion.new.tap do |wrapper|
		wrapper.grammar = Grammar::Concatenation.with('abc', wrapper, 'xyz')
		wrapper.freeze
	    end

	    parser.push klass
	    expect(parser.parse('abcabcxyzxyz')).to eq([klass.grammar.new('abc', klass.grammar.new('abc', nil, 'xyz', location:3), 'xyz', location:0)])
	end

	it 'must match a right-recursive Concatenation' do
	    klass = Grammar::Recursion.new.tap do |wrapper|
		wrapper.grammar = Grammar::Concatenation.with('abc', wrapper)
		wrapper.freeze
	    end

	    parser.push klass
	    expect(parser.parse('abcabc')).to eq([klass.grammar.new('abc', klass.grammar.new('abc', nil, location:3), location:0)])
	end

	it 'must match an Alternation with a nested center-recursive Concatenation' do
	    concatenation_klass = nil
	    klass = Grammar::Recursion.new.tap do |wrapper|
		concatenation_klass = Grammar::Concatenation.with('(', wrapper, ')')
		wrapper.grammar = Grammar::Alternation.with('abc', 'def', concatenation_klass)
		wrapper.freeze
	    end

	    parser.push klass
	    expect(parser.parse('(abc)')).to eq([klass.grammar.new(concatenation_klass.new('(', klass.grammar.new('abc', location:1), ')', location:0), location:0)])
	end

	it 'must match a nested outer-recursive grammar' do
	    # Testing this without using the DSL because the DSL is inconvenient to use here
	    # module Test
	    #     using Grammar::DSL
	    #     alternation :Rule0 do
	    #         element 'abc'
	    #         element concatenation { elements Rule0, ',', Rule0 }
	    #     end
	    # end

	    nested_klass = nil
	    klass = Grammar::Recursion.new.tap do |wrapper|
		nested_klass = Grammar::Concatenation.with(',', wrapper)
		wrapper.grammar = Grammar::Concatenation.with('abc', nested_klass.any)
		wrapper.freeze
	    end

	    parser.push klass
	    expect(parser.parse('abc,abc')).to eq([klass.grammar.new('abc', [nested_klass.new(',', klass.grammar.new('abc', []))])])
	end

	context 'Mutual Recursion' do
	    it 'must match a mutually recursive Alternation with nested Concatenations' do
		klassA = nil
		klassB = nil
		klass = Grammar::Recursion.new.tap do |wrapper|
		    klassA = Grammar::Concatenation.with('xyz', wrapper)
		    klassB = Grammar::Concatenation.with('uvw', wrapper)
		    wrapper.grammar = Grammar::Alternation.with('abc', 'def', klassA, klassB)
		    wrapper.freeze
		end

		parser.push klass
		expect(parser.parse('abc')).to eq([klass.grammar.new('abc')])
		expect(parser.parse('def')).to eq([klass.grammar.new('def')])
		expect(parser.parse('xyzabc')).to eq([klass.grammar.new(klassA.new('xyz', klass.grammar.new('abc')))])
		expect(parser.parse('uvwabc')).to eq([klass.grammar.new(klassB.new('uvw', klass.grammar.new('abc')))])
	    end

	    it 'must match a mutually recursive Concatenation with nested Alternations' do
		klassA = nil
		klassB = nil
		klass = Grammar::Recursion.new.tap do |wrapper|
		    klassA = Grammar::Alternation.with('def', wrapper)
		    klassB = Grammar::Alternation.with('uvw', wrapper)
		    wrapper.grammar = Grammar::Concatenation.with('abc', klassA, klassB, 'xyz')
		    wrapper.freeze
		end

		parser.push klass
		expect(parser.parse('abcdefuvwxyz')).to eq([klass.grammar.new('abc', klassA.new('def'), klassB.new('uvw'), 'xyz')])
	    end
	end
    end
end
