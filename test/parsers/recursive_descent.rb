require 'parsers/recursive_descent'
require 'support/grammar_parser'

RSpec.describe Parsers::RecursiveDescent do
    let(:parser) { Parsers::RecursiveDescent.new }

    it_should_behave_like 'a grammar parser'
end
