module Parsers
    class Context
	def initialize(local:{}, parent:nil)
	    @context = local || {}
	    @parent = parent
	end

	def [](key)
	    @context.fetch(key) {|k| @parent&.[](k) }
	end

	def []=(key, value)
	    @context[key] = value
	end

	def key?(key)
	    @context.key?(key) or @parent&.key?(key)
	end

	def pop
	    @parent
	end

	def push(local = {})
	    self.class.new(local:local, parent:self)
	end

	# Don't bother creating a new context if the pattern doesn't have any context vars
	def push_pattern(pattern)
	    if pattern and pattern.respond_to?(:context) and pattern.context and not pattern.context.empty?
		self.push(pattern.context.dup)
	    else
		self
	    end
	end
    end
end
