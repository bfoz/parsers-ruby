module Parsers
    class NamedRules
	def initialize(*args)
	    @rules = args.select {|a| Hash === a}.reduce({}) {|h,a| h.update(a)}
	end

	# @group Accessors

	def [](index)
	    @rules[index]
	end

	# @return [Array]	An array of rule names
	def names
	    @rules.keys
	end
	alias keys names

	# @return [Array]	An array of the rules (unsorted)
	def rules
	    @rules.values
	end
	alias values rules

	# @endgroup

	# @return [Hash]	the reference tree for the set of rules. The keys are the rule name and the values are arrays of the rule's references.
	def references()
	    visit = ->(rule) do
		case rule
		    when String 	# Ignore
		    when Grammar::Alternation, Grammar::Concatenation
			rule.flat_map {|element| visit.call(element)}
		    when Grammar::Repetition
			visit.call(rule.grammar)
		    when Parsers::RecursiveReference, Parsers::RuleReference
			rule.rule_name
		    else
			raise ArgumentError.new("Unknown rule type: '#{rule.class}'")
		end
	    end

	    @rules.reduce({}) do |result, (rule_name, rule)|
		result[rule_name] = Array(visit.call(rule)).compact.uniq
		result
	    end
	end

	def sorted_names(_references=nil)
	    _references ||= self.references()
	    result = []
	    marks = []
	    path = []

	    visit = ->(node) do
		return if marks.include?(node)
		marks.push node
		if path.include?(node)
		    # Ignore cycles in the reference graph
		else
		    path.push node
		    _references[node].each(&visit) if _references.key?(node)
		    path.delete(node)
		    result.push node if _references.key?(node)
		end
	    end
	    _references.keys.each(&visit)

	    result
	end


	# @return [Hash]	a new {Hash} containing the named rules
	def to_h()
	    @rules.dup
	end

	# @group to_ruby()

	# Find all of the cycles in the grammar and break them
	# @return [Hash]	The discovered cycles. Keys are the cycle roots and values are arrays of the cycle members (excluding the root).
	private def break_cycles(_references=nil)
	    _references ||= self.references
	    marks = []
	    path = []

	    cycles = Hash.new {|h,k| h[k] = [] }
	    visit = ->(node) do
	    	# Skip the node if it's already marked, unless this happens to be a node that's already known to be the end of a cycle
	    	#  Because in that case this is probably an alternate route through a cycle
	    	#  ie. rule1 -> rule2 -> rule4 -> rule1 and rule1 -> rule3 -> rule4 -> rule1
		return if marks.include?(node) and (cycles.none? {|_,_cycles| _cycles.any? {|cycle| cycle.include?(node) } })
		if path.include?(node)
		    # Record the cycle
		    cycle = path.drop_while {|a| not (a == node) }.drop(1)
		    unless (cycle.empty? or cycles.fetch(node, []).include?(cycle))
			cycles[node].push(cycle)
		    end
		else
		    path.push node
		    _references[node].dup.each(&visit)
		    path.delete(node)
		    marks.push node
		end
	    end

	    # Find and break the cycles
	    _references.keys.each do |node|
		visit.call(node)
	    end

	    [cycles, _references]
	end

	# Does the rule reference itself? Do any of its internal rules (or their internal rules) reference the rule?
	# @return [Bool]
	private def internally_recursive_rule?(rule_name, internal_rules, _references)
	    is_recursive = ->(_rule_name) do
		_references.fetch(_rule_name, []).include?(rule_name) || internal_rules.fetch(_rule_name, []).any?(&is_recursive)
	    end
	    return is_recursive.call(rule_name)
	end

	# Find all of the external references for the given rule as well as for all of its internal rules
	# @return [Array]
	def external_references_for_node(rule, internal_rules, _references=nil, path:[])
	    _references ||= self.references
	    __refs = internal_rules.fetch(rule, []).flat_map do |a|
		next if path.include?(a)
		external_references_for_node(a, internal_rules, _references, path:path+[a])
	    end.compact.uniq
	    # Combine the arrays in the given order to preserve the dependency ordering
	    __refs + _references.fetch(rule, []) - internal_rules.fetch(rule, [])
	end

	# Find all of the rules that refer to node
	private def find_referers(node, _references=nil)
	    _references ||= self.references
	    _references.reduce([]) do |result, (rule_name, __references)|
		result.push(rule_name) if __references.include?(node)
		result
	    end
	end

	# @return [Array,String]
	private def internal_rules_to_ruby(rule_type, rule_name, rule, internal_rules:, _references:)
	    rule_is_recursive = internally_recursive_rule?(rule_name, internal_rules, _references)
	    _expand_the_rule = (internal_rules.key?(rule_name) and not internal_rules[rule_name].empty?)
	    _mapped = rule.map do |element|
		rule_to_ruby("", element, rule_locals:internal_rules, _references:_references).tap do |_rule|
		    _expand_the_rule = true if (Array === _rule)
		    rule_is_recursive = true if ((Parsers::RecursiveReference === element) and (_rule == rule_name))
		end
	    end

	    if _expand_the_rule or rule_is_recursive
		prefix = rule_type + ' do'
		prefix += " |#{rule_name}|" if rule_is_recursive
		local_rules = []
		if internal_rules.key?(rule_name)
		    local_rules = internal_rules[rule_name].map do |local_name|
			_rule = rule_to_ruby(local_name, @rules[local_name], rule_locals:internal_rules, _references:_references)
			if Array === _rule
			    ["\t#{local_name} = #{_rule.first}"] + _rule[1..-1].map {|r| "\t#{r}"}
			else
			    "\t#{local_name} = " + _rule
			end
		    end
		    local_rules.push('') unless local_rules.empty?
		end
		[prefix] + local_rules.flatten + _mapped.map do |element|
		    if Array === element
			["\telement " + element.first] + element[1..-1].map {|_element| "\t#{_element}"}
		    else
			"\telement #{element}"
		    end
		end.flatten + ["end"]
	    elsif 1 == _mapped.length
		_mapped.first
	    else
		rule_type + '(' + _mapped.join(', ') + ')'
	    end
	end

	private def ruby_repetition_suffix(rule)
	    if rule.maximum and rule.minimum
		if rule.maximum == rule.minimum
		    if rule.maximum != 1
			".repeat(#{rule.minimum})"
		    end
		elsif rule.minimum.zero? and (1 == rule.maximum)
		    '.optional'
		else
		    ".repeat(#{rule.minimum},#{rule.maximum})"
		end
	    elsif rule.maximum or rule.minimum
		if 1 == rule.maximum
		    '.optional'
		elsif 0 == rule.minimum
		    '.any'
		elsif 1 == rule.minimum
		    '.at_least(1)'
		else
		    ".repeat(#{rule.minimum},#{rule.maximum})"
		end
	    end
	end

	# @return [Array,String]
	private def rule_to_ruby(rule_name, rule, rule_locals:, _references:)
	    case rule
		when String
		    rule.to_s.dump
		when Grammar::Alternation
		    if rule.all? {|element| String === element}
			"'" + rule.to_a.join("' | '") + "'"
		    else
			internal_rules_to_ruby('alternation', rule_name, rule, internal_rules:rule_locals, _references:_references)
		    end
		when Grammar::Concatenation
		    internal_rules_to_ruby('concatenation', rule_name, rule, internal_rules:rule_locals, _references:_references)

		when Grammar::Recursion
		    key = rules.key(rule.grammar)
		    if key
			key
		    else
			rule_to_ruby(rule_name, rule.grammar, rule_locals:rule_locals, _references:_references)
		    end
		when Grammar::Repetition
		    suffix = ruby_repetition_suffix(rule)
		    _rule = rule_to_ruby(rule_name, rule.grammar, rule_locals:rule_locals, _references:_references)
		    if Array === _rule
			_rule.last.concat(suffix)
			_rule
		    elsif (Grammar::Alternation===rule.grammar) and not _rule.start_with?('alternation(')
			'(' + _rule + ')' + suffix
		    else
			_rule + suffix
		    end
		when Parsers::RecursiveReference, Parsers::RuleReference
		    __prefix = (Parsers::RecursiveReference === rule) ? 'RecursiveReference' : 'RuleReference'
		    if rule_locals.key?(rule_name) and rule_locals[rule_name].include?(rule.rule_name)
			rule_to_ruby(rule.rule_name, @rules[rule.rule_name], rule_locals:rule_locals, _references:_references)
		    else
			rule.rule_name
		    end
		else
		    raise StandardError.new("Unknown Grammar type #{rule.class}")
	    end
	end

	# @return [String] 	The resulting Ruby source
	def to_ruby()
	    cycles, _references = break_cycles()

	    # Create the internal rule set for the recursive node of each cycle to avoid
	    #  losing references to the reparented rules
	    #  This must be done as a separate step, after finding the cycles, so that
	    #  all of the cycles have been broken first (to avoid reintroducing a cycle)
	    internal_rules = Hash.new {|h,k| h[k] = [] }
	    orphaned_rules = []
	    reparent = ->(rule, parent) do
		# Re-parent the rule
		internal_rules[parent].push rule
		orphaned_rules.push rule
	    end
	    cycles.each do |node, _cycles|
		_cycles.each do |_cycle|
		    _cycle.each do |rule|
			referers = find_referers(rule, _references)
			if referers.empty?
			    raise StandardError.new("In the cycle for #{node}, #{rule} has no referers!! #{_cycle}")
			elsif referers.length == 1
			    # Internalize the rule if it isn't used anywhere else
			    reparent.call(rule, node)
			else
			    # If all of the referers are either internal rules of the root node, or are external references of the root node,
			    #  then re-parent the rule in the root node
			    node_references = external_references_for_node(node, internal_rules, _references)
			    if referers.all? {|referer| internal_rules[node].include?(referer) or node_references.include?(referer)}
				reparent.call(rule, node)
			    else
				# If the first node of a recursive cycle can't be internalized then the overall grammar has serious issues
				puts("Cannot internalize '#{rule}' into '#{node}' because it has referers: #{referers}")
				# raise StandardError.new("Can't internalize '#{rule}' into '#{node}' because it has referers: #{referers}")
			    end
			end
		    end
		end
	    end
	    non_root_rules = orphaned_rules.uniq

	    # Sort the internal rules
	    internal_rules.transform_values! do |locals|
	    	sorted_names(_references.slice(*locals.uniq))
	    end

	    (self.sorted_names(_references)-non_root_rules).map do |rule_name|
		_ruby = rule_to_ruby(rule_name, @rules[rule_name], rule_locals:internal_rules, _references:_references)
		if Array === _ruby
		    _ruby = _ruby.join("\n")
		end
		"#{rule_name}\t= #{_ruby}" if _ruby
	    end.join("\n") + "\n"
	end

	# @endgroup
    end
end
