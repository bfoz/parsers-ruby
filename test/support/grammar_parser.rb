RSpec.shared_examples 'a grammar parser' do
    let(:parser) { described_class.new }

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

    context 'Grammar::Repetition' do
	it 'must greedily match a star-repeated Alternation' do
	    klass = Grammar::Alternation.with('abc', 'def')
	    parser.push klass.at_least(0)
	    expect(parser.parse('abcdefabc')).to eq([[klass.new('abc', location:0), klass.new('def', location:3), klass.new('abc', location:6)]])
	end

	it 'must greedily match a star-repeated Concatenation' do
	    klass = Grammar::Concatenation.with('abc')
	    parser.push klass.at_least(0)
	    expect(parser.parse('abcabcabc')).to eq([[klass.new('abc', location:0), klass.new('abc', location:3), klass.new('abc', location:6)]])
	end

	it 'must match the minimum' do
	    klass = Grammar::Concatenation.with('abc')
	    parser.push klass.at_least(3)
	    expect(parser.parse('abcabcabc')).to eq([[klass.new('abc', location:0), klass.new('abc', location:3), klass.new('abc', location:6)]])
	end

	it 'must match more than the minimum' do
	    klass = Grammar::Concatenation.with('abc')
	    parser.push klass.at_least(1)
	    expect(parser.parse('abcabcabc')).to eq([[klass.new('abc', location:0), klass.new('abc', location:3), klass.new('abc', location:6)]])
	end

	it 'must reject less than the minimum' do
	    klass = Grammar::Concatenation.with('abc')
	    parser.push klass.at_least(3)
	    expect(parser.parse('abc')).to be_nil
	end

	it 'must match the maximum number of repetitions' do
	    klass = Grammar::Concatenation.with('abc')
	    parser.push klass.at_most(3)
	    expect(parser.parse('abcabcabc')).to eq([[klass.new('abc', location:0), klass.new('abc', location:3), klass.new('abc', location:6)]])
	end

	it 'must match less than the maximum number of repetitions' do
	    klass = Grammar::Concatenation.with('abc')
	    parser.push klass.at_most(3)
	    expect(parser.parse('abc')).to eq([[klass.new('abc', location:0)]])
	end

	it 'must match more than the maximum with a following match' do
	    klass = Grammar::Concatenation.with('abc')
	    outer_klass = Grammar::Concatenation.with(klass.at_most(2), klass)
	    parser.push outer_klass
	    expect(parser.parse('abcabcabc')).to eq([outer_klass.new([klass.new('abc', location:0), klass.new('abc', location:3)], klass.new('abc', location:6))])
	end

	it 'must match more than the minimum and less than the maximum' do
	    klass = Grammar::Concatenation.with('abc')
	    parser.push klass.repeat(1,3)
	    expect(parser.parse('abcabc')).to eq([[klass.new('abc', location:0), klass.new('abc', location:3)]])
	end

	it 'must match the minimum when there is a maximum' do
	    klass = Grammar::Concatenation.with('abc')
	    parser.push klass.repeat(1,3)
	    expect(parser.parse('abc')).to eq([[klass.new('abc', location:0)]])
	end

	it 'must match the maximum when there is a minimum' do
	    klass = Grammar::Concatenation.with('abc')
	    parser.push klass.repeat(1,3)
	    expect(parser.parse('abcabcabc')).to eq([[klass.new('abc', location:0), klass.new('abc', location:3), klass.new('abc', location:6)]])
	end

	context 'Ignore' do
	    let(:klass) { Grammar::Alternation.with('abc', 'def', 'xyz') }

	    # The input string has a trailing space to ensure that none of the repetition tests
	    #  consume trailing characters that match the ignore-pattern
	    let(:input) { StringScanner.new('abc def xyz ') }

	    it 'must ignore the ignore-pattern' do
		parser.push Grammar::Repetition.with(klass, maximum:nil, minimum:0, ignore:/\s*/)
		expect(parser.parse(input)).to eq([[klass.new('abc'), klass.new('def'), klass.new('xyz')]])
		expect(input.pos).to eq(11)
	    end

	    it 'must accept the maximum' do
		parser.push Grammar::Repetition.with(klass, maximum:3, minimum:nil, ignore:/\s*/)
		expect(parser.parse(input)).to eq([[klass.new('abc'), klass.new('def'), klass.new('xyz')]])
		expect(input.pos).to eq(11)
	    end

	    it 'must accept less than the maximum' do
		parser.push Grammar::Repetition.with(klass, maximum:4, minimum:nil, ignore:/\s*/)
		expect(parser.parse(input)).to eq([[klass.new('abc'), klass.new('def'), klass.new('xyz')]])
		expect(input.pos).to eq(11)
	    end

	    it 'must accept no more than the maximum' do
		parser.push Grammar::Repetition.with(klass, maximum:2, minimum:nil, ignore:/\s*/)
		expect(parser.parse(input)).to eq([[klass.new('abc'), klass.new('def')]])
		expect(input.pos).to eq(7)
	    end

	    it 'must accept the minimum' do
		parser.push Grammar::Repetition.with(klass, maximum:nil, minimum:3, ignore:/\s*/)
		expect(parser.parse(input)).to eq([[klass.new('abc'), klass.new('def'), klass.new('xyz')]])
		expect(input.pos).to eq(11)
	    end

	    it 'must reject less than the minimum' do
		parser.push Grammar::Repetition.with(klass, maximum:nil, minimum:4, ignore:/\s*/)
		expect(parser.parse(input)).to be_nil
		expect(input.pos).to eq(0)
	    end
	end

	context 'at least 0' do
	    it 'must greedily match a nested Alternation' do
		repeat_klass = Grammar::Alternation.with('def', 'ghi')
		klass = Grammar::Concatenation.with('abc', repeat_klass.at_least(0), 'z')
		parser.push klass
		expect(parser.parse('abcdefghiz')).to eq([klass.new('abc', [repeat_klass.new('def', location:3), repeat_klass.new('ghi', location:6)], 'z', location:0)])
	    end

	    it 'must greedily match a nested Concatenation' do
		repeat_klass = Grammar::Concatenation.with('b', 'def')
		klass = Grammar::Concatenation.with('a', repeat_klass.at_least(0), 'z')
		parser.push klass
		expect(parser.parse('abdefbdefz')).to eq([klass.new('a', [repeat_klass.new('b', 'def', location:1), repeat_klass.new('b', 'def', location:5)], 'z', location:0)])
	    end

	    it 'must match a repeated nested Grammar' do
		klass0 = Grammar::Alternation.with('b')
		klass1 = Grammar::Concatenation.with('c')
		repeat_klass = Grammar::Concatenation.with(klass0, klass1)
		klass = Grammar::Concatenation.with('a', repeat_klass.at_least(0), 'z')

		parser.push klass
		expect(parser.parse('abcbcz')).to eq([klass.new('a',
								[repeat_klass.new(klass0.new('b', location:1), klass1.new('c', location:2), location:1),
								repeat_klass.new(klass0.new('b', location:3), klass1.new('c', location:4), location:3)],
								'z', location:0)])
	    end

	    it 'must match a repeated nested Grammar' do
		klass0 = Grammar::Alternation.with('b')
		klass1 = Grammar::Concatenation.with('c')
		repeat_klass = Grammar::Concatenation.with(klass0, klass1)
		klass = Grammar::Concatenation.with('a', repeat_klass.at_least(0), 'z')

		parser.push klass
		expect(parser.parse('abcbcz')).to eq([klass.new('a',
								[repeat_klass.new(klass0.new('b', location:1), klass1.new('c', location:2), location:1),
							 	repeat_klass.new(klass0.new('b', location:3), klass1.new('c', location:4), location:3)],
								'z', location:0)])
	    end

	    it 'must match a different repeated nested Grammar' do
		klass0 = Grammar::Alternation.with('c')
		klass1 = Grammar::Concatenation.with(klass0, 'd', 'e')
		repeat_klass = Grammar::Concatenation.with('b', klass1)
		klass = Grammar::Concatenation.with('a', repeat_klass.at_least(0), 'z')

		parser.push klass
		expect(parser.parse('abcdebcdez')).to eq([klass.new('a',
								    [repeat_klass.new('b', klass1.new(klass0.new('c', location:2), 'd', 'e', location:2), location:1),
								     repeat_klass.new('b', klass1.new(klass0.new('c', location:6), 'd', 'e', location:6), location:5)],
								    'z', location:0)])
	    end

	    it 'must greedily match a trailing nested repeating Concatenation' do
		prefix_klass = Grammar::Concatenation.with('abc')
		repeat_klass = Grammar::Concatenation.with('b', 'def')
		klass = Grammar::Concatenation.with(prefix_klass, repeat_klass.at_least(0))
		parser.push klass

		expect(parser.parse('abcbdefbdef')).to eq([klass.new(prefix_klass.new('abc', location:0), [repeat_klass.new('b', 'def', location:3), repeat_klass.new('b', 'def', location:7)], location:0)])
	    end

	    it 'must match a Concatenation with a nested optional Regexp that matches nothing' do
		klass = Grammar::Concatenation.with(/ ?/).any
		parser.push klass
		expect(parser.parse('')).to eq([[klass.grammar.new('')]])
	    end
	end

	context 'at least 1' do
	    it 'must match a String followed by a repeating Concatenation' do
		repeat_klass = Grammar::Concatenation.with('b', 'def')
		klass = Grammar::Concatenation.with('a', repeat_klass.at_least(1))

		parser.push klass
		expect(parser.parse('abdefbdef')).to eq([klass.new('a', [repeat_klass.new('b', 'def', location:1), repeat_klass.new('b', 'def', location:5)], location:0)])
	    end
	end

	context 'Optional' do
	    it 'must match an optional nested grammar' do
		klass = Grammar::Concatenation.with('abc')

		parser.push klass.optional
		expect(parser.parse('abc')).to eq([klass.new('abc')])
	    end

	    it 'must not match a missing optional nested grammar' do
		klass = Grammar::Concatenation.with('abc')

		parser.push klass.optional
		expect(parser.parse('')).to eq(nil)
	    end
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
