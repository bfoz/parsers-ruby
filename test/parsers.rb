require 'stringio'

require 'parsers'

RSpec.describe Parsers do
    it 'must load a BNF file into an appropriate parser' do
	expect(Parsers.load(StringIO.new('<digit> ::= "0" | "1"'))).to be_a(Parsers::RecursiveDescent)
    end

    it 'must load an EBNF file into an appropriate parser' do
	expect(Parsers.load(StringIO.new('rule = "abc" | "xyz";'))).to be_a(Parsers::RecursiveDescent)
    end

    context 'Convert to EBNF' do
	def stringify(*args, eol:'')
	    args.join(eol+"\n") + eol
	end

	def rules(_rules, separator:' = ', eol:)
	    stringify(_rules.map {|a| a.join(separator)}, eol:eol)
	end

	def ebnf(_rules)
	    rules(_rules, separator:' = ', eol:' ;')
	end

	it 'must properly handle references to identical rules' do
	    rule3 = 'xyz'
	    rule4 = 'xyz'
	    expect(Parsers.rules_to_ebnf({
		'rule1' => Grammar::Concatenation.with('abc', Parsers::RuleReference.new('rule3', rule3)),
		'rule2' => Grammar::Concatenation.with('def', Parsers::RuleReference.new('rule4', rule4)),
		'rule3' => rule3,
		'rule4' => rule4
	    })).to eq(ebnf(
		rule1:'"abc" rule3',
		rule2:'"def" rule4',
		rule3:'"xyz"',
		rule4:'"xyz"'
	    ))
	end

	it 'must properly handle recursive references to identical rules' do
	    rule3 = 'xyz'
	    rule4 = 'xyz'
	    expect(Parsers.rules_to_ebnf({
		'rule1' => Grammar::Concatenation.with('abc', Parsers::RecursiveReference.new('rule3', rule3)),
		'rule2' => Grammar::Concatenation.with('def', Parsers::RecursiveReference.new('rule4', rule4)),
		'rule3' => rule3,
		'rule4' => rule4
	    })).to eq(ebnf(
		rule1:'"abc" rule3',
		rule2:'"def" rule4',
		rule3:'"xyz"',
		rule4:'"xyz"'
	    ))
	end
    end
end
