RSpec.shared_examples 'Grammar::Repetition' do
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
	    expect(parser.parse(input)).to eq([[klass.new('abc', location:0), klass.new('def', location:4), klass.new('xyz', location:8)]])
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

    context 'Leading Ignore' do
	let(:klass) { Grammar::Alternation.with('abc', 'def', 'xyz') }

	# The input string has a trailing space to ensure that none of the repetition tests
	#  consume trailing characters that match the ignore-pattern
	let(:input) { StringScanner.new(' abc def xyz ') }

	it 'must reject the ignore-pattern' do
	    parser.push Grammar::Repetition.any(klass, ignore:/\s*/)
	    expect(parser.parse(input)).to eq([[]])
	    expect(input.pos).to eq(0)
	end

	it 'must reject the maximum' do
	    parser.push Grammar::Repetition.at_most(3, klass, ignore:/\s*/)
	    expect(parser.parse(input)).to eq([[]])
	    expect(input.pos).to eq(0)
	end

	it 'must reject less than the maximum' do
	    parser.push Grammar::Repetition.at_most(4, klass, ignore:/\s*/)
	    expect(parser.parse(input)).to eq([[]])
	    expect(input.pos).to eq(0)
	end

	it 'must accept no more than the maximum' do
	    parser.push Grammar::Repetition.at_most(2, klass, ignore:/\s*/)
	    expect(parser.parse(input)).to eq([[]])
	    expect(input.pos).to eq(0)
	end

	it 'must accept the minimum' do
	    parser.push Grammar::Repetition.with(klass, maximum:nil, minimum:3, ignore:/\s*/)
	    expect(parser.parse(input)).to be_nil
	    expect(input.pos).to eq(0)
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
