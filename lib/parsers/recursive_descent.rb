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
		    redoing = true	# Start off assuming a redo to prevent the ignore pattern from matching before the first element
		    matches = pattern.elements.map do |element|
			a = visit(input, element)
			if (not a) and (not element.is_a?(Grammar::Recursion)) and (not (element.respond_to?(:optional?) and element.optional?))
			    if (not redoing) && pattern.ignore && visit(input, pattern.ignore)
				redoing = true
				redo	# Skip the "ignore" match and try the element again
			    end

			    input.pos = position 	# Backtracking
			    return
			end
			redoing = nil
			a
		    end
		    pattern.new(*matches, location:position)

		when Grammar::Repetition
		    result = []
		    if pattern.minimum&.nonzero?
			redoing = nil
			position = input.pos
			pattern.minimum.times do |i|
			    a = visit(input, pattern.grammar)
			    if a
				result.push(a)
			    else
				if (not redoing) && pattern.ignore && visit(input, pattern.ignore)
				    redoing = true
				    redo	# Skip the "ignore" match and try the element again
				end

				input.pos = position 	# Backtrack
				return			# Failure
			    end
			    redoing = nil
			end
		    end

		    redoing = nil
		    if pattern.maximum
			(pattern.maximum - (pattern.minimum or 0)).times do
			    position = input.pos
			    a = visit(input, pattern.grammar)
			    if a
				result.push(a)
			    else
				# If the pattern failed again (ie. it was a redo) then the input position needs to
				#  be rewound to before the ignore-pattern matched, otherwise the trailing ignore-match
				#  will be improperly consumed
				if redoing
				    position = redoing		# Backtrack to before the ignore pattern was matched
				elsif pattern.ignore
				    pre_ignore_position = input.pos
				    if visit(input, pattern.ignore)
					redoing = pre_ignore_position	# Save the input position from before the ignore pattern in case we need it later
					redo	# Skip the "ignore" match and try the element again
				    end
				end

				input.pos = position 	# Backtrack
				break			# Failure
			    end
			    redoing = nil
			    break if input.eos?
			end
		    else
			# No max limit, so go until failure or EOS
			loop do
			    position = input.pos
			    a = visit(input, pattern.grammar)
			    if a
				result.push(a)
			    else
				# If the pattern failed again (ie. it was a redo) then the input position needs to
				#  be rewound to before the ignore-pattern matched, otherwise the trailing ignore-match
				#  will be improperly consumed
				if redoing
				    position = redoing		# Backtrack to before the ignore pattern was matched
				elsif pattern.ignore
				    pre_ignore_position = input.pos
				    if visit(input, pattern.ignore)
					redoing = pre_ignore_position	# Save the input position from before the ignore pattern in case we need it later
					redo	# Skip the "ignore" match and try the element again
				    end
				end

				input.pos = position 	# Backtrack
				break			# Failure
			    end
			    redoing = nil
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
