require 'parsers/context'

RSpec.describe Parsers::Context do
    it 'must have a local key' do
	context = Parsers::Context.new(local:{key:42})
	expect(context.key?(:key)).to be_truthy
    end

    it 'must not have a key that it does not have locally' do
	context = Parsers::Context.new()
	expect(context.key?(:key)).to be_falsey
    end

    it 'must have a key when the parent has the key' do
	parent = Parsers::Context.new(local:{key:42})
	context = Parsers::Context.new(parent:parent)
	expect(context.key?(:key)).to be_truthy
    end

    it 'must not have a key that the parent does not have either' do
	parent = Parsers::Context.new()
	context = Parsers::Context.new(parent:parent)
	expect(context.key?(:key)).to be_falsey
    end

    describe 'Setting a key' do
    	it 'must set the key locally when the parent does not have the key' do
	    parent = Parsers::Context.new()
	    context = Parsers::Context.new(parent:parent)
	    context[:key] = 42
	    expect(context.key?(:key)).to be_truthy
	    expect(parent.key?(:key)).to be_falsey
    	end

    	it 'must set the key locally when the parent has the key' do
	    parent = Parsers::Context.new(local:{key:42})
	    context = Parsers::Context.new(parent:parent)
	    context[:key] = 24
	    expect(context[:key]).to eq(24)
	    expect(parent[:key]).to eq(42)
    	end
    end
end
