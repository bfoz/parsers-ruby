require 'stringio'

require 'parsers/ebnf'

RSpec.describe Parsers::EBNF do
    def stringify(*args)
	StringIO.new(args.join(";\n") + ';')
    end

    it 'must read a simple grammar from a file' do
	expect(Parsers::EBNF.read(stringify('rule = "abc"'))).to eq({'rule' => 'abc'})
	expect(Parsers::EBNF.read(stringify('rule = "abc" | "xyz"'))).to eq({'rule' => Grammar::Alternation.with('abc', 'xyz')})
	expect(Parsers::EBNF.read(stringify('rule = "abc", "def"'))).to eq({'rule' => Grammar::Concatenation.with('abc', 'def')})
	expect(Parsers::EBNF.read(stringify('rule = "abc", "def" | "xyz"'))).to eq({'rule' => Grammar::Alternation.with(Grammar::Concatenation.with('abc', 'def'), 'xyz')})
    end

    it 'must read multiple rules from a file' do
	expect(Parsers::EBNF.read(stringify('rule0 = "abc"', 'rule1 = "xyz"'))).to eq({'rule0' => 'abc', 'rule1' => 'xyz'})
    end

    it 'must read a grouped rule' do
	expect(Parsers::EBNF.read(stringify('rule = ("abc")'))).to eq({'rule' => 'abc'})
	expect(Parsers::EBNF.read(stringify('rule = ("abc" | "def")'))).to eq({'rule' => Grammar::Alternation.with('abc', 'def')})
    end

    context 'Recursion' do
	it 'must read a direct left-right recursive grammar from a file' do
	    expect(Parsers::EBNF.read(stringify('rule = "abc", "def" | rule, rule'))).to eq({"rule" => Grammar::Concatenation.with('abc', 'def').at_least(1)})
	end

	it 'must read a direct left recursive grammar from a file' do
	    expect(Parsers::EBNF.read(stringify('rule = "abc", "def" | rule, "xyz"'))).to eq({"rule" => Grammar::Concatenation.with('abc', 'def', Grammar::Repetition.any('xyz'))})

	    # Left-recursion that can be converted to an at_least(1) repetition
	    expect(Parsers::EBNF.read(stringify('rule = "abc" | rule, "abc"'))).to eq({"rule" => Grammar::Repetition.at_least(1, 'abc')})
	    expect(Parsers::EBNF.read(stringify('rule = "abc", "def" | rule, "abc", "def"'))).to eq({"rule" => Grammar::Concatenation.with('abc', 'def').at_least(1)})
	end

	it 'must read a direct right recursive grammar from a file' do
	    expect(Parsers::EBNF.read(stringify('rule = "abc", "def" | "xyz", rule'))).to eq({"rule" => Grammar::Concatenation.with(Grammar::Repetition.any('xyz'), 'abc', 'def')})

	    # Right-recursion that can be converted to an at_least(1) repetition
	    expect(Parsers::EBNF.read(stringify('rule = "abc" | "abc", rule'))).to eq({"rule" => Grammar::Repetition.at_least(1, 'abc')})
	    expect(Parsers::EBNF.read(stringify('rule = "abc", "def" | "abc", "def", rule'))).to eq({"rule" => Grammar::Concatenation.with('abc', 'def').at_least(1)})
	end
    end

    context 'References' do
	it 'must resolve backwards rule references' do
	    rule0 = Grammar::Concatenation.with('abc', 'def')
	    expect(Parsers::EBNF.read(stringify('rule0="abc", "def"', 'rule1="xyz", rule0'))).to eq({'rule0' => rule0, 'rule1' => Grammar::Concatenation.with('xyz', rule0)})
	end

	it 'must resolve forward rule references' do
	    rule1 = Grammar::Concatenation.with('def', 'xyz')
	    expect(Parsers::EBNF.read(stringify('rule0="abc", rule1', 'rule1="def", "xyz"'))).to eq({'rule0' => Grammar::Concatenation.with('abc', rule1), 'rule1' => rule1})
	end

	it 'must list the root-most rule first' do
	    expect(Parsers::EBNF.read(stringify('rule0="abc", "def"', 'rule1="xyz", rule0')).first.first).to eq('rule1')
	end
    end

    context 'Repetition' do
	it 'must read an optional group rule' do
	    expect(Parsers::EBNF.read(stringify('rule = ["abc"]'))).to eq({'rule' => Grammar::Repetition.optional('abc')})
	end

	it 'must read a repetition group rule' do
	    expect(Parsers::EBNF.read(stringify('rule = {"abc"}'))).to eq({'rule' => Grammar::Repetition.any('abc')})
	    expect(Parsers::EBNF.read(stringify('rule = {"abc", "def"}'))).to eq({'rule' => Grammar::Repetition.any(Grammar::Concatenation.with('abc', 'def'))})
	    expect(Parsers::EBNF.read(stringify('rule = {"abc" | "def"}'))).to eq({'rule' => Grammar::Repetition.any(Grammar::Alternation.with('abc', 'def'))})
	end

	it 'must read a group nested in a repetition group' do
	    expect(Parsers::EBNF.read(stringify('rule = {("abc", "def")}'))).to eq({'rule' => Grammar::Repetition.any(Grammar::Concatenation.with('abc', 'def'))})
	    expect(Parsers::EBNF.read(stringify('rule = {("abc" | "def")}'))).to eq({'rule' => Grammar::Repetition.any(Grammar::Alternation.with('abc', 'def'))})
	end
    end
end
