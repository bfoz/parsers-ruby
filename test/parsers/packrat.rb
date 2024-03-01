require 'parsers/packrat'
require 'support/grammar_parser'

RSpec.describe Parsers::Packrat do
    it_should_behave_like 'a grammar parser'

    let(:parser) { described_class.new }
    let(:cache)  { parser.instance_variable_get(:@cache) }

    it 'must not cache a simple string match' do
	grammar = 'abc'
	parser.push grammar

	parser.parse('abc')
	expect(cache).to be_empty
    end

    it 'must clear the cache between subsequent parses' do
	grammar = /abc/
	parser.push grammar

	parser.parse('abc')
	expect(cache).not_to be_empty

	parser.parse('xyz')
	# NOTE!! let(:cache) is only initialized once, so in this context it will always be the result of the first parse
	expect(parser.instance_variable_get(:@cache)).not_to eq(cache)
    end

    it 'must cache a simple regular expression match' do
	grammar = /abc/
	parser.push(grammar)

	parser.parse('abc')
	expect(cache[0]).not_to be_empty
	expect(cache[0][grammar]).not_to be_empty
	expect(cache[0][grammar][0]).to eq(3)
    end

    it 'must cache a character range match' do
	grammar = 'a'..'z'
	parser.push(grammar)

	parser.parse('d')
	expect(cache[0]).not_to be_empty
	expect(cache[0][grammar]).not_to be_empty
	expect(cache[0][grammar][0]).to eq(1)
    end

    it 'must cache nested unterminated lists with overlapping separators' do
	inner_repeat = Grammar::Concatenation.with(' ', 'a').any
	inner_list = Grammar::Concatenation.with('a', inner_repeat)
	outer_repeat = Grammar::Concatenation.with(' _ ', inner_list).any
	outer_list = Grammar::Concatenation.with(inner_list, outer_repeat)

	parser.push outer_list
	parser.parse('a _ a')

	expect(cache).not_to be_empty
	expect(cache.length()).to eq(4)

	expect(cache[0]).not_to be_empty
	expect(cache[0].length()).to eq(2)

	expect(cache[0][outer_list]).not_to be_empty
	expect(cache[0][outer_list][0]).to eq(5)		# length
	expect(cache[0][outer_list][1]).to be_instance_of(outer_list)

	expect(cache[0][inner_list]).not_to be_empty
	expect(cache[0][inner_list][0]).to eq(1)		# length
	expect(cache[0][inner_list][1]).to be_instance_of(inner_list)

	expect(cache[1]).not_to be_empty
	expect(cache[1].length()).to eq(4)

	expect(cache[1][outer_repeat]).not_to be_empty
	expect(cache[1][outer_repeat][0]).to eq(4)		# length

	expect(cache[1][outer_repeat.grammar]).not_to be_empty
	expect(cache[1][outer_repeat.grammar][0]).to eq(4)	# length

	# This is a non-match
	expect(cache[1][inner_repeat]).not_to be_empty
	expect(cache[1][inner_repeat][0]).to eq(0)		# length

	# This is a non-match
	expect(cache[1][inner_repeat.grammar]).not_to be_empty
	expect(cache[1][inner_repeat.grammar][0]).to eq(0)	# length

	expect(cache[4]).not_to be_empty
	expect(cache[4].length()).to eq(1)

	expect(cache[4][inner_list]).not_to be_empty
	expect(cache[4][inner_list][0]).to eq(1)		# length
    end

    context 'Grammar::Alternation' do
	it 'must cache an Alternation' do
	    grammar = Grammar::Alternation.with('abc', 'def')

	    parser.push grammar
	    parser.parse('abc')

	    expect(cache).not_to be_empty
	    expect(cache.length()).to eq(1)

	    expect(cache[0].length()).to eq(1)

	    expect(cache[0][grammar]).not_to be_empty
	    expect(cache[0][grammar][0]).to eq(3)
	    expect(cache[0][grammar][1]).to eq('abc')
	end

	it 'must cache an Alternation with nested Concatenations' do
	    abc_klass = Grammar::Concatenation.with('abc')
	    def_klass = Grammar::Concatenation.with('def')
	    grammar = Grammar::Alternation.with(abc_klass, def_klass)

	    parser.push grammar
	    parser.parse('abc')

	    expect(cache).not_to be_empty
	    expect(cache.length()).to eq(1)

	    expect(cache[0]).not_to be_empty
	    expect(cache[0].length()).to eq(3)

	    expect(cache[0][grammar]).not_to be_empty
	    expect(cache[0][grammar][0]).to eq(3)		# length

	    expect(cache[0][abc_klass]).not_to be_empty
	    expect(cache[0][abc_klass][0]).to eq(3)		# length

	    # This is a non-match
	    expect(cache[0][def_klass]).not_to be_empty
	    expect(cache[0][def_klass][0]).to eq(0)		# length
	end

	it 'must cache an Alternation with nested Concatenations and Strings' do
	    abc_klass = Grammar::Concatenation.with('abc')
	    grammar = Grammar::Alternation.with(abc_klass, 'def')

	    parser.push grammar
	    parser.parse('abc')

	    expect(cache).not_to be_empty
	    expect(cache.length()).to eq(1)

	    expect(cache[0]).not_to be_empty
	    expect(cache[0].length()).to eq(2)

	    expect(cache[0][grammar]).not_to be_empty
	    expect(cache[0][grammar][0]).to eq(3)		# length

	    expect(cache[0][abc_klass]).not_to be_empty
	    expect(cache[0][abc_klass][0]).to eq(3)		# length
	end

	it 'must cache an empty string alternate' do
	    grammar = Grammar::Alternation.with('abc', '')
	    parser.push grammar
	    parser.parse('xyz')

	    expect(cache).not_to be_empty
	    expect(cache.length()).to eq(1)

	    expect(cache[0]).not_to be_empty
	    expect(cache[0].length()).to eq(1)

	    # This is a non-match
	    expect(cache[0][grammar]).not_to be_empty
	    expect(cache[0][grammar][0]).to eq(0)		# length
	end
    end

    context 'Grammar::Concatenation' do
	it 'must cache a Concatenation' do
	    grammar = Grammar::Concatenation.with('abc', 'def')

	    parser.push grammar
	    parser.parse('abcdef')

	    expect(cache).not_to be_empty
	    expect(cache.length()).to eq(1)

	    expect(cache[0]).not_to be_empty
	    expect(cache[0].length()).to eq(1)

	    expect(cache[0][grammar]).not_to be_empty
	    expect(cache[0][grammar][0]).to eq(6)		# length
	    expect(cache[0][grammar][1]).not_to be_nil
	end

	it 'must cache a greedy Concatenation' do
	    grammar = Grammar::Concatenation.with('a', 'bc', 'd')

	    parser.push grammar
	    parser.parse('abcd')

	    expect(cache).not_to be_empty
	    expect(cache.length()).to eq(1)

	    expect(cache[0]).not_to be_empty
	    expect(cache[0].length()).to eq(1)

	    expect(cache[0][grammar]).not_to be_empty
	    expect(cache[0][grammar][0]).to eq(4)		# length
	    expect(cache[0][grammar][1]).not_to be_nil
	end

	it 'must cache a Concatenation with a nested Alternation' do
	    inner_klass = Grammar::Alternation.with('bcd', 'efg')
	    grammar = Grammar::Concatenation.with('a', inner_klass, 'h')

	    parser.push grammar
	    parser.parse('abcdh')

	    expect(cache).not_to be_empty
	    expect(cache.length()).to eq(2)

	    expect(cache[0]).not_to be_empty
	    expect(cache[0].length()).to eq(1)

	    expect(cache[0][grammar]).not_to be_empty
	    expect(cache[0][grammar][0]).to eq(5)		# length
	    expect(cache[0][grammar][1]).not_to be_nil

	    expect(cache[1][inner_klass]).not_to be_empty
	    expect(cache[1][inner_klass][0]).to eq(3)		# length
	    expect(cache[1][inner_klass][1]).not_to be_nil
	end

	it 'must cache multiple levels of nesting' do
	    repeat_klass = Grammar::Concatenation.with('def')
	    grammar = Grammar::Concatenation.with('abc', repeat_klass, 'z')

	    parser.push grammar
	    parser.parse('abcdefz')

	    expect(cache).not_to be_empty
	    expect(cache.length()).to eq(2)

	    expect(cache[0]).not_to be_empty
	    expect(cache[0].length()).to eq(1)

	    expect(cache[0][grammar]).not_to be_empty
	    expect(cache[0][grammar][0]).to eq(7)		# length
	    expect(cache[0][grammar][1]).not_to be_nil

	    expect(cache[3][repeat_klass]).not_to be_empty
	    expect(cache[3][repeat_klass][0]).to eq(3)		# length
	    expect(cache[3][repeat_klass][1]).not_to be_nil
	end

	it 'must cache a Concatenation with a nested boundary Alternation' do
	    bcd_efg = Grammar::Alternation.with('bcd', 'efg')
	    grammar = Grammar::Concatenation.with('a', bcd_efg)

	    parser.push grammar
	    parser.parse('abcd')

	    expect(cache).not_to be_empty
	    expect(cache.length()).to eq(2)

	    expect(cache[0]).not_to be_empty
	    expect(cache[0].length()).to eq(1)

	    expect(cache[0][grammar]).not_to be_empty
	    expect(cache[0][grammar][0]).to eq(4)		# length
	    expect(cache[0][grammar][1]).not_to be_nil

	    expect(cache[1][bcd_efg]).not_to be_empty
	    expect(cache[1][bcd_efg][0]).to eq(3)		# length
	    expect(cache[1][bcd_efg][1]).not_to be_nil
	end

	it 'must cache a Concatenation with a nested optional when the nested optional fails' do
	    optional_klass = Grammar::Concatenation.with(/[0-9]+/).optional
	    grammar = Grammar::Concatenation.with('a', optional_klass, 'z')

	    parser.push grammar
	    parser.parse('az')

	    expect(cache).not_to be_empty
	    expect(cache.length()).to eq(2)

	    expect(cache[0]).not_to be_empty
	    expect(cache[0].length()).to eq(1)

	    expect(cache[0][grammar]).not_to be_empty
	    expect(cache[0][grammar][0]).to eq(2)	# length
	    expect(cache[0][grammar][1]).not_to be_nil

	    expect(cache[1]).not_to be_empty
	    expect(cache[1].length()).to eq(3)

	    # This is a non-match
	    expect(cache[1][optional_klass]).not_to be_empty
	    expect(cache[1][optional_klass][0]).to eq(0)	# length
	    expect(cache[1][optional_klass][1]).to be_nil

	    # This is a non-match
	    expect(cache[1][optional_klass.grammar]).not_to be_empty
	    expect(cache[1][optional_klass.grammar][0]).to eq(0)	# length
	    expect(cache[1][optional_klass.grammar][1]).to be_nil

	    # This is a non-match
	    expect(cache[1][/[0-9]+/]).not_to be_empty
	    expect(cache[1][/[0-9]+/][0]).to eq(0)		# length
	    expect(cache[1][/[0-9]+/][1]).to be_nil
	end

	it 'must not cache a nested empty string' do
	    grammar = Grammar::Concatenation.with('a', '', 'b')

	    parser.push grammar
	    parser.parse('ab')

	    expect(cache).not_to be_empty
	    expect(cache.length()).to eq(1)

	    expect(cache[0]).not_to be_empty
	    expect(cache[0].length()).to eq(1)

	    expect(cache[0][grammar]).not_to be_empty
	    expect(cache[0][grammar][0]).to eq(2)		# length
	    expect(cache[0][grammar][1]).not_to be_nil
	end

	context 'Ignore' do
	    it 'must ignore the ignore-pattern' do
		grammar = Grammar::Concatenation.with('abc', 'def', 'xyz', ignore:/ /)

		parser.push grammar
		parser.parse('abc def xyz')

		expect(cache).not_to be_empty
		expect(cache.length()).to eq(3)

		expect(cache[0]).not_to be_empty
		expect(cache[0].length()).to eq(1)

		expect(cache[0][grammar]).not_to be_empty
		expect(cache[0][grammar][0]).to eq(11)		# length
		expect(cache[0][grammar][1]).not_to be_nil
	    end

	    it 'must ignore an optional ignore-pattern' do
		ignore_klass = Grammar::Repetition.any(',')
		grammar = Grammar::Concatenation.with('abc', 'def', ignore:ignore_klass)

		parser.push grammar
		parser.parse('abc,def')

		expect(cache).not_to be_empty
		expect(cache.length()).to eq(2)

		expect(cache[0]).not_to be_empty
		expect(cache[0].length()).to eq(1)

		expect(cache[0][grammar]).not_to be_empty
		expect(cache[0][grammar][0]).to eq(7)		# length
		expect(cache[0][grammar][1]).not_to be_nil

		expect(cache[3][ignore_klass]).not_to be_empty
		expect(cache[3][ignore_klass][0]).to eq(1)		# length
		expect(cache[3][ignore_klass][1]).not_to be_nil
	    end

	    it 'must ignore an optional Regexp ignore-pattern' do
		ignore_klass = /,*/
		grammar = Grammar::Concatenation.with('abc', 'def', ignore:ignore_klass)

		parser.push grammar
		parser.parse('abc,def')

		expect(cache).not_to be_empty
		expect(cache.length()).to eq(2)

		expect(cache[0]).not_to be_empty
		expect(cache[0].length()).to eq(1)

		expect(cache[0][grammar]).not_to be_empty
		expect(cache[0][grammar][0]).to eq(7)		# length
		expect(cache[0][grammar][1]).not_to be_nil

		expect(cache[3][ignore_klass]).not_to be_empty
		expect(cache[3][ignore_klass][0]).to eq(1)	# length
		expect(cache[3][ignore_klass][1]).not_to be_nil
	    end

	    it 'must ignore an optional missing Regexp ignore-pattern' do
		ignore_klass = /,*/
		grammar = Grammar::Concatenation.with('abc', 'def', ignore:ignore_klass)

		parser.push grammar
		parser.parse('abcdef')

		expect(cache).not_to be_empty
		expect(cache.length()).to eq(1)

		expect(cache[0]).not_to be_empty
		expect(cache[0].length()).to eq(1)

		expect(cache[0][grammar]).not_to be_empty
		expect(cache[0][grammar][0]).to eq(6)		# length
		expect(cache[0][grammar][1]).not_to be_nil
	    end

	    it 'must not ignore forever' do
		ignore_klass = /,*/
		grammar = Grammar::Concatenation.with('abc', 'def', ignore:ignore_klass)

		parser.push grammar
		parser.parse('abcxyz')

		expect(cache).not_to be_empty
		expect(cache.length()).to eq(2)

		expect(cache[0]).not_to be_empty
		expect(cache[0].length()).to eq(1)

		expect(cache[0][grammar]).not_to be_empty
		expect(cache[0][grammar][0]).to eq(0)		# length
		expect(cache[0][grammar][1]).to be_nil
	    end

	    it 'must ignore before an any-repetition' do
		repeat_klass = Grammar::Repetition.with('xyz', maximum:nil, minimum:0, ignore:/\s*/)
		grammar = Grammar::Concatenation.with('abc', repeat_klass, ignore:/\s*/)

		parser.push grammar
		expect(parser.parse('abc xyz')).to eq([grammar.new('abc', ['xyz'])])

		expect(cache.length()).to eq(3)

		expect(cache[0].length()).to eq(1)

		expect(cache[0][grammar][0]).to eq(7)		# length
		expect(cache[0][grammar][1]).not_to be_nil

		expect(cache[4].length()).to be >= 1

		expect(cache[4][repeat_klass][0]).to eq(3)	# length
		expect(cache[4][repeat_klass][1]).not_to be_nil
	    end

	    it 'must ignore a trailing ignore after a repetition' do
		repeat_klass = Grammar::Repetition.with('xyz', maximum:nil, minimum:0, ignore:/\s*/)
		grammar = Grammar::Concatenation.with('abc', repeat_klass, ignore:/\s*/)

		parser.push grammar
		expect(parser.parse('abc xyz ')).to eq([grammar.new('abc', ['xyz'])])

		expect(cache.length()).to be >= 2

		expect(cache[0].length()).to eq(1)

		expect(cache[0][grammar][0]).to eq(7)		# length
		expect(cache[0][grammar][1]).not_to be_nil

		expect(cache[4].length()).to eq(1)

		expect(cache[4][repeat_klass][0]).to eq(3)		# length
		expect(cache[4][repeat_klass][1]).not_to be_nil
	    end

	    it 'must not ignore a leading ignore' do
		grammar = Grammar::Concatenation.with('abc', 'def', 'xyz', ignore:/ /)

		parser.push grammar
		input = StringScanner.new(' abc def xyz')
		parser.parse(input)

		expect(cache.length()).to eq(1)

		expect(cache[0].length()).to eq(1)

		expect(cache[0][grammar][0]).to eq(0)		# length
		expect(cache[0][grammar][1]).to be_nil
	    end
	end
    end

    context 'Grammar::Latch' do
	it 'must not cache a simple latch' do
	    latch = Grammar::Latch.with('abc')
	    grammar = Grammar::Concatenation.with(latch, latch)

	    parser.push grammar
	    parser.parse('abcabc')

	    expect(cache.length()).to eq(1)

	    expect(cache[0]).not_to be_empty
	    expect(cache[0].length()).to eq(1)

	    expect(cache[0][grammar]).not_to be_empty
	    expect(cache[0][grammar][0]).to eq(6)		# length
	    expect(cache[0][grammar][1]).not_to be_nil
	end

	it 'must not cache a latched Alternation' do
	    inner_klass = Grammar::Alternation.with('abc', 'xyz')
	    latch = Grammar::Latch.with(inner_klass)
	    grammar = Grammar::Concatenation.with(latch, latch)

	    parser.push grammar
	    parser.parse('abcabc')

	    expect(cache.length()).to eq(2)

	    expect(cache[0]).not_to be_empty
	    expect(cache[0].length()).to eq(2)

	    expect(cache[0][grammar]).not_to be_empty
	    expect(cache[0][grammar][0]).to eq(6)		# length
	    expect(cache[0][grammar][1]).not_to be_nil

	    expect(cache[0][inner_klass]).not_to be_empty
	    expect(cache[0][inner_klass][0]).to eq(3)		# length
	    expect(cache[0][inner_klass][1]).not_to be_nil

	    expect(cache[3]).not_to be_empty
	    expect(cache[3].length()).to eq(1)

	    expect(cache[3][inner_klass]).not_to be_empty
	    expect(cache[3][inner_klass][0]).to eq(3)		# length
	    expect(cache[3][inner_klass][1]).not_to be_nil
	    expect(cache[3][inner_klass][1].location).to eq(3)
	end

	it 'must not cache a nested latch in an outer context' do
	    latch = Grammar::Latch.with(Grammar::Alternation.with('abc', 'xyz'))
	    inner_klass = Grammar::Concatenation.with(latch, 'def')
	    outer_klass = Grammar::Concatenation.with(inner_klass, inner_klass, context:{latch => nil})

	    parser.push outer_klass
	    parser.parse('abcdefabcdef')

	    expect(cache.length()).to eq(2)

	    expect(cache[0]).not_to be_empty
	    expect(cache[0].length()).to eq(3)

	    expect(cache[0][outer_klass]).not_to be_empty
	    expect(cache[0][outer_klass][0]).to eq(12)		# length
	    expect(cache[0][outer_klass][1]).not_to be_nil

	    expect(cache[0][inner_klass]).not_to be_empty
	    expect(cache[0][inner_klass][0]).to eq(6)		# length
	    expect(cache[0][inner_klass][1]).not_to be_nil

	    expect(cache[0][latch.grammar]).not_to be_empty
	    expect(cache[0][latch.grammar][0]).to eq(3)		# length
	    expect(cache[0][latch.grammar][1]).not_to be_nil

	    expect(cache[6]).not_to be_empty
	    expect(cache[6].length()).to eq(2)

	    expect(cache[6][inner_klass]).not_to be_empty
	    expect(cache[6][inner_klass][0]).to eq(6)		# length
	    expect(cache[6][inner_klass][1]).not_to be_nil

	    expect(cache[6][latch.grammar]).not_to be_empty
	    expect(cache[6][latch.grammar][0]).to eq(3)		# length
	    expect(cache[6][latch.grammar][1]).not_to be_nil
	end

	it 'must not cache a nested latch in an inner context' do
	    latch = Grammar::Latch.with(Grammar::Alternation.with('abc', 'xyz'))
	    inner_klass = Grammar::Concatenation.with(latch, latch, context:{latch => nil})
	    outer_klass = Grammar::Concatenation.with(inner_klass, inner_klass)

	    parser.push outer_klass
	    parser.parse('abcabcxyzxyz')

	    expect(cache.length()).to eq(4)

	    expect(cache[0].length()).to eq(3)

	    expect(cache[0][outer_klass]).not_to be_empty
	    expect(cache[0][outer_klass][0]).to eq(12)		# length
	    expect(cache[0][outer_klass][1]).not_to be_nil

	    expect(cache[0][inner_klass]).not_to be_empty
	    expect(cache[0][inner_klass][0]).to eq(6)		# length
	    expect(cache[0][inner_klass][1]).not_to be_nil

	    expect(cache[0][latch.grammar]).not_to be_empty
	    expect(cache[0][latch.grammar][0]).to eq(3)		# length
	    expect(cache[0][latch.grammar][1]).not_to be_nil

	    expect(cache[6]).not_to be_empty
	    expect(cache[6].length()).to eq(2)

	    expect(cache[6][inner_klass]).not_to be_empty
	    expect(cache[6][inner_klass][0]).to eq(6)		# length
	    expect(cache[6][inner_klass][1]).not_to be_nil

	    expect(cache[6][latch.grammar]).not_to be_empty
	    expect(cache[6][latch.grammar][0]).to eq(3)		# length
	    expect(cache[6][latch.grammar][1]).not_to be_nil
	end
    end

    context 'Grammar::Repetition' do
	it 'must cache a star-repeated Alternation' do
	    klass = Grammar::Alternation.with('abc', 'def')
	    repeat_klass = klass.at_least(0)

	    parser.push repeat_klass
	    parser.parse('abcdefabc')

	    expect(cache.length()).to eq(3)

	    expect(cache[0].length()).to eq(2)

	    expect(cache[0][repeat_klass][0]).to eq(9)	# length
	    expect(cache[0][repeat_klass][1]).not_to be_nil

	    expect(cache[0][klass][0]).to eq(3)		# length
	    expect(cache[0][klass][1]).not_to be_nil

	    expect(cache[3].length()).to eq(1)

	    expect(cache[3][klass][0]).to eq(3)		# length
	    expect(cache[3][klass][1]).not_to be_nil

	    expect(cache[6].length()).to eq(1)

	    expect(cache[6][klass][0]).to eq(3)		# length
	    expect(cache[6][klass][1]).not_to be_nil
	end

	it 'must cache a star-repeated Concatenation' do
	    klass = Grammar::Concatenation.with('abc')
	    repeat_klass = klass.at_least(0)

	    parser.push repeat_klass
	    parser.parse('abcabcabc')

	    expect(cache.length()).to eq(3)

	    expect(cache[0].length()).to eq(2)

	    expect(cache[0][repeat_klass][0]).to eq(9)	# length
	    expect(cache[0][repeat_klass][1]).not_to be_nil

	    expect(cache[0][klass][0]).to eq(3)		# length
	    expect(cache[0][klass][1]).not_to be_nil

	    expect(cache[3].length()).to eq(1)

	    expect(cache[3][klass][0]).to eq(3)		# length
	    expect(cache[3][klass][1]).not_to be_nil

	    expect(cache[6].length()).to eq(1)

	    expect(cache[6][klass][0]).to eq(3)		# length
	    expect(cache[6][klass][1]).not_to be_nil
	end

	it 'must cache a minimum-repetition' do
	    klass = Grammar::Concatenation.with('abc')
	    repeat_klass = klass.at_least(3)

	    parser.push repeat_klass
	    parser.parse('abcabcabc')

	    # The 4th match indicates a failure to repeat (as expected)
	    expect(cache.length()).to eq(4)

	    expect(cache[0].length()).to eq(2)

	    expect(cache[0][repeat_klass][0]).to eq(9)	# length
	    expect(cache[0][repeat_klass][1]).not_to be_nil

	    expect(cache[0][klass][0]).to eq(3)		# length
	    expect(cache[0][klass][1]).not_to be_nil

	    expect(cache[3].length()).to eq(1)

	    expect(cache[3][klass][0]).to eq(3)		# length
	    expect(cache[3][klass][1]).not_to be_nil

	    expect(cache[6].length()).to eq(1)

	    expect(cache[6][klass][0]).to eq(3)		# length
	    expect(cache[6][klass][1]).not_to be_nil
	end

	it 'must cache all matches of a minimum-repetition' do
	    klass = Grammar::Concatenation.with('abc')
	    repeat_klass = klass.at_least(1)

	    parser.push repeat_klass
	    parser.parse('abcabcabc')

	    expect(cache.length()).to eq(3)

	    expect(cache[0].length()).to eq(2)

	    expect(cache[0][repeat_klass][0]).to eq(9)	# length
	    expect(cache[0][repeat_klass][1]).not_to be_nil

	    expect(cache[0][klass][0]).to eq(3)		# length
	    expect(cache[0][klass][1]).not_to be_nil

	    expect(cache[3].length()).to eq(1)

	    expect(cache[3][klass][0]).to eq(3)		# length
	    expect(cache[3][klass][1]).not_to be_nil

	    expect(cache[6].length()).to eq(1)

	    expect(cache[6][klass][0]).to eq(3)		# length
	    expect(cache[6][klass][1]).not_to be_nil
	end

	it 'must cache when rejecting less than the minimum required repetitions' do
	    klass = Grammar::Concatenation.with('abc')
	    repeat_klass = klass.at_least(3)

	    parser.push repeat_klass
	    parser.parse('abc')

	    # The 2nd match is caching the fact that the repetition failed early
	    expect(cache.length()).to eq(2)

	    expect(cache[0].length()).to eq(2)

	    # The repetition failed
	    expect(cache[0][repeat_klass][0]).to eq(0)	# length
	    expect(cache[0][repeat_klass][1]).to be_nil

	    expect(cache[0][klass][0]).to eq(3)		# length
	    expect(cache[0][klass][1]).not_to be_nil

	    expect(cache[3].length()).to eq(1)

	    # An expected Concatenation failed to match
	    expect(cache[3][klass][0]).to eq(0)		# length
	    expect(cache[3][klass][1]).to be_nil
	end

	it 'must cache a maximum-repetition' do
	    klass = Grammar::Concatenation.with('abc')
	    repeat_klass = klass.at_most(3)

	    parser.push repeat_klass
	    parser.parse('abcabcabc')

	    expect(cache.length()).to eq(3)

	    expect(cache[0].length()).to eq(2)

	    expect(cache[0][repeat_klass][0]).to eq(9)	# length
	    expect(cache[0][repeat_klass][1]).not_to be_nil

	    expect(cache[0][klass][0]).to eq(3)		# length
	    expect(cache[0][klass][1]).not_to be_nil

	    expect(cache[3].length()).to eq(1)

	    expect(cache[3][klass][0]).to eq(3)		# length
	    expect(cache[3][klass][1]).not_to be_nil

	    expect(cache[6].length()).to eq(1)

	    expect(cache[6][klass][0]).to eq(3)		# length
	    expect(cache[6][klass][1]).not_to be_nil
	end

	it 'must cache when matching less than the maximum number of repetitions' do
	    klass = Grammar::Concatenation.with('abc')
	    repeat_klass = klass.at_most(3)

	    parser.push repeat_klass
	    parser.parse('abc')

	    expect(cache.length()).to eq(1)

	    expect(cache[0].length()).to eq(2)

	    expect(cache[0][repeat_klass][0]).to eq(3)	# length
	    expect(cache[0][repeat_klass][1]).not_to be_nil

	    expect(cache[0][klass][0]).to eq(3)		# length
	    expect(cache[0][klass][1]).not_to be_nil
	end

	it 'must cache when matching more than the maximum with a following match' do
	    klass = Grammar::Concatenation.with('abc')
	    repeat_klass = klass.at_most(2)
	    outer_klass = Grammar::Concatenation.with(repeat_klass, klass)

	    parser.push outer_klass
	    parser.parse('abcabcabc')

	    expect(cache.length()).to eq(3)

	    expect(cache[0].length()).to eq(3)

	    expect(cache[0][outer_klass][0]).to eq(9)	# length
	    expect(cache[0][outer_klass][1]).not_to be_nil

	    expect(cache[0][repeat_klass][0]).to eq(6)	# length
	    expect(cache[0][repeat_klass][1]).not_to be_nil

	    expect(cache[0][klass][0]).to eq(3)		# length
	    expect(cache[0][klass][1]).not_to be_nil

	    expect(cache[3].length()).to eq(1)

	    expect(cache[3][klass][0]).to eq(3)		# length
	    expect(cache[3][klass][1]).not_to be_nil

	    expect(cache[6].length()).to eq(1)

	    expect(cache[6][klass][0]).to eq(3)		# length
	    expect(cache[6][klass][1]).not_to be_nil
	end

	it 'must cache when matching more than the minimum and less than the maximum' do
	    klass = Grammar::Concatenation.with('abc')
	    repeat_klass = klass.repeat(1,3)

	    parser.push repeat_klass
	    parser.parse('abcabc')

	    expect(cache.length()).to eq(2)

	    expect(cache[0].length()).to eq(2)

	    expect(cache[0][repeat_klass][0]).to eq(6)	# length
	    expect(cache[0][repeat_klass][1]).not_to be_nil

	    expect(cache[0][klass][0]).to eq(3)		# length
	    expect(cache[0][klass][1]).not_to be_nil

	    expect(cache[3].length()).to eq(1)

	    expect(cache[3][klass][0]).to eq(3)		# length
	    expect(cache[3][klass][1]).not_to be_nil
	end

	it 'must cache when matching the minimum when there is a maximum' do
	    klass = Grammar::Concatenation.with('abc')
	    repeat_klass = klass.repeat(1,3)

	    parser.push repeat_klass
	    parser.parse('abc')

	    expect(cache.length()).to eq(2)

	    expect(cache[0].length()).to eq(2)

	    expect(cache[0][repeat_klass][0]).to eq(3)	# length
	    expect(cache[0][repeat_klass][1]).not_to be_nil

	    expect(cache[0][klass][0]).to eq(3)		# length
	    expect(cache[0][klass][1]).not_to be_nil
	end

	it 'must cache when matching the maximum when there is a minimum' do
	    klass = Grammar::Concatenation.with('abc')
	    repeat_klass = klass.repeat(1,3)

	    parser.push repeat_klass
	    parser.parse('abcabcabc')

	    expect(cache.length()).to eq(3)

	    expect(cache[0].length()).to eq(2)

	    expect(cache[0][repeat_klass][0]).to eq(9)	# length
	    expect(cache[0][repeat_klass][1]).not_to be_nil

	    expect(cache[0][klass][0]).to eq(3)		# length
	    expect(cache[0][klass][1]).not_to be_nil

	    expect(cache[3].length()).to eq(1)

	    expect(cache[3][klass][0]).to eq(3)		# length
	    expect(cache[3][klass][1]).not_to be_nil

	    expect(cache[6].length()).to eq(1)

	    expect(cache[6][klass][0]).to eq(3)		# length
	    expect(cache[6][klass][1]).not_to be_nil
	end

	context 'Ignore' do
	    let(:klass) { Grammar::Alternation.with('abc', 'def', 'xyz') }

	    # The input string has a trailing space to ensure that none of the repetition tests
	    #  consume trailing characters that match the ignore-pattern
	    let(:input) { StringScanner.new('abc def xyz ') }

	    it 'must cache while ignoring the ignore-pattern' do
		repeat_klass = Grammar::Repetition.with(klass, maximum:nil, minimum:0, ignore:/\s*/)
		parser.push repeat_klass

		parser.parse(input)

		expect(cache.length()).to be >= 3

		expect(cache[0].length()).to eq(2)

		expect(cache[0][repeat_klass][0]).to eq(11)	# length
		expect(cache[0][repeat_klass][1]).not_to be_nil

		expect(cache[0][klass][0]).to eq(3)		# length
		expect(cache[0][klass][1]).not_to be_nil

		expect(cache[4].length()).to eq(1)

		expect(cache[4][klass][0]).to eq(3)		# length
		expect(cache[4][klass][1]).not_to be_nil

		expect(cache[8].length()).to eq(1)

		expect(cache[8][klass][0]).to eq(3)		# length
		expect(cache[8][klass][1]).not_to be_nil
	    end

	    it 'must cache while accepting the maximum' do
		repeat_klass = Grammar::Repetition.with(klass, maximum:3, minimum:nil, ignore:/\s*/)
		parser.push repeat_klass

		parser.parse(input)

		expect(cache.length()).to be >= 3

		expect(cache[0].length()).to eq(2)

		expect(cache[0][repeat_klass][0]).to eq(11)	# length
		expect(cache[0][repeat_klass][1]).not_to be_nil

		expect(cache[0][klass][0]).to eq(3)		# length
		expect(cache[0][klass][1]).not_to be_nil

		expect(cache[4].length()).to eq(1)

		expect(cache[4][klass][0]).to eq(3)		# length
		expect(cache[4][klass][1]).not_to be_nil

		expect(cache[8].length()).to eq(1)

		expect(cache[8][klass][0]).to eq(3)		# length
		expect(cache[8][klass][1]).not_to be_nil
	    end

	    it 'must cache while accepting less than the maximum' do
		repeat_klass = Grammar::Repetition.with(klass, maximum:4, minimum:nil, ignore:/\s*/)
		parser.push repeat_klass

		parser.parse(input)

		expect(cache.length()).to be >= 3

		expect(cache[0].length()).to eq(2)

		expect(cache[0][repeat_klass][0]).to eq(11)	# length
		expect(cache[0][repeat_klass][1]).not_to be_nil

		expect(cache[0][klass][0]).to eq(3)		# length
		expect(cache[0][klass][1]).not_to be_nil

		expect(cache[4].length()).to eq(1)

		expect(cache[4][klass][0]).to eq(3)		# length
		expect(cache[4][klass][1]).not_to be_nil

		expect(cache[8].length()).to eq(1)

		expect(cache[8][klass][0]).to eq(3)		# length
		expect(cache[8][klass][1]).not_to be_nil
	    end

	    it 'must cache while accepting no more than the maximum' do
		repeat_klass = Grammar::Repetition.with(klass, maximum:2, minimum:nil, ignore:/\s*/)
		parser.push repeat_klass

		parser.parse(input)

		expect(cache.length()).to be >= 2

		expect(cache[0].length()).to eq(2)

		expect(cache[0][repeat_klass][0]).to eq(7)	# length
		expect(cache[0][repeat_klass][1]).not_to be_nil

		expect(cache[0][klass][0]).to eq(3)		# length
		expect(cache[0][klass][1]).not_to be_nil

		expect(cache[4].length()).to eq(1)

		expect(cache[4][klass][0]).to eq(3)		# length
		expect(cache[4][klass][1]).not_to be_nil
	    end

	    it 'must cache while accepting the minimum' do
		repeat_klass = Grammar::Repetition.with(klass, maximum:nil, minimum:3, ignore:/\s*/)
		parser.push repeat_klass

		parser.parse(input)

		expect(cache.length()).to be >= 3

		expect(cache[0].length()).to eq(2)

		expect(cache[0][repeat_klass][0]).to eq(11)	# length
		expect(cache[0][repeat_klass][1]).not_to be_nil

		expect(cache[0][klass][0]).to eq(3)		# length
		expect(cache[0][klass][1]).not_to be_nil

		expect(cache[4].length()).to eq(1)

		expect(cache[4][klass][0]).to eq(3)		# length
		expect(cache[4][klass][1]).not_to be_nil

		expect(cache[8].length()).to eq(1)

		expect(cache[8][klass][0]).to eq(3)		# length
		expect(cache[8][klass][1]).not_to be_nil
	    end

	    it 'must cache while rejecting less than the minimum' do
		repeat_klass = Grammar::Repetition.with(klass, maximum:nil, minimum:4, ignore:/\s*/)
		parser.push repeat_klass

		parser.parse(input)

		expect(cache.length()).to be >= 3

		expect(cache[0].length()).to eq(2)

		expect(cache[0][repeat_klass][0]).to eq(0)	# length
		expect(cache[0][repeat_klass][1]).to be_nil

		expect(cache[0][klass][0]).to eq(3)		# length
		expect(cache[0][klass][1]).not_to be_nil

		expect(cache[4].length()).to eq(1)

		expect(cache[4][klass][0]).to eq(3)		# length
		expect(cache[4][klass][1]).not_to be_nil

		expect(cache[8].length()).to eq(1)

		expect(cache[8][klass][0]).to eq(3)		# length
		expect(cache[8][klass][1]).not_to be_nil
	    end
	end

	context 'at least 0' do
	    it 'must cache while greedily matching a nested Alternation' do
		inner_klass = Grammar::Alternation.with('def', 'ghi')
		repeat_klass = inner_klass.at_least(0)
		klass = Grammar::Concatenation.with('abc', repeat_klass, 'z')

		parser.push klass
		parser.parse('abcdefghiz')

		expect(cache.length()).to be >= 4

		expect(cache[0].length()).to eq(1)

		expect(cache[0][klass][0]).to eq(10)		# length
		expect(cache[0][klass][1]).not_to be_nil

		expect(cache[3].length()).to eq(2)

		expect(cache[3][repeat_klass][0]).to eq(6)	# length
		expect(cache[3][repeat_klass][1]).not_to be_nil

		expect(cache[3][inner_klass][0]).to eq(3)	# length
		expect(cache[3][inner_klass][1]).not_to be_nil

		expect(cache[6].length()).to eq(1)

		expect(cache[6][inner_klass][0]).to eq(3)	# length
		expect(cache[6][inner_klass][1]).not_to be_nil
	    end

	    it 'must cache while greedily matching a nested Concatenation' do
		inner_klass = Grammar::Concatenation.with('b', 'def')
		repeat_klass = inner_klass.at_least(0)
		klass = Grammar::Concatenation.with('a', repeat_klass, 'z')

		parser.push klass
		parser.parse('abdefbdefz')

		expect(cache.length()).to be >= 3

		expect(cache[0].length()).to eq(1)

		expect(cache[0][klass][0]).to eq(10)		# length
		expect(cache[0][klass][1]).not_to be_nil

		expect(cache[1].length()).to eq(2)

		expect(cache[1][inner_klass][0]).to eq(4)	# length
		expect(cache[1][inner_klass][1]).not_to be_nil

		expect(cache[1][repeat_klass][0]).to eq(8)	# length
		expect(cache[1][repeat_klass][1]).not_to be_nil

		expect(cache[5].length()).to eq(1)

		expect(cache[5][inner_klass][0]).to eq(4)	# length
		expect(cache[5][inner_klass][1]).not_to be_nil
	    end

	    it 'must cache a repeated nested Grammar' do
		klass0 = Grammar::Alternation.with('b')
		klass1 = Grammar::Concatenation.with('c')
		inner_klass = Grammar::Concatenation.with(klass0, klass1)
		repeat_klass = inner_klass.at_least(0)
		klass = Grammar::Concatenation.with('a', repeat_klass, 'z')

		parser.push klass
		parser.parse('abcbcz')

		expect(cache.length()).to be >= 5

		expect(cache[0].length()).to eq(1)

		expect(cache[0][klass][0]).to eq(6)		# length
		expect(cache[0][klass][1]).not_to be_nil

		expect(cache[1].length()).to eq(3)

		expect(cache[1][klass0][0]).to eq(1)		# length
		expect(cache[1][klass0][1]).not_to be_nil

		expect(cache[1][repeat_klass][0]).to eq(4)	# length
		expect(cache[1][repeat_klass][1]).not_to be_nil

		expect(cache[1][inner_klass][0]).to eq(2)	# length
		expect(cache[1][inner_klass][1]).not_to be_nil

		expect(cache[2].length()).to eq(1)

		expect(cache[2][klass1][0]).to eq(1)		# length
		expect(cache[2][klass1][1]).not_to be_nil

		expect(cache[3].length()).to eq(2)

		expect(cache[3][klass0][0]).to eq(1)		# length
		expect(cache[3][klass0][1]).not_to be_nil

		expect(cache[3][klass0][0]).to eq(1)		# length
		expect(cache[3][klass0][1]).not_to be_nil

		expect(cache[4].length()).to eq(1)

		expect(cache[4][klass1][0]).to eq(1)		# length
		expect(cache[4][klass1][1]).not_to be_nil
	    end

	    it 'must cache a repeated nested Grammar' do
		klass0 = Grammar::Alternation.with('b')
		klass1 = Grammar::Concatenation.with('c')
		inner_klass = Grammar::Concatenation.with(klass0, klass1)
		repeat_klass = inner_klass.at_least(0)
		klass = Grammar::Concatenation.with('a', repeat_klass, 'z')

		parser.push klass
		parser.parse('abcbcz')

		expect(cache.length()).to be >= 5

		expect(cache[0].length()).to eq(1)

		expect(cache[0][klass][0]).to eq(6)	    # length
		expect(cache[0][klass][1]).not_to be_nil

		expect(cache[1].length()).to eq(3)

		expect(cache[1][repeat_klass][0]).to eq(4)    # length
		expect(cache[1][repeat_klass][1]).not_to be_nil

		expect(cache[1][inner_klass][0]).to eq(2)    # length
		expect(cache[1][inner_klass][1]).not_to be_nil

		expect(cache[1][klass0][0]).to eq(1)	    # length
		expect(cache[1][klass0][1]).not_to be_nil

		expect(cache[2].length()).to eq(1)

		expect(cache[2][klass1][0]).to eq(1)	    # length
		expect(cache[2][klass1][1]).not_to be_nil

		expect(cache[3].length()).to eq(2)

		expect(cache[3][inner_klass][0]).to eq(2)    # length
		expect(cache[3][inner_klass][1]).not_to be_nil

		expect(cache[3][klass0][0]).to eq(1)	    # length
		expect(cache[3][klass0][1]).not_to be_nil

		expect(cache[4].length()).to eq(1)

		expect(cache[4][klass1][0]).to eq(1)	    # length
		expect(cache[4][klass1][1]).not_to be_nil
	    end

	    it 'must cache a different repeated nested Grammar' do
		klass0 = Grammar::Alternation.with('c')
		klass1 = Grammar::Concatenation.with(klass0, 'd', 'e')
		inner_klass = Grammar::Concatenation.with('b', klass1)
		repeat_klass = inner_klass.at_least(0)
		klass = Grammar::Concatenation.with('a', repeat_klass, 'z')

		parser.push klass
		parser.parse('abcdebcdez')

		expect(cache.length()).to be >= 5

		expect(cache[0].length()).to eq(1)

		expect(cache[0][klass][0]).to eq(10)		# length
		expect(cache[0][klass][1]).not_to be_nil

		expect(cache[1].length()).to eq(2)

		expect(cache[1][repeat_klass][0]).to eq(8)	# length
		expect(cache[1][repeat_klass][1]).not_to be_nil

		expect(cache[1][inner_klass][0]).to eq(4)	# length
		expect(cache[1][inner_klass][1]).not_to be_nil

		expect(cache[2].length()).to eq(2)

		expect(cache[2][klass0][0]).to eq(1)		# length
		expect(cache[2][klass0][1]).not_to be_nil

		expect(cache[2][klass1][0]).to eq(3)		# length
		expect(cache[2][klass1][1]).not_to be_nil

		expect(cache[5].length()).to eq(1)

		expect(cache[5][inner_klass][0]).to eq(4)	# length
		expect(cache[5][inner_klass][1]).not_to be_nil

		expect(cache[6].length()).to eq(2)

		expect(cache[6][klass0][0]).to eq(1)		# length
		expect(cache[6][klass0][1]).not_to be_nil

		expect(cache[6][klass1][0]).to eq(3)		# length
		expect(cache[6][klass1][1]).not_to be_nil
	    end

	    it 'must cache while greedily matchin a trailing nested repeating Concatenation' do
		prefix_klass = Grammar::Concatenation.with('abc')
		inner_klass = Grammar::Concatenation.with('b', 'def')
		repeat_klass = inner_klass.at_least(0)
		klass = Grammar::Concatenation.with(prefix_klass, repeat_klass)

		parser.push klass
		parser.parse('abcbdefbdef')

		expect(cache.length()).to be >= 3

		expect(cache[0].length()).to eq(2)

		expect(cache[0][klass][0]).to eq(11)		# length
		expect(cache[0][klass][1]).not_to be_nil

		expect(cache[0][prefix_klass][0]).to eq(3)	# length
		expect(cache[0][prefix_klass][1]).not_to be_nil

		expect(cache[3].length()).to eq(2)

		expect(cache[3][repeat_klass][0]).to eq(8)	# length
		expect(cache[3][repeat_klass][1]).not_to be_nil

		expect(cache[3][inner_klass][0]).to eq(4)	# length
		expect(cache[3][inner_klass][1]).not_to be_nil

		expect(cache[7].length()).to eq(1)

		expect(cache[7][inner_klass][0]).to eq(4)	# length
		expect(cache[7][inner_klass][1]).not_to be_nil
	    end

	    it 'must cache a Concatenation with a nested optional Regexp that matches nothing' do
		klass = Grammar::Concatenation.with(/ ?/)
		repeat_klass = klass.any

		parser.push repeat_klass
		parser.parse('')

		expect(cache.length()).to eq(1)

		expect(cache[0].length()).to eq(3)

		expect(cache[0][repeat_klass][0]).to eq(0)	# length
		expect(cache[0][repeat_klass][1]).not_to be_nil

		expect(cache[0][klass][0]).to eq(0)		# length
		expect(cache[0][klass][1]).not_to be_nil

		expect(cache[0][/ ?/][0]).to eq(0)		# length
		expect(cache[0][/ ?/][1]).not_to be_nil
	    end
	end

	context 'at least 1' do
	    it 'must cache a String followed by a repeating Concatenation' do
		inner_klass = Grammar::Concatenation.with('b', 'def')
		repeat_klass = inner_klass.at_least(1)
		klass = Grammar::Concatenation.with('a', repeat_klass)

		parser.push klass
		parser.parse('abdefbdef')

		expect(cache.length()).to eq(3)

		expect(cache[0].length()).to eq(1)

		expect(cache[0][klass][0]).to eq(9)		# length
		expect(cache[0][klass][1]).not_to be_nil

		expect(cache[1].length()).to eq(2)

		expect(cache[1][inner_klass][0]).to eq(4)	# length
		expect(cache[1][inner_klass][1]).not_to be_nil

		expect(cache[1][repeat_klass][0]).to eq(8)	# length
		expect(cache[1][repeat_klass][1]).not_to be_nil

		expect(cache[5].length()).to eq(1)

		expect(cache[5][inner_klass][0]).to eq(4)	# length
		expect(cache[5][inner_klass][1]).not_to be_nil
	    end
	end

	context 'Optional' do
	    it 'must cache an optional nested grammar' do
		klass = Grammar::Concatenation.with('abc')
		repeat_klass = klass.optional

		parser.push repeat_klass
		parser.parse('abc')

		expect(cache.length()).to eq(1)

		expect(cache[0].length()).to eq(2)

		expect(cache[0][repeat_klass][0]).to eq(3)	# length
		expect(cache[0][repeat_klass][1]).not_to be_nil

		expect(cache[0][klass][0]).to eq(3)		# length
		expect(cache[0][klass][1]).not_to be_nil
	    end

	    it 'must not cache a missing optional nested grammar' do
		klass = Grammar::Concatenation.with('abc')
		repeat_klass = klass.optional

		parser.push repeat_klass
		parser.parse('')

		expect(cache.length()).to eq(1)

		expect(cache[0].length()).to eq(2)

		expect(cache[0][repeat_klass][0]).to eq(0)	# length
		expect(cache[0][repeat_klass][1]).to be_nil

		expect(cache[0][klass][0]).to eq(0)		# length
		expect(cache[0][klass][1]).to be_nil
	    end
	end
    end

    context 'Grammar::Recursion' do
	it 'must cache a center-recursive Concatenation' do
	    klass = Grammar::Recursion.new.tap do |wrapper|
		wrapper.grammar = Grammar::Concatenation.with('abc', wrapper, 'xyz')
		wrapper.freeze
	    end

	    parser.push klass
	    parser.parse('abcabcxyzxyz')

	    expect(cache.length()).to be >= 2

	    expect(cache[0].length()).to eq(2)

	    expect(cache[0][klass.grammar][0]).to eq(12)	# length
	    expect(cache[0][klass.grammar][1]).not_to be_nil

	    expect(cache[0][klass][0]).to eq(12)		# length
	    expect(cache[0][klass][1]).not_to be_nil

	    expect(cache[3].length()).to eq(2)

	    expect(cache[3][klass.grammar][0]).to eq(6)		# length
	    expect(cache[3][klass.grammar][1]).not_to be_nil

	    expect(cache[3][klass][0]).to eq(6)			# length
	    expect(cache[3][klass][1]).not_to be_nil

	    expect(cache[6].length()).to eq(2)

	    expect(cache[6][klass.grammar][0]).to eq(0)		# length
	    expect(cache[6][klass.grammar][1]).to be_nil

	    expect(cache[6][klass][0]).to eq(0)			# length
	    expect(cache[6][klass][1]).to be_nil
	end

	it 'must cache a right-recursive Concatenation' do
	    klass = Grammar::Recursion.new.tap do |wrapper|
		wrapper.grammar = Grammar::Concatenation.with('abc', wrapper)
		wrapper.freeze
	    end

	    parser.push klass
	    parser.parse('abcabc')

	    expect(cache.length()).to be >= 2

	    expect(cache[0].length()).to eq(2)

	    expect(cache[0][klass.grammar][0]).to eq(6)		# length
	    expect(cache[0][klass.grammar][1]).not_to be_nil

	    expect(cache[0][klass][0]).to eq(6)			# length
	    expect(cache[0][klass][1]).not_to be_nil

	    expect(cache[3].length()).to eq(2)

	    expect(cache[3][klass.grammar][0]).to eq(3)		# length
	    expect(cache[3][klass.grammar][1]).not_to be_nil

	    expect(cache[3][klass][0]).to eq(3)			# length
	    expect(cache[3][klass][1]).not_to be_nil

	    expect(cache[6].length()).to eq(2)

	    expect(cache[6][klass.grammar][0]).to eq(0)		# length
	    expect(cache[6][klass.grammar][1]).to be_nil

	    expect(cache[6][klass][0]).to eq(0)			# length
	    expect(cache[6][klass][1]).to be_nil
	end

	it 'must cache an Alternation with a nested center-recursive Concatenation' do
	    concatenation_klass = nil
	    klass = Grammar::Recursion.new.tap do |wrapper|
		concatenation_klass = Grammar::Concatenation.with('(', wrapper, ')')
		wrapper.grammar = Grammar::Alternation.with('abc', 'def', concatenation_klass)
		wrapper.freeze
	    end

	    parser.push klass
	    parser.parse('(abc)')

	    expect(cache.length()).to eq(2)

	    expect(cache[0].length()).to eq(3)

	    expect(cache[0][klass.grammar][0]).to eq(5)		# length
	    expect(cache[0][klass.grammar][1]).not_to be_nil

	    expect(cache[0][concatenation_klass][0]).to eq(5)	# length
	    expect(cache[0][concatenation_klass][1]).not_to be_nil

	    expect(cache[0][klass][0]).to eq(5)			# length
	    expect(cache[0][klass][1]).not_to be_nil

	    expect(cache[1].length()).to eq(3)

	    expect(cache[1][klass.grammar][0]).to eq(3)		# length
	    expect(cache[1][klass.grammar][1]).not_to be_nil

	    expect(cache[1][klass][0]).to eq(3)			# length
	    expect(cache[1][klass][1]).not_to be_nil

	    expect(cache[1][concatenation_klass][0]).to eq(0)	# length
	    expect(cache[1][concatenation_klass][1]).to be_nil
	end

	it 'must cache a nested outer-recursive grammar' do
	    # Testing this without using the DSL because the DSL is inconvenient to use here
	    # module Test
	    #     using Grammar::DSL
	    #     alternation :Rule0 do
	    #         element 'abc'
	    #         element concatenation { elements Rule0, ',', Rule0 }
	    #     end
	    # end

	    nested_klass = nil
	    repeat_klass = nil
	    klass = Grammar::Recursion.new.tap do |wrapper|
		nested_klass = Grammar::Concatenation.with(',', wrapper)
		repeat_klass = nested_klass.any
		wrapper.grammar = Grammar::Concatenation.with('abc', repeat_klass)
		wrapper.freeze
	    end

	    parser.push klass
	    parser.parse('abc,abc')

	    expect(cache.length()).to eq(4)

	    expect(cache[0].length()).to eq(2)

	    expect(cache[0][klass.grammar][0]).to eq(7)		# length
	    expect(cache[0][klass.grammar][1]).not_to be_nil

	    expect(cache[0][klass][0]).to eq(7)			# length
	    expect(cache[0][klass][1]).not_to be_nil

	    expect(cache[3].length()).to eq(2)

	    expect(cache[3][repeat_klass][0]).to eq(4)		# length
	    expect(cache[3][repeat_klass][1]).not_to be_nil

	    expect(cache[3][nested_klass][0]).to eq(4)		# length
	    expect(cache[3][nested_klass][1]).not_to be_nil

	    expect(cache[4].length()).to eq(2)

	    expect(cache[4][klass.grammar][0]).to eq(3)		# length
	    expect(cache[4][klass.grammar][1]).not_to be_nil

	    expect(cache[4][klass][0]).to eq(3)			# length
	    expect(cache[4][klass][1]).not_to be_nil

	    expect(cache[7].length()).to eq(2)

	    expect(cache[7][repeat_klass][0]).to eq(0)		# length
	    expect(cache[7][repeat_klass][1]).not_to be_nil

	    expect(cache[7][nested_klass][0]).to eq(0)		# length
	    expect(cache[7][nested_klass][1]).to be_nil
	end

	context 'Mutual Recursion' do
	    it 'must cache a mutually recursive Alternation with nested Concatenations' do
		klassA = nil
		klassB = nil
		klass = Grammar::Recursion.new.tap do |wrapper|
		    klassA = Grammar::Concatenation.with('xyz', wrapper)
		    klassB = Grammar::Concatenation.with('uvw', wrapper)
		    wrapper.grammar = Grammar::Alternation.with('abc', 'def', klassA, klassB)
		    wrapper.freeze
		end

		parser.push klass
		parser.parse('xyzabc')

		expect(cache.length()).to eq(2)

		expect(cache[0].length()).to eq(4)

		expect(cache[0][klass.grammar][0]).to eq(6)	# length
		expect(cache[0][klass.grammar][1]).not_to be_nil

		expect(cache[0][klassA][0]).to eq(6)		# length
		expect(cache[0][klassA][1]).not_to be_nil

		expect(cache[0][klassB][0]).to eq(0)		# length
		expect(cache[0][klassB][1]).to be_nil

		expect(cache[0][klass][0]).to eq(6)		# length
		expect(cache[0][klass][1]).not_to be_nil

		expect(cache[3].length()).to eq(4)

		expect(cache[3][klass.grammar][0]).to eq(3)	# length
		expect(cache[3][klass.grammar][1]).not_to be_nil

		expect(cache[3][klass][0]).to eq(3)		# length
		expect(cache[3][klass][1]).not_to be_nil

		expect(cache[3][klassA][0]).to eq(0)		# length
		expect(cache[3][klassA][1]).to be_nil

		expect(cache[3][klassB][0]).to eq(0)		# length
		expect(cache[3][klassB][1]).to be_nil
	    end

	    it 'must cache a mutually recursive Concatenation with nested Alternations' do
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

		expect(cache.length()).to eq(3)

		expect(cache[0].length()).to eq(2)

		expect(cache[0][klass.grammar][0]).to eq(12)	# length
		expect(cache[0][klass.grammar][1]).not_to be_nil

		expect(cache[0][klass][0]).to eq(12)		# length
		expect(cache[0][klass][1]).not_to be_nil

		expect(cache[3].length()).to eq(3)

		expect(cache[3][klass.grammar][0]).to eq(0)	# length
		expect(cache[3][klass.grammar][1]).to be_nil

		expect(cache[3][klassA][0]).to eq(3)		# length
		expect(cache[3][klassA][1]).not_to be_nil

		expect(cache[3][klass][0]).to eq(0)		# length
		expect(cache[3][klass][1]).to be_nil

		expect(cache[6].length()).to eq(3)

		expect(cache[6][klass.grammar][0]).to eq(0)	# length
		expect(cache[6][klass.grammar][1]).to be_nil

		expect(cache[6][klass][0]).to eq(0)		# length
		expect(cache[6][klass][1]).to be_nil

		expect(cache[6][klassB][0]).to eq(3)		# length
		expect(cache[6][klassB][1]).not_to be_nil
	    end
	end
    end
end
