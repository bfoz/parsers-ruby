require 'stringio'

require 'parsers'

RSpec.describe Parsers do
    it 'must load a BNF file into an appropriate parser' do
	expect(Parsers.load(StringIO.new('<digit> ::= "0" | "1"'))).to be_a(Parsers::RecursiveDescent)
    end
end
