require_relative 'parsers/bnf'
require_relative 'parsers/ebnf'
require_relative 'parsers/recursive_descent'

module Parsers
    # Read from a grammar file and load the grammar into an appropriate parser
    def self.load(filename)
	grammar = self.read(filename)
	return unless grammar
	RecursiveDescent.new(grammar.values.first)
    end

    # Read from a grammar file
    # @param path [IO,String]	the file, or IO-like object, to read the grammar from
    # @return [Grammar] the grammer contained in the file given by _path_
    def self.read(path)
	BNF.read(path) or EBNF.read(path)
    end
end
