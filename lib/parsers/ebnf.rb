require 'grammar/dsl'

require_relative 'recursive_descent'

module Parsers
    # https://en.wikipedia.org/wiki/Extended_Backus-Naur_form
    module EBNF
	using Grammar::DSL

	# letter = "A" | "B" | "C" | "D" | "E" | "F" | "G"| "H" | "I" | "J" | "K" | "L" | "M" | "N"| "O" | "P" | "Q" | "R" | "S" | "T" | "U"| "V" | "W" | "X" | "Y" | "Z" | "a" | "b"| "c" | "d" | "e" | "f" | "g" | "h" | "i"| "j" | "k" | "l" | "m" | "n" | "o" | "p"| "q" | "r" | "s" | "t" | "u" | "v" | "w"| "x" | "y" | "z" ;
	Letter = /[a-zA-Z]/

	# digit = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;
	Digit = /[0-9]/

	# symbol = "[" | "]" | "{" | "}" | "(" | ")" | "<" | ">" | "'" | '"' | "=" | "|" | "." | "," | ";" ;
	Symbol0 = /[\[\]{}\(\)<>"=\|\.,;]/
	Symbol1 = /[\[\]{}\(\)<>'=\|\.,;]/

	# character = letter | digit | symbol | "_" ;
	Character0 = alternation(Letter, Digit, Symbol0, "_")
	Character1 = alternation(Letter, Digit, Symbol1, "_")

	# identifier = letter , { letter | digit | "_" } ;
	Identifier = concatenation(Letter, (Letter | Digit | "_").at_least(0))

	# terminal = "'" , character , { character } , "'" | '"' , character , { character } , '"' ;
	Terminal = alternation(concatenation("'", Character0.at_least(1), "'"), concatenation('"', Character1.at_least(1), '"'))

	# rhs = identifier | terminal | "[" , rhs , "]" | "{" , rhs , "}" | "(" , rhs , ")" | rhs , "|" , rhs | rhs , "," , rhs ;
	concatenation :RHS do
	    alternation :Expression do
		element Identifier
		element Terminal
		element Optional:   concatenation('[', RHS, ']')		# Optional-repeat group
		element Repetition: concatenation('{', RHS, '}')		# Any-repeat group
		element Group:	    concatenation('(', RHS, ')')		# Group
	    end

	    element List: concatenation(Expression, concatenation(/\s*,\s*/, Expression).any)
	    element concatenation(/\s*\|\s*/, List).any
	end

	#rule = lhs , "=" , rhs , ";" ;
	# lhs = identifier ;
	Rule = concatenation(Identifier, /\s*=\s*/, RHS, /\s*;/)

	#grammar = { rule } ;
	Rules = concatenation(Rule, concatenation(/(\s*\n)*/, Rule).any)

	class Identifier
	    def to_s
		[self.first, *self.last].join
	    end
	end

	class Terminal
	    def to_s
		self.match[1].reduce('') {|memo, character| memo + character.to_s }
	    end
	end

	# Parse the given input and return a single parse tree, or nil
	# @param [String]	the input string to be parsed
	# @return [Grammar]
	def self.parse(input)
	    matches = Parsers::RecursiveDescent.new(EBNF::Rules).parse(input)

	    # A proper BNF file should have only a single valid parse
	    return matches.first if 1 == matches&.length
	end

	# @return [Hash] the resulting set of Grammar elements, sorted by reference-count
	def self.read(filename)
	    ebnf_syntax = parse(filename.respond_to?(:string) ? filename.string : File.read(filename))
	    return unless ebnf_syntax

	    rules = {}
	    reference_counts = Hash.new(0)

	    bnf_rules = [ebnf_syntax.first, *ebnf_syntax.last.map(&:last)]	# Flatten the parse tree
	    while not bnf_rules.empty?
		_rules = bnf_rules.reject do |_rule|
		    rule_name = _rule.first.to_s
		    expression = _rule[-2]

		    converted_expression = self.convert_rhs(rule_name, expression, rules, reference_counts)
		    if converted_expression
			reference_counts[rule_name] = 0 unless reference_counts.key?(rule_name) 	# Ensure that every rule has an entry (for the sorting step below)
			rules[rule_name] = converted_expression
		    end
		end

		break if _rules.length == bnf_rules.length	# Bail out if none of the rules could be processed

		bnf_rules = _rules
	    end

	    # At this point, all of the non-recursive and direct-recursive rules have been handled
	    #  The only rules that weren't fully processed are the ones that either have dangling references, or are indirectly recursive

	    # Sort the resulting Hash to move the root-most rules to the beginning
	    #  Ideally, rules.values.first will be the root rule
	    reference_counts.sort_by {|k,v| v}.map do |rule_name, _|
		[rule_name, rules[rule_name]]
	    end.to_h
	end

	# @param rules [Hash]
	def self.convert_rhs(rule_name, rhs, rules, reference_counts)
	    flattened_rhs = [rhs.first, *rhs.last.map(&:last)]
	    is_recursive = false

	    # Each element of the RHS is potentially a Concatenation
	    # The RHS itself is potentially an Alternation
	    mapped_rhs = flattened_rhs.map.with_index do |_list, i|
		flattened_list = [_list.first, *_list.last.map(&:last)]
		mapped_list = flattened_list.map.with_index do |_expression, j|
		    if EBNF::Terminal === _expression.match
			# The Expression is a quoted string, so just extract it
			_expression.to_s
		    elsif EBNF::Identifier === _expression.match
			# The Expression is a rule-reference, which needs to be mapped to the referenced rule
			reference_name = _expression.to_s
			if rules[reference_name]
			    # If the referenced rule has already been converted, just use it
			    reference_counts[reference_name] += 1
			    rules[reference_name]
			elsif rule_name == reference_name
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
			    _expression
			else
			    # The referenced rule hasn't been converted, so bail out and try again later
			    return
			end
		    elsif EBNF::RHS::Expression::Group === _expression.match
			self.convert_rhs(rule_name, _expression.match[1], rules, reference_counts)
		    elsif EBNF::RHS::Expression::Optional === _expression.match
			inner_rhs = self.convert_rhs(rule_name, _expression.match[1], rules, reference_counts)
			if inner_rhs
			    Grammar::Repetition.optional(inner_rhs)
			end
		    elsif EBNF::RHS::Expression::Repetition === _expression.match
			inner_rhs = self.convert_rhs(rule_name, _expression.match[1], rules, reference_counts)
			if inner_rhs
			    Grammar::Repetition.any(inner_rhs)
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
		recursive_list = mapped_rhs[recursion_index]

		if is_recursive.last == :both
		    # Left and Right recursive (with no elements between the recursive elements)
		    # All other elements become one-or-more repetitions
		    if recursive_list.length == 2
			mapped_rhs = mapped_rhs.map do |list|
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
		    mapped_rhs = mapped_rhs.map do |list|
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
		    mapped_rhs = mapped_rhs.map do |list|
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

	    if mapped_rhs.length > 1
		# A RHS with more than one element must be an alternation
		Grammar::Alternation.with(*mapped_rhs)
	    else
		# If the RHS has only a single element, it must be a Concatenation
		#  So, use it, whatever it is
		mapped_rhs.first
	    end
	end
    end
end
