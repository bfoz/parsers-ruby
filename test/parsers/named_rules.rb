require 'parsers/named_rules'

RSpec.describe Parsers::NamedRules do
    it 'must initialize from a Hash of rules' do
	rules = Parsers::NamedRules.new('rule1' => Grammar::Alternation.with('abc'), 'rule2' => Grammar::Concatenation.with())
	expect(rules['rule1']).to eq(Grammar::Alternation.with('abc'))
	expect(rules['rule2']).not_to eq(Grammar::Alternation.with('abc'))
    end

    describe 'Export to Ruby' do
	it 'must convert a single Alternation to ruby' do
	    rules = Parsers::NamedRules.new('rule1' => Grammar::Alternation.with('abc'))
	    expect(rules.to_ruby).to eq("rule1\t= 'abc'\n")
	end

	it 'must convert a single Concatenation to ruby' do
	    rules = Parsers::NamedRules.new('rule1' => Grammar::Concatenation.with('abc'))
	    expect(rules.to_ruby).to eq("rule1\t= \"abc\"\n")
	end

	it 'must convert a single named repetition to ruby' do
	    rules = Parsers::NamedRules.new('rule1' => Grammar::Alternation.with('abc', 'xyz').at_least(1))
	    expect(rules.to_ruby).to eq("rule1\t= ('abc' | 'xyz').at_least(1)\n")
	end

	it 'must convert multiple rules' do
	    rules = Parsers::NamedRules.new('rule1' => Grammar::Alternation.with('abc'), 'rule2' => Grammar::Concatenation.with('xyz'))
	    expect(rules.to_ruby).to eq("rule1\t= 'abc'\nrule2\t= \"xyz\"\n")
	end

	it 'must sort rules according to references' do
	    rules = Parsers::NamedRules.new('rule1' => Grammar::Alternation.with('abc', Parsers::RuleReference.new('rule2', nil)), 'rule2' => Grammar::Concatenation.with('xyz'))
	    expect(rules.to_ruby).to eq("rule2\t= \"xyz\"\nrule1\t= alternation(\"abc\", rule2)\n")
	end

	it 'must convert a recursive rule' do
	    rules = Parsers::NamedRules.new('rule1' => Grammar::Alternation.with('abc', Parsers::RecursiveReference.new('rule1', nil)))
	    expect(rules.to_ruby).to eq("rule1\t= alternation do |rule1|\n\telement \"abc\"\n\telement rule1\nend\n")
	end

	it 'must nest indirectly recursive rules' do
	    rules = Parsers::NamedRules.new(
		'rule1' => Grammar::Alternation.with('abc', Parsers::RuleReference.new('rule2', nil)),
		'rule2' => Grammar::Concatenation.with('xyz', Parsers::RuleReference.new('rule1', nil))
	    )
	    expect(rules.to_ruby).to eq("rule1\t= alternation do |rule1|\n\trule2 = concatenation(\"xyz\", rule1)\n\n\telement \"abc\"\n\telement rule2\nend\n")
	end

	it 'must properly nest multiply indirectly recursive rules' do
	    rules = Parsers::NamedRules.new(
		'rule1' => Grammar::Alternation.with('abc', Parsers::RuleReference.new('rule2', nil)),
		'rule2' => Grammar::Concatenation.with('xyz', Parsers::RuleReference.new('rule3', nil)),
		'rule3' => Grammar::Concatenation.with('def', Parsers::RuleReference.new('rule1', nil))
	    )

	    expect(rules.to_ruby).to eq(<<~EOS
		rule1	= alternation do |rule1|
			rule3 = concatenation("def", rule1)
			rule2 = concatenation("xyz", rule3)

			element "abc"
			element rule2
		end
	    EOS
	    )
	end

	it 'must nest indirectly recursive rules with a common sub-rule' do
	    rules = Parsers::NamedRules.new(
		'rule1' => Grammar::Alternation.with('abc', Parsers::RuleReference.new('rule2', nil), Parsers::RuleReference.new('rule3', nil)),
		'rule2' => Grammar::Concatenation.with('xyz', Parsers::RuleReference.new('rule4', nil)),
		'rule3' => Grammar::Concatenation.with('abc', Parsers::RuleReference.new('rule4', nil)),
		'rule4' => Grammar::Concatenation.with('def', Parsers::RuleReference.new('rule1', nil))
	    )

	    expect(rules.to_ruby).to eq(<<~EOS
		rule1	= alternation do |rule1|
			rule4 = concatenation("def", rule1)
			rule2 = concatenation("xyz", rule4)
			rule3 = concatenation("abc", rule4)

			element "abc"
			element rule2
			element rule3
		end
	    EOS
	    )
	end

	it 'must nest multiply indirectly recursive rules with a common internal cycle' do
	    rules = Parsers::NamedRules.new(
		'rule0' => Grammar::Concatenation.with('abc', Parsers::RuleReference.new('rule1', nil)),
		'rule1' => Grammar::Alternation.with('abc', Parsers::RuleReference.new('rule2', nil), Parsers::RuleReference.new('rule3', nil)),
		'rule2' => Grammar::Concatenation.with('def', Parsers::RuleReference.new('rule4', nil)),
		'rule3' => Grammar::Concatenation.with('ghi', Parsers::RuleReference.new('rule4', nil)),
		'rule4' => Grammar::Concatenation.with('uvw', Parsers::RuleReference.new('rule5', nil)),
		'rule5' => Grammar::Concatenation.with('xyz', Parsers::RuleReference.new('rule1', nil))
	    )

	    expect(rules.to_ruby).to eq(<<~EOS
		rule1	= alternation do |rule1|
			rule5 = concatenation("xyz", rule1)
			rule4 = concatenation("uvw", rule5)
			rule2 = concatenation("def", rule4)
			rule3 = concatenation("ghi", rule4)

			element "abc"
			element rule2
			element rule3
		end
		rule0	= concatenation("abc", rule1)
	    EOS
	    )
	end
    end
end
