require_relative 'parsers/bnf'
require_relative 'parsers/ebnf'
require_relative 'parsers/w3c_ebnf'
require_relative 'parsers/recursive_descent'

module Parsers
    RuleReference = Struct.new(:rule_name, :rule)

    def self.dump(rules, filename)
	# Detect the output type from the filename
	if filename.end_with?('.ebnf')
	    File.open(filename, 'w') do |file|
		file.write(rules_to_ebnf(rules))
	    end
	else
	    # Default to returning a String in EBNF format
	    rules_to_ebnf(rules)
	end
    end

    # Read from a grammar file and load the grammar into an appropriate parser
    # @return [Parser]  a new Parser loaded with the given grammar
    def self.load(filename)
	grammar = self.read(filename)
	return unless grammar
	RecursiveDescent.new(grammar.values.first)
    end

    # Read from a grammar file
    # @param path [IO,String]	the file, or IO-like object, to read the grammar from
    # @return [Grammar] the grammer contained in the file given by _path_
    def self.read(path)
	BNF.read(path) or EBNF.read(path) or W3C_EBNF.read(path)
    end

    def self.repetition_to_ebnf(repetition, rules)
    	raise StandardError.new('EBNF does not support maximum-repetitions') if repetition.maximum

	ebnf = self.rule_to_ebnf(rules, repetition.grammar)
	if ebnf
	    Array.new((repetition.minimum or 0), ebnf).join(' ') + ' { ' + ebnf + ' }'
	end
    end

    def self.string_to_ebnf(element)
	s = element.to_s
	if s == '"'
	    "'\"'"
	else
	    s.dump
	end
    end

    def self.element_to_ebnf(rules, element)
	# If the Grammar element is in rules, use the key as the name, otherwise stringify the Pattern
	if not (Parsers::RuleReference === element) and rules.has_value?(element)
	    rules.key(element)
	else
	    self.rule_to_ebnf(rules, element)
	end
    end

    def self.rule_to_ebnf(rules, rule)
	case rule
	    when String				then self.string_to_ebnf(rule)          # Handle String here because Alternations don't like to be compared with them
	    when Grammar::Alternation		then rule.map {|element| self.element_to_ebnf(rules, element) }.join(" | ")
	    when Grammar::Concatenation		then rule.map {|element| self.element_to_ebnf(rules, element) }.join(" ")
	    when Grammar::Recursion		then self.element_to_ebnf(rules, rule.grammar)
	    when Grammar::Repetition		then self.repetition_to_ebnf(rule, rules)
	    when Parsers::RuleReference 	then rule.rule_name or self.element_to_ebnf(rules, rule.rule)
	end
    end

    # @return [String]    A new String containing the serialized form of the given rule set
    def self.rules_to_ebnf(rules)
	rules.transform_values do |rule|
	    self.rule_to_ebnf(rules, rule)
	end.map do |rule_name, rule|
	    "#{rule_name} = #{rule}"
	end.join(" ;\n") + " ;"
    end
end
