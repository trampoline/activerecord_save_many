require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

module ActiveRecord
  describe SaveMany do
    it "fails" do
      fail "hey buddy, you should probably rename this file and start specing for real"
    end

    it "creates a save_many method on an ActiveRecord class" do
      class Foo < ActiveRecord::Base ; end

      Foo.respond_to?(:save_many).should be(true)
    end
  end
end
