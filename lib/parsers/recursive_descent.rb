require 'strscan'

require 'grammar'

module Parsers
    class RecursiveDescent
	attr_reader :patterns

	def initialize(grammar=nil)
	    @patterns = []
	    self.push(grammar) if grammar
	end

	def parse(input)
	    input = StringScanner.new(input) if input.is_a?(String)

	    forest = self.roots.map do |root|
		visit(input, root)
	    end.compact

	    forest unless forest.empty?
	end

	def push(pattern)
	    @patterns.push pattern
	end

	def roots
	    @patterns
	end

	# @param [StringScanner] The input to parse
	# @param [Grammar] The pattern to attempt to parse
	private def visit(input, pattern)
	    case pattern
		when Range
		    # FIXME This is a terrible way to do this
		    visit(input, /[#{pattern.first}-#{pattern.last}]/)
		when Regexp
		    input.matched if input.scan(Regexp.new(pattern))
		when String
		    input.matched if input.scan(Regexp.new(Regexp.escape(pattern)))

		when Grammar::Alternation
		    _position = input.pos
		    longest_match = nil
		    position_after_longest_match = _position
		    pattern.elements.each do |element|
			input.pos = _position
			if element.is_a?(String) and element.empty?
			    if longest_match.nil?
				position_after_longest_match = input.pos
				longest_match = element
			    end
			else
			    match = visit(input, element)
			    if match and (input.pos > position_after_longest_match)
				position_after_longest_match = input.pos
				longest_match = match
			    end
			end
		    end
		    if longest_match
			input.pos = position_after_longest_match
			pattern.new(longest_match, location:_position)
		    end

		when Grammar::Concatenation
		    position = input.pos
		    matches = pattern.elements.map do |element|
			a = visit(input, element)
			if not a and not element.is_a?(Grammar::Recursion) and not (element.respond_to?(:optional?) and element.optional?)
			    input.pos = position 	# Backtracking
			    return
			end
			a
		    end
		    pattern.new(*matches, location:position)

		when Grammar::Repetition
		    result = []
		    if pattern.minimum&.nonzero?
			pattern.minimum.times do |i|
			    position = input.pos
			    a = visit(input, pattern.grammar)
			    if a
				result.push(a)
			    else
				input.pos = position 	# Backtrack
				return			# Failure
			    end
			end
		    end

		    if pattern.maximum
			(pattern.maximum - (pattern.minimum or 0)).times do
			    position = input.pos
			    a = visit(input, pattern.grammar)
			    if a
				result.push(a)
			    else
				input.pos = position 	# Backtrack
				break			# Failure
			    end
		    	end
		    else
			# No max limit, so go until failure or EOS
			loop do
			    position = input.pos
			    a = visit(input, pattern.grammar)
			    if a
				result.push(a)
			    else
				input.pos = position 	# Backtrack
				break			# Failure
			    end
			    break if input.eos?
			end
		    end

		    if pattern.optional? and (result.length <= 1)
			result.first
		    else
			result
		    end

		when Grammar::Recursion
		    visit(input, pattern.grammar)

		else
		    raise ArgumentError.new("Unknown pattern: #{pattern}")
	    end
	end
    end
end
