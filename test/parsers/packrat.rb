require 'parsers/packrat'
require 'support/grammar_parser'

RSpec.describe Parsers::Packrat do
    it_should_behave_like 'a grammar parser'
end
