require 'strscan'

require 'grammar'

require_relative 'context'

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
		visit(input, root, context:Context.new)
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
	private def visit(input, pattern, context:)
	    case pattern
		when Range
		    # FIXME This is a terrible way to do this
		    visit(input, /[#{pattern.first}-#{pattern.last}]/, context:context)
		when Regexp
		    input.matched if input.scan(Regexp.new(pattern))
		when String
		    input.matched if input.scan(Regexp.new(Regexp.escape(pattern)))

		when Grammar::Alternation
		    context = context.push_pattern(pattern)
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
			    match = visit(input, element, context:context)
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
		    context = context.push_pattern(pattern)
		    position = input.pos
		    redoing = true	# Start off assuming a redo to prevent the ignore pattern from matching before the first element
		    matches = pattern.elements.map do |element|
			_match = visit(input, element, context:context)
			if failed_or_empty = ((not _match) or (_match.respond_to?(:empty?) and _match.empty?))
			    allowed_to_fail = (
				(element.respond_to?(:optional?) and element.optional?) or
				(element.respond_to?(:at_least?) and element.at_least?(0)) or
				(element.respond_to?(:empty?) and element.empty?) or
				((Regexp === element) and (element =~ ''))	# If the element is a regexp that can match nothing
			    )
			    if allowed_to_fail
				if (not element.is_a?(Grammar::Recursion))
				    if (not redoing) && pattern.ignore && visit(input, pattern.ignore, context:context)
					redoing = true
					redo	# Skip the "ignore" match and try the element again
				    end
				end
			    elsif pattern.ignore and (not redoing)
				if visit(input, pattern.ignore, context:context)
				    redoing = true
				    redo	# Skip the "ignore" match and try the element again
				end
			    else
				input.pos = position 	# Backtracking
				return
			    end
			end
			redoing = nil
			_match
		    end
		    pattern.new(*matches, location:position)

		when Grammar::Latch
		    if context.key?(pattern)
			latch = context[pattern]
			unless latch.nil?
			    return case latch
				when String then visit(input, latch, context:context)
				else
				    a = visit(input, pattern.grammar, context:context)
				    if a and (latch == a)
					a
				    end
			    end
			end
		    end
		    context[pattern] = visit(input, pattern.grammar, context:context).tap {|a| puts "Saving latch match #{a}"}

		when Grammar::Repetition
		    redoing = input.pos	# Start off assuming a redo to prevent the ignore pattern from matching before the first element
		    result = []
		    if pattern.minimum&.nonzero?
			position = input.pos
			pattern.minimum.times do |i|
			    a = visit(input, pattern.grammar, context:context)
			    if a
				result.push(a)
			    else
				if (not redoing) && pattern.ignore && visit(input, pattern.ignore, context:context)
				    redoing = true
				    redo	# Skip the "ignore" match and try the element again
				end

				input.pos = position 	# Backtrack
				return			# Failure
			    end
			    redoing = nil
			end
		    end

		    if pattern.maximum
			(pattern.maximum - (pattern.minimum or 0)).times do
			    position = input.pos
			    a = visit(input, pattern.grammar, context:context)
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
				    if visit(input, pattern.ignore, context:context)
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
			    a = visit(input, pattern.grammar, context:context)
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
				    if visit(input, pattern.ignore, context:context)
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
		    visit(input, pattern.grammar, context:context)

		else
		    raise ArgumentError.new("Unknown pattern: #{pattern}")
	    end
	end
    end
end
