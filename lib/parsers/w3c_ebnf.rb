require 'grammar/dsl'

require_relative 'recursive_descent'

module Parsers
    # https://en.wikipedia.org/wiki/Extended_Backus-Naur_form
    module W3C_EBNF
	using Grammar::DSL

	Hexadecimal = concatenation('#x', /[0-9a-fA-F]+/)
	Character = alternation(Hexadecimal, /[ !"]/, /[\u{24}-\u{FFFF}]/)
	RangeCharacter = alternation(Hexadecimal, /[ !"]/, /[\u{23}-\u{5C}\u{5E}-\u{FFFF}]/)	# Character.except(']')

	Character0 = /[a-zA-Z0-9_\[\]{}\(\)<>"=\|\.,;]+/		# Exclude single-quote
	Character1 = /[a-zA-Z0-9_\[\]{}\(\)<>'=\|\.,;]+/		# Exclude double-quote

	Identifier = /[a-zA-Z][a-zA-Z0-9_]+/

	# rhs = #xN | Range | identifier | terminal | "(" , rhs , ")";
	concatenation :RHS do
	    alternation :Expression do
		element Hexadecimal
		element Identifier
		element Terminal:	alternation(concatenation("'", Character0, "'"), concatenation('"', Character1, '"'))
		element Range:		concatenation('[', alternation(RangeCharacter, concatenation(RangeCharacter, '-', RangeCharacter)).one_or_more, ']')
		element NegatedRange: 	concatenation('[^', alternation(RangeCharacter, concatenation(RangeCharacter, '-', RangeCharacter)).one_or_more, ']')

		element Exclusion:	concatenation(Expression, /\s*-\s*/, Expression)
		element Repetition:	concatenation(Expression, /[\?\*\+]/)		# Repetition
		element Group:		concatenation('(', RHS, ')')			# Group
	    end

	    element List: concatenation(Expression, concatenation(/[[:blank:]]*/, Expression).any)
	    element concatenation(/\s*\|\s*/, List).any
	end

	# Rule = Identifier "::=" RHS
	Rule = concatenation(Identifier, /[[:blank:]]*::=[[:blank:]]*/, RHS)

	Rules = concatenation(Rule, concatenation(/([[:blank:]]*\n)*/, Rule).any)

	class RHS::Expression::Terminal
	    def to_s
		self.match[1].to_s
	    end
	end

	# Parse the given input and return a single parse tree, or nil
	# @param [String]	the input string to be parsed
	# @return [Grammar]
	def self.parse(input)
	    matches = Parsers::RecursiveDescent.new(W3C_EBNF::Rules).parse(input)

	    # A proper BNF file should have only a single valid parse
	    return matches.first if 1 == matches&.length
	end

	# @return [Hash] the resulting set of Grammar elements, sorted by reference-count
	def self.read(filename)
	    ebnf_syntax = parse(filename.respond_to?(:string) ? filename.string : File.read(filename))
	    return unless ebnf_syntax

	    rules = {}
	    reference_counts = Hash.new(0)

	    flattened_rules = [ebnf_syntax.first, *ebnf_syntax.last.map(&:last)]	# Flatten the parse tree
	    loop do
		_rules = flattened_rules.reject do |_rule|
		    rule_name = _rule.first.to_s
		    expression = _rule.last

		    converted_expression = self.convert_rhs(rule_name, expression, rules, reference_counts)
		    if converted_expression
			reference_counts[rule_name] = 0 unless reference_counts.key?(rule_name) 	# Ensure that every rule has an entry (for the sorting step below)
			rules[rule_name] = converted_expression
		    end
		end

		break if _rules.length == flattened_rules.length	# Bail out if none of the rules could be processed

		flattened_rules = _rules
	    end

	    # At this point, all of the non-recursive and direct-recursive rules have been handled
	    #  The only rules that weren't fully processed are the ones that either have dangling references, or are indirectly recursive

	    # Sort the resulting Hash to move the root-most rules to the beginning
	    #  Ideally, rules.values.first will be the root rule
	    reference_counts.sort_by {|k,v| v}.map do |rule_name, _|
		[rule_name, rules[rule_name]]
	    end.to_h
	end

	def self.convert_expression(expression, list_index:, expression_index:, rule_name:, reference_counts:, rules:, flattened_list:nil, is_recursive:nil)
	    # Because of weirdness in the way that I implemented recursion in Grammar, RHS::Expression will either be an Array or a simple match
	    #  FIXME I really should fix Grammar such that this is always an Alternation match, but it's not a simple fix
	    if expression.respond_to?(:first) && expression.respond_to?(:last)
		flattened_expression = [expression.first, *expression.last]
	    else
		flattened_expression = [expression]
	    end

	    # More weirdness...
	    # if W3C_EBNF::RHS::Expression::Repetition === flattened_expression.match
	    if /[\?\*\+]/ =~ flattened_expression.last.match.to_s
		inner_rhs = self.convert_expression(flattened_expression.first, list_index:list_index, expression_index:0, rules:rules, reference_counts:reference_counts, rule_name:rule_name)
		if inner_rhs
		    case flattened_expression.last.match.to_s
			when '?' then Grammar::Repetition.optional(inner_rhs)
			when '*' then Grammar::Repetition.any(inner_rhs)
			when '+' then Grammar::Repetition.one_or_more(inner_rhs)
		    end
		end
	    elsif W3C_EBNF::RHS::Expression::Terminal === flattened_expression.first.match
		# The Expression is a quoted string, so just extract it
		flattened_expression.first.to_s
	    elsif W3C_EBNF::Identifier === flattened_expression.first.match
		# The Expression is a rule-reference, which needs to be mapped to the referenced rule
		reference_name = flattened_expression.first.to_s
		if rules[reference_name]
		    # If the referenced rule has already been converted, just use it
		    reference_counts[reference_name] += 1
		    rules[reference_name]
		elsif rule_name == reference_name	# Is the reference direct-recursive?
		    if expression_index.zero?
			is_recursive = [list_index, :left]
		    elsif expression_index == (flattened_list.length - 1)
			if is_recursive and (is_recursive == [list_index, :left])
			    # If this list is already marked as left-recursive, and it's now found to also be right recursive,
			    #  then it must be both-recursive
			    is_recursive = [list_index, :both]
			else
			    is_recursive = [list_index, :right]
			end
		    else
			is_recursive = [list_index, :center]
		    end
		    [flattened_expression.first, is_recursive]
		else
		    # The referenced rule hasn't been converted, so bail out and try again later
		    return
		end
	    elsif W3C_EBNF::RHS::Expression::Group === flattened_expression.first.match
		self.convert_rhs(rule_name, flattened_expression.first.match[1], rules, reference_counts)
	    end
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
		    result = convert_expression(_expression, list_index:i, expression_index:j, rule_name:rule_name, rules:rules, reference_counts:reference_counts, flattened_list:flattened_list, is_recursive:is_recursive)
		    if result.nil?
			# This happens when convert_expression() can't look up a forward rule reference
			#  The only thing that can be done about it is to bail out and try again later
			return
		    elsif result.is_a?(Array)
			is_recursive = result.last
			result = result.first
		    end
		    result
		end

		# If the resulting list has only a single element, flatten it. Otherwise, make a Concatenation
		if mapped_list.length > 1
		    Grammar::Concatenation.with(*mapped_list)
		else
		    mapped_list.first	# This intentionally generates a nil when mapped_list is empty
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
