require_relative 'recursive_descent'

module Parsers
    class Packrat < RecursiveDescent
	def parse(input)
	    # Start with a fresh cache on every parse, otherwise subsequent parses will step on each other
	    @cache = Hash.new {|h,k| h[k] = {} }
	    super
	end

	private def visit(input, pattern, context:)
	    if (String === pattern) or (Grammar::Latch === pattern)
		# Latches are cached in the Context stack, and we'd prefer to avoid filling the
		#  cache with strings (both the key and the value would be the same string)
		super
	    elsif @cache.has_key?(input.pos) and @cache[input.pos].has_key?(pattern)
		length, result = @cache[input.pos][pattern]
		input.pos += length
		result
	    else
		position = input.pos
		super.tap do |result|
		    length = input.pos - position
		    @cache[position][pattern] = [length, result]
		end
	    end
	end
    end
end
