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

	class RHS
	    # Return all of the rule references in this {RHS}
	    # @return [Array<String>]
	    def references(rule_name)
		self.to_a.flat_map do |list|
		    [list.first, *list.last.map(&:last)].flat_map do |expression|
			expression.references(rule_name)
		    end
		end.compact.uniq
	    end

	    # @return [Array<List>]
	    def to_a
		[self.first, *self.last.map(&:last)]
	    end
	end

	class RHS::Expression
	    # Return all of the rule references in this {Expression}
	    # @return [Array<String>]
	    def references(rule_name)
		case self.match
		    when EBNF::Identifier
			reference_name = self.to_s
			reference_name if reference_name != rule_name
		    when EBNF::RHS::Expression::Group, EBNF::RHS::Expression::Optional, EBNF::RHS::Expression::Repetition
			self.match[1].references(rule_name)
		end
	    end
	end

	class Rule
	    # Return all of the rule references in this {Rule}
	    # @return [Array<String>]
	    def references
		self.rhs.references(self.rule_name)
	    end

	    # @return [RHS]
	    def rhs
		self[-2]
	    end

	    def rule_name
		self.first.to_s
	    end
	end

	class Rules
	    def to_a
		[self.first, *self.last.map(&:last)]
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
	    recursive_rules = {}

	    bnf_rules = ebnf_syntax.to_a	# Flatten the parse tree

	    # Find all of the grammar's rule names ahead of time to make it easier to detect unresolved rule references
	    bnf_rules.each {|rule| rules[rule.rule_name] = nil}

	    # Process the grammar to handle the low-hanging fruit
	    bnf_rules = self.convert_rules(bnf_rules, rules:rules, reference_counts:reference_counts, recursions:recursive_rules)

	    # At this point, all of the non-recursive and direct-recursive rules have been handled
	    #  The only rules that weren't fully processed are the ones that either have dangling references, or are indirectly recursive

	    # Rule references that aren't in the grammar have been marked with a nil-value in the reference_counts hash
	    unresolved_references = reference_counts.select {|k,v| v.nil?}
	    unless unresolved_references.empty?
		puts "UNRESOLVED REFERENCES!!! #{unresolved_references.length}"
	    end

	    # The unprocessed rules that don't correspond to nil-valued reference counts are indirectly-recursive
	    bnf_rules = bnf_rules.select {|rule| reference_counts[rule.rule_name]}
	    bnf_rules.reduce([]) do |paths, rule|
		rule_name = rule.rule_name

		# Start a new path for this rule
		paths.push([rule_name])

		# Find all of the rule references in the rule that aren't directly recursive
		references = rule.references

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

	# NOTE This modifies its arguments
	def self.convert_rules(grammar, rules:, reference_counts:, recursions:)
	    while not grammar.empty?
		_rules = grammar.reject do |_rule|
		    rule_name = _rule.rule_name
		    rules[rule_name] ||= self.convert_rhs(rule_name, _rule.rhs, rules, reference_counts, recursions:recursions)
		end

		break if _rules.length == grammar.length	# Bail out if none of the rules could be processed

		grammar = _rules
	    end

	    grammar
	end

	# @param rules [Hash]
	# @return [Grammar::Alternation, Grammar::Concatenation]	the resulting Grammar element, or nil if the RHS couldn't be converted
	def self.convert_rhs(rule_name, rhs, rules, reference_counts, recursions:)
	    recursives = []

	    # Each element of the RHS is potentially a Concatenation
	    # The RHS itself is potentially an Alternation
	    mapped_rhs = rhs.to_a.map do |_list|
		recursives.push(nil)	# Start off assuming that this rule isn't recursive

		flattened_list = [_list.first, *_list.last.map(&:last)]
		mapped_list = flattened_list.map.with_index do |_expression, j|
		    if EBNF::Terminal === _expression.match
			# The Expression is a quoted string, so just extract it
			_expression.to_s
		    elsif EBNF::Identifier === _expression.match
			# The Expression is a rule-reference, which needs to be mapped to the referenced rule

			reference_name = _expression.to_s

			# NOTE The order of this conditional is important
			if rules[reference_name] and not recursions.key?(reference_name)
			    # If the referenced rule has already been converted, just use it
			    reference_counts[reference_name] += 1
			    RuleReference.new(reference_name, rules[reference_name])
			elsif rule_name == reference_name	# Direct recursive?
			    if j.zero?
				recursives[-1] = :left
			    elsif j == (flattened_list.length - 1)
				if :left == recursives.last
				    # If this list is already marked as left-recursive, and it's now found to also be right recursive,
				    #  then it must be both-recursive
				    recursives[-1] = :both
				else
				    recursives[-1] = :right
				end
			    else
				recursives[-1] = :center
			    end
			    _expression
			elsif recursions.key?(reference_name)
			    # If the referenced rule is known to be indirectly-recursive, use the recursion proxy for it
			    reference_counts[reference_name] += 1
			    recursions[reference_name]
			elsif not rules.key?(reference_name)
			    # WARNING This is a hack for marking rule references that don't match any of the rules in the grammar
			    reference_counts[rule_name] ||= nil
			else
			    # The referenced rule hasn't been converted, so bail out and try again later
			    return
			end
		    elsif EBNF::RHS::Expression::Group === _expression.match
			# If the Group can't be converted, bail out and try again later
			self.convert_rhs(rule_name, _expression.match[1], rules, reference_counts, recursions:recursions) or return
		    elsif EBNF::RHS::Expression::Optional === _expression.match
			inner_rhs = self.convert_rhs(rule_name, _expression.match[1], rules, reference_counts, recursions:recursions)
			if inner_rhs
			    Grammar::Repetition.optional(inner_rhs)
			else
			    # If the Optional can't be converted, bail out and try again later
			    return
			end
		    elsif EBNF::RHS::Expression::Repetition === _expression.match
			inner_rhs = self.convert_rhs(rule_name, _expression.match[1], rules, reference_counts, recursions:recursions)
			if inner_rhs
			    Grammar::Repetition.any(inner_rhs)
			else
			    # If the Repetition can't be converted, bail out and try again later
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

	    if recursives.any?
		leftmost_parts, rightmost_parts = recursives.zip(mapped_rhs.to_a).reduce([[],[]]) do |(_leftmost_parts, _rightmost_parts), (is_recursive, list)|
		    if :left == is_recursive
			# Take the rightmost parts of the recursive elements and append them to all of the other elements as a star-repeated Alternation
			# Parsing Techniques - Chapter 5.6
			remainder_list = list.to_a.drop(1)
			remainder_list = (remainder_list.length > 1) ? Grammar::Concatenation.with(*remainder_list) : remainder_list.first
			_rightmost_parts.push(remainder_list) if remainder_list
		    elsif :right == is_recursive
			# Take the leftmost parts of the recursive elements and prepend them to all of the other elements as a star-repeated Alternation
			# Parsing Techniques - Chapter 5.4.2
			remainder_list = list.to_a.tap(&:pop)
			remainder_list = (remainder_list.length > 1) ? Grammar::Concatenation.with(*remainder_list) : remainder_list.first
			_leftmost_parts.push(remainder_list) if remainder_list
		    end
		    [_leftmost_parts, _rightmost_parts]
		end

		rightmost_parts = if rightmost_parts.length > 1
		    Grammar::Alternation.with(*rightmost_parts)
		else
		    rightmost_parts.first
		end
		right_repetition = Grammar::Repetition.any(rightmost_parts) if rightmost_parts

		leftmost_parts = if leftmost_parts.length > 1
		    Grammar::Alternation.with(*leftmost_parts)
		else
		    leftmost_parts.first
		end
		left_repetition = Grammar::Repetition.any(leftmost_parts) if leftmost_parts

		mapped_rhs = recursives.zip(mapped_rhs).map do |is_recursive, list|
		    next if is_recursive and (is_recursive != :both) 	# Skip the recursive elements

		    if (rightmost_parts == list) or (leftmost_parts == list)
			# This prettifies the situation where the repeated-grammar is the same as what it's being prepended/appended to
			Grammar::Repetition.at_least(1, list)
		    elsif Grammar::Concatenation === list
			# If the list element is already a Concatenation, insert the repetiton elements into it
			# WARNING This is a dirty hack and I'm sure it will come back to bite me someday
			list.dup.tap do |_list|
			    _list.instance_variable_get(:@elements).unshift(left_repetition) if left_repetition
			    _list.instance_variable_get(:@elements).push(right_repetition) if right_repetition
			end
		    else
			# This looks funny to account for the fact that Repetition is splattable
			Grammar::Concatenation.with(*[left_repetition, list, right_repetition].compact)
		    end
		end.compact
	    end

	    # This is a weird hack for handling the weird case of a rule that is both left and right recursive (with no elements between the recursive elements)
	    #  In this situation, make all of the other elements into one-or-more repetitions
	    # I don't remember where I got this idea, or why it came up (I'm pretty sure it in developing a grammar for something),
	    #  but it works for the situation it was intended for.
	    recursion_index = recursives.find_index(:both)
	    if recursion_index
		recursive_list = mapped_rhs[recursion_index]
		mapped_rhs = mapped_rhs.map do |list|
		    next if list.equal?(recursive_list) 	# Skip the recursive element
		    list.at_least(1)
		end.compact
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
