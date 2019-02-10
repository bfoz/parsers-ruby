require 'grammar/dsl'

require_relative 'recursive_descent'

module Parsers
    # https://en.wikipedia.org/wiki/Backus-Naur_form
    module BNF
	using Grammar::DSL

	# <character>      ::= <letter> | <digit> | <symbol>
	# <letter>         ::= "A" | "B" | "C" | "D" | "E" | "F" | "G" | "H" | "I" | "J" | "K" | "L" | "M" | "N" | "O" | "P" | "Q" | "R" | "S" | "T" | "U" | "V" | "W" | "X" | "Y" | "Z" | "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" | "j" | "k" | "l" | "m" | "n" | "o" | "p" | "q" | "r" | "s" | "t" | "u" | "v" | "w" | "x" | "y" | "z"
	# <digit>          ::= "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9"
	# <symbol>         ::=  "|" | " " | "!" | "#" | "$" | "%" | "&" | "(" | ")" | "*" | "+" | "," | "-" | "." | "/" | ":" | ";" | ">" | "=" | "<" | "?" | "@" | "[" | "\" | "]" | "^" | "_" | "`" | "{" | "}" | "~"
	Character = /[a-zA-Z0-9 -!#-&(-\/:-@\[-`{-~]/	# Everything except single- and double-quotes

	# <character1>     ::= <character> | "'"
	Character1 = alternation(Character, "'")

	# <character2>     ::= <character> | '"'
	Character2 = alternation(Character, '"')

	# <literal>        ::= '"' <text1> '"' | "'" <text2> "'"
	# <text1>          ::= "" | <character1> <text1>
	# <text2>          ::= "" | <character2> <text2>
	Literal = concatenation('"', Character1.any, '"') | concatenation("'", Character2.any, "'")

	# <rule-char>      ::= <letter> | <digit> | "-"
	# <rule-name>      ::= <letter> | <rule-name> <rule-char>
	RuleName = /[a-zA-Z0-9-]*/

	Identifier = concatenation('<', RuleName, '>')

	# <term>           ::= <literal> | "<" <rule-name> ">"
	Terminal = Literal | Identifier

	# <opt-whitespace> ::= " " <opt-whitespace> | ""
	OptWhitespace = /[ \t\f\v]*/

	# <list>           ::= <term> | <term> <opt-whitespace> <list>
	List = concatenation(Terminal, concatenation(OptWhitespace, Terminal).any)

	# <expression>     ::= <list> | <list> <opt-whitespace> "|" <opt-whitespace> <expression>
	Expression = concatenation(List, concatenation(OptWhitespace, /\|/, OptWhitespace, List).any)

	# A rule for <EOL> needs to be added here because it's a special token in BNF files,
	#  but it isn't explicitly represented in the BNF grammar.
	# EOL matches the "system" newline character(s)
	EOL = alternation("\n", "\r\n")

	# <rule>           ::= <opt-whitespace> "<" <rule-name> ">" <opt-whitespace> "::=" <opt-whitespace> <expression> <line-end>
	# <line-end>       ::= <opt-whitespace> <EOL> | <line-end> <line-end>
	Rule = concatenation(Identifier, OptWhitespace, '::=', OptWhitespace, Expression)

	# <syntax>         ::= <rule> | <rule> <syntax>
	Syntax = concatenation(/\s*/, Rule, concatenation(/( *[\r]?\n)+/, Rule).any)

	class Expression
	    def to_a
		[self.first, *self.last.map(&:last)]
	    end
	end

	class Rule
	    def rhs
		self.last
	    end

	    def rule_name
		self.first[1]
	    end
	end

	class Syntax
	    def to_a
		[self[1], *self.last.map(&:last)]
	    end
	end

	# Parse the given input and return a single parse tree, or nil
	# @param [String]	the input string to be parsed
	# @return [Grammar]
	def self.parse(input)
	    matches = Parsers::RecursiveDescent.new(BNF::Syntax).parse(input)

	    # A proper BNF file should have only a single valid parse
	    return matches.first if 1 == matches&.length
	end

	# @param rules [Hash]
	def self.convert_expression(expression_name, expression, rules, reference_counts, recursions:)
	    flattened_expression = [expression.first, *expression.last.map(&:last)]
	    is_recursive = false

	    # Each of the Expression's elements is potentially a Concatenation
	    mapped_expression = flattened_expression.map.with_index do |_list, i|
		flattened_list = [_list.first, *_list.last.map(&:last)]
		mapped_list = flattened_list.map.with_index do |_terminal, j|
		    if BNF::Literal === _terminal.match
			# The terminal is a quoted string, so just extract it
			_terminal.match.match[1].reduce('') {|memo, character| memo + character.to_s }
		    else
			# The terminal is a rule-reference, which needs to be mapped to the referenced rule
			reference_name = _terminal.match[1].to_s
			# NOTE The order of this conditional is important
			if rules[reference_name] and not recursions.key?(reference_name)
			# if rules[reference_name]
			    # If the referenced rule has already been converted, just use it
			    reference_counts[reference_name] += 1
			    rules[reference_name]
			elsif expression_name == reference_name		# Direct recursive?
			    if j.zero?
				is_recursive = [i, :left]
			    elsif j == (flattened_list.length - 1)
				if is_recursive and (is_recursive == [i, :left])
				    # If this list is already marked as left-recursive, and it's now found to also be right recursive,
				    #  then it must be both-recursive
				    is_recursive = [i, :both]
				else
				    is_recursive = [i, :right]
				end
			    else
				is_recursive = [i, :center]
			    end
			    _terminal
			elsif recursions.key?(reference_name)
			    # If the referenced rule is known to be indirectly-recursive, use the recursion proxy for it
			    reference_counts[reference_name] += 1
			    recursions[reference_name]
			elsif not rules.key?(reference_name)
			    # WARNING This is a hack for marking rule references that don't match any of the rules in the grammar
			    reference_counts[expression_name] ||= nil
			else
			    # The referenced rule hasn't been converted, so bail out and try again later
			    return
			end
		    end
		end

		# If the resulting list has only a single element, flatten it. Otherwise, make a Concatenation
		if mapped_list.length > 1
		    Grammar::Concatenation.with(*mapped_list)
		else
		    mapped_list.first
		end
	    end

	    if is_recursive
		recursion_index = is_recursive.first
		recursive_list = mapped_expression[recursion_index]

		if is_recursive.last == :both
		    # Left and Right recursive (with no elements between the recursive elements)
		    # All other elements become one-or-more repetitions
		    if recursive_list.length == 2
			mapped_expression = mapped_expression.map do |list|
			    next if list.equal?(recursive_list) 	# Skip the recursive element
			    list.at_least(1)
			end.compact
		    end
		elsif is_recursive.last == :right
		    # Take the leftmost parts of the recursive element and prepend them to all of the other elements as a star-repeat
		    # Parsing Techniques - Chapter 5.4.2

		    remainder_list = recursive_list.to_a.tap(&:pop)
		    remainder_list = (remainder_list.length > 1) ? Grammar::Concatenation.with(*remainder_list) : remainder_list.first

		    remainder = Grammar::Repetition.any(remainder_list)
		    mapped_expression = mapped_expression.map do |list|
			next if list.equal?(recursive_list) 	# Skip the recursive element

			if remainder_list == list
			    # This prettifies the situation where the repeated-grammar is the same as what it's being prepended to
			    Grammar::Repetition.at_least(1, remainder_list)
			elsif Grammar::Concatenation === list
			    list.dup.tap {|_list| _list.instance_variable_get(:@elements).unshift(remainder) }
			else
			    Grammar::Concatenation.with(remainder, list)
			end
		    end.compact
		elsif is_recursive.last == :left
		    # Take the rightmost parts of the recursive element and append them to all of the other elements as a star-repeat
		    # Parsing Techniques - Chapter 5.6

		    remainder_list = recursive_list.to_a.drop(1)
		    remainder_list = (remainder_list.length > 1) ? Grammar::Concatenation.with(*remainder_list) : remainder_list.first

		    remainder = Grammar::Repetition.any(remainder_list)
		    mapped_expression = mapped_expression.map do |list|
			next if list.equal?(recursive_list) 	# Skip the recursive element

			if remainder_list == list
			    # This prettifies the situation where the repeated-grammar is the same as what it's being prepended to
			    Grammar::Repetition.at_least(1, remainder_list)
			elsif Grammar::Concatenation === list
			    list.dup.tap {|_list| _list.instance_variable_get(:@elements).push(remainder) }
			else
			    Grammar::Concatenation.with(remainder, list)
			end
		    end.compact
		end
	    end

	    if mapped_expression.length > 1
		# An Expression with more than one element must be an alternation
		Grammar::Alternation.with(*mapped_expression)
	    else
		# If the Expression has only a single element, it must be a Concatenation
		#  So, use it, whatever it is
		mapped_expression.first
	    end
	end

	# NOTE This modifies its arguments
	def self.convert_rules(grammar, rules:, reference_counts:, recursions:)
	    while not grammar.empty?
		_rules = grammar.reject do |_rule|
		    rule_name = _rule.rule_name
		    rules[rule_name] ||= self.convert_expression(rule_name, _rule.rhs, rules, reference_counts, recursions:recursions)
		end

		break if _rules.length == grammar.length	# Bail out if none of the rules could be processed

		grammar = _rules
	    end

	    grammar
	end

	# @return [Hash] the resulting set of Grammar elements, sorted by reference-count
	def self.read(filename)
	    bnf_syntax = parse(filename.respond_to?(:string) ? filename.string : File.read(filename))
	    return unless bnf_syntax

	    rules = {}
	    reference_counts = Hash.new(0)
	    recursive_rules = {}

	    bnf_rules = bnf_syntax.to_a	# Flatten the parse tree

	    # Find all of the grammar's rule names ahead of time to make it easier to detect unresolved rule references
	    bnf_rules.each {|rule| rules[rule.rule_name] = nil}

	    bnf_rules = self.convert_rules(bnf_rules, rules:rules, reference_counts:reference_counts, recursions:recursive_rules)

	    # At this point, all of the non-recursive and direct-recursive rules have been handled
	    #  The only rules that weren't fully processed are the ones that either have dangling references, or are indirectly recursive

	    # Rule references that aren't in the grammar have been marked with a nil-value in the reference_counts hash

	    # The unprocessed rules that don't correspond to nil-valued reference counts are indirectly-recursive
	    bnf_rules = bnf_rules.select {|rule| reference_counts[rule.first.to_s]}
	    bnf_rules.reduce([]) do |paths, rule|
		rule_name = rule.rule_name

		# Start a new path for this rule
		paths.push([rule_name])

		# Find all of the rule references in the rule that aren't directly recursive
		references = rule.rhs.to_a.flat_map do |list|
		    [list.first, *list.last.map(&:last)].map do |terminal|
			if BNF::Identifier === terminal.match
			    reference_name = terminal.match[1].to_s
			    reference_name if reference_name != rule_name
			end
		    end
		end.compact.uniq

		# Expand and append, then return the new paths as the new memo object
		paths.flat_map do |path|
		    next [path] unless path.last == rule_name
		    references.map do |reference|
			if reference == path.first
			    recursive_rules[reference] ||= Grammar::Recursion.new()
			end
			[*path, reference]
		    end
		end
	    end

	    # Now convert the indirectly-recursive rules
	    self.convert_rules(bnf_rules, rules:rules, reference_counts:reference_counts, recursions:recursive_rules)

	    # Fixup the recursion proxies
	    recursive_rules.each do |reference_name, recursion|
		recursion.grammar = rules[reference_name]
	    end

	    # Sort the resulting Hash to move the root-most rules to the beginning
	    #  Ideally, rules.first will be the root rule
	    rules.sort_by {|k,v| reference_counts[k]}.to_h
	end
    end
end
