require 'stringio'

require 'parsers/w3c_ebnf'

RSpec.describe Parsers::W3C_EBNF do
    def stringify(*args)
	StringIO.new(args.join("\n") )
    end

    def rules(_rules)
	stringify(_rules.map {|a| a.join(' ::= ')})
    end

    def read(_rules)
	Parsers::W3C_EBNF.read(rules(_rules))
    end

    it 'must read a simple grammar from a file' do
	expect(Parsers::W3C_EBNF.read(stringify('rule ::= "abc"'))).to eq({'rule' => 'abc'})
	expect(Parsers::W3C_EBNF.read(stringify('rule ::= "abc" | "xyz"'))).to eq({'rule' => Grammar::Alternation.with('abc', 'xyz')})
	expect(Parsers::W3C_EBNF.read(stringify('rule ::= "abc" "def"'))).to eq({'rule' => Grammar::Concatenation.with('abc', 'def')})
    end

    it 'must give precedence to concatenation over alternation' do
	expect(Parsers::W3C_EBNF.read(stringify('rule ::= "abc" "def" | "xyz"'))).to eq({'rule' => Grammar::Alternation.with(Grammar::Concatenation.with('abc', 'def'), 'xyz')})
    end

    it 'must read multiple rules from a file' do
	expect(Parsers::W3C_EBNF.read(stringify('rule0 ::= "abc"', 'rule1 ::= "xyz"'))).to eq({'rule0' => 'abc', 'rule1' => 'xyz'})
    end

    it 'must read a grouped rule' do
	expect(Parsers::W3C_EBNF.read(stringify('rule ::= ("abc")'))).to eq({'rule' => 'abc'})
	expect(Parsers::W3C_EBNF.read(stringify('rule ::= ("abc" | "def")'))).to eq({'rule' => Grammar::Alternation.with('abc', 'def')})
    end

    context 'Recursion' do
	it 'must read a direct left-right recursive grammar from a file' do
	    expect(Parsers::W3C_EBNF.read(stringify('rule ::= "abc" "def" | rule rule'))).to eq({"rule" => Grammar::Concatenation.with('abc', 'def').at_least(1)})
	end

	it 'must read a direct left recursive grammar from a file' do
	    expect(Parsers::W3C_EBNF.read(stringify('rule ::= "abc" "def" | rule "xyz"'))).to eq({"rule" => Grammar::Concatenation.with('abc', 'def', Grammar::Repetition.any('xyz'))})

	    # Left-recursion that can be converted to an at_least(1) repetition
	    expect(Parsers::W3C_EBNF.read(stringify('rule ::= "abc" | rule "abc"'))).to eq({"rule" => Grammar::Repetition.at_least(1, 'abc')})
	    expect(Parsers::W3C_EBNF.read(stringify('rule ::= "abc" "def" | rule "abc" "def"'))).to eq({"rule" => Grammar::Concatenation.with('abc', 'def').at_least(1)})
	end

	it 'must read a multiply direct left recursive alternation' do
	    expect(read(rule: '"abc" | rule "def" | rule "xyz"')).to eq({'rule' => Grammar::Concatenation.with('abc', Grammar::Alternation.with('def', 'xyz').any)})
	end

	it 'must read a direct right recursive grammar from a file' do
	    expect(Parsers::W3C_EBNF.read(stringify('rule ::= "abc" "def" | "xyz" rule'))).to eq({"rule" => Grammar::Concatenation.with(Grammar::Repetition.any('xyz'), 'abc', 'def')})

	    # Right-recursion that can be converted to an at_least(1) repetition
	    expect(Parsers::W3C_EBNF.read(stringify('rule ::= "abc" | "abc" rule'))).to eq({"rule" => Grammar::Repetition.at_least(1, 'abc')})
	    expect(Parsers::W3C_EBNF.read(stringify('rule ::= "abc" "def" | "abc" "def" rule'))).to eq({"rule" => Grammar::Concatenation.with('abc', 'def').at_least(1)})
	end

	it 'must read a simple indirectly recursive grammar' do
	    recursion = Grammar::Recursion.new
	    rule3 = Grammar::Alternation.with('xyz', recursion)
	    rule2 = Grammar::Alternation.with('def', rule3)
	    rule1 = Grammar::Alternation.with('abc', rule2)
	    recursion.grammar = rule1

	    expect(read('rule1' => '"abc" | rule2', 'rule2' => '"def" | rule3', 'rule3' => '"xyz" | rule1')).to eq({'rule1'=>rule1, 'rule2'=>rule2, 'rule3'=>rule3})
	end

	it 'must read an indirectly recursive grammar' do
	    recursion = Grammar::Recursion.new
	    rule3 = Grammar::Alternation.with('xyz', recursion)
	    rule2 = Grammar::Alternation.with('def', rule3)
	    rule1 = Grammar::Alternation.with('abc', rule2)
	    recursion.grammar = rule1
	    rule4 = Grammar::Concatenation.with('abc', recursion)

	    expect(read('rule1' => '"abc" | rule2', 'rule2' => '"def" | rule3', 'rule3' => '"xyz" | rule1', 'rule4' => '"abc" rule1')).to eq({'rule4'=>rule4, 'rule1'=>rule1, 'rule2'=>rule2, 'rule3'=>rule3})
	end

	it 'must read a multiply indirectly recursive grammar' do
	    recursion0 = Grammar::Recursion.new
	    rule3 = Grammar::Alternation.with('xyz', recursion0)
	    rule2 = Grammar::Alternation.with('def', rule3)
	    rule1 = Grammar::Alternation.with('abc', rule2)
	    recursion0.grammar = rule1

	    recursion1 = Grammar::Recursion.new
	    rule7 = Grammar::Alternation.with('zyx', recursion1)
	    rule6 = Grammar::Alternation.with('fed', rule7)
	    rule5 = Grammar::Alternation.with('cba', rule6)
	    recursion1.grammar = rule5

	    rule4 = Grammar::Concatenation.with('abc', recursion0, recursion1)

	    expect(read(
		'rule1' => '"abc" | rule2',
		'rule2' => '"def" | rule3',
		'rule3' => '"xyz" | rule1',
		'rule4' => '"abc" rule1 rule5',
		'rule5' => '"cba" | rule6',
		'rule6' => '"fed" | rule7',
		'rule7' => '"zyx" | rule5'
	    )).to eq({
		'rule4'=>rule4,		# The root rule should always be first
		'rule1'=>rule1,
		'rule2'=>rule2,
		'rule3'=>rule3,
		'rule5'=>rule5,
		'rule6'=>rule6,
		'rule7'=>rule7
	    })
	end

	it 'must read a nested indirectly recursive grammar' do
	    recursion = Grammar::Recursion.new
	    rule3 = Grammar::Alternation.with('xyz', recursion)
	    rule2 = Grammar::Alternation.with('def', rule3)
	    rule1 = Grammar::Alternation.with('abc', rule2)
	    recursion.grammar = rule1

	    expect(read('rule1' => '"abc" | rule2', 'rule2' => '"def" | (rule3)', 'rule3' => '"xyz" | rule1')).to eq({'rule1'=>rule1, 'rule2'=>rule2, 'rule3'=>rule3})
	end
    end

    context 'References' do
	it 'must resolve backwards rule references' do
	    rule0 = Grammar::Concatenation.with('abc', 'def')
	    expect(Parsers::W3C_EBNF.read(stringify('rule0::="abc" "def"', 'rule1::="xyz" rule0'))).to eq({'rule0' => rule0, 'rule1' => Grammar::Concatenation.with('xyz', rule0)})
	end

	it 'must resolve forward rule references' do
	    rule1 = Grammar::Concatenation.with('def', 'xyz')
	    expect(Parsers::W3C_EBNF.read(stringify('rule0::="abc" rule1', 'rule1::="def" "xyz"'))).to eq({'rule0' => Grammar::Concatenation.with('abc', rule1), 'rule1' => rule1})
	end

	it 'must list the root-most rule first' do
	    expect(Parsers::W3C_EBNF.read(stringify('rule0::="abc" "def"', 'rule1::="xyz" rule0')).first.first).to eq('rule1')
	end
    end

    context 'Repetition' do
	it 'must read an optional group rule' do
	    expect(Parsers::W3C_EBNF.read(stringify('rule ::= "abc"?'))).to eq({'rule' => Grammar::Repetition.optional('abc')})
	    expect(Parsers::W3C_EBNF.read(stringify('rule ::= ("abc" "def")?'))).to eq({'rule' => Grammar::Repetition.optional(Grammar::Concatenation.with('abc', 'def'))})
	    expect(Parsers::W3C_EBNF.read(stringify('rule ::= ("abc" | "def")?'))).to eq({'rule' => Grammar::Repetition.optional(Grammar::Alternation.with('abc', 'def'))})
	end

	it 'must read a repetition group rule' do
	    expect(Parsers::W3C_EBNF.read(stringify('rule ::= "abc"*'))).to eq({'rule' => Grammar::Repetition.any('abc')})
	    expect(Parsers::W3C_EBNF.read(stringify('rule ::= ("abc" "def")*'))).to eq({'rule' => Grammar::Repetition.any(Grammar::Concatenation.with('abc', 'def'))})
	    expect(Parsers::W3C_EBNF.read(stringify('rule ::= ("abc" | "def")*'))).to eq({'rule' => Grammar::Repetition.any(Grammar::Alternation.with('abc', 'def'))})
	end

	it 'must read a group nested in a repetition group' do
	    expect(Parsers::W3C_EBNF.read(stringify('rule ::= (("abc" "def"))*'))).to eq({'rule' => Grammar::Repetition.any(Grammar::Concatenation.with('abc', 'def'))})
	    expect(Parsers::W3C_EBNF.read(stringify('rule ::= (("abc" | "def"))*'))).to eq({'rule' => Grammar::Repetition.any(Grammar::Alternation.with('abc', 'def'))})
	end
    end
end
